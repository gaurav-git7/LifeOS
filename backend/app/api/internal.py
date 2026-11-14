"""Secret-protected job endpoints called by Supabase pg_cron. ARCHITECTURE.md §11.2.

Not part of the public OpenAPI docs. Header: X-Job-Secret: <JOB_SECRET>.
"""

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from ..core.deps import require_job_secret
from ..events.dispatcher import sweep
from ..jobs import scheduled
from ..modules.agent.orchestrator import sweep_jobs

router = APIRouter(
    prefix="/internal/jobs", dependencies=[Depends(require_job_secret)], include_in_schema=False
)


@router.post("/process-events")
async def process_events():
    return {"processed": await sweep()}


@router.post("/daily-summary")
async def daily_summary():
    return {"summaries": await scheduled.daily_summaries()}


@router.post("/daily-review")
async def daily_review():
    return {"reviews": await scheduled.daily_reviews()}


@router.post("/weekly-review")
async def weekly_review():
    return {"reviews": await scheduled.weekly_reviews()}


@router.post("/run-agent-jobs")
async def run_agent_jobs():
    return {"jobs": await sweep_jobs()}


class ReleaseIn(BaseModel):
    version: str = Field(min_length=1, max_length=32)  # e.g. 0.2.0
    url: str = Field(min_length=8, max_length=300)  # GitHub release page


@router.post("/announce-release")
async def announce_release(body: ReleaseIn):
    """Called by the release-apk workflow: push "update available" to every
    phone that isn't on this version yet."""
    return {"notified": await scheduled.announce_release(body.version, body.url)}


@router.post("/cleanup")
async def cleanup():
    return await scheduled.cleanup()
