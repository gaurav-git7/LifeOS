from datetime import date

from fastapi import APIRouter
from sqlalchemy import select

from ...core.deps import DB, CurrentUser
from ...core.time import local_today, week_start
from ...models import Habit, ScheduleBlock, UserPreferences
from ..goals.router import active_goal_progress
from ..habits.router import habits_today
from ..planner.router import BlockRead
from ..progression.service import level_info
from ..tasks.router import TaskRead
from . import service

router = APIRouter(tags=["analytics"])


@router.get("/dashboard/today", summary="Everything the Home screen needs in one call")
async def dashboard_today(db: DB, user: CurrentUser):
    today = local_today(user.timezone)
    from ...core.time import day_bounds_utc

    start, end = day_bounds_utc(today, user.timezone)
    blocks = (
        await db.execute(
            select(ScheduleBlock)
            .where(
                ScheduleBlock.user_id == user.id,
                ScheduleBlock.deleted_at.is_(None),
                ScheduleBlock.start_at < end,
                ScheduleBlock.end_at > start,
            )
            .order_by(ScheduleBlock.start_at)
        )
    ).scalars()
    return {
        "date": today,
        "stats": await service.day_stats(db, user, today),
        "priorities": [TaskRead.model_validate(t) for t in await service.priorities(db, user)],
        "schedule": [BlockRead.model_validate(b) for b in blocks],
        "habits": await habits_today(db, user),
        "learning": await service.learning_overview(db, user),
        "goals": await active_goal_progress(db, user),
        "progression": level_info(user.total_xp),
        "insight": await service.latest_insight(db, user),
        "pending_proposals": await service.pending_proposals_count(db, user),
        "best_streak": max(
            [
                h.current_streak
                for h in (
                    await db.execute(
                        select(Habit).where(Habit.user_id == user.id, Habit.deleted_at.is_(None))
                    )
                ).scalars()
            ],
            default=0,
        ),
    }


@router.get("/analytics/daily")
async def daily(db: DB, user: CurrentUser, day: date | None = None):
    return await service.day_stats(db, user, day or local_today(user.timezone))


@router.get("/analytics/weekly")
async def weekly(db: DB, user: CurrentUser, start: date | None = None):
    prefs = await db.get(UserPreferences, user.id)
    ws = start or week_start(local_today(user.timezone), prefs.week_start_day if prefs else 1)
    return await service.week_stats(db, user, ws)


@router.get("/analytics/streaks")
async def streaks(db: DB, user: CurrentUser):
    rows = (
        await db.execute(
            select(Habit)
            .where(Habit.user_id == user.id, Habit.deleted_at.is_(None))
            .order_by(Habit.current_streak.desc())
        )
    ).scalars()
    return [
        {"habit_id": h.id, "title": h.title, "current_streak": h.current_streak, "best_streak": h.best_streak}
        for h in rows
    ]


@router.get("/analytics/ai-usage")
async def ai_usage(db: DB, user: CurrentUser):
    return await service.ai_usage(db, user)
