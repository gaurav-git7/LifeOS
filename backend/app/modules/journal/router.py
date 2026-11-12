"""Mood check-ins and journal entries. Private by default; AI access is opt-in
per user (preferences) and per entry (`ai_allowed`). ARCHITECTURE.md §8.4 C."""

import uuid
from datetime import date, datetime

from fastapi import APIRouter
from pydantic import BaseModel, Field

from ...core.crud import CrudSpec, EntityRead, crud_router
from ...core.time import local_today, tz
from ...events.outbox import emit
from ...models import JournalEntry, MoodEntry, UserPreferences
from ..progression.service import XP, award_xp, stable_id

# ---------- mood ----------


class MoodBase(BaseModel):
    recorded_at: datetime
    mood: int = Field(ge=1, le=5)
    energy: int | None = Field(default=None, ge=1, le=10)
    motivation: int | None = Field(default=None, ge=1, le=10)
    tags: list[str] = Field(default_factory=list, max_length=12)
    note: str | None = Field(default=None, max_length=2000)


class MoodCreate(MoodBase):
    id: uuid.UUID | None = None


class MoodUpdate(BaseModel):
    mood: int | None = Field(default=None, ge=1, le=5)
    energy: int | None = Field(default=None, ge=1, le=10)
    motivation: int | None = Field(default=None, ge=1, le=10)
    tags: list[str] | None = None
    note: str | None = None


class MoodRead(MoodBase, EntityRead):
    pass


async def _mood_created(db, user, m: MoodEntry, values: dict) -> None:
    day = m.recorded_at.astimezone(tz(user.timezone)).date()
    await award_xp(
        db, user, XP["mood"], "mood.daily", source_type="mood", source_id=stable_id(user.id, "mood", day)
    )
    emit(db, user.id, "mood.recorded", entity_type="mood", entity_id=m.id)


mood_spec = CrudSpec(
    model=MoodEntry,
    create_schema=MoodCreate,
    update_schema=MoodUpdate,
    read_schema=MoodRead,
    label="Mood entry",
    on_create=_mood_created,
)

# ---------- journal ----------


class JournalBase(BaseModel):
    entry_date: date | None = None  # defaults to today (user's timezone)
    title: str | None = Field(default=None, max_length=200)
    content: str = Field(max_length=100_000)
    ai_allowed: bool | None = None  # defaults to the user's journal_ai_enabled preference


class JournalCreate(JournalBase):
    id: uuid.UUID | None = None


class JournalUpdate(BaseModel):
    title: str | None = Field(default=None, max_length=200)
    content: str | None = Field(default=None, max_length=100_000)
    ai_allowed: bool | None = None


class JournalRead(EntityRead):
    entry_date: date
    title: str | None
    content: str
    ai_allowed: bool
    word_count: int


async def _journal_prep(db, user, values: dict) -> None:
    if values.get("entry_date") is None:
        values["entry_date"] = local_today(user.timezone)
    if values.get("ai_allowed") is None:
        prefs = await db.get(UserPreferences, user.id)
        values["ai_allowed"] = bool(prefs and prefs.journal_ai_enabled)
    values["word_count"] = len((values.get("content") or "").split())


async def _journal_created(db, user, j: JournalEntry, values: dict) -> None:
    await award_xp(
        db,
        user,
        XP["journal"],
        "journal.daily",
        source_type="journal",
        source_id=stable_id(user.id, "journal", j.entry_date),
    )
    emit(db, user.id, "journal.created", entity_type="journal", entity_id=j.id)


async def _journal_updated(db, user, j: JournalEntry, info: dict) -> None:
    j.word_count = len((j.content or "").split())


journal_spec = CrudSpec(
    model=JournalEntry,
    create_schema=JournalCreate,
    update_schema=JournalUpdate,
    read_schema=JournalRead,
    label="Journal entry",
    filter_fields=("entry_date",),
    before_create=_journal_prep,
    on_create=_journal_created,
    on_update=_journal_updated,
)

router = APIRouter()
router.include_router(crud_router(mood_spec, "/mood", ["journal"]))
router.include_router(crud_router(journal_spec, "/journal", ["journal"]))
