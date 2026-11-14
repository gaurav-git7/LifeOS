"""Identity & auth tables. ARCHITECTURE.md §8.4 A."""

import uuid
from datetime import datetime, time

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base
from ..core.models_base import CreatedMixin, IdMixin, UserOwnedMixin
from ..core.types import UTCDateTime, utcnow


class User(IdMixin, CreatedMixin, Base):
    __tablename__ = "users"

    email: Mapped[str] = mapped_column(sa.String(320), unique=True, index=True)  # stored lowercased
    password_hash: Mapped[str] = mapped_column(sa.String(255))
    display_name: Mapped[str] = mapped_column(sa.String(80))
    timezone: Mapped[str] = mapped_column(sa.String(64), default="UTC")
    email_verified_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    role: Mapped[str] = mapped_column(sa.String(16), default="user")  # user | admin
    status: Mapped[str] = mapped_column(sa.String(16), default="active")  # active | disabled
    last_login_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    token_version: Mapped[int] = mapped_column(sa.Integer, default=0)  # bump = log out everywhere
    total_xp: Mapped[int] = mapped_column(sa.Integer, default=0)
    friend_code: Mapped[str | None] = mapped_column(sa.String(12), unique=True)  # share to be added
    level: Mapped[int] = mapped_column(sa.SmallInteger, default=1)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, onupdate=utcnow)


class UserPreferences(Base):
    __tablename__ = "user_preferences"

    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    theme: Mapped[str] = mapped_column(sa.String(8), default="dark")
    week_start_day: Mapped[int] = mapped_column(sa.SmallInteger, default=1)
    daily_review_enabled: Mapped[bool] = mapped_column(sa.Boolean, default=True)
    daily_review_time: Mapped[time] = mapped_column(sa.Time, default=time(21, 0))
    weekly_review_enabled: Mapped[bool] = mapped_column(sa.Boolean, default=True)
    weekly_review_day: Mapped[int] = mapped_column(sa.SmallInteger, default=7)
    notifications_enabled: Mapped[bool] = mapped_column(sa.Boolean, default=True)
    quiet_hours_start: Mapped[time | None] = mapped_column(sa.Time)
    quiet_hours_end: Mapped[time | None] = mapped_column(sa.Time)
    ai_enabled: Mapped[bool] = mapped_column(sa.Boolean, default=True)
    ai_memory_enabled: Mapped[bool] = mapped_column(sa.Boolean, default=True)
    mood_ai_enabled: Mapped[bool] = mapped_column(sa.Boolean, default=False)
    journal_ai_enabled: Mapped[bool] = mapped_column(sa.Boolean, default=False)
    ai_daily_budget_usd: Mapped[float | None] = mapped_column(sa.Float)  # None = server default
    reduce_motion: Mapped[bool] = mapped_column(sa.Boolean, default=False)
    ambient_intensity: Mapped[str] = mapped_column(sa.String(8), default="normal")
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, onupdate=utcnow)


class RefreshToken(IdMixin, CreatedMixin, UserOwnedMixin, Base):
    __tablename__ = "refresh_tokens"

    token_hash: Mapped[str] = mapped_column(sa.String(64), unique=True)
    family_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, index=True)
    device_label: Mapped[str | None] = mapped_column(sa.String(80))
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime)
    revoked_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    replaced_by: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid)


class EmailToken(IdMixin, CreatedMixin, UserOwnedMixin, Base):
    __tablename__ = "email_tokens"

    purpose: Mapped[str] = mapped_column(sa.String(24))  # verify_email | reset_password
    token_hash: Mapped[str] = mapped_column(sa.String(64), unique=True)
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime)
    used_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


class Invite(IdMixin, CreatedMixin, Base):
    __tablename__ = "invites"

    code_hash: Mapped[str] = mapped_column(sa.String(64), unique=True)
    email: Mapped[str | None] = mapped_column(sa.String(320))
    created_by: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL")
    )
    max_uses: Mapped[int] = mapped_column(sa.Integer, default=1)
    used_count: Mapped[int] = mapped_column(sa.Integer, default=0)
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime)


class DeviceToken(IdMixin, CreatedMixin, UserOwnedMixin, Base):
    __tablename__ = "device_tokens"

    fcm_token: Mapped[str] = mapped_column(sa.String(512), unique=True)
    platform: Mapped[str] = mapped_column(sa.String(16), default="android")
    app_version: Mapped[str | None] = mapped_column(sa.String(32))
    last_seen_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    invalidated_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
