"""Generic CRUD for user-owned, syncable entities.

Every simple entity (tasks, goals, habits, …) gets the same behaviour:
- list with filters + cursor pagination (`?status=&updated_since=&limit=&cursor=`)
- create — client may send its own UUID; re-sending the same id is idempotent
- get / patch (optimistic concurrency via `If-Match: <version>`) / soft delete
- ownership checks on every referenced id (goal_id, task_id, …)
- hooks so modules can add events, XP, etc.

See ARCHITECTURE.md §6.2 and §18 conventions.
"""

import base64
import uuid
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from datetime import datetime
from typing import Annotated, Any, Generic, TypeVar

from fastapi import APIRouter, BackgroundTasks, Header, Query, Request
from pydantic import BaseModel, ConfigDict
from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..events.outbox import commit_and_dispatch
from ..models import User
from .deps import DB, CurrentUser
from .errors import AppError, not_found
from .types import utcnow

Hook = Callable[[AsyncSession, User, Any, dict], Awaitable[None]]
# Mutates the incoming values before they are written (defaults, JSON-safe conversion, ...)
PrepHook = Callable[[AsyncSession, User, dict], Awaitable[None]]


class EntityRead(BaseModel):
    """Fields every syncable entity returns."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
    version: int


T = TypeVar("T")


class Page(BaseModel, Generic[T]):
    items: list[T]
    next_cursor: str | None = None


@dataclass
class CrudSpec:
    model: type
    create_schema: type[BaseModel]
    update_schema: type[BaseModel]
    read_schema: type[BaseModel]
    label: str
    # field name -> model it must reference (and the user must own)
    refs: dict[str, type] = field(default_factory=dict)
    # query params accepted as equality filters (?status=todo&goal_id=…)
    filter_fields: tuple[str, ...] = ()
    before_create: PrepHook | None = None
    before_update: PrepHook | None = None
    on_create: Hook | None = None
    on_update: Hook | None = None
    on_delete: Hook | None = None


# ---------- service functions ----------


async def get_owned(
    db: AsyncSession,
    model: type,
    obj_id: uuid.UUID,
    user_id: uuid.UUID,
    *,
    label="Item",
    include_deleted: bool = False,
):
    obj = await db.get(model, obj_id)
    if obj is None or obj.user_id != user_id or (not include_deleted and getattr(obj, "deleted_at", None)):
        raise not_found(label)
    return obj


async def check_refs(db: AsyncSession, user_id: uuid.UUID, values: dict, refs: dict[str, type]) -> None:
    for fname, ref_model in refs.items():
        ref_id = values.get(fname)
        if ref_id is None:
            continue
        ref = await db.get(ref_model, ref_id)
        if ref is None or ref.user_id != user_id or getattr(ref, "deleted_at", None):
            raise AppError("invalid_reference", f"{fname} does not exist.", 422, {"field": fname})


async def create_entity(db: AsyncSession, spec: CrudSpec, user: User, data: BaseModel):
    values = data.model_dump(exclude_unset=True)
    obj_id = values.pop("id", None)
    if obj_id is not None:
        existing = await db.get(spec.model, obj_id)
        if existing is not None:
            if existing.user_id != user.id:
                raise AppError("id_conflict", "This id is already used.", 409)
            return existing, False  # idempotent retry
    if spec.before_create:
        await spec.before_create(db, user, values)
    await check_refs(db, user.id, values, spec.refs)
    obj = spec.model(id=obj_id or uuid.uuid4(), user_id=user.id, **values)
    db.add(obj)
    await db.flush()
    if spec.on_create:
        await spec.on_create(db, user, obj, values)
    return obj, True


async def update_entity(
    db: AsyncSession,
    spec: CrudSpec,
    user: User,
    obj_id: uuid.UUID,
    data: BaseModel,
    if_match: int | None = None,
):
    obj = await get_owned(db, spec.model, obj_id, user.id, label=spec.label)
    if if_match is not None and obj.version != if_match:
        raise AppError(
            "version_conflict",
            "This item was changed somewhere else.",
            412,
            {"current_version": obj.version},
        )
    changes = data.model_dump(exclude_unset=True)
    if spec.before_update:
        await spec.before_update(db, user, changes)
    await check_refs(db, user.id, changes, spec.refs)
    before = {k: getattr(obj, k) for k in changes}
    for k, v in changes.items():
        setattr(obj, k, v)
    obj.version += 1
    obj.updated_at = utcnow()
    if spec.on_update:
        await spec.on_update(db, user, obj, {"changes": changes, "before": before})
    await db.flush()
    return obj


async def delete_entity(db: AsyncSession, spec: CrudSpec, user: User, obj_id: uuid.UUID) -> None:
    obj = await get_owned(db, spec.model, obj_id, user.id, label=spec.label)
    obj.deleted_at = utcnow()
    obj.version += 1
    obj.updated_at = utcnow()
    if spec.on_delete:
        await spec.on_delete(db, user, obj, {})


def _encode_cursor(obj) -> str:
    raw = f"{obj.created_at.isoformat()}|{obj.id}"
    return base64.urlsafe_b64encode(raw.encode()).decode()


def _decode_cursor(cursor: str) -> tuple[datetime, uuid.UUID]:
    try:
        ts, oid = base64.urlsafe_b64decode(cursor.encode()).decode().split("|")
        return datetime.fromisoformat(ts), uuid.UUID(oid)
    except Exception as e:  # noqa: BLE001
        raise AppError("invalid_cursor", "Invalid cursor.", 400) from e


async def list_entities(
    db: AsyncSession,
    spec: CrudSpec,
    user: User,
    *,
    filters: dict[str, Any],
    updated_since: datetime | None,
    include_deleted: bool,
    limit: int,
    cursor: str | None,
    extra_where: list | None = None,
    order_by=None,
):
    m = spec.model
    q = select(m).where(m.user_id == user.id)
    if not include_deleted:
        q = q.where(m.deleted_at.is_(None))
    if updated_since:
        q = q.where(m.updated_at > updated_since)
    for k, v in filters.items():
        q = q.where(getattr(m, k) == v)
    for cond in extra_where or []:
        q = q.where(cond)
    if cursor:
        ts, oid = _decode_cursor(cursor)
        q = q.where(or_(m.created_at < ts, and_(m.created_at == ts, m.id < oid)))
    q = q.order_by(*(order_by or [m.created_at.desc(), m.id.desc()])).limit(limit + 1)
    rows = list((await db.execute(q)).scalars())
    next_cursor = _encode_cursor(rows[limit - 1]) if len(rows) > limit else None
    return rows[:limit], next_cursor


def _coerce_filter(model: type, name: str, raw: str):
    col = getattr(model, name).property.columns[0]
    try:
        py = col.type.python_type
    except NotImplementedError:
        return raw
    if py is uuid.UUID:
        return uuid.UUID(raw)
    if py is bool:
        return raw.lower() in ("1", "true", "yes")
    if py is int:
        return int(raw)
    return raw


# ---------- router factory ----------


def crud_router(spec: CrudSpec, prefix: str, tags: list[str]) -> APIRouter:
    router = APIRouter(prefix=prefix, tags=tags)
    Read = spec.read_schema
    Create = spec.create_schema
    Update = spec.update_schema

    @router.get("", response_model=Page[Read], summary=f"List {spec.label.lower()}s")
    async def list_items(
        request: Request,
        db: DB,
        user: CurrentUser,
        updated_since: datetime | None = None,
        include_deleted: bool = False,
        limit: Annotated[int, Query(ge=1, le=200)] = 50,
        cursor: str | None = None,
    ):
        filters = {}
        for name in spec.filter_fields:
            if name in request.query_params:
                try:
                    filters[name] = _coerce_filter(spec.model, name, request.query_params[name])
                except ValueError as e:
                    raise AppError("invalid_filter", f"Invalid value for {name}.", 422) from e
        rows, next_cursor = await list_entities(
            db,
            spec,
            user,
            filters=filters,
            updated_since=updated_since,
            include_deleted=include_deleted,
            limit=limit,
            cursor=cursor,
        )
        return Page[Read](items=[Read.model_validate(r) for r in rows], next_cursor=next_cursor)

    @router.post("", response_model=Read, status_code=201, summary=f"Create {spec.label.lower()}")
    async def create_item(body: Create, db: DB, user: CurrentUser, bg: BackgroundTasks):  # type: ignore[valid-type]
        obj, _ = await create_entity(db, spec, user, body)
        await commit_and_dispatch(db, bg)
        return Read.model_validate(obj)

    @router.get("/{item_id}", response_model=Read, summary=f"Get {spec.label.lower()}")
    async def get_item(item_id: uuid.UUID, db: DB, user: CurrentUser):
        return Read.model_validate(await get_owned(db, spec.model, item_id, user.id, label=spec.label))

    @router.patch("/{item_id}", response_model=Read, summary=f"Update {spec.label.lower()}")
    async def update_item(
        item_id: uuid.UUID,
        body: Update,  # type: ignore[valid-type]
        db: DB,
        user: CurrentUser,
        bg: BackgroundTasks,
        if_match: Annotated[int | None, Header()] = None,
    ):
        obj = await update_entity(db, spec, user, item_id, body, if_match)
        await commit_and_dispatch(db, bg)
        return Read.model_validate(obj)

    @router.delete("/{item_id}", status_code=204, summary=f"Delete {spec.label.lower()}")
    async def delete_item(item_id: uuid.UUID, db: DB, user: CurrentUser, bg: BackgroundTasks):
        await delete_entity(db, spec, user, item_id)
        await commit_and_dispatch(db, bg)

    return router
