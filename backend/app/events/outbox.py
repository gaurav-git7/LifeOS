"""Transactional outbox. ARCHITECTURE.md §10.

Services call `emit()` inside their transaction; routers call
`commit_and_dispatch()` so the event row commits atomically with the change
and is then processed right away in a background task (fast path).
The pg_cron sweeper catches anything the fast path missed.
"""

import uuid

from fastapi import BackgroundTasks
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.serialize import jsonable
from ..models import ActivityEvent

_PENDING_KEY = "pending_event_ids"


def emit(
    db: AsyncSession,
    user_id: uuid.UUID,
    event_type: str,
    *,
    entity_type: str | None = None,
    entity_id: uuid.UUID | None = None,
    payload: dict | None = None,
) -> ActivityEvent:
    ev = ActivityEvent(
        id=uuid.uuid4(),
        user_id=user_id,
        event_type=event_type,
        entity_type=entity_type,
        entity_id=entity_id,
        payload=jsonable(payload or {}),
    )
    db.add(ev)
    db.info.setdefault(_PENDING_KEY, []).append(ev.id)
    return ev


async def commit_and_dispatch(db: AsyncSession, bg: BackgroundTasks | None = None) -> None:
    await db.commit()
    ids = db.info.pop(_PENDING_KEY, [])
    if bg is not None:
        from .dispatcher import process_event_by_id

        for event_id in ids:
            bg.add_task(process_event_by_id, event_id)
