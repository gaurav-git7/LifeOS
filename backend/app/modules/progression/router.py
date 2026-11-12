from fastapi import APIRouter
from sqlalchemy import select

from ...core.deps import DB, CurrentUser
from ...models import UserAchievement, XpLedger
from .service import ACHIEVEMENTS, ensure_catalog, level_info

router = APIRouter(prefix="/progression", tags=["progression"])


@router.get("")
async def progression(db: DB, user: CurrentUser):
    """Level, rank, XP progress and achievements (locked + unlocked)."""
    await ensure_catalog(db)
    await db.commit()
    unlocked = {
        ua.achievement_code: ua.unlocked_at
        for ua in (
            await db.execute(select(UserAchievement).where(UserAchievement.user_id == user.id))
        ).scalars()
    }
    return {
        **level_info(user.total_xp),
        "achievements": [
            {
                "code": a.code,
                "title": a.title,
                "description": a.description,
                "icon": a.icon,
                "unlocked_at": unlocked.get(a.code),
            }
            for a in ACHIEVEMENTS
        ],
    }


@router.get("/xp-history")
async def xp_history(db: DB, user: CurrentUser, limit: int = 50):
    rows = (
        await db.execute(
            select(XpLedger)
            .where(XpLedger.user_id == user.id)
            .order_by(XpLedger.created_at.desc())
            .limit(min(limit, 200))
        )
    ).scalars()
    return [
        {
            "amount": r.amount,
            "reason": r.reason,
            "source_type": r.source_type,
            "source_id": r.source_id,
            "created_at": r.created_at,
        }
        for r in rows
    ]
