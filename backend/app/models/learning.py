"""Learning paths, skills, topics, study sessions, projects. ARCHITECTURE.md §8.4 D."""

import uuid
from datetime import date, datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base
from ..core.models_base import SyncMixin
from ..core.types import JSONType, UTCDateTime


class LearningPath(SyncMixin, Base):
    __tablename__ = "learning_paths"

    title: Mapped[str] = mapped_column(sa.String(200))
    description: Mapped[str | None] = mapped_column(sa.Text)
    target_date: Mapped[date | None] = mapped_column(sa.Date)
    status: Mapped[str] = mapped_column(sa.String(12), default="active")  # active|paused|completed|archived
    goal_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("goals.id", ondelete="SET NULL"))
    source: Mapped[str] = mapped_column(sa.String(8), default="manual")


class Skill(SyncMixin, Base):
    __tablename__ = "skills"

    name: Mapped[str] = mapped_column(sa.String(80))
    category: Mapped[str] = mapped_column(
        sa.String(16), default="concept"
    )  # language|framework|tool|concept|soft_skill
    current_level: Mapped[int] = mapped_column(sa.SmallInteger, default=1)  # 1..5
    target_level: Mapped[int] = mapped_column(sa.SmallInteger, default=3)
    skill_xp: Mapped[int] = mapped_column(sa.Integer, default=0)


class LearningTopic(SyncMixin, Base):
    __tablename__ = "learning_topics"

    learning_path_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("learning_paths.id", ondelete="CASCADE"), index=True
    )
    skill_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("skills.id", ondelete="SET NULL")
    )
    title: Mapped[str] = mapped_column(sa.String(200))
    description: Mapped[str | None] = mapped_column(sa.Text)
    resources: Mapped[list] = mapped_column(JSONType, default=list)  # [{"title","url"}]
    difficulty: Mapped[str] = mapped_column(sa.String(8), default="medium")  # easy|medium|hard
    status: Mapped[str] = mapped_column(
        sa.String(12), default="not_started"
    )  # not_started|in_progress|done|skipped
    sort_order: Mapped[int] = mapped_column(sa.Integer, default=0)
    estimated_minutes: Mapped[int | None] = mapped_column(sa.Integer)
    prerequisite_ids: Mapped[list] = mapped_column(JSONType, default=list)  # list of topic id strings
    revision_count: Mapped[int] = mapped_column(sa.SmallInteger, default=0)
    next_revision_at: Mapped[date | None] = mapped_column(sa.Date)
    completed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


class StudySession(SyncMixin, Base):
    __tablename__ = "study_sessions"

    skill_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("skills.id", ondelete="SET NULL")
    )
    topic_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("learning_topics.id", ondelete="SET NULL")
    )
    project_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("projects.id", ondelete="SET NULL")
    )
    started_at: Mapped[datetime] = mapped_column(UTCDateTime, index=True)
    ended_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    duration_minutes: Mapped[int] = mapped_column(sa.Integer, default=0)
    session_type: Mapped[str] = mapped_column(sa.String(16), default="learning")
    problems_solved: Mapped[int | None] = mapped_column(sa.Integer)
    focus_rating: Mapped[int | None] = mapped_column(sa.SmallInteger)
    notes: Mapped[str | None] = mapped_column(sa.Text)
    source: Mapped[str] = mapped_column(sa.String(12), default="manual")  # manual|focus_timer


class Project(SyncMixin, Base):
    __tablename__ = "projects"

    name: Mapped[str] = mapped_column(sa.String(120))
    description: Mapped[str | None] = mapped_column(sa.Text)
    tech_stack: Mapped[list] = mapped_column(JSONType, default=list)
    repo_url: Mapped[str | None] = mapped_column(sa.String(300))
    status: Mapped[str] = mapped_column(sa.String(8), default="active")  # idea|active|paused|done|archived
    start_date: Mapped[date | None] = mapped_column(sa.Date)
    target_date: Mapped[date | None] = mapped_column(sa.Date)
    progress_pct: Mapped[int] = mapped_column(sa.SmallInteger, default=0)
    goal_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("goals.id", ondelete="SET NULL"))
