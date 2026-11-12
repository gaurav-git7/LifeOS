import uuid
from typing import Annotated

import jwt
from fastapi import Depends, Header
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import User
from .config import settings
from .database import get_db
from .errors import AppError
from .security import constant_time_equals, decode_access_token

DB = Annotated[AsyncSession, Depends(get_db)]

_bearer = HTTPBearer(auto_error=False)


async def get_current_user(
    db: DB,
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> User:
    if creds is None:
        raise AppError("not_authenticated", "Sign in required.", 401)
    try:
        data = decode_access_token(creds.credentials)
    except jwt.ExpiredSignatureError as e:
        raise AppError("token_expired", "Session expired.", 401) from e
    except jwt.PyJWTError as e:
        raise AppError("invalid_token", "Invalid session.", 401) from e

    user = await db.get(User, uuid.UUID(data["sub"]))
    if user is None or user.status != "active" or data.get("ver") != user.token_version:
        raise AppError("invalid_token", "Invalid session.", 401)
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


async def require_admin(user: CurrentUser) -> User:
    if user.role != "admin":
        raise AppError("forbidden", "Admins only.", 403)
    return user


AdminUser = Annotated[User, Depends(require_admin)]


async def require_job_secret(x_job_secret: Annotated[str | None, Header()] = None) -> None:
    if not x_job_secret or not constant_time_equals(x_job_secret, settings.JOB_SECRET):
        raise AppError("forbidden", "Invalid job secret.", 403)
