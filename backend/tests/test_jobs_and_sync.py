import uuid
from datetime import UTC, datetime, time, timedelta

from sqlalchemy import select

from app.core.time import local_today
from app.models import ActivityEvent, DailySummary, Habit, HabitLog, User, UserPreferences

from .conftest import API

JOB = {"X-Job-Secret": "test-job-secret"}


async def test_internal_jobs_require_secret(client):
    assert (await client.post("/internal/jobs/process-events")).status_code == 403
    assert (
        await client.post("/internal/jobs/process-events", headers={"X-Job-Secret": "nope"})
    ).status_code == 403
    assert (await client.post("/internal/jobs/process-events", headers=JOB)).status_code == 200


async def test_sweeper_processes_pending_events(client, user, session):
    async with session() as db:
        me = await db.scalar(select(User))
        db.add(ActivityEvent(user_id=me.id, event_type="task.completed", payload={}))
        await db.commit()
    r = await client.post("/internal/jobs/process-events", headers=JOB)
    assert r.json()["processed"] == 1
    r = await client.post("/internal/jobs/process-events", headers=JOB)
    assert r.json()["processed"] == 0


async def test_daily_summary_marks_missed_habits_once(client, user, session):
    h = (await client.post(f"{API}/habits", json={"title": "Gym"}, headers=user["h"])).json()
    async with session() as db:  # pretend the habit started two days ago
        habit = await db.get(Habit, uuid.UUID(h["id"]))
        habit.created_at = datetime.now(UTC) - timedelta(days=2)
        await db.commit()
    assert (await client.post("/internal/jobs/daily-summary", headers=JOB)).json()["summaries"] == 1
    assert (await client.post("/internal/jobs/daily-summary", headers=JOB)).json()["summaries"] == 0
    yesterday = local_today("Asia/Kolkata") - timedelta(days=1)
    async with session() as db:
        log = await db.scalar(select(HabitLog))
        assert log.status == "missed" and log.log_date == yesterday
        assert await db.scalar(select(DailySummary).where(DailySummary.summary_date == yesterday))


async def test_daily_review_runs_once_after_review_time(client, user, session):
    await client.post(f"{API}/tasks", json={"title": "Something"}, headers=user["h"])
    async with session() as db:
        prefs = await db.scalar(select(UserPreferences))
        prefs.daily_review_time = time(0, 0)
        await db.commit()
    assert (await client.post("/internal/jobs/daily-review", headers=JOB)).json()["reviews"] == 1
    assert (await client.post("/internal/jobs/daily-review", headers=JOB)).json()["reviews"] == 0
    review = (await client.get(f"{API}/agent/reviews/daily", headers=user["h"])).json()
    assert review["available"] and review["insight"]


async def test_weekly_review_and_cleanup(client, user):
    r = await client.post(f"{API}/agent/reviews/weekly/run", headers=user["h"])
    assert r.json()["available"] and r.json()["report"]
    assert (await client.post("/internal/jobs/cleanup", headers=JOB)).status_code == 200


async def test_sync_push_pull_conflicts_and_idempotency(client, user):
    tid = str(uuid.uuid4())
    push = lambda changes: client.post(f"{API}/sync/push", json={"changes": changes}, headers=user["h"])  # noqa: E731

    r = (
        await push(
            [
                {
                    "change_id": "c-00000001",
                    "entity": "tasks",
                    "op": "upsert",
                    "id": tid,
                    "data": {"title": "Offline task"},
                }
            ]
        )
    ).json()
    assert r[0]["status"] == "applied" and r[0]["version"] == 1

    r = (
        await push(
            [
                {
                    "change_id": "c-00000002",
                    "entity": "tasks",
                    "op": "upsert",
                    "id": tid,
                    "base_version": 1,
                    "data": {"priority": "high"},
                }
            ]
        )
    ).json()
    assert r[0]["status"] == "applied" and r[0]["version"] == 2

    stale = (
        await push(
            [
                {
                    "change_id": "c-00000003",
                    "entity": "tasks",
                    "op": "upsert",
                    "id": tid,
                    "base_version": 1,
                    "data": {"priority": "low"},
                }
            ]
        )
    ).json()
    assert stale[0]["status"] == "conflict" and stale[0]["server"]["priority"] == "high"

    replay = (
        await push(
            [
                {
                    "change_id": "c-00000002",
                    "entity": "tasks",
                    "op": "upsert",
                    "id": tid,
                    "base_version": 1,
                    "data": {"priority": "high"},
                }
            ]
        )
    ).json()
    assert replay[0]["status"] == "applied" and replay[0]["version"] == 2  # same answer, not re-applied

    bad = (
        await push(
            [
                {
                    "change_id": "c-00000004",
                    "entity": "tasks",
                    "op": "upsert",
                    "id": str(uuid.uuid4()),
                    "data": {"title": ""},
                }
            ]
        )
    ).json()
    assert bad[0]["status"] == "rejected"

    # journal conflicts never overwrite
    jid = str(uuid.uuid4())
    await push(
        [
            {
                "change_id": "j-00000001",
                "entity": "journal_entries",
                "op": "upsert",
                "id": jid,
                "data": {"content": "first"},
            }
        ]
    )
    await push(
        [
            {
                "change_id": "j-00000002",
                "entity": "journal_entries",
                "op": "upsert",
                "id": jid,
                "base_version": 1,
                "data": {"content": "edit on phone A"},
            }
        ]
    )
    r = (
        await push(
            [
                {
                    "change_id": "j-00000003",
                    "entity": "journal_entries",
                    "op": "upsert",
                    "id": jid,
                    "base_version": 1,
                    "data": {"content": "edit on phone B"},
                }
            ]
        )
    ).json()
    assert r[0]["status"] == "conflict" and "copy" in r[0]["error"]

    pulled = (await client.get(f"{API}/sync/pull", headers=user["h"])).json()
    assert len(pulled["changes"]["tasks"]) == 1 and len(pulled["changes"]["journal_entries"]) == 2

    await push([{"change_id": "d-00000001", "entity": "tasks", "op": "delete", "id": tid, "base_version": 2}])
    later = (
        await client.get(f"{API}/sync/pull", params={"since": pulled["cursor"]}, headers=user["h"])
    ).json()
    assert later["changes"]["tasks"][0]["deleted_at"] is not None  # tombstone syncs


async def test_habit_log_via_sync(client, user):
    h = (await client.post(f"{API}/habits", json={"title": "Water"}, headers=user["h"])).json()
    r = (
        await client.post(
            f"{API}/sync/push",
            json={
                "changes": [
                    {
                        "change_id": "h-00000001",
                        "entity": "habit_logs",
                        "op": "upsert",
                        "id": str(uuid.uuid4()),
                        "data": {
                            "habit_id": h["id"],
                            "log_date": local_today("Asia/Kolkata").isoformat(),
                            "status": "done",
                        },
                    }
                ]
            },
            headers=user["h"],
        )
    ).json()
    assert r[0]["status"] == "applied", r
    habit = (await client.get(f"{API}/habits/{h['id']}", headers=user["h"])).json()
    assert habit["current_streak"] == 1
