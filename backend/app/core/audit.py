import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from ..models import AuditLog


def audit(
    db: AsyncSession,
    user_id: uuid.UUID | None,
    action: str,
    *,
    actor: str = "user",
    entity_type: str | None = None,
    entity_id: uuid.UUID | None = None,
    before: dict | None = None,
    after: dict | None = None,
    proposal_id: uuid.UUID | None = None,
    ip: str | None = None,
) -> None:
    """Adds an audit row to the current transaction (committed with it)."""
    db.add(
        AuditLog(
            user_id=user_id,
            actor=actor,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            before=before,
            after=after,
            proposal_id=proposal_id,
            ip=ip,
        )
    )
