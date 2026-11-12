"""Processes outbox events. ARCHITECTURE.md §10.2.

- Claim with FOR UPDATE SKIP LOCKED so the fast path and the pg_cron sweeper
  never process the same event twice.
- Failures retry with exponential backoff, giving up after 5 attempts.
- Handlers must be idempotent.
"""

import logging
import uuid
from collections.abc import Awaitable, Callable
from datetime import timedelta

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.database import session_factory
from ..core.types import utcnow
from ..models import ActivityEvent, User

log = logging.getLogger("lifeos.events")
MAX_ATTEMPTS = 5

Handler = Callable[[AsyncSession, User, ActivityEvent], Awaitable[None]]
HANDLERS: dict[str, list[Handler]] = {}


def on(*event_types: str):
    def register(fn: Handler) -> Handler:
        for t in event_types:
            HANDLERS.setdefault(t, []).append(fn)
        return fn

    return register


async def _claim(db: AsyncSession, event_id: uuid.UUID) -> ActivityEvent | None:
    ev = await db.scalar(
        select(ActivityEvent)
        .where(ActivityEvent.id == event_id, ActivityEvent.status == "pending")
        .with_for_update(skip_locked=True)
    )
    if ev is None:
        return None
    ev.status = "processing"
    ev.attempts += 1
    await db.commit()
    return ev


async def process_event_by_id(event_id: uuid.UUID) -> bool:
    """Returns True if the event was processed successfully by this call."""
    from . import handlers  # noqa: F401  (registers handlers)

    async with session_factory()() as db:
        ev = await _claim(db, event_id)
        if ev is None:
            return False
        try:
            user = await db.get(User, ev.user_id)
            if user is not None:
                for handler in HANDLERS.get(ev.event_type, []):
                    await handler(db, user, ev)
            ev.status = "done"
            ev.processed_at = utcnow()
            ev.last_error = None
            await db.commit()
            # handlers may emit follow-up events (e.g. achievement.unlocked)
            follow_ups = db.info.pop("pending_event_ids", [])
        except Exception as e:  # noqa: BLE001
            log.exception("Event %s (%s) failed", ev.id, ev.event_type)
            await db.rollback()
            ev = await db.get(ActivityEvent, event_id)
            assert ev is not None
            ev.last_error = str(e)[:1000]
            if ev.attempts >= MAX_ATTEMPTS:
                ev.status = "failed"
            else:
                ev.status = "pending"
                ev.next_attempt_at = utcnow() + timedelta(minutes=2**ev.attempts)
            await db.commit()
            return False
    for fid in follow_ups:
        await process_event_by_id(fid)
    return True


async def sweep(limit: int = 50) -> int:
    """Process due pending events (and recover ones stuck in 'processing')."""
    now = utcnow()
    async with session_factory()() as db:
        stuck_before = now - timedelta(minutes=10)
        stuck = (
            await db.execute(
                select(ActivityEvent).where(
                    ActivityEvent.status == "processing", ActivityEvent.next_attempt_at < stuck_before
                )
            )
        ).scalars()
        for ev in stuck:
            ev.status = "pending"
        await db.commit()
        ids = list(
            (
                await db.execute(
                    select(ActivityEvent.id)
                    .where(
                        ActivityEvent.status == "pending",
                        or_(ActivityEvent.next_attempt_at <= now, ActivityEvent.next_attempt_at.is_(None)),
                    )
                    .order_by(ActivityEvent.occurred_at)
                    .limit(limit)
                )
            ).scalars()
        )
    done = 0
    for event_id in ids:
        done += await process_event_by_id(event_id)
    return done
