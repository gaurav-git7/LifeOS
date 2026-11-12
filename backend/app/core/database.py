from collections.abc import AsyncIterator

from sqlalchemy import MetaData, event
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from .config import settings

NAMING = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING)


_engine: AsyncEngine | None = None
_sessionmaker: async_sessionmaker[AsyncSession] | None = None


def _make_engine(url: str) -> AsyncEngine:
    if url.startswith("postgresql"):
        # search_path keeps app tables in their own schema (not exposed by
        # Supabase's Data API). statement_cache_size=0 keeps asyncpg working
        # behind Supabase's poolers.
        return create_async_engine(
            url,
            echo=settings.DB_ECHO,
            pool_pre_ping=True,
            pool_size=5,
            max_overflow=5,
            connect_args={
                "statement_cache_size": 0,
                "server_settings": {"search_path": f"{settings.DB_SCHEMA},public"},
            },
        )
    engine = create_async_engine(url, echo=settings.DB_ECHO)

    @event.listens_for(engine.sync_engine, "connect")
    def _sqlite_pragmas(dbapi_conn, _):  # pragma: no cover - trivial
        cur = dbapi_conn.cursor()
        cur.execute("PRAGMA foreign_keys=ON")
        cur.close()

    return engine


def configure(url: str | None = None) -> None:
    """(Re)create the engine. Called at import and by tests."""
    global _engine, _sessionmaker
    _engine = _make_engine(url or settings.DATABASE_URL)
    _sessionmaker = async_sessionmaker(_engine, expire_on_commit=False)


def engine() -> AsyncEngine:
    assert _engine is not None
    return _engine


def session_factory() -> async_sessionmaker[AsyncSession]:
    assert _sessionmaker is not None
    return _sessionmaker


async def get_db() -> AsyncIterator[AsyncSession]:
    """Request-scoped session. Services commit explicitly."""
    async with session_factory()() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise


configure()
