"""Password hashing, JWTs and opaque tokens. See ARCHITECTURE.md §9."""

import hashlib
import hmac
import secrets
import uuid
from datetime import timedelta

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

from .config import settings
from .types import utcnow

_hasher = PasswordHasher()  # Argon2id with library defaults

# A small list of passwords that are always rejected.
COMMON_PASSWORDS = {
    "password",
    "password1",
    "password123",
    "1234567890",
    "qwertyuiop",
    "iloveyou12",
    "123456789a",
    "admin12345",
    "welcome123",
    "letmein123",
    "qwerty1234",
    "passw0rd12",
}


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, hashed: str) -> bool:
    try:
        return _hasher.verify(hashed, password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def password_problem(password: str) -> str | None:
    if len(password) < 10:
        return "Password must be at least 10 characters."
    if password.lower() in COMMON_PASSWORDS:
        return "This password is too common."
    return None


def create_access_token(user_id: uuid.UUID, token_version: int) -> str:
    now = utcnow()
    payload = {
        "sub": str(user_id),
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=settings.ACCESS_TOKEN_MINUTES)).timestamp()),
        "jti": secrets.token_hex(8),
        "ver": token_version,
        "typ": "access",
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm="HS256")


def decode_access_token(token: str) -> dict:
    """Raises jwt.PyJWTError on invalid/expired tokens."""
    data = jwt.decode(token, settings.JWT_SECRET, algorithms=["HS256"])
    if data.get("typ") != "access":
        raise jwt.InvalidTokenError("wrong token type")
    return data


def new_opaque_token() -> str:
    """256-bit random token for refresh / email / invite links."""
    return secrets.token_urlsafe(32)


def sha256(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def constant_time_equals(a: str, b: str) -> bool:
    return hmac.compare_digest(a.encode(), b.encode())
