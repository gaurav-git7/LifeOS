"""XP, levels, achievements. ARCHITECTURE.md §8.4 D2 / UI_UX.md §10."""

import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base
from ..core.models_base import CreatedMixin, IdMixin, UserOwnedMixin
from ..core.types import UTCDateTime, utcnow


class XpLedger(IdMixin, CreatedMixin, UserOwnedMixin, Base):
    __tablename__ = "xp_ledger"
    __table_args__ = (sa.UniqueConstraint("user_id", "reason", "source_id", name="uq_xp_ledger_once"),)

    amount: Mapped[int] = mapped_column(sa.Integer)
    reason: Mapped[str] = mapped_column(sa.String(48))
    source_type: Mapped[str | None] = mapped_column(sa.String(32))
    source_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid)
    skill_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid)


class Achievement(Base):
    __tablename__ = "achievements"

    code: Mapped[str] = mapped_column(sa.String(48), primary_key=True)
    title: Mapped[str] = mapped_column(sa.String(80))
    description: Mapped[str] = mapped_column(sa.String(200))
    icon: Mapped[str] = mapped_column(sa.String(32))
    sort_order: Mapped[int] = mapped_column(sa.Integer, default=0)


class UserAchievement(IdMixin, UserOwnedMixin, Base):
    __tablename__ = "user_achievements"
    __table_args__ = (sa.UniqueConstraint("user_id", "achievement_code", name="uq_user_achievements_once"),)

    achievement_code: Mapped[str] = mapped_column(
        sa.String(48), sa.ForeignKey("achievements.code", ondelete="CASCADE")
    )
    unlocked_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
