from functools import lru_cache
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """All configuration comes from environment variables (or backend/.env).

    See docs/ARCHITECTURE.md §19.2 and docs/SETUP.md.
    """

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    APP_ENV: Literal["development", "test", "production"] = "development"
    APP_VERSION: str = "0.1.0"

    # Database. Local default is SQLite so the API runs with zero setup.
    # Production: postgresql+asyncpg://... (Supabase session pooler).
    DATABASE_URL: str = "sqlite+aiosqlite:///./lifeos_dev.db"
    DB_SCHEMA: str = "app"  # Postgres schema for app tables (not exposed by Supabase Data API)
    DB_ECHO: bool = False

    # Auth
    JWT_SECRET: str = "dev-only-change-me-dev-only-change-me"
    ACCESS_TOKEN_MINUTES: int = 15
    REFRESH_TOKEN_DAYS: int = 30
    REGISTRATION_MODE: Literal["open", "invite", "closed"] = "open"
    PUBLIC_APP_URL: str = "http://localhost:8000"  # used in email links

    # Internal job endpoints (called by pg_cron)
    JOB_SECRET: str = "dev-job-secret"

    # AI
    GEMINI_API_KEY: str = ""
    # "-latest" aliases follow Google's newest Flash / Flash-Lite / Pro, so a model
    # retirement (like gemini-2.5-flash, Nov 2026) doesn't break the assistant.
    GEMINI_MODEL_LITE: str = "gemini-flash-lite-latest"
    GEMINI_MODEL_DEFAULT: str = "gemini-flash-latest"
    GEMINI_MODEL_PRO: str = "gemini-pro-latest"
    # USD per 1M tokens (input, output), used for the daily budget estimate only.
    # Rough, on the high side; unknown models count at the "flash" price.
    GEMINI_PRICES: dict[str, tuple[float, float]] = Field(
        default_factory=lambda: {
            "gemini-flash-lite-latest": (0.10, 0.40),
            "gemini-flash-latest": (0.50, 3.00),
            "gemini-pro-latest": (2.00, 12.0),
            "gemini-2.5-flash-lite": (0.10, 0.40),
            "gemini-2.5-flash": (0.30, 2.50),
            "gemini-2.5-pro": (1.25, 10.0),
        }
    )
    AI_DAILY_BUDGET_USD: float = 0.10
    # Per-person caps on AI calls (admins are exempt). Protects the shared Gemini key.
    AI_CALLS_PER_MINUTE: int = 4
    AI_CALLS_PER_DAY: int = 40
    LLM_PROVIDER: Literal["auto", "gemini", "fake"] = "auto"  # auto = gemini if key set, else fake

    # Notifications
    FIREBASE_CREDENTIALS_JSON: str = ""  # service-account JSON, raw or base64
    EMAIL_PROVIDER: Literal["console", "resend", "smtp"] = "console"
    EMAIL_FROM: str = "LifeOS <onboarding@resend.dev>"
    RESEND_API_KEY: str = ""
    SMTP_HOST: str = "smtp.gmail.com"
    SMTP_PORT: int = 587
    SMTP_USER: str = ""
    SMTP_PASSWORD: str = ""

    # Storage (Supabase) — used for exports/backups if configured
    SUPABASE_URL: str = ""
    SUPABASE_SERVICE_KEY: str = ""

    # Misc
    CORS_ORIGINS: list[str] = Field(default_factory=list)
    RATE_LIMIT_ENABLED: bool = True
    SENTRY_DSN: str = ""

    @property
    def is_postgres(self) -> bool:
        return self.DATABASE_URL.startswith("postgresql")

    @property
    def llm_provider(self) -> str:
        if self.LLM_PROVIDER != "auto":
            return self.LLM_PROVIDER
        return "gemini" if self.GEMINI_API_KEY else "fake"


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
