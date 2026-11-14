"""Habits, daily logs and streaks. ARCHITECTURE.md §8.4 B."""

import uuid
from datetime import date, time, timedelta
from typing import Literal

from fastapi import APIRouter, BackgroundTasks
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core.crud import CrudSpec, EntityRead, crud_router, get_owned
from ...core.deps import DB, CurrentUser
from ...core.errors import AppError
from ...core.recurrence import is_due_on, is_weekly_target, validate_rrule
from ...core.time import local_today, tz
from ...core.types import utcnow
from ...events.outbox import commit_and_dispatch, emit
from ...models import Habit, HabitLog, User
from ..progression.service import XP, award_xp, revoke_xp, stable_id

LogStatus = Literal["done", "skipped", "missed"]


class HabitBase(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    description: str | None = None
    recurrence_rule: str = "FREQ=DAILY"
    target_per_period: int = Field(default=1, ge=1, le=31)
    reminder_time: time | None = None
    color: str | None = Field(default=None, max_length=16)
    icon: str | None = Field(default=None, max_length=32)
    active: bool = True
    visibility: Literal["private", "friends"] = "private"

    @field_validator("recurrence_rule")
    @classmethod
    def _rrule(cls, v):
        return validate_rrule(v) or "FREQ=DAILY"


class HabitCreate(HabitBase):
    id: uuid.UUID | None = None


class HabitUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = None
    recurrence_rule: str | None = None
    target_per_period: int | None = Field(default=None, ge=1, le=31)
    reminder_time: time | None = None
    color: str | None = None
    icon: str | None = None
    active: bool | None = None
    visibility: Literal["private", "friends"] | None = None

    @field_validator("recurrence_rule")
    @classmethod
    def _rrule(cls, v):
        return validate_rrule(v)


class HabitRead(HabitBase, EntityRead):
    current_streak: int
    best_streak: int


class HabitLogIn(BaseModel):
    status: LogStatus = "done"
    note: str | None = Field(default=None, max_length=1000)


class HabitLogRead(EntityRead):
    habit_id: uuid.UUID
    log_date: date
    status: str
    note: str | None


def habit_start(habit: Habit, user: User) -> date:
    return habit.created_at.astimezone(tz(user.timezone)).date()


async def recompute_streak(db: AsyncSession, user: User, habit: Habit) -> int:
    """Consecutive due days completed, counting back from today.
    Today not done yet doesn't break the streak; 'skipped' days are neutral."""
    today = local_today(user.timezone)
    since = today - timedelta(days=400)
    logs = {
        log.log_date: log.status
        for log in (
            await db.execute(
                select(HabitLog).where(
                    HabitLog.habit_id == habit.id, HabitLog.deleted_at.is_(None), HabitLog.log_date >= since
                )
            )
        ).scalars()
    }
    start = habit_start(habit, user)
    if is_weekly_target(habit.recurrence_rule):
        # "N times a week": streak = consecutive weeks (Mon–Sun) with N done.
        # The current week only counts once it's met, and never breaks the streak.
        target = max(habit.target_per_period or 1, 1)
        streak, wk = 0, today - timedelta(days=today.weekday())
        while wk + timedelta(days=6) >= max(start, since):
            done = sum(1 for d, s in logs.items() if s == "done" and wk <= d <= wk + timedelta(days=6))
            if done >= target:
                streak += 1
            elif wk + timedelta(days=6) < today:
                break
            wk -= timedelta(days=7)
        habit.current_streak = streak
        habit.best_streak = max(habit.best_streak, streak)
        return streak
    streak, day = 0, today
    while day >= max(start, since):
        if is_due_on(habit.recurrence_rule, start, day):
            status = logs.get(day)
            if status == "done":
                streak += 1
            elif status == "skipped":
                pass
            elif day == today:
                pass  # still time today
            else:
                break
        day -= timedelta(days=1)
    habit.current_streak = streak
    habit.best_streak = max(habit.best_streak, streak)
    return streak


async def log_habit(
    db: AsyncSession, user: User, habit: Habit, day: date, status: str, note: str | None
) -> HabitLog:
    if day > local_today(user.timezone):
        raise AppError("future_date", "You can't log a habit for a future day.", 422)
    log = await db.scalar(select(HabitLog).where(HabitLog.habit_id == habit.id, HabitLog.log_date == day))
    previous = log.status if log and not log.deleted_at else None
    if log is None:
        log = HabitLog(user_id=user.id, habit_id=habit.id, log_date=day, status=status, note=note)
        db.add(log)
        await db.flush()
    else:
        log.status, log.note, log.deleted_at = status, note, None
        log.version += 1
        log.updated_at = utcnow()

    if status == "done" and previous != "done":
        await award_xp(db, user, XP["habit"], "habit.logged", source_type="habit_log", source_id=log.id)
    elif status != "done" and previous == "done":
        await revoke_xp(db, user, "habit.logged", log.id)

    streak = await recompute_streak(db, user, habit)
    habit.version += 1
    for n, key in ((7, "habit_streak_7"), (30, "habit_streak_30")):
        if status == "done" and streak and streak % n == 0:
            await award_xp(
                db,
                user,
                XP[key],
                f"habit.streak{n}",
                source_type="habit",
                source_id=stable_id(habit.id, n, day),
            )
    emit(
        db,
        user.id,
        "habit.logged",
        entity_type="habit",
        entity_id=habit.id,
        payload={"date": day, "status": status, "streak": streak},
    )
    return log


spec = CrudSpec(
    model=Habit,
    create_schema=HabitCreate,
    update_schema=HabitUpdate,
    read_schema=HabitRead,
    label="Habit",
    filter_fields=("active",),
)

router = APIRouter(tags=["habits"])


@router.put(
    "/habits/{habit_id}/logs/{day}", response_model=HabitLogRead, summary="Log a habit for a day (idempotent)"
)
async def put_log(
    habit_id: uuid.UUID, day: date, body: HabitLogIn, db: DB, user: CurrentUser, bg: BackgroundTasks
):
    habit = await get_owned(db, Habit, habit_id, user.id, label="Habit")
    log = await log_habit(db, user, habit, day, body.status, body.note)
    await commit_and_dispatch(db, bg)
    return HabitLogRead.model_validate(log)


@router.delete("/habits/{habit_id}/logs/{day}", status_code=204, summary="Remove a day's log")
async def delete_log(habit_id: uuid.UUID, day: date, db: DB, user: CurrentUser):
    habit = await get_owned(db, Habit, habit_id, user.id, label="Habit")
    log = await db.scalar(select(HabitLog).where(HabitLog.habit_id == habit.id, HabitLog.log_date == day))
    if log and not log.deleted_at:
        if log.status == "done":
            await revoke_xp(db, user, "habit.logged", log.id)
        log.deleted_at = utcnow()
        log.version += 1
        await recompute_streak(db, user, habit)
        await db.commit()


@router.get("/habits/{habit_id}/logs", response_model=list[HabitLogRead], summary="Habit history")
async def list_logs(
    habit_id: uuid.UUID, db: DB, user: CurrentUser, start: date | None = None, end: date | None = None
):
    await get_owned(db, Habit, habit_id, user.id, label="Habit")
    end = end or local_today(user.timezone)
    start = start or end - timedelta(days=90)
    rows = (
        await db.execute(
            select(HabitLog)
            .where(
                HabitLog.habit_id == habit_id,
                HabitLog.deleted_at.is_(None),
                HabitLog.log_date >= start,
                HabitLog.log_date <= end,
            )
            .order_by(HabitLog.log_date)
        )
    ).scalars()
    return [HabitLogRead.model_validate(r) for r in rows]


@router.get("/habits/today", summary="Habits due today with today's status")
async def habits_today(db: DB, user: CurrentUser):
    today = local_today(user.timezone)
    habits = list(
        (
            await db.execute(
                select(Habit).where(
                    Habit.user_id == user.id, Habit.deleted_at.is_(None), Habit.active.is_(True)
                )
            )
        ).scalars()
    )
    logs = {
        log.habit_id: log.status
        for log in (
            await db.execute(
                select(HabitLog).where(
                    HabitLog.user_id == user.id, HabitLog.log_date == today, HabitLog.deleted_at.is_(None)
                )
            )
        ).scalars()
    }
    return [
        {**HabitRead.model_validate(h).model_dump(mode="json"), "today_status": logs.get(h.id)}
        for h in habits
        if is_due_on(h.recurrence_rule, habit_start(h, user), today)
    ]


router.include_router(crud_router(spec, "/habits", ["habits"]))
