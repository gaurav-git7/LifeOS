"""Tool registry — the only actions the agent can propose. ARCHITECTURE.md §12.5.

Each tool has: a strict argument model, a validator (ownership, no past
dates), a human summary for the approval card, and an executor that calls
the same module code the HTTP API uses. No raw SQL, no deletes, no auth
changes, no journal edits.
"""

import uuid
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from typing import Literal
from zoneinfo import ZoneInfo

from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core.crud import create_entity, get_owned, update_entity
from ...core.errors import AppError
from ...core.recurrence import validate_rrule
from ...core.time import local_today
from ...core.types import utcnow
from ...models import Goal, LearningTopic, Project, Skill, Task, User
from ..goals.router import GoalCreate, GoalUpdate, goal_spec
from ..habits.router import HabitCreate
from ..habits.router import spec as habit_spec
from ..learning.router import PathCreate, SkillCreate, TopicCreate, path_spec, skill_spec, topic_spec
from ..planner.router import BlockCreate, ReminderCreate, block_spec, reminder_spec
from ..tasks.router import TaskCreate, TaskUpdate
from ..tasks.router import spec as task_spec

Priority = Literal["low", "medium", "high"]


def _not_past_dt(v: datetime | None) -> None:
    if v is not None and v < utcnow() - timedelta(minutes=5):
        raise AppError("invalid_action", "That time is in the past.", 422)


def _not_past_date(user: User, v: date | None) -> None:
    if v is not None and v < local_today(user.timezone):
        raise AppError("invalid_action", "That date is in the past.", 422)


async def _own(db: AsyncSession, model, obj_id, user: User, label: str) -> None:
    if obj_id is not None:
        await get_owned(db, model, obj_id, user.id, label=label)


# ---------- argument models ----------


class CreateTaskArgs(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None
    priority: Priority = "medium"
    due_at: datetime | None = None
    due_date: date | None = None
    estimated_minutes: int | None = Field(default=None, ge=0, le=1440)
    goal_id: uuid.UUID | None = None
    project_id: uuid.UUID | None = None
    recurrence_rule: str | None = None
    tags: list[str] = Field(default_factory=list, max_length=10)

    @field_validator("recurrence_rule")
    @classmethod
    def _rrule(cls, v):
        return validate_rrule(v)


class UpdateTaskArgs(BaseModel):
    task_id: uuid.UUID
    title: str | None = Field(default=None, min_length=1, max_length=200)
    priority: Priority | None = None
    due_at: datetime | None = None
    due_date: date | None = None
    estimated_minutes: int | None = Field(default=None, ge=0, le=1440)
    status: Literal["todo", "in_progress", "cancelled"] | None = None


class RescheduleItem(BaseModel):
    task_id: uuid.UUID
    due_at: datetime | None = None
    due_date: date | None = None

    @model_validator(mode="after")
    def _one(self):
        if self.due_at is None and self.due_date is None:
            raise ValueError("due_at or due_date required")
        return self


class RescheduleArgs(BaseModel):
    items: list[RescheduleItem] = Field(min_length=1, max_length=20)


class CreateGoalArgs(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None
    category: Literal["learning", "career", "health", "personal", "finance", "other"] = "personal"
    progress_type: Literal["numeric", "milestones", "tasks", "boolean"] = "tasks"
    target_value: float | None = Field(default=None, ge=0)
    unit: str | None = Field(default=None, max_length=24)
    target_date: date | None = None


class AdjustGoalArgs(BaseModel):
    goal_id: uuid.UUID
    title: str | None = Field(default=None, min_length=1, max_length=200)
    target_value: float | None = Field(default=None, ge=0)
    target_date: date | None = None


class CreateReminderArgs(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    remind_at: datetime
    task_id: uuid.UUID | None = None


class ScheduleBlockArgs(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    start_at: datetime
    end_at: datetime
    block_type: Literal["task", "study", "focus", "break", "other"] = "task"
    task_id: uuid.UUID | None = None
    topic_id: uuid.UUID | None = None

    @model_validator(mode="after")
    def _order(self):
        if self.end_at <= self.start_at:
            raise ValueError("end_at must be after start_at")
        if self.end_at - self.start_at > timedelta(hours=8):
            raise ValueError("blocks are at most 8 hours")
        return self


class PlanTopic(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None
    difficulty: Literal["easy", "medium", "hard"] = "medium"
    estimated_minutes: int | None = Field(default=None, ge=0, le=10_000)


class CreateLearningPathArgs(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None
    target_date: date | None = None
    skill_name: str | None = Field(default=None, max_length=80)
    topics: list[PlanTopic] = Field(min_length=1, max_length=40)


class CreateHabitArgs(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    recurrence_rule: str = "FREQ=DAILY"
    reminder_time: time | None = None

    @field_validator("recurrence_rule")
    @classmethod
    def _rrule(cls, v):
        return validate_rrule(v) or "FREQ=DAILY"


# ---------- validators & executors ----------


async def v_create_task(db, user, a: CreateTaskArgs):
    _not_past_dt(a.due_at)
    _not_past_date(user, a.due_date)
    await _own(db, Goal, a.goal_id, user, "Goal")
    await _own(db, Project, a.project_id, user, "Project")


async def x_create_task(db, user, a: CreateTaskArgs) -> dict:
    task, _ = await create_entity(
        db, task_spec, user, TaskCreate(**a.model_dump(exclude_none=True), source="agent")
    )
    return {"task_id": str(task.id)}


async def v_update_task(db, user, a: UpdateTaskArgs):
    await _own(db, Task, a.task_id, user, "Task")
    _not_past_dt(a.due_at)
    _not_past_date(user, a.due_date)


async def x_update_task(db, user, a: UpdateTaskArgs) -> dict:
    changes = a.model_dump(exclude_none=True, exclude={"task_id"})
    await update_entity(db, task_spec, user, a.task_id, TaskUpdate(**changes))
    return {"task_id": str(a.task_id)}


async def v_reschedule(db, user, a: RescheduleArgs):
    for it in a.items:
        await _own(db, Task, it.task_id, user, "Task")
        _not_past_dt(it.due_at)
        _not_past_date(user, it.due_date)


async def x_reschedule(db, user, a: RescheduleArgs) -> dict:
    for it in a.items:
        await update_entity(
            db,
            task_spec,
            user,
            it.task_id,
            TaskUpdate(**it.model_dump(exclude_none=True, exclude={"task_id"})),
        )
    return {"task_ids": [str(it.task_id) for it in a.items]}


async def v_create_goal(db, user, a: CreateGoalArgs):
    _not_past_date(user, a.target_date)


async def x_create_goal(db, user, a: CreateGoalArgs) -> dict:
    goal, _ = await create_entity(
        db,
        goal_spec,
        user,
        GoalCreate(**a.model_dump(exclude_none=True), start_date=local_today(user.timezone)),
    )
    return {"goal_id": str(goal.id)}


async def v_adjust_goal(db, user, a: AdjustGoalArgs):
    await _own(db, Goal, a.goal_id, user, "Goal")
    _not_past_date(user, a.target_date)


async def x_adjust_goal(db, user, a: AdjustGoalArgs) -> dict:
    await update_entity(
        db, goal_spec, user, a.goal_id, GoalUpdate(**a.model_dump(exclude_none=True, exclude={"goal_id"}))
    )
    return {"goal_id": str(a.goal_id)}


async def v_reminder(db, user, a: CreateReminderArgs):
    _not_past_dt(a.remind_at)
    await _own(db, Task, a.task_id, user, "Task")


async def x_reminder(db, user, a: CreateReminderArgs) -> dict:
    r, _ = await create_entity(db, reminder_spec, user, ReminderCreate(**a.model_dump(exclude_none=True)))
    return {"reminder_id": str(r.id)}


async def v_block(db, user, a: ScheduleBlockArgs):
    _not_past_dt(a.start_at)
    await _own(db, Task, a.task_id, user, "Task")
    await _own(db, LearningTopic, a.topic_id, user, "Topic")


async def x_block(db, user, a: ScheduleBlockArgs) -> dict:
    b, _ = await create_entity(
        db, block_spec, user, BlockCreate(**a.model_dump(exclude_none=True), source="agent")
    )
    return {"block_id": str(b.id)}


async def v_path(db, user, a: CreateLearningPathArgs):
    _not_past_date(user, a.target_date)


async def x_path(db, user, a: CreateLearningPathArgs) -> dict:
    skill_id = None
    if a.skill_name:
        skill = await db.scalar(
            select(Skill).where(
                Skill.user_id == user.id,
                Skill.deleted_at.is_(None),
                func.lower(Skill.name) == a.skill_name.lower(),
            )
        )
        if skill is None:
            skill, _ = await create_entity(db, skill_spec, user, SkillCreate(name=a.skill_name))
        skill_id = skill.id
    path, _ = await create_entity(
        db,
        path_spec,
        user,
        PathCreate(title=a.title, description=a.description, target_date=a.target_date, source="agent"),
    )
    topic_ids = []
    for i, t in enumerate(a.topics):
        topic, _ = await create_entity(
            db,
            topic_spec,
            user,
            TopicCreate(
                learning_path_id=path.id,
                skill_id=skill_id,
                title=t.title,
                description=t.description,
                difficulty=t.difficulty,
                estimated_minutes=t.estimated_minutes,
                sort_order=i,
            ),
        )
        topic_ids.append(str(topic.id))
    return {
        "learning_path_id": str(path.id),
        "skill_id": str(skill_id) if skill_id else None,
        "topic_ids": topic_ids,
    }


async def v_none(db, user, a) -> None:
    return None


async def x_habit(db, user, a: CreateHabitArgs) -> dict:
    h, _ = await create_entity(db, habit_spec, user, HabitCreate(**a.model_dump(exclude_none=True)))
    return {"habit_id": str(h.id)}


# ---------- registry ----------


@dataclass(frozen=True)
class Tool:
    name: str
    args: type[BaseModel]
    summary: Callable[[BaseModel, ZoneInfo], str]  # (args, user's timezone)
    validate: Callable[[AsyncSession, User, BaseModel], Awaitable[None]]
    execute: Callable[[AsyncSession, User, BaseModel], Awaitable[dict]]


def _when(a, z: ZoneInfo) -> str:
    if getattr(a, "due_at", None):
        return f" · due {a.due_at.astimezone(z):%a %d %b, %H:%M}"
    if getattr(a, "due_date", None):
        return f" · due {a.due_date:%a %d %b}"
    return ""


TOOLS: dict[str, Tool] = {
    t.name: t
    for t in [
        Tool(
            "create_task",
            CreateTaskArgs,
            lambda a, z: f"Create task “{a.title}”{_when(a, z)}",
            v_create_task,
            x_create_task,
        ),
        Tool("update_task", UpdateTaskArgs, lambda a, z: "Update a task", v_update_task, x_update_task),
        Tool(
            "reschedule_tasks",
            RescheduleArgs,
            lambda a, z: f"Reschedule {len(a.items)} task(s)",
            v_reschedule,
            x_reschedule,
        ),
        Tool(
            "create_goal",
            CreateGoalArgs,
            lambda a, z: f"Create goal “{a.title}”",
            v_create_goal,
            x_create_goal,
        ),
        Tool("adjust_goal", AdjustGoalArgs, lambda a, z: "Adjust a goal", v_adjust_goal, x_adjust_goal),
        Tool(
            "create_reminder",
            CreateReminderArgs,
            lambda a, z: f"Remind you “{a.title}” · {a.remind_at.astimezone(z):%a %d %b, %H:%M}",
            v_reminder,
            x_reminder,
        ),
        Tool(
            "schedule_block",
            ScheduleBlockArgs,
            lambda a, z: (
                f"Block {a.start_at.astimezone(z):%a %H:%M}–{a.end_at.astimezone(z):%H:%M} for “{a.title}”"
            ),
            v_block,
            x_block,
        ),
        Tool(
            "create_learning_path",
            CreateLearningPathArgs,
            lambda a, z: f"Create roadmap “{a.title}” with {len(a.topics)} topics",
            v_path,
            x_path,
        ),
        Tool("create_habit", CreateHabitArgs, lambda a, z: f"Start habit “{a.title}”", v_none, x_habit),
    ]
}


def resolve(tool_name: str) -> Tool:
    name = tool_name.strip().removeprefix("propose_")
    tool = TOOLS.get(name)
    if tool is None:
        raise AppError("unknown_tool", f"Unknown action “{tool_name}”.", 422)
    return tool
