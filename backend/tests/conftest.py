import os

# Must be set before the app is imported (settings are cached).
os.environ.update(
    APP_ENV="test",
    RATE_LIMIT_ENABLED="false",
    LLM_PROVIDER="fake",
    EMAIL_PROVIDER="console",
    REGISTRATION_MODE="open",
    JOB_SECRET="test-job-secret",
    JWT_SECRET="test-jwt-secret-test-jwt-secret-1234",
)

import pytest  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402
from sqlalchemy import text  # noqa: E402

from app.core import database  # noqa: E402
from app.core.config import settings  # noqa: E402
from app.core.database import Base  # noqa: E402
from app.main import app  # noqa: E402

API = "/api/v1"
PASSWORD = "correct-horse-battery"


@pytest.fixture
async def db_url(tmp_path):
    url = os.environ.get("TEST_DATABASE_URL") or f"sqlite+aiosqlite:///{(tmp_path / 'test.db').as_posix()}"
    database.configure(url)
    async with database.engine().begin() as conn:
        if url.startswith("postgresql"):
            await conn.execute(text(f'CREATE SCHEMA IF NOT EXISTS "{settings.DB_SCHEMA}"'))
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield url
    await database.engine().dispose()


@pytest.fixture
async def client(db_url):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c


@pytest.fixture
def session(db_url):
    return database.session_factory()


async def register(
    client: AsyncClient,
    email: str = "me@example.com",
    name: str = "Gaurav",
    tz: str = "Asia/Kolkata",
    **extra,
) -> dict:
    r = await client.post(
        f"{API}/auth/register",
        json={"email": email, "password": PASSWORD, "display_name": name, "timezone": tz, **extra},
    )
    assert r.status_code == 201, r.text
    return r.json()


def auth(tokens: dict) -> dict:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


@pytest.fixture
async def user(client) -> dict:
    """Registered user; returns {"tokens", "h" (auth headers)}."""
    tokens = await register(client)
    return {"tokens": tokens, "h": auth(tokens)}
