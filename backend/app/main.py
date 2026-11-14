"""LifeOS API — FastAPI modular monolith. ARCHITECTURE.md §6."""

import logging
from contextlib import asynccontextmanager

from fastapi import APIRouter, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi.errors import RateLimitExceeded
from sqlalchemy import text

from .api.internal import router as internal_router
from .core import database
from .core.config import settings
from .core.errors import install_error_handlers
from .core.rate_limit import limiter
from .modules.agent.router import router as agent_router
from .modules.analytics.router import router as analytics_router
from .modules.auth.router import router as auth_router
from .modules.feedback.router import router as feedback_router
from .modules.goals.router import router as goals_router
from .modules.habits.router import router as habits_router
from .modules.journal.router import router as journal_router
from .modules.learning.router import router as learning_router
from .modules.planner.router import router as planner_router
from .modules.progression.router import router as progression_router
from .modules.progression.service import ensure_catalog
from .modules.sync.router import router as sync_router
from .modules.tasks.router import router as tasks_router
from .modules.users.router import router as users_router

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("lifeos")


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:  # seed the achievements catalog (no-op if already there)
        async with database.session_factory()() as db:
            await ensure_catalog(db)
            await db.commit()
    except Exception:  # noqa: BLE001 — tables may not exist before the first migration
        log.warning("Skipping achievements seed (run `alembic upgrade head`).")
    if settings.APP_ENV == "production" and settings.JWT_SECRET.startswith("dev-only"):
        log.error("JWT_SECRET is the development default — set a real secret!")
    log.info("LifeOS API %s · env=%s · llm=%s", settings.APP_VERSION, settings.APP_ENV, settings.llm_provider)
    yield
    await database.engine().dispose()


def create_app() -> FastAPI:
    app = FastAPI(
        title="LifeOS API",
        version=settings.APP_VERSION,
        description="Personal life OS with a single approval-based AI agent.",
        lifespan=lifespan,
        docs_url="/docs" if settings.APP_ENV != "production" else None,
        redoc_url=None,
    )
    install_error_handlers(app)

    app.state.limiter = limiter

    @app.exception_handler(RateLimitExceeded)
    async def _rate_limited(_, exc: RateLimitExceeded):
        return JSONResponse(
            {
                "error": {
                    "code": "rate_limited",
                    "message": "Too many requests. Try again soon.",
                    "details": {"limit": str(exc.detail)},
                }
            },
            status_code=429,
        )

    if settings.CORS_ORIGINS:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.CORS_ORIGINS,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )

    api = APIRouter(prefix="/api/v1")
    for r in (
        auth_router,
        users_router,
        tasks_router,
        goals_router,
        habits_router,
        planner_router,
        learning_router,
        journal_router,
        progression_router,
        analytics_router,
        agent_router,
        sync_router,
        feedback_router,
    ):
        api.include_router(r)
    app.include_router(api)
    app.include_router(internal_router)

    @app.get("/health", tags=["system"])
    async def health():
        try:
            async with database.engine().connect() as conn:
                await conn.execute(text("SELECT 1"))
            db_ok = True
        except Exception:  # noqa: BLE001
            db_ok = False
        return JSONResponse(
            {"status": "ok" if db_ok else "degraded", "database": db_ok, "version": settings.APP_VERSION},
            status_code=200 if db_ok else 503,
        )

    return app


app = create_app()
