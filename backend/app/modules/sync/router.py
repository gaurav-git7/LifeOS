"""Offline sync. ARCHITECTURE.md §15.2.

push: each change carries the version it was based on. Matching version →
applied (version + 1). Different version → conflict, server copy returned.
Journal entries are never overwritten: a conflicting edit becomes a copy.
Each change has a change_id so retries are idempotent.

pull: everything (including soft-deleted tombstones) changed after `since`.
"""

import uuid
from datetime import date, datetime
from typing import Any, Literal

from fastapi import APIRouter, BackgroundTasks
from pydantic import BaseModel, Field, ValidationError
from sqlalchemy import select

from ...core.crud import CrudSpec, check_refs
from ...core.deps import DB, CurrentUser
from ...core.errors import AppError
from ...core.serialize import jsonable, row_to_dict
from ...core.types import utcnow
from ...events.outbox import commit_and_dispatch
from ...models import SYNC_ENTITIES, Habit, HabitLog, IdempotencyKey, User
from ..goals.router import goal_spec, milestone_spec
from ..habits.router import HabitLogIn, log_habit
from ..habits.router import spec as habit_spec
from ..journal.router import journal_spec, mood_spec
from ..learning.router import path_spec, project_spec, session_spec, skill_spec, topic_spec
from ..planner.router import block_spec, reminder_spec
from ..tasks.router import spec as task_spec

SPECS: dict[str, CrudSpec] = {
    "tasks": task_spec,
    "goals": goal_spec,
    "goal_milestones": milestone_spec,
    "habits": habit_spec,
    "reminders": reminder_spec,
    "schedule_blocks": block_spec,
    "mood_entries": mood_spec,
    "journal_entries": journal_spec,
    "learning_paths": path_spec,
    "skills": skill_spec,
    "learning_topics": topic_spec,
    "study_sessions": session_spec,
    "projects": project_spec,
}
PULL_LIMIT = 500

router = APIRouter(prefix="/sync", tags=["sync"])


class Change(BaseModel):
    change_id: str = Field(min_length=8, max_length=128)
    entity: str
    op: Literal["upsert", "delete"]
    id: uuid.UUID
    base_version: int | None = None  # None = new item
    data: dict[str, Any] = Field(default_factory=dict)


class PushIn(BaseModel):
    changes: list[Change] = Field(max_length=500)


class ChangeResult(BaseModel):
    change_id: str
    status: Literal["applied", "conflict", "rejected"]
    id: uuid.UUID
    version: int | None = None
    server: dict | None = None
    error: str | None = None


async def _apply(db, user: User, ch: Change) -> ChangeResult:
    model = SYNC_ENTITIES.get(ch.entity)
    if model is None:
        return ChangeResult(change_id=ch.change_id, status="rejected", id=ch.id, error="unknown entity")
    spec = SPECS.get(ch.entity)
    row = await db.get(model, ch.id)

    if row is not None and row.user_id != user.id:
        return ChangeResult(change_id=ch.change_id, status="rejected", id=ch.id, error="not yours")

    if ch.op == "delete":
        if row is None:
            return ChangeResult(change_id=ch.change_id, status="applied", id=ch.id)
        if ch.base_version is not None and row.version != ch.base_version:
            return ChangeResult(
                change_id=ch.change_id,
                status="conflict",
                id=ch.id,
                version=row.version,
                server=row_to_dict(row),
            )
        row.deleted_at = row.deleted_at or utcnow()
        row.version += 1
        return ChangeResult(change_id=ch.change_id, status="applied", id=ch.id, version=row.version)

    try:
        if ch.entity == "habit_logs":
            return await _apply_habit_log(db, user, ch, row)
        if row is None:
            if spec is None:
                return ChangeResult(change_id=ch.change_id, status="rejected", id=ch.id, error="not syncable")
            else:
                payload = spec.create_schema.model_validate({**ch.data, "id": ch.id})
                values = payload.model_dump(exclude_unset=True)
                values.pop("id", None)
                if spec.before_create:
                    await spec.before_create(db, user, values)
                await check_refs(db, user.id, values, spec.refs)
                row = model(id=ch.id, user_id=user.id, **values)
                db.add(row)
                await db.flush()
                if spec.on_create:
                    await spec.on_create(db, user, row, values)
            return ChangeResult(change_id=ch.change_id, status="applied", id=ch.id, version=row.version)

        if ch.base_version != row.version:
            if ch.entity == "journal_entries" and "content" in ch.data:
                # never overwrite a journal: keep both versions
                copy = model(
                    id=uuid.uuid4(),
                    user_id=user.id,
                    entry_date=row.entry_date,
                    title=f"{row.title or 'Entry'} (conflict copy)",
                    content=ch.data["content"],
                    ai_allowed=row.ai_allowed,
                    word_count=len(ch.data["content"].split()),
                )
                db.add(copy)
                return ChangeResult(
                    change_id=ch.change_id,
                    status="conflict",
                    id=ch.id,
                    version=row.version,
                    server=row_to_dict(row),
                    error=f"saved as copy {copy.id}",
                )
            return ChangeResult(
                change_id=ch.change_id,
                status="conflict",
                id=ch.id,
                version=row.version,
                server=row_to_dict(row),
            )

        if spec is None:
            return ChangeResult(change_id=ch.change_id, status="rejected", id=ch.id, error="not syncable")
        else:
            changes = spec.update_schema.model_validate(ch.data).model_dump(exclude_unset=True)
            if spec.before_update:
                await spec.before_update(db, user, changes)
            await check_refs(db, user.id, changes, spec.refs)
        before = {k: getattr(row, k) for k in changes}
        for k, v in changes.items():
            setattr(row, k, v)
        row.version += 1
        row.updated_at = utcnow()
        if spec is not None and spec.on_update:
            await spec.on_update(db, user, row, {"changes": changes, "before": before})
        return ChangeResult(change_id=ch.change_id, status="applied", id=ch.id, version=row.version)
    except (ValidationError, AppError, TypeError) as e:
        msg = e.message if isinstance(e, AppError) else str(e)[:300]
        return ChangeResult(change_id=ch.change_id, status="rejected", id=ch.id, error=msg)


class _HabitLogSync(HabitLogIn):
    habit_id: uuid.UUID
    log_date: date


async def _apply_habit_log(db, user: User, ch: Change, row: HabitLog | None) -> ChangeResult:
    """Habit logs go through the same code as the API (streaks + XP)."""
    if row is not None and ch.base_version is not None and row.version != ch.base_version:
        return ChangeResult(
            change_id=ch.change_id, status="conflict", id=ch.id, version=row.version, server=row_to_dict(row)
        )
    data = _HabitLogSync.model_validate({**(row_to_dict(row) if row else {}), **ch.data})
    habit = await db.get(Habit, data.habit_id)
    if habit is None or habit.user_id != user.id:
        return ChangeResult(change_id=ch.change_id, status="rejected", id=ch.id, error="unknown habit")
    if row is None:  # keep the client's id for the new row
        existing = await db.scalar(
            select(HabitLog).where(HabitLog.habit_id == habit.id, HabitLog.log_date == data.log_date)
        )
        if existing is None:
            db.add(
                HabitLog(
                    id=ch.id,
                    user_id=user.id,
                    habit_id=habit.id,
                    log_date=data.log_date,
                    status="skipped",
                    version=0,
                )
            )
            await db.flush()
    log = await log_habit(db, user, habit, data.log_date, data.status, data.note)
    return ChangeResult(change_id=ch.change_id, status="applied", id=log.id, version=log.version)


@router.post("/push", response_model=list[ChangeResult])
async def push(body: PushIn, db: DB, user: CurrentUser, bg: BackgroundTasks):
    results: list[ChangeResult] = []
    for ch in body.changes:
        prior = await db.scalar(
            select(IdempotencyKey).where(
                IdempotencyKey.user_id == user.id, IdempotencyKey.key == ch.change_id
            )
        )
        if prior:
            results.append(ChangeResult.model_validate(prior.response))
            continue
        async with db.begin_nested():  # each change applies on its own
            result = await _apply(db, user, ch)
        if result.status != "rejected":
            db.add(
                IdempotencyKey(
                    user_id=user.id,
                    key=ch.change_id,
                    endpoint="sync.push",
                    response=jsonable(result.model_dump()),
                )
            )
        results.append(result)
    await commit_and_dispatch(db, bg)
    return results


@router.get("/pull")
async def pull(db: DB, user: CurrentUser, since: datetime | None = None):
    """Returns {cursor, changes: {entity: [rows]}, has_more}. Pass `cursor` back as `since`."""
    upper = utcnow()
    out: dict[str, list] = {}
    has_more = False
    for name, model in SYNC_ENTITIES.items():
        q = select(model).where(model.user_id == user.id, model.updated_at <= upper)
        if since is not None:
            q = q.where(model.updated_at > since)
        rows = list((await db.execute(q.order_by(model.updated_at).limit(PULL_LIMIT + 1))).scalars())
        if len(rows) > PULL_LIMIT:
            has_more = True
            rows = rows[:PULL_LIMIT]
            upper = min(upper, rows[-1].updated_at)
        out[name] = [row_to_dict(r) for r in rows]
    if has_more:  # keep every entity consistent with the lowest cut-off
        out = {k: [r for r in v if r["updated_at"] <= upper.isoformat()] for k, v in out.items()}
    return {"cursor": upper, "has_more": has_more, "changes": out}
