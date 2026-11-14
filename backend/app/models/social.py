"""Friends, sharing and group habits. Nothing is visible to anyone unless the
owner shares it: habits are private by default (habits.visibility)."""

import uuid
from datetime import date, datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base
from ..core.models_base import CreatedMixin, IdMixin
from ..core.types import UTCDateTime


def _user_fk(**kw):
    return mapped_column(sa.Uuid, sa.ForeignKey("users.id", ondelete="CASCADE"), index=True, **kw)


class Friendship(IdMixin, CreatedMixin, Base):
    """One row per pair. user_id asked, friend_id accepts."""

    __tablename__ = "friendships"
    __table_args__ = (sa.UniqueConstraint("user_id", "friend_id", name="uq_friendships_pair"),)

    user_id: Mapped[uuid.UUID] = _user_fk()
    friend_id: Mapped[uuid.UUID] = _user_fk()
    status: Mapped[str] = mapped_column(sa.String(12), default="pending")  # pending|accepted
    accepted_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


class FriendGroup(IdMixin, CreatedMixin, Base):
    __tablename__ = "friend_groups"

    name: Mapped[str] = mapped_column(sa.String(60))
    owner_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    invite_code: Mapped[str] = mapped_column(sa.String(16), unique=True)


class GroupMember(CreatedMixin, Base):
    __tablename__ = "group_members"

    group_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("friend_groups.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True
    )


class GroupHabit(IdMixin, CreatedMixin, Base):
    __tablename__ = "group_habits"

    group_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("friend_groups.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(sa.String(120))
    recurrence_rule: Mapped[str] = mapped_column(sa.String(255), default="FREQ=DAILY")
    target_per_period: Mapped[int] = mapped_column(sa.Integer, default=1)
    created_by: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    deleted_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


class GroupCheckin(IdMixin, CreatedMixin, Base):
    __tablename__ = "group_checkins"
    __table_args__ = (sa.UniqueConstraint("group_habit_id", "user_id", "day", name="uq_group_checkins_once"),)

    group_habit_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("group_habits.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[uuid.UUID] = _user_fk()
    day: Mapped[date] = mapped_column(sa.Date)


class Reaction(IdMixin, CreatedMixin, Base):
    """Cheers and nudges between friends. Nudges are limited (see router)."""

    __tablename__ = "reactions"

    user_id: Mapped[uuid.UUID] = _user_fk()  # from
    to_user_id: Mapped[uuid.UUID] = _user_fk()
    kind: Mapped[str] = mapped_column(sa.String(12))  # fire|clap|strong|nudge
    target: Mapped[str] = mapped_column(sa.String(80))  # habit:<id> | group_habit:<id>
