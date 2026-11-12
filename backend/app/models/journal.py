"""Mood and journal. ARCHITECTURE.md §8.4 C. Private by default."""

from datetime import date, datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base
from ..core.models_base import SyncMixin
from ..core.types import JSONType, UTCDateTime


class MoodEntry(SyncMixin, Base):
    __tablename__ = "mood_entries"

    recorded_at: Mapped[datetime] = mapped_column(UTCDateTime, index=True)
    mood: Mapped[int] = mapped_column(sa.SmallInteger)  # 1..5
    energy: Mapped[int | None] = mapped_column(sa.SmallInteger)  # 1..10
    motivation: Mapped[int | None] = mapped_column(sa.SmallInteger)  # 1..10
    tags: Mapped[list] = mapped_column(JSONType, default=list)
    note: Mapped[str | None] = mapped_column(sa.Text)


class JournalEntry(SyncMixin, Base):
    __tablename__ = "journal_entries"

    entry_date: Mapped[date] = mapped_column(sa.Date, index=True)
    title: Mapped[str | None] = mapped_column(sa.String(200))
    content: Mapped[str] = mapped_column(sa.Text)  # never rewritten by AI
    ai_allowed: Mapped[bool] = mapped_column(sa.Boolean, default=False)
    word_count: Mapped[int] = mapped_column(sa.Integer, default=0)
