"""Reminders (fired on the phone) and schedule blocks (reserved time)."""

import uuid
from datetime import date, datetime
from typing import Literal

from fastapi import APIRouter
from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy import select

from ...core.crud import CrudSpec, EntityRead, crud_router
from ...core.deps import DB, CurrentUser
from ...core.recurrence import validate_rrule
from ...core.time import day_bounds_utc, local_today
from ...models import Habit, LearningTopic, Reminder, ScheduleBlock, Task

# ---------- reminders ----------


class ReminderBase(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    task_id: uuid.UUID | None = None
    habit_id: uuid.UUID | None = None
    remind_at: datetime
    recurrence_rule: str | None = None
    delivery: Literal["local", "push"] = "local"
    status: Literal["scheduled", "fired", "cancelled"] = "scheduled"

    @field_validator("recurrence_rule")
    @classmethod
    def _rrule(cls, v):
        return validate_rrule(v)


class ReminderCreate(ReminderBase):
    id: uuid.UUID | None = None


class ReminderUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    remind_at: datetime | None = None
    recurrence_rule: str | None = None
    delivery: Literal["local", "push"] | None = None
    status: Literal["scheduled", "fired", "cancelled"] | None = None

    @field_validator("recurrence_rule")
    @classmethod
    def _rrule(cls, v):
        return validate_rrule(v)


class ReminderRead(ReminderBase, EntityRead):
    pass


reminder_spec = CrudSpec(
    model=Reminder,
    create_schema=ReminderCreate,
    update_schema=ReminderUpdate,
    read_schema=ReminderRead,
    label="Reminder",
    refs={"task_id": Task, "habit_id": Habit},
    filter_fields=("status", "task_id", "habit_id"),
)

# ---------- schedule blocks ----------

BlockType = Literal["task", "study", "focus", "break", "other"]


class BlockBase(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    task_id: uuid.UUID | None = None
    topic_id: uuid.UUID | None = None
    start_at: datetime
    end_at: datetime
    block_type: BlockType = "task"
    status: Literal["planned", "done", "skipped"] = "planned"
    source: Literal["manual", "agent"] = "manual"

    @model_validator(mode="after")
    def _order(self):
        if self.end_at <= self.start_at:
            raise ValueError("end_at must be after start_at")
        return self


class BlockCreate(BlockBase):
    id: uuid.UUID | None = None


class BlockUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    start_at: datetime | None = None
    end_at: datetime | None = None
    block_type: BlockType | None = None
    status: Literal["planned", "done", "skipped"] | None = None


class BlockRead(BlockBase, EntityRead):
    pass


block_spec = CrudSpec(
    model=ScheduleBlock,
    create_schema=BlockCreate,
    update_schema=BlockUpdate,
    read_schema=BlockRead,
    label="Schedule block",
    refs={"task_id": Task, "topic_id": LearningTopic},
    filter_fields=("status", "block_type", "task_id"),
)

router = APIRouter(tags=["planner"])


@router.get("/schedule/day", response_model=list[BlockRead], summary="Schedule blocks for a local day")
async def schedule_for_day(db: DB, user: CurrentUser, day: date | None = None):
    day = day or local_today(user.timezone)
    start, end = day_bounds_utc(day, user.timezone)
    rows = (
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
    return [BlockRead.model_validate(r) for r in rows]


router.include_router(crud_router(reminder_spec, "/reminders", ["planner"]))
router.include_router(crud_router(block_spec, "/schedule", ["planner"]))
