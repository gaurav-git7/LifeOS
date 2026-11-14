"""Crash reports, feedback, release announcements, and that friends can't see
each other's data through sync, memories or suggestions."""

import uuid

from sqlalchemy import select

from app.models import ClientReport, NotificationLog

from .conftest import API, auth, register

JOB = {"X-Job-Secret": "test-job-secret"}


async def test_crash_reports_are_deduplicated(client, user, session):
    body = {"message": "Null check operator", "stack": "#0 main\n#1 run", "app_version": "0.1.0"}
    for _ in range(3):
        assert (await client.post(f"{API}/client-errors", json=body, headers=user["h"])).status_code == 204
    await client.post(f"{API}/client-errors", json={**body, "message": "Other"}, headers=user["h"])
    async with session() as db:
        rows = (await db.execute(select(ClientReport).order_by(ClientReport.count.desc()))).scalars().all()
    assert [(r.message, r.count) for r in rows] == [("Null check operator", 3), ("Other", 1)]


async def test_feedback_notifies_admin_and_only_admins_list_reports(client, user, session):
    friend = auth(await register(client, "friend@example.com", "Maitrey"))  # first user is admin
    r = await client.post(
        f"{API}/feedback", json={"kind": "bug", "message": "Calendar is slow"}, headers=friend
    )
    assert r.status_code == 201
    async with session() as db:
        logs = (
            (await db.execute(select(NotificationLog).where(NotificationLog.kind == "feedback")))
            .scalars()
            .all()
        )
    assert len(logs) == 1 and "Maitrey" in logs[0].title

    assert (await client.get(f"{API}/admin/reports", headers=friend)).status_code == 403
    reports = (await client.get(f"{API}/admin/reports", headers=user["h"])).json()
    assert reports[0]["message"] == "Calendar is slow"


async def test_announce_release_targets_old_versions_once(client, user, session):
    friend = auth(await register(client, "friend@example.com", "Maitrey"))
    await client.post(
        f"{API}/devices", json={"fcm_token": "token-admin-123", "app_version": "0.2.0"}, headers=user["h"]
    )
    await client.post(
        f"{API}/devices", json={"fcm_token": "token-friend-12", "app_version": "0.1.0+3"}, headers=friend
    )
    body = {"version": "0.2.0", "url": "https://github.com/x/y/releases/tag/v0.2.0"}
    assert (await client.post("/internal/jobs/announce-release", json=body)).status_code in (401, 403)
    for _ in range(2):
        assert (
            await client.post("/internal/jobs/announce-release", json=body, headers=JOB)
        ).status_code == 200
    async with session() as db:
        logs = (
            (await db.execute(select(NotificationLog).where(NotificationLog.kind == "update")))
            .scalars()
            .all()
        )
    # Only the friend is behind, and only once (FCM isn't configured in tests, so it's logged as skipped).
    assert len(logs) == 1 and logs[0].title == "LifeOS 0.2.0 is ready"


async def test_sync_never_leaks_or_overwrites_other_users_rows(client, user):
    other = auth(await register(client, "b@example.com", "B"))
    tid = str(uuid.uuid4())
    push = {
        "changes": [
            {
                "change_id": "mine-0001",
                "entity": "tasks",
                "op": "upsert",
                "id": tid,
                "data": {"title": "Mine"},
            }
        ]
    }
    assert (await client.post(f"{API}/sync/push", json=push, headers=user["h"])).json()[0][
        "status"
    ] == "applied"

    pulled = (await client.get(f"{API}/sync/pull", headers=other)).json()["changes"]
    assert all(not rows for rows in pulled.values())

    steal = {
        "changes": [
            {
                "change_id": "steal-001",
                "entity": "tasks",
                "op": "upsert",
                "id": tid,
                "base_version": 1,
                "data": {"title": "x"},
            },
            {"change_id": "steal-002", "entity": "tasks", "op": "delete", "id": tid},
        ]
    }
    results = (await client.post(f"{API}/sync/push", json=steal, headers=other)).json()
    assert [r["status"] for r in results] == ["rejected", "rejected"]
    mine = (await client.get(f"{API}/tasks/{tid}", headers=user["h"])).json()
    assert mine["title"] == "Mine" and mine["deleted_at"] is None


async def test_memories_and_proposals_are_private(client, user):
    other = auth(await register(client, "b@example.com", "B"))
    m = (
        await client.post(f"{API}/agent/memories", json={"content": "I like mornings"}, headers=user["h"])
    ).json()
    await client.post(f"{API}/agent/chat", json={"message": "add task call mom tomorrow"}, headers=user["h"])

    assert (await client.get(f"{API}/agent/memories", headers=other)).json() == []
    assert (await client.get(f"{API}/agent/proposals", headers=other)).json() == []
    assert (await client.get(f"{API}/agent/conversations", headers=other)).json() == []
    assert (await client.delete(f"{API}/agent/memories/{m['id']}", headers=other)).status_code == 404
    assert len((await client.get(f"{API}/agent/memories", headers=user["h"])).json()) == 1


async def test_times_per_week_habit_streak_counts_weeks(client, user, session):
    from datetime import date, timedelta

    from app.models import Habit

    h = (
        await client.post(
            f"{API}/habits",
            json={"title": "Gym", "recurrence_rule": "FREQ=WEEKLY", "target_per_period": 2},
            headers=user["h"],
        )
    ).json()
    async with session() as db:  # pretend it started three weeks ago
        row = await db.get(Habit, uuid.UUID(h["id"]))
        row.created_at = row.created_at - timedelta(days=21)
        await db.commit()
    today = date.today()
    last_mon = today - timedelta(days=today.weekday() + 7)
    for d in (last_mon, last_mon + timedelta(days=3)):  # 2 of 2 last week
        r = await client.put(f"{API}/habits/{h['id']}/logs/{d}", json={"status": "done"}, headers=user["h"])
        assert r.status_code == 200, r.text
    habit = (await client.get(f"{API}/habits/{h['id']}", headers=user["h"])).json()
    assert habit["current_streak"] == 1  # this week isn't over, so it doesn't break it


async def test_ai_rate_limit_per_person(client, user, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "AI_CALLS_PER_MINUTE", 1)
    friend = auth(await register(client, "f@example.com", "Friend"))  # not admin
    msg = {"message": "How should I balance study and gym this week?"}
    first = (await client.post(f"{API}/agent/chat", json=msg, headers=friend)).json()
    second = (await client.post(f"{API}/agent/chat", json=msg, headers=friend)).json()
    assert first["used_ai"] is True
    assert "Give me a minute" in second["message"]
    for _ in range(2):  # the admin (first user) isn't limited
        r = (await client.post(f"{API}/agent/chat", json=msg, headers=user["h"])).json()
        assert "Give me a minute" not in r["message"]
