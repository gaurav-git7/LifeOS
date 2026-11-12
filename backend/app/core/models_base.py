"""Reusable column mixins. See ARCHITECTURE.md §8.1 (standard columns)."""

import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, declared_attr, mapped_column

from .types import UTCDateTime, new_id, utcnow


class IdMixin:
    id: Mapped[uuid.UUID] = mapped_column(sa.Uuid, primary_key=True, default=new_id)


class CreatedMixin:
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, nullable=False)


class UserOwnedMixin:
    @declared_attr
    def user_id(cls) -> Mapped[uuid.UUID]:  # noqa: N805
        return mapped_column(
            sa.Uuid, sa.ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
        )


class SyncMixin(IdMixin, CreatedMixin, UserOwnedMixin):
    """id, user_id, created_at, updated_at, deleted_at, version — for every
    user-editable entity. Supports offline sync and optimistic concurrency."""

    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, default=utcnow, onupdate=utcnow, nullable=False, index=True
    )
    deleted_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    version: Mapped[int] = mapped_column(sa.Integer, default=1, nullable=False)
