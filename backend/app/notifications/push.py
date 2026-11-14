"""Server push via Firebase Cloud Messaging. ARCHITECTURE.md §14.

Reminders are scheduled *on the phone*; FCM is only for things the server
creates (reviews, proposals, achievements).
"""

import base64
import json
import logging
import uuid
from datetime import time

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.concurrency import run_in_threadpool

from ..core.config import settings
from ..core.time import local_now
from ..core.types import utcnow
from ..models import DeviceToken, NotificationLog, User, UserPreferences

log = logging.getLogger("lifeos.push")
_firebase_app = None
_firebase_failed = False

CHANNELS = {
    "review": "reviews",
    "proposal": "agent",
    "agent_job": "agent",
    "achievement": "achievements",
    "level_up": "achievements",
    "celebration": "achievements",
    "update": "updates",
    "feedback": "updates",
}


def _firebase():
    global _firebase_app, _firebase_failed
    if _firebase_app or _firebase_failed or not settings.FIREBASE_CREDENTIALS_JSON:
        return _firebase_app
    try:
        import firebase_admin
        from firebase_admin import credentials

        raw = settings.FIREBASE_CREDENTIALS_JSON.strip()
        if not raw.startswith("{"):
            raw = base64.b64decode(raw).decode()
        _firebase_app = firebase_admin.initialize_app(credentials.Certificate(json.loads(raw)), name="lifeos")
    except Exception:  # noqa: BLE001
        _firebase_failed = True
        log.exception("Firebase init failed; push disabled")
    return _firebase_app


def _in_quiet_hours(now: time, start: time | None, end: time | None) -> bool:
    if not start or not end:
        return False
    if start <= end:
        return start <= now < end
    return now >= start or now < end  # crosses midnight


def _send_multicast(tokens: list[str], title: str, body: str, data: dict, channel: str):
    from firebase_admin import messaging

    msg = messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(title=title, body=body),
        data={k: str(v) for k, v in data.items()},
        android=messaging.AndroidConfig(
            priority="high", notification=messaging.AndroidNotification(channel_id=channel)
        ),
    )
    return messaging.send_each_for_multicast(msg, app=_firebase_app)


async def notify(
    db: AsyncSession,
    user: User,
    kind: str,
    title: str,
    body: str,
    *,
    dedupe_key: str | None = None,
    data: dict | None = None,
) -> NotificationLog | None:
    """Send a push to all of the user's devices. Idempotent via dedupe_key."""
    prefs = await db.get(UserPreferences, user.id)
    if prefs and not prefs.notifications_enabled:
        return None
    if dedupe_key:
        exists = await db.scalar(select(NotificationLog.id).where(NotificationLog.dedupe_key == dedupe_key))
        if exists:
            return None

    entry = NotificationLog(
        id=uuid.uuid4(),
        user_id=user.id,
        kind=kind,
        channel="fcm",
        title=title,
        body=body,
        dedupe_key=dedupe_key,
        attempts=1,
    )
    db.add(entry)

    if prefs and _in_quiet_hours(
        local_now(user.timezone).time(), prefs.quiet_hours_start, prefs.quiet_hours_end
    ):
        entry.status, entry.error = "skipped", "quiet_hours"
        return entry

    devices = list(
        (
            await db.execute(
                select(DeviceToken).where(
                    DeviceToken.user_id == user.id, DeviceToken.invalidated_at.is_(None)
                )
            )
        ).scalars()
    )
    if not devices or _firebase() is None:
        entry.status, entry.error = "skipped", "no_devices" if not devices else "fcm_not_configured"
        return entry

    try:
        resp = await run_in_threadpool(
            _send_multicast,
            [d.fcm_token for d in devices],
            title,
            body,
            {"kind": kind, **(data or {})},
            CHANNELS.get(kind, "agent"),
        )
        for device, r in zip(devices, resp.responses, strict=False):
            if not r.success and r.exception is not None and "Unregistered" in type(r.exception).__name__:
                device.invalidated_at = utcnow()
        entry.status = "sent" if resp.success_count else "failed"
        entry.sent_at = utcnow() if resp.success_count else None
        if not resp.success_count:
            entry.error = "all devices failed"
    except Exception as e:  # noqa: BLE001
        log.exception("FCM send failed")
        entry.status, entry.error = "failed", str(e)[:500]
    return entry
