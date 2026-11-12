"""Tasks, goals, habits, learning, journal: CRUD, isolation, XP, events."""

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.core.time import local_today
from app.models import ActivityEvent, Task, UserAchievement

from .conftest import API, auth, register


def today() -> str:
    return local_today("Asia/Kolkata").isoformat()


async def test_user_isolation(client, user):
    other = auth(await register(client, "b@example.com", "B"))
    task = (await client.post(f"{API}/tasks", json={"title": "Mine"}, headers=user["h"])).json()
    goal = (await client.post(f"{API}/goals", json={"title": "My goal"}, headers=user["h"])).json()

    assert (await client.get(f"{API}/tasks/{task['id']}", headers=other)).status_code == 404
    assert (
        await client.patch(f"{API}/tasks/{task['id']}", json={"title": "x"}, headers=other)
    ).status_code == 404
    assert (await client.delete(f"{API}/tasks/{task['id']}", headers=other)).status_code == 404
    assert (await client.get(f"{API}/tasks", headers=other)).json()["items"] == []
    r = await client.post(f"{API}/tasks", json={"title": "sneaky", "goal_id": goal["id"]}, headers=other)
    assert r.json()["error"]["code"] == "invalid_reference"
    # client-chosen id that belongs to someone else
    r = await client.post(f"{API}/tasks", json={"id": task["id"], "title": "steal"}, headers=other)
    assert r.status_code == 409


async def test_task_crud_idempotency_and_versioning(client, user):
    tid = str(uuid.uuid4())
    a = await client.post(f"{API}/tasks", json={"id": tid, "title": "Write tests"}, headers=user["h"])
    b = await client.post(f"{API}/tasks", json={"id": tid, "title": "Write tests"}, headers=user["h"])
    assert a.json()["id"] == b.json()["id"] == tid
    assert len((await client.get(f"{API}/tasks", headers=user["h"])).json()["items"]) == 1

    r = await client.patch(
        f"{API}/tasks/{tid}", json={"priority": "high"}, headers={**user["h"], "If-Match": "1"}
    )
    assert r.json()["version"] == 2
    stale = await client.patch(
        f"{API}/tasks/{tid}", json={"priority": "low"}, headers={**user["h"], "If-Match": "1"}
    )
    assert stale.status_code == 412

    assert (await client.delete(f"{API}/tasks/{tid}", headers=user["h"])).status_code == 204
    assert (await client.get(f"{API}/tasks", headers=user["h"])).json()["items"] == []
    tomb = (await client.get(f"{API}/tasks?include_deleted=true", headers=user["h"])).json()["items"]
    assert tomb[0]["deleted_at"] is not None


async def test_complete_task_awards_xp_processes_events_and_unlocks(client, user, session):
    t = (
        await client.post(f"{API}/tasks", json={"title": "Ship", "priority": "high"}, headers=user["h"])
    ).json()
    done = await client.post(f"{API}/tasks/{t['id']}/complete", headers=user["h"])
    assert done.json()["status"] == "done" and done.json()["completed_at"]

    prog = (await client.get(f"{API}/progression", headers=user["h"])).json()
    assert prog["total_xp"] == 30
    unlocked = [a["code"] for a in prog["achievements"] if a["unlocked_at"]]
    assert "first_light" in unlocked

    async with session() as db:
        statuses = set((await db.execute(select(ActivityEvent.status))).scalars())
        assert statuses == {"done"}  # fast path processed everything
        assert await db.scalar(select(UserAchievement.id))

    await client.post(f"{API}/tasks/{t['id']}/reopen", headers=user["h"])
    assert (await client.get(f"{API}/progression", headers=user["h"])).json()["total_xp"] == 0
    await client.post(f"{API}/tasks/{t['id']}/complete", headers=user["h"])
    assert (await client.get(f"{API}/progression", headers=user["h"])).json()["total_xp"] == 30


async def test_recurring_task_creates_next_instance(client, user, session):
    t = (
        await client.post(
            f"{API}/tasks",
            json={"title": "Revise", "due_date": today(), "recurrence_rule": "FREQ=DAILY"},
            headers=user["h"],
        )
    ).json()
    await client.patch(f"{API}/tasks/{t['id']}", json={"status": "done"}, headers=user["h"])
    async with session() as db:
        open_tasks = list((await db.execute(select(Task).where(Task.status == "todo"))).scalars())
    assert len(open_tasks) == 1
    assert open_tasks[0].due_date.isoformat() > today()


async def test_invalid_rrule_rejected(client, user):
    r = await client.post(
        f"{API}/tasks", json={"title": "x", "recurrence_rule": "FREQ=SOMETIMES"}, headers=user["h"]
    )
    assert r.status_code == 422


async def test_goal_progress_by_tasks_and_milestones(client, user):
    g = (
        await client.post(f"{API}/goals", json={"title": "DSA", "progress_type": "tasks"}, headers=user["h"])
    ).json()
    t1 = (
        await client.post(f"{API}/tasks", json={"title": "a", "goal_id": g["id"]}, headers=user["h"])
    ).json()
    await client.post(f"{API}/tasks", json={"title": "b", "goal_id": g["id"]}, headers=user["h"])
    await client.post(f"{API}/tasks/{t1['id']}/complete", headers=user["h"])
    prog = (await client.get(f"{API}/goals/progress", headers=user["h"])).json()
    assert prog[0]["progress"] == 0.5

    g2 = (
        await client.post(
            f"{API}/goals", json={"title": "Docker", "progress_type": "milestones"}, headers=user["h"]
        )
    ).json()
    m = (
        await client.post(
            f"{API}/goal-milestones", json={"goal_id": g2["id"], "title": "Images"}, headers=user["h"]
        )
    ).json()
    await client.post(f"{API}/goal-milestones/{m['id']}/complete", headers=user["h"])
    prog = {
        p["title"]: p["progress"]
        for p in (await client.get(f"{API}/goals/progress", headers=user["h"])).json()
    }
    assert prog["Docker"] == 1.0

    r = await client.patch(f"{API}/goals/{g['id']}", json={"status": "completed"}, headers=user["h"])
    assert r.json()["completed_at"]


async def test_habit_logging_and_streaks(client, user):
    h = (await client.post(f"{API}/habits", json={"title": "Read"}, headers=user["h"])).json()
    r = await client.put(f"{API}/habits/{h['id']}/logs/{today()}", json={"status": "done"}, headers=user["h"])
    assert r.status_code == 200
    habit = (await client.get(f"{API}/habits/{h['id']}", headers=user["h"])).json()
    assert habit["current_streak"] == 1

    today_list = (await client.get(f"{API}/habits/today", headers=user["h"])).json()
    assert today_list[0]["today_status"] == "done"

    tomorrow = (local_today("Asia/Kolkata") + timedelta(days=1)).isoformat()
    future = await client.put(f"{API}/habits/{h['id']}/logs/{tomorrow}", json={}, headers=user["h"])
    assert future.json()["error"]["code"] == "future_date"

    await client.delete(f"{API}/habits/{h['id']}/logs/{today()}", headers=user["h"])
    assert (await client.get(f"{API}/habits/{h['id']}", headers=user["h"])).json()["current_streak"] == 0
    assert (await client.get(f"{API}/progression", headers=user["h"])).json()["total_xp"] == 0


async def test_learning_path_topics_and_study_xp_cap(client, user):
    path = (await client.post(f"{API}/learning/paths", json={"title": "Java DSA"}, headers=user["h"])).json()
    topics = []
    for i, title in enumerate(["Arrays", "Hashing"]):
        topics.append(
            (
                await client.post(
                    f"{API}/learning/topics",
                    json={
                        "learning_path_id": path["id"],
                        "title": title,
                        "sort_order": i,
                        "difficulty": "easy",
                        "resources": [{"title": "docs", "url": "https://example.com/x"}],
                    },
                    headers=user["h"],
                )
            ).json()
        )
    ordered = (await client.get(f"{API}/learning/paths/{path['id']}/topics", headers=user["h"])).json()
    assert [t["title"] for t in ordered] == ["Arrays", "Hashing"]

    for t in topics:
        r = await client.post(f"{API}/learning/topics/{t['id']}/complete", headers=user["h"])
        assert r.json()["next_revision_at"]
    assert (await client.get(f"{API}/learning/paths/{path['id']}", headers=user["h"])).json()[
        "status"
    ] == "completed"

    r = await client.post(f"{API}/learning/topics/{topics[0]['id']}/revise", headers=user["h"])
    assert r.json()["revision_count"] == 1

    xp_before = (await client.get(f"{API}/progression", headers=user["h"])).json()["total_xp"]
    now = datetime.now(UTC)
    for _ in range(2):  # 2 x 120 minutes, capped at 180 XP per day
        r = await client.post(
            f"{API}/study-sessions",
            json={"started_at": now.isoformat(), "duration_minutes": 120},
            headers=user["h"],
        )
        assert r.status_code == 201, r.text
    xp_after = (await client.get(f"{API}/progression", headers=user["h"])).json()["total_xp"]
    assert xp_after - xp_before == 180


async def test_journal_and_mood(client, user):
    j = (
        await client.post(
            f"{API}/journal", json={"content": "Finally understood DP today"}, headers=user["h"]
        )
    ).json()
    assert j["entry_date"] == today() and j["word_count"] == 4 and j["ai_allowed"] is False
    j2 = (await client.post(f"{API}/journal", json={"content": "Second entry"}, headers=user["h"])).json()
    assert j2["id"]
    m = await client.post(
        f"{API}/mood",
        json={"recorded_at": datetime.now(UTC).isoformat(), "mood": 4, "energy": 7},
        headers=user["h"],
    )
    assert m.status_code == 201
    assert (
        await client.post(
            f"{API}/mood", json={"recorded_at": datetime.now(UTC).isoformat(), "mood": 9}, headers=user["h"]
        )
    ).status_code == 422
    # journal XP once per day + mood XP once per day
    assert (await client.get(f"{API}/progression", headers=user["h"])).json()["total_xp"] == 10


async def test_schedule_and_reminders(client, user):
    start = datetime.now(UTC) + timedelta(hours=1)
    b = await client.post(
        f"{API}/schedule",
        json={
            "title": "Focus",
            "start_at": start.isoformat(),
            "end_at": (start + timedelta(hours=1)).isoformat(),
        },
        headers=user["h"],
    )
    assert b.status_code == 201
    bad = await client.post(
        f"{API}/schedule",
        json={"title": "x", "start_at": start.isoformat(), "end_at": start.isoformat()},
        headers=user["h"],
    )
    assert bad.status_code == 422
    r = await client.post(
        f"{API}/reminders", json={"title": "Stretch", "remind_at": start.isoformat()}, headers=user["h"]
    )
    assert r.json()["delivery"] == "local"


async def test_dashboard_weekly_export_and_delete(client, user):
    await client.post(
        f"{API}/tasks", json={"title": "Top", "priority": "high", "due_date": today()}, headers=user["h"]
    )
    d = (await client.get(f"{API}/dashboard/today", headers=user["h"])).json()
    assert d["priorities"][0]["title"] == "Top"
    assert {"stats", "habits", "learning", "goals", "progression", "pending_proposals"} <= d.keys()

    w = (await client.get(f"{API}/analytics/weekly", headers=user["h"])).json()
    assert len(w["days"]) == 7

    export = (await client.get(f"{API}/users/me/export", headers=user["h"])).json()
    assert export["tasks"][0]["title"] == "Top"

    assert (await client.delete(f"{API}/users/me", headers=user["h"])).status_code == 204
    assert (await client.get(f"{API}/users/me", headers=user["h"])).status_code == 401


async def test_preferences(client, user):
    p = (await client.get(f"{API}/users/me/preferences", headers=user["h"])).json()
    assert p["mood_ai_enabled"] is False and p["journal_ai_enabled"] is False  # private by default
    r = await client.patch(
        f"{API}/users/me/preferences",
        json={"daily_review_time": "20:30:00", "ambient_intensity": "low"},
        headers=user["h"],
    )
    assert r.json()["daily_review_time"] == "20:30:00"
