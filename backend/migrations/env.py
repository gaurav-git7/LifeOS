"""Alembic environment (async). Tables live in the `app` schema on Postgres
(not exposed by Supabase's Data API); SQLite is used for local dev/tests."""

import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy import pool, text
from sqlalchemy.ext.asyncio import async_engine_from_config

import app.models  # noqa: F401  (registers all tables)
from app.core.config import settings
from app.core.database import Base
from app.core.types import UTCDateTime

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata
url = config.attributes.get("url") or settings.DATABASE_URL
config.set_main_option("sqlalchemy.url", url.replace("%", "%%"))


def render_item(type_, obj, autogen_context):
    """Render our portable types as plain SQLAlchemy types in migration files."""
    if type_ == "type" and isinstance(obj, UTCDateTime):
        return "sa.DateTime(timezone=True)"
    return False


def _configure(connection=None, **kw):
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        render_item=render_item,
        render_as_batch=connection is not None and connection.dialect.name == "sqlite",
        compare_type=True,
        **kw,
    )


def run_migrations_offline() -> None:
    _configure(url=url, literal_binds=True, dialect_opts={"paramstyle": "named"})
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection) -> None:
    if connection.dialect.name == "postgresql":
        connection.execute(text(f'CREATE SCHEMA IF NOT EXISTS "{settings.DB_SCHEMA}"'))
        connection.execute(text(f'SET search_path TO "{settings.DB_SCHEMA}", public'))
        connection.commit()
    _configure(connection)
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    connect_args = {"statement_cache_size": 0} if url.startswith("postgresql") else {}
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
        connect_args=connect_args,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_async_migrations())
