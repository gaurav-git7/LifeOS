"""Agent contracts. ARCHITECTURE.md §12.4.

`LLMOutput` / `LLMReview` are what Gemini must return (structured output).
Tool arguments travel as a JSON *string* because Gemini's response schema
can't express free-form objects; the backend parses and validates them
against each tool's own Pydantic model.
"""

import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


class LLMAction(BaseModel):
    tool: str = Field(description="One of the listed tool names, e.g. propose_create_task")
    arguments_json: str = Field(description="JSON object with the tool's arguments")
    reason: str = Field(description="One short sentence: why this helps the user")


class LLMMemory(BaseModel):
    type: Literal["profile", "preference", "episodic"]
    content: str


class LLMOutput(BaseModel):
    intent: str
    message: str
    confidence: float
    actions: list[LLMAction]
    memory_suggestions: list[LLMMemory]
    follow_up_question: str = Field(description="Empty string if none")


class LLMReview(BaseModel):
    insight: str = Field(description="2-3 sentences, specific and supportive")
    highlights: list[str]
    attention: list[str]
    actions: list[LLMAction]


# ---------- API ----------


class ProposalRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    group_id: uuid.UUID | None
    conversation_id: uuid.UUID | None
    origin: str
    action_type: str
    summary: str
    reason: str | None
    payload: dict[str, Any]
    payload_hash: str
    status: str
    result: dict | None
    error: str | None
    expires_at: datetime
    created_at: datetime
    decided_at: datetime | None
    executed_at: datetime | None


class ChatIn(BaseModel):
    message: str = Field(min_length=1, max_length=4000)
    conversation_id: uuid.UUID | None = None


class MemoryRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    memory_type: str
    content: str
    importance: int
    status: str
    source_type: str | None
    created_at: datetime
    last_used_at: datetime | None


class ChatOut(BaseModel):
    conversation_id: uuid.UUID
    message_id: uuid.UUID
    intent: str
    message: str
    proposals: list[ProposalRead]
    memory_suggestions: list[MemoryRead]
    follow_up_question: str | None
    used_ai: bool


class QuickCaptureIn(BaseModel):
    text: str = Field(min_length=1, max_length=500)


class ApproveIn(BaseModel):
    payload_hash: str


class GroupApproveIn(BaseModel):
    payload_hashes: dict[uuid.UUID, str]
    exclude: list[uuid.UUID] = Field(default_factory=list)


class EditProposalIn(BaseModel):
    arguments: dict[str, Any]


class JobIn(BaseModel):
    job_type: Literal["learning_path_plan"]
    input: dict[str, Any] = Field(default_factory=dict)


class JobRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    job_type: str
    status: str
    input: dict
    result: dict | None
    error: str | None
    created_at: datetime
    finished_at: datetime | None


class MemoryIn(BaseModel):
    memory_type: Literal["profile", "preference", "episodic"] = "preference"
    content: str = Field(min_length=1, max_length=500)
    importance: int = Field(default=3, ge=1, le=5)


class MemoryUpdate(BaseModel):
    content: str | None = Field(default=None, min_length=1, max_length=500)
    importance: int | None = Field(default=None, ge=1, le=5)
    memory_type: Literal["profile", "preference", "episodic", "summary"] | None = None
