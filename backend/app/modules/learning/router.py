"""Learning paths, topics (with prerequisites + spaced revision), skills,
study sessions and projects. ARCHITECTURE.md §8.4 D, UI_UX.md §9.3."""

import uuid
from datetime import date, datetime, timedelta
from typing import Literal

from fastapi import APIRouter, BackgroundTasks
from pydantic import BaseModel, Field, HttpUrl, model_validator
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core.crud import CrudSpec, EntityRead, crud_router, get_owned
from ...core.deps import DB, CurrentUser
from ...core.time import day_bounds_utc, local_today, tz
from ...core.types import utcnow
from ...events.outbox import commit_and_dispatch, emit
from ...models import Goal, LearningPath, LearningTopic, Project, Skill, StudySession, User
from ..progression.service import XP, award_xp, study_xp_today

REVISION_INTERVALS = [1, 3, 7, 21]  # days

# ---------- paths ----------

PathStatus = Literal["active", "paused", "completed", "archived"]


class PathBase(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None
    target_date: date | None = None
    status: PathStatus = "active"
    goal_id: uuid.UUID | None = None
    source: Literal["manual", "agent"] = "manual"


class PathCreate(PathBase):
    id: uuid.UUID | None = None


class PathUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = None
    target_date: date | None = None
    status: PathStatus | None = None
    goal_id: uuid.UUID | None = None


class PathRead(PathBase, EntityRead):
    pass


# ---------- topics ----------


class Resource(BaseModel):
    title: str = Field(max_length=200)
    url: HttpUrl | None = None


class TopicBase(BaseModel):
    learning_path_id: uuid.UUID
    skill_id: uuid.UUID | None = None
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None
    resources: list[Resource] = Field(default_factory=list, max_length=20)
    difficulty: Literal["easy", "medium", "hard"] = "medium"
    status: Literal["not_started", "in_progress", "done", "skipped"] = "not_started"
    sort_order: int = 0
    estimated_minutes: int | None = Field(default=None, ge=0, le=10_000)
    prerequisite_ids: list[uuid.UUID] = Field(default_factory=list, max_length=20)


class TopicCreate(TopicBase):
    id: uuid.UUID | None = None


class TopicUpdate(BaseModel):
    skill_id: uuid.UUID | None = None
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = None
    resources: list[Resource] | None = None
    difficulty: Literal["easy", "medium", "hard"] | None = None
    status: Literal["not_started", "in_progress", "skipped"] | None = None  # use /complete for done
    sort_order: int | None = None
    estimated_minutes: int | None = Field(default=None, ge=0, le=10_000)
    prerequisite_ids: list[uuid.UUID] | None = None


class TopicRead(TopicBase, EntityRead):
    revision_count: int
    next_revision_at: date | None
    completed_at: datetime | None


def _jsonify_topic(values: dict) -> None:
    if "resources" in values and values["resources"] is not None:
        values["resources"] = [
            {"title": r["title"], "url": str(r["url"]) if r.get("url") else None} for r in values["resources"]
        ]
    if "prerequisite_ids" in values and values["prerequisite_ids"] is not None:
        values["prerequisite_ids"] = [str(x) for x in values["prerequisite_ids"]]


async def _topic_prep(db, user, values: dict) -> None:
    _jsonify_topic(values)


async def complete_topic(db: AsyncSession, user: User, topic: LearningTopic) -> None:
    if topic.status == "done":
        return
    topic.status = "done"
    topic.completed_at = utcnow()
    topic.next_revision_at = local_today(user.timezone) + timedelta(days=REVISION_INTERVALS[0])
    topic.version += 1
    await award_xp(
        db,
        user,
        XP["topic"].get(topic.difficulty, 40),
        "topic.completed",
        source_type="topic",
        source_id=topic.id,
        skill_id=topic.skill_id,
    )
    emit(
        db,
        user.id,
        "learning.topic_completed",
        entity_type="topic",
        entity_id=topic.id,
        payload={"path_id": topic.learning_path_id, "title": topic.title},
    )
    await db.flush()
    remaining = await db.scalar(
        select(func.count()).where(
            LearningTopic.learning_path_id == topic.learning_path_id,
            LearningTopic.deleted_at.is_(None),
            LearningTopic.status.not_in(["done", "skipped"]),
        )
    )
    if remaining == 0:
        path = await db.get(LearningPath, topic.learning_path_id)
        if path and path.status != "completed":
            path.status = "completed"
            path.version += 1
            emit(
                db,
                user.id,
                "learning.path_completed",
                entity_type="learning_path",
                entity_id=path.id,
                payload={"title": path.title},
            )


path_spec = CrudSpec(
    model=LearningPath,
    create_schema=PathCreate,
    update_schema=PathUpdate,
    read_schema=PathRead,
    label="Learning path",
    refs={"goal_id": Goal},
    filter_fields=("status", "goal_id"),
)
topic_spec = CrudSpec(
    model=LearningTopic,
    create_schema=TopicCreate,
    update_schema=TopicUpdate,
    read_schema=TopicRead,
    label="Topic",
    before_create=_topic_prep,
    before_update=_topic_prep,
    refs={"learning_path_id": LearningPath, "skill_id": Skill},
    filter_fields=("learning_path_id", "skill_id", "status"),
)

# ---------- skills ----------


class SkillBase(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    category: Literal["language", "framework", "tool", "concept", "soft_skill"] = "concept"
    current_level: int = Field(default=1, ge=1, le=5)
    target_level: int = Field(default=3, ge=1, le=5)


class SkillCreate(SkillBase):
    id: uuid.UUID | None = None


class SkillUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=80)
    category: Literal["language", "framework", "tool", "concept", "soft_skill"] | None = None
    current_level: int | None = Field(default=None, ge=1, le=5)
    target_level: int | None = Field(default=None, ge=1, le=5)


class SkillRead(SkillBase, EntityRead):
    skill_xp: int


skill_spec = CrudSpec(
    model=Skill,
    create_schema=SkillCreate,
    update_schema=SkillUpdate,
    read_schema=SkillRead,
    label="Skill",
    filter_fields=("category",),
)

# ---------- study sessions ----------

SessionType = Literal["learning", "practice", "revision", "project", "problem_solving"]


class SessionBase(BaseModel):
    skill_id: uuid.UUID | None = None
    topic_id: uuid.UUID | None = None
    project_id: uuid.UUID | None = None
    started_at: datetime
    ended_at: datetime | None = None
    duration_minutes: int | None = Field(default=None, ge=0, le=24 * 60)
    session_type: SessionType = "learning"
    problems_solved: int | None = Field(default=None, ge=0, le=1000)
    focus_rating: int | None = Field(default=None, ge=1, le=5)
    notes: str | None = None
    source: Literal["manual", "focus_timer"] = "manual"

    @model_validator(mode="after")
    def _duration(self):
        if self.duration_minutes is None:
            if self.ended_at is None:
                raise ValueError("Provide duration_minutes or ended_at")
            self.duration_minutes = max(0, round((self.ended_at - self.started_at).total_seconds() / 60))
        return self


class SessionCreate(SessionBase):
    id: uuid.UUID | None = None


class SessionUpdate(BaseModel):
    notes: str | None = None
    problems_solved: int | None = Field(default=None, ge=0, le=1000)
    focus_rating: int | None = Field(default=None, ge=1, le=5)
    session_type: SessionType | None = None


class SessionRead(SessionBase, EntityRead):
    duration_minutes: int


async def _session_created(db: AsyncSession, user: User, s: StudySession, values: dict) -> None:
    start, end = day_bounds_utc(s.started_at.astimezone(tz(user.timezone)).date(), user.timezone)
    already = await study_xp_today(db, user, start, end)
    amount = min(s.duration_minutes * XP["study_per_minute"], max(0, XP["study_daily_cap"] - already))
    await award_xp(
        db, user, amount, "study.session", source_type="study_session", source_id=s.id, skill_id=s.skill_id
    )
    if s.topic_id:
        topic = await db.get(LearningTopic, s.topic_id)
        if topic and topic.status == "not_started":
            topic.status = "in_progress"
            topic.version += 1
            if s.skill_id is None and topic.skill_id:
                s.skill_id = topic.skill_id
    emit(
        db,
        user.id,
        "study.session_completed",
        entity_type="study_session",
        entity_id=s.id,
        payload={"minutes": s.duration_minutes, "skill_id": s.skill_id, "topic_id": s.topic_id},
    )


session_spec = CrudSpec(
    model=StudySession,
    create_schema=SessionCreate,
    update_schema=SessionUpdate,
    read_schema=SessionRead,
    label="Study session",
    refs={"skill_id": Skill, "topic_id": LearningTopic, "project_id": Project},
    filter_fields=("skill_id", "topic_id", "project_id", "session_type"),
    on_create=_session_created,
)

# ---------- projects ----------

ProjectStatus = Literal["idea", "active", "paused", "done", "archived"]


class ProjectBase(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    description: str | None = None
    tech_stack: list[str] = Field(default_factory=list, max_length=30)
    repo_url: str | None = Field(default=None, max_length=300)
    status: ProjectStatus = "active"
    start_date: date | None = None
    target_date: date | None = None
    progress_pct: int = Field(default=0, ge=0, le=100)
    goal_id: uuid.UUID | None = None


class ProjectCreate(ProjectBase):
    id: uuid.UUID | None = None


class ProjectUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = None
    tech_stack: list[str] | None = None
    repo_url: str | None = None
    status: ProjectStatus | None = None
    start_date: date | None = None
    target_date: date | None = None
    progress_pct: int | None = Field(default=None, ge=0, le=100)
    goal_id: uuid.UUID | None = None


class ProjectRead(ProjectBase, EntityRead):
    pass


async def _project_updated(db, user, p: Project, info: dict) -> None:
    if info["changes"].get("status") == "done" and info["before"].get("status") != "done":
        p.progress_pct = 100
        await award_xp(db, user, XP["project"], "project.completed", source_type="project", source_id=p.id)
        emit(
            db, user.id, "project.completed", entity_type="project", entity_id=p.id, payload={"name": p.name}
        )


project_spec = CrudSpec(
    model=Project,
    create_schema=ProjectCreate,
    update_schema=ProjectUpdate,
    read_schema=ProjectRead,
    label="Project",
    refs={"goal_id": Goal},
    filter_fields=("status", "goal_id"),
    on_update=_project_updated,
)

# ---------- router ----------

router = APIRouter(tags=["learning"])


@router.get(
    "/learning/paths/{path_id}/topics", response_model=list[TopicRead], summary="Topics in path order"
)
async def path_topics(path_id: uuid.UUID, db: DB, user: CurrentUser):
    await get_owned(db, LearningPath, path_id, user.id, label="Learning path")
    rows = (
        await db.execute(
            select(LearningTopic)
            .where(LearningTopic.learning_path_id == path_id, LearningTopic.deleted_at.is_(None))
            .order_by(LearningTopic.sort_order, LearningTopic.created_at)
        )
    ).scalars()
    return [TopicRead.model_validate(r) for r in rows]


@router.post("/learning/topics/{topic_id}/complete", response_model=TopicRead)
async def complete_topic_endpoint(topic_id: uuid.UUID, db: DB, user: CurrentUser, bg: BackgroundTasks):
    topic = await get_owned(db, LearningTopic, topic_id, user.id, label="Topic")
    await complete_topic(db, user, topic)
    await commit_and_dispatch(db, bg)
    return TopicRead.model_validate(topic)


@router.post("/learning/topics/{topic_id}/revise", response_model=TopicRead, summary="Mark a revision done")
async def revise_topic(topic_id: uuid.UUID, db: DB, user: CurrentUser, bg: BackgroundTasks):
    topic = await get_owned(db, LearningTopic, topic_id, user.id, label="Topic")
    today = local_today(user.timezone)
    on_time = topic.next_revision_at is None or today <= topic.next_revision_at + timedelta(days=1)
    topic.revision_count += 1
    idx = min(topic.revision_count, len(REVISION_INTERVALS) - 1)
    topic.next_revision_at = today + timedelta(days=REVISION_INTERVALS[idx])
    topic.version += 1
    if on_time:
        await award_xp(
            db,
            user,
            XP["topic_revision"],
            "topic.revised",
            source_type="topic",
            source_id=uuid.uuid5(topic.id, str(topic.revision_count)),
            skill_id=topic.skill_id,
        )
    emit(db, user.id, "learning.topic_revised", entity_type="topic", entity_id=topic.id)
    await commit_and_dispatch(db, bg)
    return TopicRead.model_validate(topic)


@router.get("/learning/revisions-due", response_model=list[TopicRead], summary="Topics due for revision")
async def revisions_due(db: DB, user: CurrentUser):
    today = local_today(user.timezone)
    rows = (
        await db.execute(
            select(LearningTopic)
            .where(
                LearningTopic.user_id == user.id,
                LearningTopic.deleted_at.is_(None),
                LearningTopic.next_revision_at <= today,
            )
            .order_by(LearningTopic.next_revision_at)
        )
    ).scalars()
    return [TopicRead.model_validate(r) for r in rows]


router.include_router(crud_router(path_spec, "/learning/paths", ["learning"]))
router.include_router(crud_router(topic_spec, "/learning/topics", ["learning"]))
router.include_router(crud_router(skill_spec, "/skills", ["learning"]))
router.include_router(crud_router(session_spec, "/study-sessions", ["learning"]))
router.include_router(crud_router(project_spec, "/projects", ["projects"]))
