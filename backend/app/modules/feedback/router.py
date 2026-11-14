"""Crash reports and feedback from the app.

Free alternative to a crash-reporting service: the app posts errors here and
they land in app.client_reports. The same crash from the same user is stored
once with a counter. Feedback also pushes a notification to admins.
"""

import hashlib
import uuid
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select

from ...core.deps import DB, AdminUser, CurrentUser
from ...core.rate_limit import limiter
from ...core.types import utcnow
from ...models import ClientReport, User
from ...notifications.push import notify

router = APIRouter(tags=["feedback"])


class CrashIn(BaseModel):
    message: str = Field(min_length=1, max_length=2000)
    stack: str | None = Field(default=None, max_length=12_000)
    app_version: str | None = Field(default=None, max_length=32)


class FeedbackIn(BaseModel):
    kind: Literal["bug", "idea", "other"] = "other"
    message: str = Field(min_length=1, max_length=4000)
    app_version: str | None = Field(default=None, max_length=32)
    screen: str | None = Field(default=None, max_length=120)


class ReportRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    kind: str
    message: str
    details: str | None
    app_version: str | None
    count: int
    status: str
    created_at: datetime
    last_seen_at: datetime


def _fingerprint(message: str, stack: str | None) -> str:
    # Message + the first few stack frames: line numbers shift between builds less than text does.
    head = "\n".join((stack or "").splitlines()[:6])
    return hashlib.sha256(f"{message}\n{head}".encode()).hexdigest()[:64]


@router.post("/client-errors", status_code=204)
@limiter.limit("30/hour")
async def report_crash(request: Request, body: CrashIn, db: DB, user: CurrentUser):
    fp = _fingerprint(body.message, body.stack)
    row = await db.scalar(
        select(ClientReport).where(ClientReport.user_id == user.id, ClientReport.fingerprint == fp)
    )
    if row is None:
        db.add(
            ClientReport(
                user_id=user.id,
                kind="crash",
                message=body.message,
                details=body.stack,
                app_version=body.app_version,
                fingerprint=fp,
            )
        )
    else:
        row.count += 1
        row.last_seen_at = utcnow()
        row.app_version = body.app_version or row.app_version
        if row.status == "fixed":
            row.status = "new"  # it came back
    await db.commit()


@router.post("/feedback", status_code=201)
@limiter.limit("10/hour")
async def send_feedback(request: Request, body: FeedbackIn, db: DB, user: CurrentUser):
    db.add(
        ClientReport(
            user_id=user.id,
            kind=body.kind,
            message=body.message,
            details=body.screen,
            app_version=body.app_version,
        )
    )
    admins = (await db.execute(select(User).where(User.role == "admin", User.id != user.id))).scalars()
    for admin in admins:
        await notify(
            db,
            admin,
            "feedback",
            f"Feedback from {user.display_name}",
            body.message[:140],
        )
    await db.commit()
    return {"message": "Thanks — sent."}


@router.get("/admin/reports", response_model=list[ReportRead], tags=["admin"])
async def list_reports(db: DB, admin: AdminUser, status: str | None = None, limit: int = 100):
    q = select(ClientReport).order_by(ClientReport.last_seen_at.desc()).limit(min(limit, 500))
    if status:
        q = q.where(ClientReport.status == status)
    return [ReportRead.model_validate(r) for r in (await db.execute(q)).scalars()]
