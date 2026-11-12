"""Agent tables. ARCHITECTURE.md §8.4 E."""

import uuid
from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base
from ..core.models_base import CreatedMixin, IdMixin, SyncMixin, UserOwnedMixin
from ..core.types import JSONType, UTCDateTime


class AgentConversation(SyncMixin, Base):
    __tablename__ = "agent_conversations"

    title: Mapped[str] = mapped_column(sa.String(200), default="New conversation")
    last_message_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    archived: Mapped[bool] = mapped_column(sa.Boolean, default=False)


class AgentMessage(IdMixin, CreatedMixin, UserOwnedMixin, Base):
    __tablename__ = "agent_messages"

    conversation_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid, sa.ForeignKey("agent_conversations.id", ondelete="CASCADE"), index=True
    )
    role: Mapped[str] = mapped_column(sa.String(16))  # user|assistant|system_event
    content: Mapped[str] = mapped_column(sa.Text)
    meta: Mapped[dict] = mapped_column("metadata", JSONType, default=dict)


class AgentMemory(SyncMixin, Base):
    __tablename__ = "agent_memories"

    memory_type: Mapped[str] = mapped_column(sa.String(12))  # profile|preference|episodic|summary
    content: Mapped[str] = mapped_column(sa.Text)
    importance: Mapped[int] = mapped_column(sa.SmallInteger, default=3)
    source_type: Mapped[str | None] = mapped_column(sa.String(32))
    source_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid)
    status: Mapped[str] = mapped_column(
        sa.String(12), default="active"
    )  # proposed|active|superseded|rejected
    superseded_by: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid)
    last_used_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    expires_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


class ActionProposal(IdMixin, CreatedMixin, UserOwnedMixin, Base):
    __tablename__ = "action_proposals"

    conversation_id: Mapped[uuid.UUID | None] = mapped_column(
        sa.Uuid, sa.ForeignKey("agent_conversations.id", ondelete="SET NULL")
    )
    group_id: Mapped[uuid.UUID | None] = mapped_column(sa.Uuid, index=True)
    origin: Mapped[str] = mapped_column(
        sa.String(16), default="chat"
    )  # chat|daily_review|weekly_review|agent_job|quick_capture
    action_type: Mapped[str] = mapped_column(sa.String(48))
    payload: Mapped[dict] = mapped_column(JSONType)
    payload_hash: Mapped[str] = mapped_column(sa.String(64))
    summary: Mapped[str] = mapped_column(sa.String(300))
    reason: Mapped[str | None] = mapped_column(sa.Text)
    status: Mapped[str] = mapped_column(sa.String(12), default="pending", index=True)
    result: Mapped[dict | None] = mapped_column(JSONType)
    error: Mapped[str | None] = mapped_column(sa.Text)
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime)
    decided_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    executed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


class AgentJob(IdMixin, CreatedMixin, UserOwnedMixin, Base):
    __tablename__ = "agent_jobs"

    job_type: Mapped[str] = mapped_column(sa.String(32))
    input: Mapped[dict] = mapped_column(JSONType, default=dict)
    status: Mapped[str] = mapped_column(sa.String(12), default="pending", index=True)
    result: Mapped[dict | None] = mapped_column(JSONType)
    error: Mapped[str | None] = mapped_column(sa.Text)
    attempts: Mapped[int] = mapped_column(sa.SmallInteger, default=0)
    started_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    finished_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


class LlmCall(IdMixin, CreatedMixin, UserOwnedMixin, Base):
    __tablename__ = "llm_calls"
    __table_args__ = (sa.Index("ix_llm_calls_user_created", "user_id", "created_at"),)

    purpose: Mapped[str] = mapped_column(sa.String(24))
    model: Mapped[str] = mapped_column(sa.String(64))
    prompt_version: Mapped[str] = mapped_column(sa.String(32))
    input_tokens: Mapped[int] = mapped_column(sa.Integer, default=0)
    output_tokens: Mapped[int] = mapped_column(sa.Integer, default=0)
    cached_tokens: Mapped[int] = mapped_column(sa.Integer, default=0)
    cost_usd: Mapped[float] = mapped_column(sa.Float, default=0)
    latency_ms: Mapped[int] = mapped_column(sa.Integer, default=0)
    status: Mapped[str] = mapped_column(sa.String(20))  # ok|error|invalid_output|blocked_by_budget
    error: Mapped[str | None] = mapped_column(sa.Text)
