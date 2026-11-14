"""The single LifeOS agent. ARCHITECTURE.md §12.1.

chat:          rules first → context → ONE structured Gemini call → validate → proposals
quick_capture: rules only (no LLM)
daily/weekly:  stats in Python → skip LLM when nothing happened → one call → proposals
jobs:          long AI work (learning-path plans) run in the background
"""

import json
import logging
import uuid
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core.config import settings
from ...core.database import session_factory
from ...core.errors import AppError
from ...core.serialize import jsonable
from ...core.time import local_now, local_today, week_start
from ...core.types import utcnow
from ...models import (
    ActionProposal,
    AgentConversation,
    AgentJob,
    AgentMemory,
    AgentMessage,
    DailySummary,
    LearningTopic,
    Task,
    User,
    UserPreferences,
    WeeklySummary,
)
from ...notifications.push import notify
from ..analytics.service import day_stats, learning_overview, priorities, save_daily_summary, week_stats
from . import prompts
from .context import build, guess_intent, recent_messages, render_prompt
from .intent import parse_capture, parse_command
from .llm_client import BudgetExceeded, LLMFailed, call_llm
from .memory import replace_summary, save_suggestions
from .proposals import create_proposal
from .schemas import LLMAction, LLMOutput, LLMReview

log = logging.getLogger("lifeos.agent")


async def _prefs(db: AsyncSession, user: User) -> UserPreferences:
    prefs = await db.get(UserPreferences, user.id)
    if prefs is None:
        prefs = UserPreferences(user_id=user.id)
        db.add(prefs)
        await db.flush()
    return prefs


async def _proposals_from_actions(
    db: AsyncSession,
    user: User,
    actions: list[LLMAction],
    *,
    origin: str,
    conversation_id=None,
    limit: int = 20,
) -> tuple[list[ActionProposal], list[str]]:
    """Validates each LLM action; invalid ones are dropped (and reported), never executed."""
    group_id = uuid.uuid4() if len(actions) > 1 else None
    created, errors = [], []
    for a in actions[:limit]:
        try:
            args = json.loads(a.arguments_json or "{}")
            if not isinstance(args, dict):
                raise ValueError("arguments must be an object")
            async with db.begin_nested():
                p = await create_proposal(
                    db,
                    user,
                    a.tool,
                    args,
                    reason=a.reason,
                    origin=origin,
                    conversation_id=conversation_id,
                    group_id=group_id,
                )
            created.append(p)
        except (AppError, ValueError) as e:
            errors.append(f"{a.tool}: {getattr(e, 'message', str(e))}")
    if len(created) == 1:
        created[0].group_id = None
    return created, errors


# ---------- chat ----------


async def chat(db: AsyncSession, user: User, message: str, conversation_id: uuid.UUID | None) -> dict:
    prefs = await _prefs(db, user)
    if not prefs.ai_enabled:
        raise AppError("ai_disabled", "The assistant is turned off in settings.", 403)

    if conversation_id:
        conv = await db.get(AgentConversation, conversation_id)
        if conv is None or conv.user_id != user.id or conv.deleted_at:
            raise AppError("not_found", "Conversation not found.", 404)
    else:
        conv = AgentConversation(user_id=user.id, title=message[:60])
        db.add(conv)
        await db.flush()
    history = await recent_messages(db, conv.id)
    db.add(AgentMessage(user_id=user.id, conversation_id=conv.id, role="user", content=message))

    now = local_now(user.timezone)
    proposals: list[ActionProposal] = []
    memories: list[AgentMemory] = []
    follow_up, used_ai, meta = None, False, {}

    command = parse_command(message, now)
    if command:  # rule path: no LLM
        intent = command[0]
        try:
            p = await create_proposal(
                db,
                user,
                command[0],
                command[1],
                reason="You asked for this.",
                origin="chat",
                conversation_id=conv.id,
            )
            proposals.append(p)
            reply = "Here it is — approve to add it."
        except AppError as e:
            reply = f"I couldn't set that up: {e.message}"
    else:
        intent = guess_intent(message)
        ctx, untrusted = await build(db, user, intent, message)
        try:
            res = await call_llm(
                db,
                user,
                purpose="chat",
                prompt_version=prompts.CHAT_VERSION,
                system=prompts.CHAT_SYSTEM,
                prompt=render_prompt(ctx, untrusted, history, message),
                schema=LLMOutput,
                tier="lite" if intent == "general" and len(message) < 60 else "default",
            )
            used_ai = True
            out: LLMOutput = res.parsed
            intent, reply = out.intent or intent, out.message
            follow_up = out.follow_up_question or None
            proposals, errors = await _proposals_from_actions(
                db, user, out.actions, origin="chat", conversation_id=conv.id
            )
            memories = await save_suggestions(db, user, out.memory_suggestions, source_id=conv.id)
            meta = {"llm_call_id": str(res.call.id), "confidence": out.confidence, "dropped_actions": errors}
        except BudgetExceeded:
            reply = (
                "I've used today's AI budget, so I can't think this one through right now. "
                "Everything else in LifeOS still works, and I'll be back tomorrow."
            )
        except LLMFailed as e:
            reply = {
                "quota": "I've hit the AI usage limit for now. Try again in a little while.",
                "key": "The assistant isn't set up correctly on the server (AI key problem).",
                "model": "The assistant isn't set up correctly on the server (AI model unavailable).",
                "output": "I got muddled answering that. Could you rephrase it?",
                "slow": "The AI took too long to answer. Try again, or ask something shorter.",
                "slow_down": "That's a lot of messages at once. Give me a minute, then try again.",
                "daily_limit": (
                    f"You've used today's {settings.AI_CALLS_PER_DAY} assistant messages. "
                    "It resets tomorrow; everything else in LifeOS still works."
                ),
            }.get(e.kind, "I couldn't reach the AI just now. Please try again in a moment.")
            if user.role == "admin":  # the owner sees the real reason
                reply += "\n\n[admin] " + f"{e.kind}: {str(e)[:300]}"

    assistant = AgentMessage(
        user_id=user.id,
        conversation_id=conv.id,
        role="assistant",
        content=reply,
        meta=jsonable(
            {"intent": intent, "proposal_ids": [p.id for p in proposals], "follow_up": follow_up, **meta}
        ),
    )
    db.add(assistant)
    conv.last_message_at = utcnow()
    conv.version += 1
    await db.flush()
    return {
        "conversation_id": conv.id,
        "message_id": assistant.id,
        "intent": intent,
        "message": reply,
        "proposals": proposals,
        "memory_suggestions": memories,
        "follow_up_question": follow_up,
        "used_ai": used_ai,
    }


async def quick_capture(db: AsyncSession, user: User, text: str) -> ActionProposal:
    p = parse_capture(text, local_now(user.timezone))
    args: dict = {"title": p.title}
    if p.due_at:
        args["due_at"] = p.due_at.isoformat()
    elif p.due_date:
        args["due_date"] = p.due_date.isoformat()
    return await create_proposal(
        db, user, "create_task", args, reason="From quick capture.", origin="quick_capture"
    )


# ---------- reviews ----------


def _template_insight(stats: dict) -> str:
    if not any(stats[k] for k in ("tasks_done", "tasks_open", "habits_due", "study_minutes")):
        return "A quiet day. Rest counts too — tomorrow is a fresh start."
    bits = []
    if stats["tasks_done"]:
        bits.append(f"you finished {stats['tasks_done']} task{'s' * (stats['tasks_done'] != 1)}")
    if stats["habits_due"]:
        bits.append(f"kept {stats['habits_done']} of {stats['habits_due']} habits")
    if stats["study_minutes"]:
        bits.append(f"studied {stats['study_minutes']} minutes")
    text = ("Today " + ", ".join(bits) + ".") if bits else "Today was light on progress."
    if stats["tasks_overdue"]:
        text += f" {stats['tasks_overdue']} task(s) are overdue — pick one to move or drop."
    return text


async def daily_review(
    db: AsyncSession, user: User, day: date | None = None, *, force_ai: bool = False
) -> DailySummary:
    """Saves today's summary + insight (+ up to 3 proposals). At most one LLM call."""
    prefs = await _prefs(db, user)
    day = day or local_today(user.timezone)
    summary = await save_daily_summary(db, user, day)
    stats = await day_stats(db, user, day)
    meaningful = any(stats[k] for k in ("tasks_done", "tasks_open", "habits_due", "study_minutes"))
    review: dict = {"done": True, "highlights": [], "attention": [], "used_ai": False}
    insight = _template_insight(stats)

    if prefs.ai_enabled and (meaningful or force_ai):
        tomorrow = day + timedelta(days=1)
        overdue = (
            await db.execute(
                select(Task)
                .where(
                    Task.user_id == user.id,
                    Task.deleted_at.is_(None),
                    Task.status.in_(["todo", "in_progress"]),
                    (Task.due_date < day) | (Task.due_at < utcnow()),
                )
                .limit(10)
            )
        ).scalars()
        revisions = await db.scalar(
            select(LearningTopic.id)
            .where(LearningTopic.user_id == user.id, LearningTopic.next_revision_at <= tomorrow)
            .limit(1)
        )
        ctx = {
            "today": day.isoformat(),
            "tomorrow": tomorrow.isoformat(),
            "timezone": user.timezone,
            "stats": stats,
            "priorities_tomorrow": [
                {"id": str(t.id), "title": t.title, "priority": t.priority}
                for t in await priorities(db, user, 5)
            ],
            "overdue": [{"id": str(t.id), "title": t.title} for t in overdue],
            "revisions_due": bool(revisions),
        }
        if prefs.mood_ai_enabled:
            ctx["mood_avg"] = stats["mood_avg"]
        else:
            ctx["stats"] = {k: v for k, v in stats.items() if k not in ("mood_avg", "energy_avg")}
        try:
            res = await call_llm(
                db,
                user,
                purpose="daily_review",
                prompt_version=prompts.DAILY_VERSION,
                system=prompts.DAILY_SYSTEM,
                prompt=render_prompt(jsonable(ctx), [], [], "Daily review"),
                schema=LLMReview,
                tier="default",
            )
            out: LLMReview = res.parsed
            insight = out.insight
            proposals, _ = await _proposals_from_actions(
                db, user, out.actions, origin="daily_review", limit=3
            )
            review.update(
                highlights=out.highlights[:5],
                attention=out.attention[:5],
                used_ai=True,
                proposal_ids=[str(p.id) for p in proposals],
            )
        except (BudgetExceeded, LLMFailed):
            pass

    summary.ai_insight = insight
    summary.stats = {**(summary.stats or {}), "review": review}
    await notify(
        db,
        user,
        "review",
        "Your daily review is ready",
        insight[:140],
        dedupe_key=f"daily_review:{user.id}:{day}",
    )
    return summary


async def weekly_review(db: AsyncSession, user: User, start: date | None = None) -> WeeklySummary:
    prefs = await _prefs(db, user)
    start = start or week_start(local_today(user.timezone) - timedelta(days=6), prefs.week_start_day)
    stats = await week_stats(db, user, start)
    if not prefs.mood_ai_enabled:
        stats_for_ai = {
            **stats,
            "totals": {k: v for k, v in stats["totals"].items() if k != "mood_avg"},
            "days": [
                {k: v for k, v in d.items() if k not in ("mood_avg", "energy_avg")} for d in stats["days"]
            ],
        }
    else:
        stats_for_ai = stats
    row = await db.scalar(
        select(WeeklySummary).where(WeeklySummary.user_id == user.id, WeeklySummary.week_start == start)
    )
    if row is None:
        row = WeeklySummary(user_id=user.id, week_start=start, week_end=start + timedelta(days=6))
        db.add(row)
    row.stats = stats
    t = stats["totals"]
    report = (
        f"This week: {t['tasks_done']} tasks done, {t['study_minutes']} minutes of study"
        + (f", {round(t['habit_consistency'] * 100)}% habit consistency" if t["habit_consistency"] else "")
        + "."
    )
    recs: list[str] = []
    if prefs.ai_enabled:
        ctx = {
            "week_start": start.isoformat(),
            "today": local_today(user.timezone).isoformat(),
            "timezone": user.timezone,
            "stats": stats_for_ai,
            "learning": await learning_overview(db, user),
        }
        try:
            res = await call_llm(
                db,
                user,
                purpose="weekly_review",
                prompt_version=prompts.WEEKLY_VERSION,
                system=prompts.WEEKLY_SYSTEM,
                prompt=render_prompt(jsonable(ctx), [], [], "Weekly review"),
                schema=LLMReview,
                tier="default",
            )
            out: LLMReview = res.parsed
            report, recs = out.insight, out.attention[:4]
            await _proposals_from_actions(db, user, out.actions, origin="weekly_review", limit=4)
            await replace_summary(db, user, f"Week of {start}: {out.insight}")
        except (BudgetExceeded, LLMFailed):
            pass
    row.ai_report, row.recommendations, row.generated_at = report, recs, utcnow()
    await notify(
        db,
        user,
        "review",
        "Your weekly review is ready",
        report[:140],
        dedupe_key=f"weekly_review:{user.id}:{start}",
    )
    return row


# ---------- background jobs ----------


async def run_job(job_id: uuid.UUID) -> None:
    """Executes one agent job in its own session (BackgroundTasks / sweeper)."""
    async with session_factory()() as db:
        job = await db.scalar(select(AgentJob).where(AgentJob.id == job_id).with_for_update(skip_locked=True))
        if job is None or job.status not in ("pending", "running"):
            return
        job.status, job.started_at, job.attempts = "running", utcnow(), job.attempts + 1
        await db.commit()
        user = await db.get(User, job.user_id)
        try:
            assert user is not None
            if job.job_type != "learning_path_plan":
                raise AppError("unknown_job", "Unknown job type.")
            inp = job.input or {}
            subject = str(inp.get("subject") or inp.get("skill") or "a new skill")[:120]
            message = (
                f"Make a learning roadmap for {subject}. Weeks: {inp.get('weeks', 4)}. "
                f"Hours per week: {inp.get('hours_per_week', 6)}. Current level: {inp.get('level', 'beginner')}."
            )
            ctx, _ = await build(db, user, "learning_plan", message)
            res = await call_llm(
                db,
                user,
                purpose="learning_plan",
                prompt_version=prompts.PLAN_VERSION,
                system=prompts.PLAN_SYSTEM,
                prompt=render_prompt(ctx, [], [], message),
                schema=LLMOutput,
                tier="default",
            )
            proposals, errors = await _proposals_from_actions(
                db, user, res.parsed.actions, origin="agent_job"
            )
            if not proposals:
                raise AppError("plan_failed", "The plan couldn't be turned into valid suggestions.")
            job.result = jsonable(
                {
                    "message": res.parsed.message,
                    "proposal_ids": [p.id for p in proposals],
                    "group_id": proposals[0].group_id,
                    "dropped": errors,
                }
            )
            job.status = "done"
            await notify(
                db,
                user,
                "agent_job",
                "Your plan is ready",
                res.parsed.message[:140],
                dedupe_key=f"job:{job.id}",
                data={"job_id": str(job.id)},
            )
        except (AppError, BudgetExceeded, LLMFailed, AssertionError) as e:
            job.status = "failed"
            job.error = getattr(e, "message", None) or (
                "AI budget reached" if isinstance(e, BudgetExceeded) else str(e) or type(e).__name__
            )
        job.finished_at = utcnow()
        await db.commit()


async def sweep_jobs() -> int:
    """Restart jobs that never started or got stuck (e.g. after a restart)."""
    now = utcnow()
    async with session_factory()() as db:
        ids = list(
            (
                await db.execute(
                    select(AgentJob.id)
                    .where(
                        ((AgentJob.status == "pending") & (AgentJob.created_at < now - timedelta(minutes=1)))
                        | (
                            (AgentJob.status == "running")
                            & (AgentJob.started_at < now - timedelta(minutes=5))
                        ),
                        AgentJob.attempts < 3,
                    )
                    .limit(10)
                )
            ).scalars()
        )
    for job_id in ids:
        await run_job(job_id)
    return len(ids)
