"""Tasks, goals, habits, reminders, schedule. ARCHITECTURE.md §8.4 B."""

import uuid
from datetime import date, datetime, time

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base
from ..core.models_base import SyncMixin
from ..core.types import JSONType, UTCDateTime


class Task(SyncMixin, Base):
    __tablename__ = "tasks"
    __table_args__ = (sa.Index("ix_tasks_user_status_due", "user_id", "status", "due_at"),)

    title: Mapped[str] = mapped_column(sa.String(200))
    description: Mapped[str | None] = mapped_column(sa.Text)
    status: Mapped[str] = mapped_column(sa.String(16), default="todo")  # todo|in_progress|done|cancelled
    priority: Mapped[str] = mapped_column(sa.String(8), default="medium")  # low|medium|high
    due_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    due_date: Mapped[date | None] = mapped_column(sa.Date)
    estimated_minutes: Mapped[int | None] = mapped_column(sa.Integer)
    actual_minutes: Mapped[int | None] = mapped_column(sa.Integer)
    goal_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("goals.id", ondelete="SET NULL"))
    project_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("projects.id", ondelete="SET NULL")
    )
    parent_task_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("tasks.id", ondelete="SET NULL")
    )
    recurrence_rule: Mapped[str | None] = mapped_column(sa.String(255))
    tags: Mapped[list] = mapped_column(JSONType, default=list)
    source: Mapped[str] = mapped_column(sa.String(16), default="manual")  # manual|agent|quick_capture
    completed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    sort_order: Mapped[int] = mapped_column(sa.Integer, default=0)


class Goal(SyncMixin, Base):
    __tablename__ = "goals"

    title: Mapped[str] = mapped_column(sa.String(200))
    description: Mapped[str | None] = mapped_column(sa.Text)
    category: Mapped[str] = mapped_column(sa.String(16), default="personal")
    progress_type: Mapped[str] = mapped_column(
        sa.String(12), default="tasks"
    )  # numeric|milestones|tasks|boolean
    target_value: Mapped[float | None] = mapped_column(sa.Float)
    current_value: Mapped[float | None] = mapped_column(sa.Float)
    unit: Mapped[str | None] = mapped_column(sa.String(24))
    start_date: Mapped[date | None] = mapped_column(sa.Date)
    target_date: Mapped[date | None] = mapped_column(sa.Date)
    status: Mapped[str] = mapped_column(sa.String(12), default="active")  # active|paused|completed|archived
    completed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


class GoalMilestone(SyncMixin, Base):
    __tablename__ = "goal_milestones"

    goal_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("goals.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(sa.String(200))
    target_date: Mapped[date | None] = mapped_column(sa.Date)
    sort_order: Mapped[int] = mapped_column(sa.Integer, default=0)
    completed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


class Habit(SyncMixin, Base):
    __tablename__ = "habits"

    title: Mapped[str] = mapped_column(sa.String(120))
    description: Mapped[str | None] = mapped_column(sa.Text)
    recurrence_rule: Mapped[str] = mapped_column(sa.String(255), default="FREQ=DAILY")
    target_per_period: Mapped[int] = mapped_column(sa.Integer, default=1)
    reminder_time: Mapped[time | None] = mapped_column(sa.Time)
    color: Mapped[str | None] = mapped_column(sa.String(16))
    icon: Mapped[str | None] = mapped_column(sa.String(32))
    active: Mapped[bool] = mapped_column(sa.Boolean, default=True)
    current_streak: Mapped[int] = mapped_column(sa.Integer, default=0)
    best_streak: Mapped[int] = mapped_column(sa.Integer, default=0)


class HabitLog(SyncMixin, Base):
    __tablename__ = "habit_logs"
    __table_args__ = (sa.UniqueConstraint("habit_id", "log_date", name="uq_habit_logs_habit_day"),)

    habit_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("habits.id", ondelete="CASCADE"), index=True
    )
    log_date: Mapped[date] = mapped_column(sa.Date)  # user-local date
    status: Mapped[str] = mapped_column(sa.String(8), default="done")  # done|skipped|missed
    note: Mapped[str | None] = mapped_column(sa.Text)


class Reminder(SyncMixin, Base):
    __tablename__ = "reminders"

    title: Mapped[str] = mapped_column(sa.String(200))
    task_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("tasks.id", ondelete="SET NULL"))
    habit_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("habits.id", ondelete="SET NULL")
    )
    remind_at: Mapped[datetime] = mapped_column(UTCDateTime)
    recurrence_rule: Mapped[str | None] = mapped_column(sa.String(255))
    delivery: Mapped[str] = mapped_column(sa.String(8), default="local")  # local|push
    status: Mapped[str] = mapped_column(sa.String(12), default="scheduled")  # scheduled|fired|cancelled


class ScheduleBlock(SyncMixin, Base):
    __tablename__ = "schedule_blocks"

    title: Mapped[str] = mapped_column(sa.String(200))
    task_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, sa.ForeignKey("tasks.id", ondelete="SET NULL"))
    topic_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("learning_topics.id", ondelete="SET NULL")
    )
    start_at: Mapped[datetime] = mapped_column(UTCDateTime, index=True)
    end_at: Mapped[datetime] = mapped_column(UTCDateTime)
    block_type: Mapped[str] = mapped_column(sa.String(8), default="task")  # task|study|focus|break|other
    status: Mapped[str] = mapped_column(sa.String(8), default="planned")  # planned|done|skipped
    source: Mapped[str] = mapped_column(sa.String(8), default="manual")  # manual|agent
