"""Rate limiting (slowapi, in-memory — fine for a single instance). ARCHITECTURE.md §9.3."""

from slowapi import Limiter
from slowapi.util import get_remote_address
from starlette.requests import Request

from .config import settings


def client_key(request: Request) -> str:
    # uvicorn runs with --proxy-headers on Render, so client.host is the real IP.
    return get_remote_address(request)


limiter = Limiter(key_func=client_key, enabled=settings.RATE_LIMIT_ENABLED, headers_enabled=False)
