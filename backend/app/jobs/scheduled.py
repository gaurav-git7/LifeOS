"""Scheduled jobs. Plain async functions — the trigger (pg_cron → HTTP) is
separate, so swapping to Celery/ARQ later only changes the trigger.
ARCHITECTURE.md §11.

All jobs are *catch-up* style: if the server was asleep at the exact hour,
the next run still does the work, and nothing runs twice.
"""

import logging
from datetime import timedelta

from sqlalchemy import delete, select

from ..core.database import session_factory
from ..core.recurrence import is_due_on
from ..core.time import local_now, local_today, week_start
from ..core.types import utcnow
from ..events.dispatcher import process_event_by_id
from ..models import (
    ActivityEvent,
    DailySummary,
    EmailToken,
    Habit,
    HabitLog,
    IdempotencyKey,
    NotificationLog,
    RefreshToken,
    User,
    UserPreferences,
    WeeklySummary,
)
from ..modules.agent import orchestrator
from ..modules.agent.proposals import expire_stale
from ..modules.analytics.service import save_daily_summary
from ..modules.habits.router import habit_start, recompute_streak

log = logging.getLogger("lifeos.jobs")


async def _users() -> list:
    async with session_factory()() as db:
        return list((await db.execute(select(User.id).where(User.status == "active"))).scalars())


async def _dispatch(db) -> None:
    ids = db.info.pop("pending_event_ids", [])
    for event_id in ids:
        await process_event_by_id(event_id)


async def daily_summaries() -> int:
    """Yesterday's summary + mark missed habits. Runs hourly; does each day once."""
    done = 0
    for user_id in await _users():
        async with session_factory()() as db:
            try:
                user = await db.get(User, user_id)
                yesterday = local_today(user.timezone) - timedelta(days=1)
                exists = await db.scalar(
                    select(DailySummary.id).where(
                        DailySummary.user_id == user.id, DailySummary.summary_date == yesterday
                    )
                )
                if exists:
                    continue
                habits = list(
                    (
                        await db.execute(
                            select(Habit).where(
                                Habit.user_id == user.id, Habit.deleted_at.is_(None), Habit.active.is_(True)
                            )
                        )
                    ).scalars()
                )
                for h in habits:
                    if not is_due_on(h.recurrence_rule, habit_start(h, user), yesterday):
                        continue
                    logged = await db.scalar(
                        select(HabitLog.id).where(HabitLog.habit_id == h.id, HabitLog.log_date == yesterday)
                    )
                    if not logged:
                        db.add(HabitLog(user_id=user.id, habit_id=h.id, log_date=yesterday, status="missed"))
                        await db.flush()
                        await recompute_streak(db, user, h)
                await save_daily_summary(db, user, yesterday)
                await db.commit()
                done += 1
            except Exception:  # noqa: BLE001
                await db.rollback()
                log.exception("daily summary failed for %s", user_id)
    return done


async def daily_reviews() -> int:
    """Runs each user's daily review once, at/after their chosen time."""
    done = 0
    for user_id in await _users():
        async with session_factory()() as db:
            try:
                user = await db.get(User, user_id)
                prefs = await db.get(UserPreferences, user.id)
                if prefs is None or not prefs.daily_review_enabled:
                    continue
                now = local_now(user.timezone)
                if now.time() < prefs.daily_review_time:
                    continue
                row = await db.scalar(
                    select(DailySummary).where(
                        DailySummary.user_id == user.id, DailySummary.summary_date == now.date()
                    )
                )
                if row is not None and (row.stats or {}).get("review", {}).get("done"):
                    continue
                await orchestrator.daily_review(db, user, now.date())
                await db.commit()
                await _dispatch(db)
                done += 1
            except Exception:  # noqa: BLE001
                await db.rollback()
                log.exception("daily review failed for %s", user_id)
    return done


async def weekly_reviews() -> int:
    done = 0
    for user_id in await _users():
        async with session_factory()() as db:
            try:
                user = await db.get(User, user_id)
                prefs = await db.get(UserPreferences, user.id)
                if prefs is None or not prefs.weekly_review_enabled:
                    continue
                now = local_now(user.timezone)
                if now.isoweekday() != prefs.weekly_review_day or now.time() < prefs.daily_review_time:
                    continue
                start = week_start(now.date(), prefs.week_start_day)
                if await db.scalar(
                    select(WeeklySummary.id).where(
                        WeeklySummary.user_id == user.id, WeeklySummary.week_start == start
                    )
                ):
                    continue
                await orchestrator.weekly_review(db, user, start)
                await db.commit()
                done += 1
            except Exception:  # noqa: BLE001
                await db.rollback()
                log.exception("weekly review failed for %s", user_id)
    return done


async def cleanup() -> dict:
    now = utcnow()
    async with session_factory()() as db:
        expired = await expire_stale(db)
        r1 = await db.execute(delete(EmailToken).where(EmailToken.expires_at < now - timedelta(days=7)))
        r2 = await db.execute(delete(RefreshToken).where(RefreshToken.expires_at < now - timedelta(days=7)))
        r3 = await db.execute(
            delete(IdempotencyKey).where(IdempotencyKey.created_at < now - timedelta(hours=48))
        )
        r4 = await db.execute(
            delete(ActivityEvent).where(
                ActivityEvent.status == "done", ActivityEvent.occurred_at < now - timedelta(days=180)
            )
        )
        r5 = await db.execute(
            delete(NotificationLog).where(NotificationLog.created_at < now - timedelta(days=180))
        )
        await db.commit()
    return {
        "proposals_expired": expired,
        "email_tokens": r1.rowcount,
        "refresh_tokens": r2.rowcount,
        "idempotency_keys": r3.rowcount,
        "events": r4.rowcount,
        "notifications": r5.rowcount,
    }
