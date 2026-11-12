"""Agent: rule path, fake-LLM path, approval security, groups, budget, memory."""

import uuid
from datetime import timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select

from app.core.time import local_today
from app.models import LearningTopic, LlmCall, Task, User
from app.modules.agent.intent import parse_capture
from app.modules.agent.proposals import create_proposal

from .conftest import API


async def test_rule_path_needs_no_llm(client, user, session):
    r = (
        await client.post(
            f"{API}/agent/chat", json={"message": "add task buy milk tomorrow"}, headers=user["h"]
        )
    ).json()
    assert r["used_ai"] is False
    p = r["proposals"][0]
    assert p["action_type"] == "create_task" and p["payload"]["title"] == "Buy milk"
    assert p["payload"]["due_date"] == (local_today("Asia/Kolkata") + timedelta(days=1)).isoformat()
    async with session() as db:
        assert await db.scalar(select(LlmCall.id)) is None


async def test_llm_path_proposes_and_approval_executes(client, user, session):
    r = (
        await client.post(f"{API}/agent/chat", json={"message": "help me learn docker"}, headers=user["h"])
    ).json()
    assert r["used_ai"] is True
    p = r["proposals"][0]
    assert p["action_type"] == "create_learning_path" and p["status"] == "pending"

    # nothing exists before approval
    async with session() as db:
        assert await db.scalar(select(LearningTopic.id)) is None

    bad = await client.post(
        f"{API}/agent/proposals/{p['id']}/approve", json={"payload_hash": "x" * 64}, headers=user["h"]
    )
    assert bad.json()["error"]["code"] == "payload_changed"

    ok = (
        await client.post(
            f"{API}/agent/proposals/{p['id']}/approve",
            json={"payload_hash": p["payload_hash"]},
            headers=user["h"],
        )
    ).json()
    assert ok["status"] == "executed" and len(ok["result"]["topic_ids"]) == 3
    again = await client.post(
        f"{API}/agent/proposals/{p['id']}/approve",
        json={"payload_hash": p["payload_hash"]},
        headers=user["h"],
    )
    assert again.status_code == 409  # can't execute twice

    async with session() as db:
        call = await db.scalar(select(LlmCall))
        assert call.status == "ok" and call.prompt_version == "chat-v1"
    conv = (
        await client.get(f"{API}/agent/conversations/{r['conversation_id']}/messages", headers=user["h"])
    ).json()
    assert [m["role"] for m in conv] == ["user", "assistant"]


async def test_edit_reject_and_other_users_cannot_approve(client, user):
    from .conftest import auth, register

    p = (
        await client.post(f"{API}/agent/chat", json={"message": "add task read a book"}, headers=user["h"])
    ).json()["proposals"][0]
    edited = (
        await client.patch(
            f"{API}/agent/proposals/{p['id']}", json={"arguments": {"priority": "high"}}, headers=user["h"]
        )
    ).json()
    assert edited["payload"]["priority"] == "high" and edited["payload_hash"] != p["payload_hash"]

    other = auth(await register(client, "b@example.com", "B"))
    r = await client.post(
        f"{API}/agent/proposals/{p['id']}/approve",
        json={"payload_hash": edited["payload_hash"]},
        headers=other,
    )
    assert r.status_code == 404

    await client.post(f"{API}/agent/proposals/{p['id']}/reject", headers=user["h"])
    r = await client.post(
        f"{API}/agent/proposals/{p['id']}/approve",
        json={"payload_hash": edited["payload_hash"]},
        headers=user["h"],
    )
    assert r.json()["error"]["code"] == "proposal_rejected"


async def test_past_dates_and_foreign_ids_are_rejected(client, user):
    p = await client.post(f"{API}/agent/chat", json={"message": "add task old thing"}, headers=user["h"])
    pid = p.json()["proposals"][0]["id"]
    r = await client.patch(
        f"{API}/agent/proposals/{pid}", json={"arguments": {"due_date": "2001-01-01"}}, headers=user["h"]
    )
    assert r.json()["error"]["code"] == "invalid_action"
    r = await client.patch(
        f"{API}/agent/proposals/{pid}", json={"arguments": {"goal_id": str(uuid.uuid4())}}, headers=user["h"]
    )
    assert r.status_code == 404


async def test_group_approval_is_all_or_nothing(client, user, session):
    gid = uuid.uuid4()
    async with session() as db:
        me = await db.scalar(select(User))
        a = await create_proposal(
            db, me, "create_task", {"title": "One"}, reason=None, origin="chat", group_id=gid
        )
        b = await create_proposal(
            db, me, "create_task", {"title": "Two"}, reason=None, origin="chat", group_id=gid
        )
        t = Task(user_id=me.id, title="Victim")
        db.add(t)
        await db.flush()
        c = await create_proposal(
            db,
            me,
            "update_task",
            {"task_id": str(t.id), "priority": "high"},
            reason=None,
            origin="chat",
            group_id=gid,
        )
        hashes = {str(x.id): x.payload_hash for x in (a, b, c)}
        await db.delete(t)  # makes proposal c invalid at execution time
        await db.commit()

    r = await client.post(
        f"{API}/agent/proposal-groups/{gid}/approve", json={"payload_hashes": hashes}, headers=user["h"]
    )
    assert r.json()["error"]["code"] == "group_failed"
    async with session() as db:
        assert (await db.execute(select(Task))).scalars().all() == []  # nothing applied

    r = await client.post(
        f"{API}/agent/proposal-groups/{gid}/approve",
        json={"payload_hashes": hashes, "exclude": [str(c.id)]},
        headers=user["h"],
    )
    assert r.status_code == 200 and len(r.json()) == 2
    async with session() as db:
        titles = sorted(t.title for t in (await db.execute(select(Task))).scalars())
    assert titles == ["One", "Two"]


async def test_budget_blocks_llm_but_app_still_answers(client, user, session):
    await client.patch(f"{API}/users/me/preferences", json={"ai_daily_budget_usd": 0}, headers=user["h"])
    r = (
        await client.post(
            f"{API}/agent/chat", json={"message": "how am i doing this week?"}, headers=user["h"]
        )
    ).json()
    assert r["used_ai"] is False and "budget" in r["message"]
    async with session() as db:
        assert (await db.scalar(select(LlmCall))).status == "blocked_by_budget"


async def test_ai_disabled(client, user):
    await client.patch(f"{API}/users/me/preferences", json={"ai_enabled": False}, headers=user["h"])
    r = await client.post(f"{API}/agent/chat", json={"message": "hi"}, headers=user["h"])
    assert r.json()["error"]["code"] == "ai_disabled"


async def test_quick_capture_and_memories(client, user):
    p = (
        await client.post(
            f"{API}/agent/quick-capture", json={"text": "study graphs tomorrow 7pm"}, headers=user["h"]
        )
    ).json()
    assert p["payload"]["title"] == "Study graphs" and p["payload"]["due_at"].endswith("+05:30")

    m = (
        await client.post(
            f"{API}/agent/memories", json={"content": "Prefers morning study"}, headers=user["h"]
        )
    ).json()
    assert m["status"] == "active"
    await client.patch(f"{API}/agent/memories/{m['id']}", json={"importance": 5}, headers=user["h"])
    await client.delete(f"{API}/agent/memories/{m['id']}", headers=user["h"])
    assert (await client.get(f"{API}/agent/memories", headers=user["h"])).json() == []


async def test_learning_plan_job(client, user):
    job = (
        await client.post(
            f"{API}/agent/jobs",
            json={"job_type": "learning_path_plan", "input": {"subject": "Kubernetes", "weeks": 4}},
            headers=user["h"],
        )
    ).json()
    done = (await client.get(f"{API}/agent/jobs/{job['id']}", headers=user["h"])).json()
    assert done["status"] == "done", done
    pending = (await client.get(f"{API}/agent/proposals", headers=user["h"])).json()
    assert pending[0]["action_type"] == "create_learning_path"


def test_parse_capture():
    from datetime import datetime

    now = datetime(2026, 11, 12, 10, 0, tzinfo=ZoneInfo("Asia/Kolkata"))  # Thursday
    p = parse_capture("call mom today at 6:30 pm", now)
    assert p.title == "Call mom" and p.due_at.hour == 18 and p.due_at.minute == 30
    p = parse_capture("revise SQL on monday", now)
    assert p.due_date.isoformat() == "2026-11-16" and p.due_at is None
    p = parse_capture("solve 3 problems", now)
    assert p.title == "Solve 3 problems" and p.due_date is None
