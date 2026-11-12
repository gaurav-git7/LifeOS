"""Goals + milestones. Progress is computed in Python, never by AI. ARCHITECTURE.md §8.4 B."""

import uuid
from datetime import date, datetime
from typing import Literal

from fastapi import APIRouter, BackgroundTasks
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core.crud import CrudSpec, EntityRead, crud_router, get_owned
from ...core.deps import DB, CurrentUser
from ...core.types import utcnow
from ...events.outbox import commit_and_dispatch, emit
from ...models import Goal, GoalMilestone, Task
from ..progression.service import XP, award_xp

Category = Literal["learning", "career", "health", "personal", "finance", "other"]
ProgressType = Literal["numeric", "milestones", "tasks", "boolean"]
GoalStatus = Literal["active", "paused", "completed", "archived"]


class GoalBase(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None
    category: Category = "personal"
    progress_type: ProgressType = "tasks"
    target_value: float | None = Field(default=None, ge=0)
    current_value: float | None = Field(default=None, ge=0)
    unit: str | None = Field(default=None, max_length=24)
    start_date: date | None = None
    target_date: date | None = None
    status: GoalStatus = "active"


class GoalCreate(GoalBase):
    id: uuid.UUID | None = None


class GoalUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = None
    category: Category | None = None
    progress_type: ProgressType | None = None
    target_value: float | None = Field(default=None, ge=0)
    current_value: float | None = Field(default=None, ge=0)
    unit: str | None = None
    start_date: date | None = None
    target_date: date | None = None
    status: GoalStatus | None = None


class GoalRead(GoalBase, EntityRead):
    completed_at: datetime | None = None


class MilestoneBase(BaseModel):
    goal_id: uuid.UUID
    title: str = Field(min_length=1, max_length=200)
    target_date: date | None = None
    sort_order: int = 0
    completed_at: datetime | None = None


class MilestoneCreate(MilestoneBase):
    id: uuid.UUID | None = None


class MilestoneUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    target_date: date | None = None
    sort_order: int | None = None
    completed_at: datetime | None = None


class MilestoneRead(MilestoneBase, EntityRead):
    pass


async def goal_progress(db: AsyncSession, goal: Goal) -> float:
    """0..1 according to the goal's progress_type."""
    if goal.status == "completed":
        return 1.0
    if goal.progress_type == "numeric":
        if not goal.target_value:
            return 0.0
        return max(0.0, min(1.0, (goal.current_value or 0) / goal.target_value))
    if goal.progress_type == "boolean":
        return 0.0
    if goal.progress_type == "milestones":
        base = select(func.count()).where(
            GoalMilestone.goal_id == goal.id, GoalMilestone.deleted_at.is_(None)
        )
        total = await db.scalar(base) or 0
        done = await db.scalar(base.where(GoalMilestone.completed_at.is_not(None))) or 0
        return done / total if total else 0.0
    base = select(func.count()).where(
        Task.goal_id == goal.id, Task.deleted_at.is_(None), Task.status != "cancelled"
    )
    total = await db.scalar(base) or 0
    done = await db.scalar(base.where(Task.status == "done")) or 0
    return done / total if total else 0.0


async def complete_goal(db: AsyncSession, user, goal: Goal) -> None:
    goal.completed_at = goal.completed_at or utcnow()
    await award_xp(db, user, XP["goal"], "goal.completed", source_type="goal", source_id=goal.id)
    emit(db, user.id, "goal.completed", entity_type="goal", entity_id=goal.id, payload={"title": goal.title})


async def _goal_updated(db, user, goal: Goal, info: dict) -> None:
    ch = info["changes"]
    if ch.get("status") == "completed" and info["before"].get("status") != "completed":
        await complete_goal(db, user, goal)


async def _milestone_updated(db, user, m: GoalMilestone, info: dict) -> None:
    if info["changes"].get("completed_at") and not info["before"].get("completed_at"):
        await award_xp(db, user, XP["milestone"], "goal.milestone", source_type="milestone", source_id=m.id)
        emit(
            db,
            user.id,
            "goal.milestone_reached",
            entity_type="milestone",
            entity_id=m.id,
            payload={"goal_id": m.goal_id, "title": m.title},
        )


goal_spec = CrudSpec(
    model=Goal,
    create_schema=GoalCreate,
    update_schema=GoalUpdate,
    read_schema=GoalRead,
    label="Goal",
    filter_fields=("status", "category"),
    on_update=_goal_updated,
    on_create=lambda db, u, g, v: _goal_created(db, u, g),
)


async def _goal_created(db, user, goal: Goal) -> None:
    emit(db, user.id, "goal.created", entity_type="goal", entity_id=goal.id)


milestone_spec = CrudSpec(
    model=GoalMilestone,
    create_schema=MilestoneCreate,
    update_schema=MilestoneUpdate,
    read_schema=MilestoneRead,
    label="Milestone",
    refs={"goal_id": Goal},
    filter_fields=("goal_id",),
    on_update=_milestone_updated,
)

router = APIRouter(tags=["goals"])


class GoalProgress(BaseModel):
    goal_id: uuid.UUID
    title: str
    progress: float
    target_date: date | None


@router.get("/goals/progress", response_model=list[GoalProgress])
async def active_goal_progress(db: DB, user: CurrentUser):
    goals = (
        await db.execute(
            select(Goal).where(Goal.user_id == user.id, Goal.deleted_at.is_(None), Goal.status == "active")
        )
    ).scalars()
    return [
        GoalProgress(
            goal_id=g.id,
            title=g.title,
            progress=round(await goal_progress(db, g), 4),
            target_date=g.target_date,
        )
        for g in goals
    ]


@router.post("/goal-milestones/{milestone_id}/complete", response_model=MilestoneRead)
async def complete_milestone(milestone_id: uuid.UUID, db: DB, user: CurrentUser, bg: BackgroundTasks):
    m = await get_owned(db, GoalMilestone, milestone_id, user.id, label="Milestone")
    if m.completed_at is None:
        m.completed_at = utcnow()
        m.version += 1
        await _milestone_updated(db, user, m, {"changes": {"completed_at": m.completed_at}, "before": {}})
        await commit_and_dispatch(db, bg)
    return MilestoneRead.model_validate(m)


router.include_router(crud_router(goal_spec, "/goals", ["goals"]))
router.include_router(crud_router(milestone_spec, "/goal-milestones", ["goals"]))
