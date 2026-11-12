"""Proposal → approval → execution. ARCHITECTURE.md §12.6.

An approval is bound to the exact payload the user saw (payload_hash).
Execution re-validates and runs inside a savepoint, so a failure never
leaves half-applied changes.
"""

import hashlib
import json
import uuid
from datetime import timedelta

from pydantic import ValidationError
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from ...core.audit import audit
from ...core.errors import AppError, not_found
from ...core.serialize import jsonable
from ...core.time import tz
from ...core.types import utcnow
from ...events.outbox import emit
from ...models import ActionProposal, User
from .tools import resolve

PROPOSAL_TTL = timedelta(days=7)


def payload_hash(payload: dict) -> str:
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode()).hexdigest()


def _bad_args(e: ValidationError) -> AppError:
    return AppError(
        "invalid_action",
        "The suggested change isn't valid.",
        422,
        {"errors": [{"loc": list(x["loc"]), "msg": x["msg"]} for x in e.errors()]},
    )


async def create_proposal(
    db: AsyncSession,
    user: User,
    tool_name: str,
    arguments: dict,
    *,
    reason: str | None,
    origin: str,
    conversation_id: uuid.UUID | None = None,
    group_id: uuid.UUID | None = None,
) -> ActionProposal:
    tool = resolve(tool_name)
    try:
        args = tool.args.model_validate(arguments)
    except ValidationError as e:
        raise _bad_args(e) from e
    await tool.validate(db, user, args)
    payload = jsonable(args.model_dump(mode="json", exclude_none=True))
    p = ActionProposal(
        id=uuid.uuid4(),
        user_id=user.id,
        conversation_id=conversation_id,
        group_id=group_id,
        origin=origin,
        action_type=tool.name,
        payload=payload,
        payload_hash=payload_hash(payload),
        summary=tool.summary(args, tz(user.timezone))[:300],
        reason=(reason or "")[:1000] or None,
        status="pending",
        expires_at=utcnow() + PROPOSAL_TTL,
    )
    db.add(p)
    audit(
        db,
        user.id,
        "agent.proposal_created",
        actor="agent",
        entity_type="proposal",
        entity_id=p.id,
        after={"action_type": p.action_type, "origin": origin},
    )
    return p


async def expire_stale(db: AsyncSession, user_id: uuid.UUID | None = None) -> int:
    q = update(ActionProposal).where(
        ActionProposal.status == "pending", ActionProposal.expires_at <= utcnow()
    )
    if user_id:
        q = q.where(ActionProposal.user_id == user_id)
    res = await db.execute(q.values(status="expired"))
    return res.rowcount or 0


async def _load_pending(db: AsyncSession, user: User, proposal_id: uuid.UUID) -> ActionProposal:
    p = await db.scalar(select(ActionProposal).where(ActionProposal.id == proposal_id).with_for_update())
    if p is None or p.user_id != user.id:
        raise not_found("Suggestion")
    if p.status == "pending" and p.expires_at <= utcnow():
        p.status = "expired"
    if p.status != "pending":
        raise AppError(f"proposal_{p.status}", f"This suggestion is already {p.status}.", 409)
    return p


async def _execute(db: AsyncSession, user: User, p: ActionProposal) -> dict:
    tool = resolve(p.action_type)
    try:
        args = tool.args.model_validate(p.payload)
    except ValidationError as e:
        raise _bad_args(e) from e
    await tool.validate(db, user, args)
    return await tool.execute(db, user, args)


async def approve(db: AsyncSession, user: User, proposal_id: uuid.UUID, seen_hash: str) -> ActionProposal:
    p = await _load_pending(db, user, proposal_id)
    if seen_hash != p.payload_hash:
        raise AppError(
            "payload_changed",
            "This suggestion changed. Review it again.",
            409,
            {"payload_hash": p.payload_hash},
        )
    p.decided_at = utcnow()
    try:
        async with db.begin_nested():
            result = await _execute(db, user, p)
    except AppError as e:
        p.status, p.error = "failed", e.message
        audit(
            db,
            user.id,
            "agent.proposal_failed",
            entity_type="proposal",
            entity_id=p.id,
            after={"error": e.message},
        )
        return p
    p.status, p.result, p.executed_at = "executed", result, utcnow()
    audit(
        db,
        user.id,
        "agent.proposal_executed",
        entity_type="proposal",
        entity_id=p.id,
        proposal_id=p.id,
        after={"action_type": p.action_type, "result": result},
    )
    emit(
        db,
        user.id,
        "proposal.executed",
        entity_type="proposal",
        entity_id=p.id,
        payload={"action_type": p.action_type},
    )
    return p


async def approve_group(
    db: AsyncSession, user: User, group_id: uuid.UUID, hashes: dict[uuid.UUID, str], exclude: list[uuid.UUID]
) -> list[ActionProposal]:
    """All selected proposals execute in one transaction — all succeed or none do."""
    rows = list(
        (
            await db.execute(
                select(ActionProposal)
                .where(
                    ActionProposal.group_id == group_id,
                    ActionProposal.user_id == user.id,
                    ActionProposal.status == "pending",
                )
                .with_for_update()
            )
        ).scalars()
    )
    selected = [p for p in rows if p.id not in set(exclude) and p.expires_at > utcnow()]
    if not selected:
        raise not_found("Suggestions")
    for p in selected:
        if hashes.get(p.id) != p.payload_hash:
            raise AppError(
                "payload_changed",
                "A suggestion in this group changed. Review it again.",
                409,
                {"proposal_id": str(p.id)},
            )
    try:
        async with db.begin_nested():
            results = [await _execute(db, user, p) for p in selected]
    except AppError as e:
        raise AppError("group_failed", f"Nothing was changed: {e.message}", 409) from e
    now = utcnow()
    for p, result in zip(selected, results, strict=True):
        p.status, p.result, p.executed_at, p.decided_at = "executed", result, now, now
        audit(
            db, user.id, "agent.proposal_executed", entity_type="proposal", entity_id=p.id, proposal_id=p.id
        )
    for p in rows:
        if p.id in set(exclude):
            p.status, p.decided_at = "rejected", now
    emit(db, user.id, "proposal.executed", payload={"group_id": group_id, "count": len(selected)})
    return selected


async def reject(db: AsyncSession, user: User, proposal_id: uuid.UUID) -> ActionProposal:
    p = await _load_pending(db, user, proposal_id)
    p.status, p.decided_at = "rejected", utcnow()
    audit(db, user.id, "agent.proposal_rejected", entity_type="proposal", entity_id=p.id)
    return p


async def edit(db: AsyncSession, user: User, proposal_id: uuid.UUID, arguments: dict) -> ActionProposal:
    """User modifies a proposal: validated directly, new hash, no LLM call."""
    p = await _load_pending(db, user, proposal_id)
    tool = resolve(p.action_type)
    try:
        args = tool.args.model_validate({**p.payload, **arguments})
    except ValidationError as e:
        raise _bad_args(e) from e
    await tool.validate(db, user, args)
    p.payload = jsonable(args.model_dump(mode="json", exclude_none=True))
    p.payload_hash = payload_hash(p.payload)
    p.summary = tool.summary(args, tz(user.timezone))[:300]
    audit(db, user.id, "agent.proposal_edited", entity_type="proposal", entity_id=p.id)
    return p
