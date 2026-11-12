"""Tasks. Completion awards XP, emits events and creates the next instance of
recurring tasks. ARCHITECTURE.md §8.4 B, §10.3."""

import uuid
from datetime import date, datetime, time
from typing import Literal

from fastapi import BackgroundTasks
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.ext.asyncio import AsyncSession

from ...core.crud import CrudSpec, EntityRead, crud_router, get_owned
from ...core.deps import DB, CurrentUser
from ...core.recurrence import next_after, validate_rrule
from ...core.time import tz
from ...core.types import utcnow
from ...events.outbox import commit_and_dispatch, emit
from ...models import Goal, Project, Task, User
from ..progression.service import XP, award_xp, revoke_xp

Status = Literal["todo", "in_progress", "done", "cancelled"]
Priority = Literal["low", "medium", "high"]


class TaskBase(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None
    status: Status = "todo"
    priority: Priority = "medium"
    due_at: datetime | None = None
    due_date: date | None = None
    estimated_minutes: int | None = Field(default=None, ge=0, le=24 * 60)
    actual_minutes: int | None = Field(default=None, ge=0, le=24 * 60)
    goal_id: uuid.UUID | None = None
    project_id: uuid.UUID | None = None
    parent_task_id: uuid.UUID | None = None
    recurrence_rule: str | None = None
    tags: list[str] = Field(default_factory=list, max_length=20)
    source: Literal["manual", "agent", "quick_capture"] = "manual"
    sort_order: int = 0

    @field_validator("recurrence_rule")
    @classmethod
    def _check_rrule(cls, v):
        return validate_rrule(v)


class TaskCreate(TaskBase):
    id: uuid.UUID | None = None


class TaskUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = None
    status: Status | None = None
    priority: Priority | None = None
    due_at: datetime | None = None
    due_date: date | None = None
    estimated_minutes: int | None = Field(default=None, ge=0, le=24 * 60)
    actual_minutes: int | None = Field(default=None, ge=0, le=24 * 60)
    goal_id: uuid.UUID | None = None
    project_id: uuid.UUID | None = None
    recurrence_rule: str | None = None
    tags: list[str] | None = None
    sort_order: int | None = None

    @field_validator("recurrence_rule")
    @classmethod
    def _check_rrule(cls, v):
        return validate_rrule(v)


class TaskRead(TaskBase, EntityRead):
    completed_at: datetime | None = None


async def _next_instance(db: AsyncSession, user: User, task: Task) -> Task | None:
    if not task.recurrence_rule:
        return None
    z = tz(user.timezone)
    now_local = utcnow().astimezone(z)
    if task.due_at:
        start = task.due_at.astimezone(z)
        nxt = next_after(task.recurrence_rule, start, max(now_local, start))
        due_at, due_date = (nxt, None) if nxt else (None, None)
    else:
        base = task.due_date or now_local.date()
        start = datetime.combine(base, time(9), tzinfo=z)
        nxt = next_after(task.recurrence_rule, start, max(now_local, start))
        due_at, due_date = None, (nxt.date() if nxt else None)
    if nxt is None:
        return None
    clone = Task(
        user_id=user.id,
        title=task.title,
        description=task.description,
        priority=task.priority,
        due_at=due_at,
        due_date=due_date,
        estimated_minutes=task.estimated_minutes,
        goal_id=task.goal_id,
        project_id=task.project_id,
        recurrence_rule=task.recurrence_rule,
        tags=list(task.tags or []),
        source=task.source,
    )
    db.add(clone)
    return clone


async def mark_done(db: AsyncSession, user: User, task: Task) -> None:
    """Side effects of a task becoming done (status must already be 'done')."""
    task.completed_at = task.completed_at or utcnow()
    await award_xp(
        db, user, XP["task"].get(task.priority, 20), "task.completed", source_type="task", source_id=task.id
    )
    emit(
        db,
        user.id,
        "task.completed",
        entity_type="task",
        entity_id=task.id,
        payload={"goal_id": task.goal_id, "project_id": task.project_id},
    )
    await _next_instance(db, user, task)


async def mark_reopened(db: AsyncSession, user: User, task: Task) -> None:
    task.completed_at = None
    await revoke_xp(db, user, "task.completed", task.id)
    emit(
        db, user.id, "task.reopened", entity_type="task", entity_id=task.id, payload={"goal_id": task.goal_id}
    )


async def _on_create(db, user, task: Task, values: dict) -> None:
    emit(db, user.id, "task.created", entity_type="task", entity_id=task.id)
    if task.status == "done":
        await mark_done(db, user, task)


async def _on_update(db, user, task: Task, info: dict) -> None:
    changes, before = info["changes"], info["before"]
    if "status" in changes and changes["status"] != before.get("status"):
        if changes["status"] == "done":
            await mark_done(db, user, task)
        elif before.get("status") == "done":
            await mark_reopened(db, user, task)
    emit(db, user.id, "task.updated", entity_type="task", entity_id=task.id)


spec = CrudSpec(
    model=Task,
    create_schema=TaskCreate,
    update_schema=TaskUpdate,
    read_schema=TaskRead,
    label="Task",
    refs={"goal_id": Goal, "project_id": Project, "parent_task_id": Task},
    filter_fields=("status", "priority", "goal_id", "project_id", "parent_task_id", "due_date"),
    on_create=_on_create,
    on_update=_on_update,
)
router = crud_router(spec, "/tasks", ["tasks"])


@router.post("/{task_id}/complete", response_model=TaskRead, summary="Complete a task")
async def complete_task(task_id: uuid.UUID, db: DB, user: CurrentUser, bg: BackgroundTasks):
    task = await get_owned(db, Task, task_id, user.id, label="Task")
    if task.status != "done":
        task.status = "done"
        task.version += 1
        await mark_done(db, user, task)
        await commit_and_dispatch(db, bg)
    return TaskRead.model_validate(task)


@router.post("/{task_id}/reopen", response_model=TaskRead, summary="Re-open a completed task")
async def reopen_task(task_id: uuid.UUID, db: DB, user: CurrentUser, bg: BackgroundTasks):
    task = await get_owned(db, Task, task_id, user.id, label="Task")
    if task.status == "done":
        task.status = "todo"
        task.version += 1
        await mark_reopened(db, user, task)
        await commit_and_dispatch(db, bg)
    return TaskRead.model_validate(task)
