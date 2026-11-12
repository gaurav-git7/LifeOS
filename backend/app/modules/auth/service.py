"""Auth flows. ARCHITECTURE.md §9.

- Registration respects REGISTRATION_MODE. The very first account is always
  allowed and becomes admin (so you can create invites afterwards).
- Refresh tokens rotate; re-using a revoked one revokes the whole family.
"""

import uuid
from datetime import timedelta

from fastapi import BackgroundTasks
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from ...core.audit import audit
from ...core.config import settings
from ...core.errors import AppError
from ...core.security import (
    create_access_token,
    hash_password,
    new_opaque_token,
    password_problem,
    sha256,
    verify_password,
)
from ...core.time import valid_timezone
from ...core.types import utcnow
from ...models import EmailToken, Invite, RefreshToken, User, UserPreferences
from ...notifications.email import send_reset_email, send_verification_email
from .schemas import RegisterIn, TokenPair, UserRead

VERIFY_TTL = timedelta(hours=24)
RESET_TTL = timedelta(hours=1)


def _check_password(pw: str) -> None:
    problem = password_problem(pw)
    if problem:
        raise AppError("weak_password", problem, 422)


async def _issue_tokens(
    db: AsyncSession, user: User, device_label: str | None, family_id: uuid.UUID | None = None
) -> tuple[TokenPair, RefreshToken]:
    raw = new_opaque_token()
    rt = RefreshToken(
        id=uuid.uuid4(),
        user_id=user.id,
        token_hash=sha256(raw),
        family_id=family_id or uuid.uuid4(),
        device_label=device_label,
        expires_at=utcnow() + timedelta(days=settings.REFRESH_TOKEN_DAYS),
    )
    db.add(rt)
    pair = TokenPair(
        access_token=create_access_token(user.id, user.token_version),
        refresh_token=raw,
        expires_in=settings.ACCESS_TOKEN_MINUTES * 60,
        user=UserRead.model_validate(user),
    )
    return pair, rt


async def _new_email_token(db: AsyncSession, user: User, purpose: str, ttl: timedelta) -> str:
    raw = new_opaque_token()
    db.add(EmailToken(user_id=user.id, purpose=purpose, token_hash=sha256(raw), expires_at=utcnow() + ttl))
    return raw


async def register(db: AsyncSession, data: RegisterIn, bg: BackgroundTasks, ip: str | None) -> TokenPair:
    email = data.email.lower()
    user_count = await db.scalar(select(func.count()).select_from(User))
    first_user = user_count == 0

    invite: Invite | None = None
    if not first_user:
        if settings.REGISTRATION_MODE == "closed":
            raise AppError("registration_closed", "Registration is closed.", 403)
        if settings.REGISTRATION_MODE == "invite":
            if not data.invite_code:
                raise AppError("invite_required", "An invite code is required.", 403)
            invite = await db.scalar(
                select(Invite).where(Invite.code_hash == sha256(data.invite_code.strip()))
            )
            if (
                invite is None
                or invite.expires_at < utcnow()
                or invite.used_count >= invite.max_uses
                or (invite.email and invite.email.lower() != email)
            ):
                raise AppError("invalid_invite", "This invite code is not valid.", 403)

    if await db.scalar(select(User.id).where(User.email == email)):
        raise AppError("email_taken", "An account with this email already exists.", 409)
    _check_password(data.password)
    if not valid_timezone(data.timezone):
        raise AppError("invalid_timezone", "Unknown timezone.", 422)

    user = User(
        id=uuid.uuid4(),
        email=email,
        password_hash=hash_password(data.password),
        display_name=data.display_name.strip(),
        timezone=data.timezone,
        role="admin" if first_user else "user",
        last_login_at=utcnow(),
    )
    db.add(user)
    await db.flush()
    db.add(UserPreferences(user_id=user.id))
    if invite:
        invite.used_count += 1

    token = await _new_email_token(db, user, "verify_email", VERIFY_TTL)
    pair, _ = await _issue_tokens(db, user, data.device_label)
    audit(db, user.id, "auth.register", ip=ip, after={"first_user": first_user})
    await db.commit()
    bg.add_task(send_verification_email, user.email, user.display_name, token)
    return pair


async def login(
    db: AsyncSession, email: str, password: str, device_label: str | None, ip: str | None
) -> TokenPair:
    user = await db.scalar(select(User).where(User.email == email.lower()))
    if user is None or not verify_password(password, user.password_hash):
        raise AppError("invalid_credentials", "Email or password is incorrect.", 401)
    if user.status != "active":
        raise AppError("account_disabled", "This account is disabled.", 403)
    user.last_login_at = utcnow()
    pair, _ = await _issue_tokens(db, user, device_label)
    audit(db, user.id, "auth.login", ip=ip)
    await db.commit()
    return pair


async def refresh(db: AsyncSession, raw: str, ip: str | None) -> TokenPair:
    rt = await db.scalar(select(RefreshToken).where(RefreshToken.token_hash == sha256(raw)))
    if rt is None:
        raise AppError("invalid_token", "Invalid session.", 401)
    if rt.revoked_at is not None:
        # Reuse of a rotated token = likely theft. Kill the whole login family.
        await db.execute(
            update(RefreshToken)
            .where(RefreshToken.family_id == rt.family_id, RefreshToken.revoked_at.is_(None))
            .values(revoked_at=utcnow())
        )
        audit(db, rt.user_id, "auth.refresh_reuse_detected", ip=ip)
        await db.commit()
        raise AppError("token_reused", "Session ended for security. Please sign in again.", 401)
    if rt.expires_at < utcnow():
        raise AppError("token_expired", "Session expired.", 401)
    user = await db.get(User, rt.user_id)
    if user is None or user.status != "active":
        raise AppError("invalid_token", "Invalid session.", 401)

    pair, new_rt = await _issue_tokens(db, user, rt.device_label, family_id=rt.family_id)
    rt.revoked_at = utcnow()
    rt.replaced_by = new_rt.id
    await db.commit()
    return pair


async def logout(db: AsyncSession, user: User, raw: str) -> None:
    rt = await db.scalar(select(RefreshToken).where(RefreshToken.token_hash == sha256(raw)))
    if rt and rt.user_id == user.id and rt.revoked_at is None:
        rt.revoked_at = utcnow()
    await db.commit()


async def logout_all(db: AsyncSession, user: User, ip: str | None = None) -> None:
    user.token_version += 1
    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=utcnow())
    )
    audit(db, user.id, "auth.logout_all", ip=ip)
    await db.commit()


async def _consume_email_token(db: AsyncSession, raw: str, purpose: str) -> EmailToken:
    tok = await db.scalar(
        select(EmailToken).where(EmailToken.token_hash == sha256(raw), EmailToken.purpose == purpose)
    )
    if tok is None or tok.used_at is not None or tok.expires_at < utcnow():
        raise AppError("invalid_token", "This link is invalid or has expired.", 400)
    tok.used_at = utcnow()
    return tok


async def verify_email(db: AsyncSession, raw: str) -> User:
    tok = await _consume_email_token(db, raw, "verify_email")
    user = await db.get(User, tok.user_id)
    assert user is not None
    user.email_verified_at = user.email_verified_at or utcnow()
    await db.commit()
    return user


async def resend_verification(db: AsyncSession, user: User, bg: BackgroundTasks) -> None:
    if user.email_verified_at:
        return
    token = await _new_email_token(db, user, "verify_email", VERIFY_TTL)
    await db.commit()
    bg.add_task(send_verification_email, user.email, user.display_name, token)


async def forgot_password(db: AsyncSession, email: str, bg: BackgroundTasks) -> None:
    """Always succeeds silently — never reveals whether an account exists."""
    user = await db.scalar(select(User).where(User.email == email.lower()))
    if user is None or user.status != "active":
        return
    token = await _new_email_token(db, user, "reset_password", RESET_TTL)
    await db.commit()
    bg.add_task(send_reset_email, user.email, user.display_name, token)


async def reset_password(db: AsyncSession, raw: str, new_password: str, ip: str | None) -> None:
    _check_password(new_password)
    tok = await _consume_email_token(db, raw, "reset_password")
    user = await db.get(User, tok.user_id)
    assert user is not None
    user.password_hash = hash_password(new_password)
    user.token_version += 1
    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=utcnow())
    )
    audit(db, user.id, "auth.password_reset", ip=ip)
    await db.commit()


async def change_password(db: AsyncSession, user: User, current: str, new: str, ip: str | None) -> None:
    if not verify_password(current, user.password_hash):
        raise AppError("invalid_credentials", "Current password is incorrect.", 401)
    _check_password(new)
    user.password_hash = hash_password(new)
    audit(db, user.id, "auth.password_changed", ip=ip)
    await db.commit()
