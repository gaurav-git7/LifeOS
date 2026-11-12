"""Outbox events, summaries, notifications, audit, idempotency. ARCHITECTURE.md §8.4 F."""

import uuid
from datetime import date, datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base
from ..core.models_base import CreatedMixin, IdMixin, UserOwnedMixin
from ..core.types import JSONType, UTCDateTime, utcnow


class ActivityEvent(IdMixin, UserOwnedMixin, Base):
    """Event log + transactional outbox (§10)."""

    __tablename__ = "activity_events"
    __table_args__ = (sa.Index("ix_activity_events_pending", "status", "next_attempt_at"),)

    event_type: Mapped[str] = mapped_column(sa.String(64))
    entity_type: Mapped[str | None] = mapped_column(sa.String(32))
    entity_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid)
    payload: Mapped[dict] = mapped_column(JSONType, default=dict)
    occurred_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    status: Mapped[str] = mapped_column(sa.String(12), default="pending")  # pending|processing|done|failed
    attempts: Mapped[int] = mapped_column(sa.SmallInteger, default=0)
    next_attempt_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    last_error: Mapped[str | None] = mapped_column(sa.Text)
    processed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


class DailySummary(IdMixin, UserOwnedMixin, Base):
    __tablename__ = "daily_summaries"
    __table_args__ = (sa.UniqueConstraint("user_id", "summary_date", name="uq_daily_summaries_day"),)

    summary_date: Mapped[date] = mapped_column(sa.Date)
    tasks_done: Mapped[int] = mapped_column(sa.Integer, default=0)
    tasks_open: Mapped[int] = mapped_column(sa.Integer, default=0)
    tasks_overdue: Mapped[int] = mapped_column(sa.Integer, default=0)
    habits_done: Mapped[int] = mapped_column(sa.Integer, default=0)
    habits_due: Mapped[int] = mapped_column(sa.Integer, default=0)
    study_minutes: Mapped[int] = mapped_column(sa.Integer, default=0)
    focus_minutes: Mapped[int] = mapped_column(sa.Integer, default=0)
    mood_avg: Mapped[float | None] = mapped_column(sa.Float)
    energy_avg: Mapped[float | None] = mapped_column(sa.Float)
    stats: Mapped[dict] = mapped_column(JSONType, default=dict)
    ai_insight: Mapped[str | None] = mapped_column(sa.Text)
    generated_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)


class WeeklySummary(IdMixin, UserOwnedMixin, Base):
    __tablename__ = "weekly_summaries"
    __table_args__ = (sa.UniqueConstraint("user_id", "week_start", name="uq_weekly_summaries_week"),)

    week_start: Mapped[date] = mapped_column(sa.Date)
    week_end: Mapped[date] = mapped_column(sa.Date)
    stats: Mapped[dict] = mapped_column(JSONType, default=dict)
    ai_report: Mapped[str | None] = mapped_column(sa.Text)
    recommendations: Mapped[list] = mapped_column(JSONType, default=list)
    generated_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)


class NotificationLog(IdMixin, CreatedMixin, UserOwnedMixin, Base):
    __tablename__ = "notification_logs"

    kind: Mapped[str] = mapped_column(sa.String(32))
    channel: Mapped[str] = mapped_column(sa.String(8))  # fcm|email
    title: Mapped[str] = mapped_column(sa.String(200))
    body: Mapped[str] = mapped_column(sa.Text)
    status: Mapped[str] = mapped_column(sa.String(12), default="queued")  # queued|sent|failed|skipped
    attempts: Mapped[int] = mapped_column(sa.SmallInteger, default=0)
    error: Mapped[str | None] = mapped_column(sa.Text)
    sent_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    dedupe_key: Mapped[str | None] = mapped_column(sa.String(128), unique=True)


class AuditLog(IdMixin, CreatedMixin, Base):
    __tablename__ = "audit_logs"

    user_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    actor: Mapped[str] = mapped_column(sa.String(8))  # user|agent|system
    action: Mapped[str] = mapped_column(sa.String(48))
    entity_type: Mapped[str | None] = mapped_column(sa.String(32))
    entity_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid)
    before: Mapped[dict | None] = mapped_column(JSONType)
    after: Mapped[dict | None] = mapped_column(JSONType)
    proposal_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid)
    ip: Mapped[str | None] = mapped_column(sa.String(64))


class IdempotencyKey(IdMixin, CreatedMixin, UserOwnedMixin, Base):
    __tablename__ = "idempotency_keys"
    __table_args__ = (sa.UniqueConstraint("user_id", "key", name="uq_idempotency_keys_user_key"),)

    key: Mapped[str] = mapped_column(sa.String(128))
    endpoint: Mapped[str] = mapped_column(sa.String(64))
    response: Mapped[dict] = mapped_column(JSONType, default=dict)
