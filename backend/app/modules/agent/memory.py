"""Structured memory in Postgres (no vector DB). ARCHITECTURE.md §13."""

import re

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core.types import utcnow
from ...models import AgentMemory, User, UserPreferences
from .schemas import LLMMemory

_WORD = re.compile(r"[a-z0-9]+")
STOP = {
    "the",
    "a",
    "an",
    "and",
    "or",
    "to",
    "of",
    "in",
    "on",
    "for",
    "my",
    "i",
    "me",
    "is",
    "it",
    "with",
    "at",
}


def _words(text: str) -> set[str]:
    return {w for w in _WORD.findall(text.lower()) if w not in STOP and len(w) > 2}


async def memory_enabled(db: AsyncSession, user: User) -> bool:
    prefs = await db.get(UserPreferences, user.id)
    return bool(prefs is None or prefs.ai_memory_enabled)


async def retrieve(
    db: AsyncSession, user: User, query: str = "", episodic_limit: int = 10
) -> list[AgentMemory]:
    """Profile + preference memories, the latest summary, and the most relevant
    episodic memories (importance + recency + keyword overlap)."""
    if not await memory_enabled(db, user):
        return []
    rows = list(
        (
            await db.execute(
                select(AgentMemory)
                .where(
                    AgentMemory.user_id == user.id,
                    AgentMemory.status == "active",
                    AgentMemory.deleted_at.is_(None),
                )
                .order_by(AgentMemory.created_at.desc())
                .limit(400)
            )
        ).scalars()
    )
    now = utcnow()
    rows = [m for m in rows if m.expires_at is None or m.expires_at > now]
    stable = [m for m in rows if m.memory_type in ("profile", "preference")][:50]
    summary = next((m for m in rows if m.memory_type == "summary"), None)
    q = _words(query)

    def score(m: AgentMemory) -> float:
        age_days = (now - m.created_at).days
        overlap = len(q & _words(m.content))
        return m.importance + 3 * overlap - age_days / 30

    episodic = sorted((m for m in rows if m.memory_type == "episodic"), key=score, reverse=True)[
        :episodic_limit
    ]
    picked = stable + ([summary] if summary else []) + episodic
    for m in picked:
        m.last_used_at = now
    return picked


async def save_suggestions(
    db: AsyncSession, user: User, suggestions: list[LLMMemory], source_id=None
) -> list[AgentMemory]:
    """Agent-suggested memories start as 'proposed' until the user keeps them."""
    if not suggestions or not await memory_enabled(db, user):
        return []
    existing = {
        c.lower().strip()
        for c in (
            await db.execute(
                select(AgentMemory.content).where(
                    AgentMemory.user_id == user.id, AgentMemory.deleted_at.is_(None)
                )
            )
        ).scalars()
    }
    out = []
    for s in suggestions[:3]:
        content = s.content.strip()[:500]
        if not content or content.lower() in existing:
            continue
        m = AgentMemory(
            user_id=user.id,
            memory_type=s.type,
            content=content,
            importance=3,
            source_type="conversation",
            source_id=source_id,
            status="proposed",
        )
        db.add(m)
        out.append(m)
    return out


async def replace_summary(db: AsyncSession, user: User, content: str) -> None:
    """Weekly review keeps exactly one active 'summary' memory."""
    if not await memory_enabled(db, user):
        return
    old = list(
        (
            await db.execute(
                select(AgentMemory).where(
                    AgentMemory.user_id == user.id,
                    AgentMemory.memory_type == "summary",
                    AgentMemory.status == "active",
                )
            )
        ).scalars()
    )
    new = AgentMemory(
        user_id=user.id,
        memory_type="summary",
        content=content[:1500],
        importance=4,
        source_type="weekly_review",
        status="active",
    )
    db.add(new)
    await db.flush()
    for m in old:
        m.status, m.superseded_by = "superseded", new.id
