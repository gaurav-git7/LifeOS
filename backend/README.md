# LifeOS API

FastAPI modular monolith for LifeOS. Design: [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) ·
Setup & deploy: [docs/SETUP.md](../docs/SETUP.md).

## Quick start (no accounts needed)

```powershell
python -m venv .venv
.\.venv\Scripts\python -m pip install -e ".[dev]"
copy .env.example .env
.\.venv\Scripts\alembic upgrade head
.\.venv\Scripts\uvicorn app.main:app --reload    # http://localhost:8000/docs
.\.venv\Scripts\python -m pytest -q
```

Local default is SQLite plus a fake assistant; set `DATABASE_URL` / `GEMINI_API_KEY` for the real thing.

## Layout

```
app/
  core/          config, database, portable types, security, generic CRUD, errors, deps
  models/        all ORM tables (35), grouped by domain
  modules/       auth · users · tasks · goals · habits · planner · learning · journal
                 progression (XP) · analytics · sync · agent
  events/        transactional outbox, dispatcher, deterministic handlers
  jobs/          scheduled jobs (called by pg_cron via /internal/jobs/*)
  notifications/ FCM push + email
  api/internal.py
migrations/      Alembic (tables in the `app` schema on Postgres)
tests/           pytest (SQLite by default; TEST_DATABASE_URL for Postgres)
```

## Key behaviours

- **Generic CRUD** (`core/crud.py`) for every syncable entity: client UUIDs (idempotent create),
  `If-Match` optimistic concurrency, soft delete, ownership checks on referenced ids.
- **Agent** (`modules/agent`): rules first → context → one structured Gemini call → validated proposals.
  Nothing changes until `POST /agent/proposals/{id}/approve` with the exact `payload_hash`.
- **Outbox**: events commit with the change, run right after the response, and are swept every 5 minutes.
- **XP** is awarded once per (reason, source) and reversed when actions are undone.
