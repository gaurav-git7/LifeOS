"""Profile, preferences, devices, data export, account deletion, invites."""

import uuid
from datetime import time, timedelta
from typing import Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from sqlalchemy import delete, select

from ...core.audit import audit
from ...core.deps import DB, AdminUser, CurrentUser
from ...core.errors import AppError, not_found
from ...core.security import new_opaque_token, sha256
from ...core.serialize import row_to_dict
from ...core.time import valid_timezone
from ...core.types import utcnow
from ...models import (
    SYNC_ENTITIES,
    ActionProposal,
    AgentConversation,
    AgentMemory,
    AgentMessage,
    DailySummary,
    DeviceToken,
    Invite,
    User,
    UserAchievement,
    UserPreferences,
    WeeklySummary,
    XpLedger,
)
from ..auth.schemas import UserRead

router = APIRouter(tags=["users"])


class UserUpdate(BaseModel):
    display_name: str | None = Field(default=None, min_length=1, max_length=80)
    timezone: str | None = None


class PreferencesRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    theme: str
    week_start_day: int
    daily_review_enabled: bool
    daily_review_time: time
    weekly_review_enabled: bool
    weekly_review_day: int
    notifications_enabled: bool
    quiet_hours_start: time | None
    quiet_hours_end: time | None
    ai_enabled: bool
    ai_memory_enabled: bool
    mood_ai_enabled: bool
    journal_ai_enabled: bool
    ai_daily_budget_usd: float | None
    reduce_motion: bool
    ambient_intensity: str


class PreferencesUpdate(BaseModel):
    theme: Literal["system", "light", "dark"] | None = None
    week_start_day: int | None = Field(default=None, ge=1, le=7)
    daily_review_enabled: bool | None = None
    daily_review_time: time | None = None
    weekly_review_enabled: bool | None = None
    weekly_review_day: int | None = Field(default=None, ge=1, le=7)
    notifications_enabled: bool | None = None
    quiet_hours_start: time | None = None
    quiet_hours_end: time | None = None
    ai_enabled: bool | None = None
    ai_memory_enabled: bool | None = None
    mood_ai_enabled: bool | None = None
    journal_ai_enabled: bool | None = None
    ai_daily_budget_usd: float | None = Field(default=None, ge=0, le=5)
    reduce_motion: bool | None = None
    ambient_intensity: Literal["off", "low", "normal"] | None = None


@router.get("/users/me", response_model=UserRead)
async def me(user: CurrentUser):
    return UserRead.model_validate(user)


@router.patch("/users/me", response_model=UserRead)
async def update_me(body: UserUpdate, db: DB, user: CurrentUser):
    if body.timezone is not None and not valid_timezone(body.timezone):
        raise AppError("invalid_timezone", "Unknown timezone.", 422)
    for k, v in body.model_dump(exclude_unset=True, exclude_none=True).items():
        setattr(user, k, v)
    await db.commit()
    return UserRead.model_validate(user)


async def _prefs(db, user: User) -> UserPreferences:
    prefs = await db.get(UserPreferences, user.id)
    if prefs is None:
        prefs = UserPreferences(user_id=user.id)
        db.add(prefs)
        await db.flush()
    return prefs


@router.get("/users/me/preferences", response_model=PreferencesRead)
async def get_preferences(db: DB, user: CurrentUser):
    prefs = await _prefs(db, user)
    await db.commit()
    return PreferencesRead.model_validate(prefs)


@router.patch("/users/me/preferences", response_model=PreferencesRead)
async def update_preferences(body: PreferencesUpdate, db: DB, user: CurrentUser):
    prefs = await _prefs(db, user)
    changes = body.model_dump(exclude_unset=True)
    for k, v in changes.items():
        setattr(prefs, k, v)
    if any(k.endswith("_ai_enabled") or k == "ai_memory_enabled" for k in changes):
        audit(
            db, user.id, "privacy.ai_consent_changed", after={k: v for k, v in changes.items() if "ai" in k}
        )
    await db.commit()
    return PreferencesRead.model_validate(prefs)


@router.get("/users/me/export")
async def export_data(request: Request, db: DB, user: CurrentUser):
    """Everything LifeOS stores about you, as JSON."""
    out: dict = {"user": UserRead.model_validate(user).model_dump(mode="json")}
    prefs = await db.get(UserPreferences, user.id)
    out["preferences"] = row_to_dict(prefs) if prefs else None
    for name, model in {
        **SYNC_ENTITIES,
        "agent_conversations": AgentConversation,
        "agent_messages": AgentMessage,
        "agent_memories": AgentMemory,
        "action_proposals": ActionProposal,
        "daily_summaries": DailySummary,
        "weekly_summaries": WeeklySummary,
        "xp_ledger": XpLedger,
        "user_achievements": UserAchievement,
    }.items():
        rows = (await db.execute(select(model).where(model.user_id == user.id))).scalars()
        out[name] = [row_to_dict(r) for r in rows]
    audit(db, user.id, "data.exported", ip=request.client.host if request.client else None)
    await db.commit()
    return out


@router.delete("/users/me", status_code=204)
async def delete_account(db: DB, user: CurrentUser):
    """Hard-deletes the account and all data (FK cascades + explicit deletes)."""
    audit(db, None, "account.deleted", after={"user_id": str(user.id)})
    for table in reversed(User.metadata.sorted_tables):
        if "user_id" in table.c and table.name != "audit_logs":
            await db.execute(delete(table).where(table.c.user_id == user.id))
    await db.execute(delete(User).where(User.id == user.id))
    await db.commit()


# ---------- devices (FCM tokens) ----------


class DeviceIn(BaseModel):
    fcm_token: str = Field(min_length=10, max_length=512)
    app_version: str | None = Field(default=None, max_length=32)


class DeviceRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    platform: str
    app_version: str | None
    last_seen_at: object


@router.post("/devices", response_model=DeviceRead, tags=["devices"])
async def register_device(body: DeviceIn, db: DB, user: CurrentUser):
    dev = await db.scalar(select(DeviceToken).where(DeviceToken.fcm_token == body.fcm_token))
    if dev is None:
        dev = DeviceToken(user_id=user.id, fcm_token=body.fcm_token)
        db.add(dev)
    dev.user_id = user.id  # a token moves to whoever signed in on that device last
    dev.app_version = body.app_version
    dev.last_seen_at = utcnow()
    dev.invalidated_at = None
    await db.commit()
    return DeviceRead.model_validate(dev)


@router.delete("/devices/{device_id}", status_code=204, tags=["devices"])
async def remove_device(device_id: uuid.UUID, db: DB, user: CurrentUser):
    dev = await db.get(DeviceToken, device_id)
    if dev is None or dev.user_id != user.id:
        raise not_found("Device")
    await db.delete(dev)
    await db.commit()


# ---------- invites (admin) ----------


class InviteIn(BaseModel):
    email: EmailStr | None = None
    max_uses: int = Field(default=1, ge=1, le=50)
    expires_in_days: int = Field(default=7, ge=1, le=90)


class InviteOut(BaseModel):
    code: str
    expires_at: object
    max_uses: int


@router.post("/admin/invites", response_model=InviteOut, tags=["admin"])
async def create_invite(body: InviteIn, db: DB, admin: AdminUser):
    """Returns the invite code once — it's stored only as a hash."""
    code = new_opaque_token()[:16]
    inv = Invite(
        code_hash=sha256(code),
        email=body.email.lower() if body.email else None,
        created_by=admin.id,
        max_uses=body.max_uses,
        expires_at=utcnow() + timedelta(days=body.expires_in_days),
    )
    db.add(inv)
    audit(db, admin.id, "admin.invite_created", after={"email": inv.email, "max_uses": inv.max_uses})
    await db.commit()
    return InviteOut(code=code, expires_at=inv.expires_at, max_uses=inv.max_uses)
