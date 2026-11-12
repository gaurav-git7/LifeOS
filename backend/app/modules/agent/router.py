import uuid
from datetime import date

from fastapi import APIRouter, BackgroundTasks, Request
from sqlalchemy import select

from ...core.audit import audit
from ...core.deps import DB, CurrentUser
from ...core.errors import AppError, not_found
from ...core.rate_limit import limiter
from ...core.time import local_today, week_start
from ...core.types import utcnow
from ...events.outbox import commit_and_dispatch
from ...models import (
    ActionProposal,
    AgentConversation,
    AgentJob,
    AgentMemory,
    AgentMessage,
    DailySummary,
    UserPreferences,
    WeeklySummary,
)
from . import orchestrator, proposals
from .schemas import (
    ApproveIn,
    ChatIn,
    ChatOut,
    EditProposalIn,
    GroupApproveIn,
    JobIn,
    JobRead,
    MemoryIn,
    MemoryRead,
    MemoryUpdate,
    ProposalRead,
    QuickCaptureIn,
)

router = APIRouter(prefix="/agent", tags=["agent"])


# ---------- chat ----------


@router.post("/chat", response_model=ChatOut)
@limiter.limit("20/minute")
async def chat(request: Request, body: ChatIn, db: DB, user: CurrentUser, bg: BackgroundTasks):
    out = await orchestrator.chat(db, user, body.message, body.conversation_id)
    await commit_and_dispatch(db, bg)
    return ChatOut(
        **{k: v for k, v in out.items() if k not in ("proposals", "memory_suggestions")},
        proposals=[ProposalRead.model_validate(p) for p in out["proposals"]],
        memory_suggestions=[MemoryRead.model_validate(m) for m in out["memory_suggestions"]],
    )


@router.post("/quick-capture", response_model=ProposalRead, summary="Text → task suggestion (no AI)")
async def quick_capture(body: QuickCaptureIn, db: DB, user: CurrentUser):
    p = await orchestrator.quick_capture(db, user, body.text)
    await db.commit()
    return ProposalRead.model_validate(p)


@router.get("/conversations")
async def conversations(db: DB, user: CurrentUser, limit: int = 30):
    rows = (
        await db.execute(
            select(AgentConversation)
            .where(AgentConversation.user_id == user.id, AgentConversation.deleted_at.is_(None))
            .order_by(AgentConversation.last_message_at.desc())
            .limit(min(limit, 100))
        )
    ).scalars()
    return [
        {"id": c.id, "title": c.title, "last_message_at": c.last_message_at, "archived": c.archived}
        for c in rows
    ]


@router.get("/conversations/{conversation_id}/messages")
async def messages(conversation_id: uuid.UUID, db: DB, user: CurrentUser, limit: int = 100):
    conv = await db.get(AgentConversation, conversation_id)
    if conv is None or conv.user_id != user.id:
        raise not_found("Conversation")
    rows = (
        await db.execute(
            select(AgentMessage)
            .where(AgentMessage.conversation_id == conversation_id)
            .order_by(AgentMessage.created_at)
            .limit(min(limit, 500))
        )
    ).scalars()
    return [
        {"id": m.id, "role": m.role, "content": m.content, "metadata": m.meta, "created_at": m.created_at}
        for m in rows
    ]


@router.delete("/conversations/{conversation_id}", status_code=204)
async def delete_conversation(conversation_id: uuid.UUID, db: DB, user: CurrentUser):
    conv = await db.get(AgentConversation, conversation_id)
    if conv is None or conv.user_id != user.id:
        raise not_found("Conversation")
    conv.deleted_at = utcnow()
    await db.commit()


# ---------- proposals ----------


@router.get("/proposals", response_model=list[ProposalRead])
async def list_proposals(db: DB, user: CurrentUser, status: str = "pending", origin: str | None = None):
    await proposals.expire_stale(db, user.id)
    await db.commit()
    q = select(ActionProposal).where(ActionProposal.user_id == user.id, ActionProposal.status == status)
    if origin:
        q = q.where(ActionProposal.origin == origin)
    rows = (await db.execute(q.order_by(ActionProposal.created_at.desc()).limit(100))).scalars()
    return [ProposalRead.model_validate(p) for p in rows]


@router.get("/proposals/{proposal_id}", response_model=ProposalRead)
async def get_proposal(proposal_id: uuid.UUID, db: DB, user: CurrentUser):
    p = await db.get(ActionProposal, proposal_id)
    if p is None or p.user_id != user.id:
        raise not_found("Suggestion")
    return ProposalRead.model_validate(p)


@router.patch("/proposals/{proposal_id}", response_model=ProposalRead, summary="Modify before approving")
async def edit_proposal(proposal_id: uuid.UUID, body: EditProposalIn, db: DB, user: CurrentUser):
    p = await proposals.edit(db, user, proposal_id, body.arguments)
    await db.commit()
    return ProposalRead.model_validate(p)


@router.post("/proposals/{proposal_id}/approve", response_model=ProposalRead)
async def approve(proposal_id: uuid.UUID, body: ApproveIn, db: DB, user: CurrentUser, bg: BackgroundTasks):
    p = await proposals.approve(db, user, proposal_id, body.payload_hash)
    await commit_and_dispatch(db, bg)
    return ProposalRead.model_validate(p)


@router.post("/proposals/{proposal_id}/reject", response_model=ProposalRead)
async def reject(proposal_id: uuid.UUID, db: DB, user: CurrentUser):
    p = await proposals.reject(db, user, proposal_id)
    await db.commit()
    return ProposalRead.model_validate(p)


@router.post("/proposal-groups/{group_id}/approve", response_model=list[ProposalRead])
async def approve_group(
    group_id: uuid.UUID, body: GroupApproveIn, db: DB, user: CurrentUser, bg: BackgroundTasks
):
    rows = await proposals.approve_group(db, user, group_id, body.payload_hashes, body.exclude)
    await commit_and_dispatch(db, bg)
    return [ProposalRead.model_validate(p) for p in rows]


# ---------- reviews ----------


@router.get("/reviews/daily")
async def get_daily_review(db: DB, user: CurrentUser, day: date | None = None):
    day = day or local_today(user.timezone)
    row = await db.scalar(
        select(DailySummary).where(DailySummary.user_id == user.id, DailySummary.summary_date == day)
    )
    if row is None:
        return {"date": day, "available": False}
    review = (row.stats or {}).get("review", {})
    ids = [uuid.UUID(i) for i in review.get("proposal_ids", [])]
    props = (
        (await db.execute(select(ActionProposal).where(ActionProposal.id.in_(ids)))).scalars() if ids else []
    )
    return {
        "date": day,
        "available": bool(review),
        "insight": row.ai_insight,
        "highlights": review.get("highlights", []),
        "attention": review.get("attention", []),
        "proposals": [ProposalRead.model_validate(p) for p in props],
        "stats": {
            k: getattr(row, k)
            for k in (
                "tasks_done",
                "tasks_open",
                "tasks_overdue",
                "habits_done",
                "habits_due",
                "study_minutes",
                "focus_minutes",
            )
        },
    }


@router.post("/reviews/daily/run", summary="Run today's review now ('Plan tomorrow' button)")
@limiter.limit("5/hour")
async def run_daily_review(request: Request, db: DB, user: CurrentUser, bg: BackgroundTasks):
    await orchestrator.daily_review(db, user, force_ai=True)
    await commit_and_dispatch(db, bg)
    return await get_daily_review(db, user)


@router.get("/reviews/weekly")
async def get_weekly_review(db: DB, user: CurrentUser, start: date | None = None):
    q = select(WeeklySummary).where(WeeklySummary.user_id == user.id)
    q = q.where(WeeklySummary.week_start == start) if start else q.order_by(WeeklySummary.week_start.desc())
    row = await db.scalar(q.limit(1))
    if row is None:
        return {"available": False}
    return {
        "available": True,
        "week_start": row.week_start,
        "week_end": row.week_end,
        "report": row.ai_report,
        "recommendations": row.recommendations,
        "stats": row.stats,
        "generated_at": row.generated_at,
    }


@router.post("/reviews/weekly/run", summary="Generate the weekly review now")
@limiter.limit("3/hour")
async def run_weekly_review(request: Request, db: DB, user: CurrentUser, bg: BackgroundTasks):
    prefs = await db.get(UserPreferences, user.id)
    row = await orchestrator.weekly_review(
        db, user, week_start(local_today(user.timezone), prefs.week_start_day if prefs else 1)
    )
    await commit_and_dispatch(db, bg)
    return await get_weekly_review(db, user, row.week_start)


# ---------- jobs ----------


@router.post("/jobs", response_model=JobRead, status_code=202)
@limiter.limit("10/hour")
async def start_job(request: Request, body: JobIn, db: DB, user: CurrentUser, bg: BackgroundTasks):
    job = AgentJob(user_id=user.id, job_type=body.job_type, input=body.input)
    db.add(job)
    await db.commit()
    bg.add_task(orchestrator.run_job, job.id)
    return JobRead.model_validate(job)


@router.get("/jobs/{job_id}", response_model=JobRead)
async def get_job(job_id: uuid.UUID, db: DB, user: CurrentUser):
    job = await db.get(AgentJob, job_id)
    if job is None or job.user_id != user.id:
        raise not_found("Job")
    await db.refresh(job)
    return JobRead.model_validate(job)


# ---------- memories ----------


@router.get("/memories", response_model=list[MemoryRead])
async def list_memories(db: DB, user: CurrentUser, status: str | None = None):
    q = select(AgentMemory).where(AgentMemory.user_id == user.id, AgentMemory.deleted_at.is_(None))
    q = (
        q.where(AgentMemory.status == status)
        if status
        else q.where(AgentMemory.status.in_(["active", "proposed"]))
    )
    rows = (await db.execute(q.order_by(AgentMemory.created_at.desc()).limit(300))).scalars()
    return [MemoryRead.model_validate(m) for m in rows]


@router.post("/memories", response_model=MemoryRead, status_code=201, summary="Tell the assistant something")
async def add_memory(body: MemoryIn, db: DB, user: CurrentUser):
    m = AgentMemory(
        user_id=user.id,
        memory_type=body.memory_type,
        content=body.content,
        importance=body.importance,
        source_type="user",
        status="active",
    )
    db.add(m)
    audit(db, user.id, "memory.added", entity_type="memory")
    await db.commit()
    return MemoryRead.model_validate(m)


async def _memory(db, user, memory_id: uuid.UUID) -> AgentMemory:
    m = await db.get(AgentMemory, memory_id)
    if m is None or m.user_id != user.id or m.deleted_at:
        raise not_found("Memory")
    return m


@router.post("/memories/{memory_id}/accept", response_model=MemoryRead)
async def accept_memory(memory_id: uuid.UUID, db: DB, user: CurrentUser):
    m = await _memory(db, user, memory_id)
    if m.status != "proposed":
        raise AppError("not_proposed", "This memory isn't waiting for approval.", 409)
    m.status = "active"
    m.version += 1
    audit(db, user.id, "memory.accepted", entity_type="memory", entity_id=m.id)
    await db.commit()
    return MemoryRead.model_validate(m)


@router.patch("/memories/{memory_id}", response_model=MemoryRead)
async def update_memory(memory_id: uuid.UUID, body: MemoryUpdate, db: DB, user: CurrentUser):
    m = await _memory(db, user, memory_id)
    for k, v in body.model_dump(exclude_unset=True, exclude_none=True).items():
        setattr(m, k, v)
    m.version += 1
    audit(db, user.id, "memory.edited", entity_type="memory", entity_id=m.id)
    await db.commit()
    return MemoryRead.model_validate(m)


@router.delete("/memories/{memory_id}", status_code=204)
async def delete_memory(memory_id: uuid.UUID, db: DB, user: CurrentUser):
    m = await _memory(db, user, memory_id)
    m.deleted_at = utcnow()
    m.status = "rejected" if m.status == "proposed" else m.status
    audit(db, user.id, "memory.deleted", entity_type="memory", entity_id=m.id)
    await db.commit()
