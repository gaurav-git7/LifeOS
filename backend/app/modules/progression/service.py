"""XP, levels and achievements — deterministic, never AI. UI_UX.md §10."""

import uuid
from collections import defaultdict
from collections.abc import Awaitable, Callable
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core.time import tz
from ...events.outbox import emit
from ...models import (
    Achievement,
    Habit,
    JournalEntry,
    LearningPath,
    Project,
    Skill,
    StudySession,
    Task,
    User,
    UserAchievement,
    XpLedger,
)

XP = {
    "task": {"low": 10, "medium": 20, "high": 30},
    "habit": 5,
    "habit_streak_7": 5,
    "habit_streak_30": 20,
    "study_per_minute": 1,
    "study_daily_cap": 180,
    "topic": {"easy": 30, "medium": 40, "hard": 60},
    "topic_revision": 15,
    "milestone": 100,
    "goal": 250,
    "project": 250,
    "journal": 5,
    "mood": 5,
}

RANKS = [(30, "Architect"), (20, "Master"), (15, "Expert"), (10, "Specialist"), (5, "Adept"), (1, "Initiate")]


def xp_for_next(level: int) -> int:
    """XP needed to go from `level` to `level + 1`."""
    return round(100 * level**1.5)


def level_info(total_xp: int) -> dict:
    level, remaining = 1, max(total_xp, 0)
    while remaining >= xp_for_next(level):
        remaining -= xp_for_next(level)
        level += 1
    rank = next(name for min_level, name in RANKS if level >= min_level)
    return {
        "level": level,
        "rank": rank,
        "xp_into_level": remaining,
        "xp_for_next": xp_for_next(level),
        "total_xp": total_xp,
    }


def stable_id(*parts: object) -> uuid.UUID:
    """Deterministic id for 'once per day' style XP sources."""
    return uuid.uuid5(uuid.NAMESPACE_URL, "lifeos:" + ":".join(str(p) for p in parts))


async def award_xp(
    db: AsyncSession,
    user: User,
    amount: int,
    reason: str,
    *,
    source_type: str | None = None,
    source_id: uuid.UUID | None = None,
    skill_id: uuid.UUID | None = None,
) -> int:
    """Adds XP once per (reason, source). Returns XP actually awarded."""
    if amount <= 0:
        return 0
    exists = await db.scalar(
        select(XpLedger.id).where(
            XpLedger.user_id == user.id, XpLedger.reason == reason, XpLedger.source_id == source_id
        )
    )
    if exists:
        return 0
    db.add(
        XpLedger(
            user_id=user.id,
            amount=amount,
            reason=reason,
            source_type=source_type,
            source_id=source_id,
            skill_id=skill_id,
        )
    )
    old_level = user.level
    user.total_xp += amount
    user.level = level_info(user.total_xp)["level"]
    if skill_id:
        skill = await db.get(Skill, skill_id)
        if skill and skill.user_id == user.id:
            skill.skill_xp += amount
    if user.level > old_level:
        emit(db, user.id, "level.up", payload={"from": old_level, "to": user.level})
    return amount


async def revoke_xp(db: AsyncSession, user: User, reason: str, source_id: uuid.UUID) -> None:
    """Undo XP when an action is undone (e.g. a task is re-opened)."""
    row = await db.scalar(
        select(XpLedger).where(
            XpLedger.user_id == user.id, XpLedger.reason == reason, XpLedger.source_id == source_id
        )
    )
    if row is None:
        return
    user.total_xp = max(0, user.total_xp - row.amount)
    user.level = level_info(user.total_xp)["level"]
    if row.skill_id:
        skill = await db.get(Skill, row.skill_id)
        if skill:
            skill.skill_xp = max(0, skill.skill_xp - row.amount)
    await db.delete(row)


async def study_xp_today(db: AsyncSession, user: User, day_start, day_end) -> int:
    return int(
        await db.scalar(
            select(func.coalesce(func.sum(XpLedger.amount), 0)).where(
                XpLedger.user_id == user.id,
                XpLedger.reason == "study.session",
                XpLedger.created_at >= day_start,
                XpLedger.created_at < day_end,
            )
        )
        or 0
    )


# ---------- achievements ----------

Check = Callable[[AsyncSession, User], Awaitable[bool]]


@dataclass(frozen=True)
class AchievementDef:
    code: str
    title: str
    description: str
    icon: str
    check: Check


async def _count(db, stmt) -> int:
    return int(await db.scalar(stmt) or 0)


async def _deep_diver(db: AsyncSession, user: User) -> bool:
    rows = (
        await db.execute(
            select(StudySession.started_at, StudySession.duration_minutes).where(
                StudySession.user_id == user.id, StudySession.deleted_at.is_(None)
            )
        )
    ).all()
    per_day: dict = defaultdict(int)
    z = tz(user.timezone)
    for started, minutes in rows:
        per_day[started.astimezone(z).date()] += minutes or 0
    return any(m >= 180 for m in per_day.values())


ACHIEVEMENTS: list[AchievementDef] = [
    AchievementDef(
        "first_light",
        "First Light",
        "Complete your first task",
        "sparkles",
        lambda db, u: _gt(db, select(func.count()).where(Task.user_id == u.id, Task.status == "done"), 1),
    ),
    AchievementDef(
        "week_warrior",
        "Week Warrior",
        "Reach a 7-day habit streak",
        "flame",
        lambda db, u: _gt(db, select(func.max(Habit.best_streak)).where(Habit.user_id == u.id), 7),
    ),
    AchievementDef(
        "consistent",
        "Consistent",
        "Reach a 30-day habit streak",
        "calendar-check",
        lambda db, u: _gt(db, select(func.max(Habit.best_streak)).where(Habit.user_id == u.id), 30),
    ),
    AchievementDef("deep_diver", "Deep Diver", "Study 3 hours in one day", "timer", _deep_diver),
    AchievementDef(
        "pathfinder",
        "Pathfinder",
        "Finish a learning roadmap",
        "map",
        lambda db, u: _gt(
            db,
            select(func.count()).where(LearningPath.user_id == u.id, LearningPath.status == "completed"),
            1,
        ),
    ),
    AchievementDef(
        "century",
        "Century",
        "Solve 100 problems",
        "brain",
        lambda db, u: _gt(
            db,
            select(func.sum(StudySession.problems_solved)).where(
                StudySession.user_id == u.id, StudySession.deleted_at.is_(None)
            ),
            100,
        ),
    ),
    AchievementDef(
        "shipper",
        "Shipper",
        "Complete a project",
        "rocket",
        lambda db, u: _gt(
            db, select(func.count()).where(Project.user_id == u.id, Project.status == "done"), 1
        ),
    ),
    AchievementDef(
        "reflective",
        "Reflective",
        "Write 20 journal entries",
        "notebook-pen",
        lambda db, u: _gt(
            db,
            select(func.count()).where(JournalEntry.user_id == u.id, JournalEntry.deleted_at.is_(None)),
            20,
        ),
    ),
]


async def _gt(db: AsyncSession, stmt, threshold: int) -> bool:
    return await _count(db, stmt) >= threshold


async def ensure_catalog(db: AsyncSession) -> None:
    existing = set((await db.execute(select(Achievement.code))).scalars())
    for i, a in enumerate(ACHIEVEMENTS):
        if a.code not in existing:
            db.add(
                Achievement(code=a.code, title=a.title, description=a.description, icon=a.icon, sort_order=i)
            )
    await db.flush()


async def check_achievements(db: AsyncSession, user: User) -> list[str]:
    """Unlocks any newly earned achievements; returns their codes."""
    await ensure_catalog(db)
    unlocked = set(
        (
            await db.execute(
                select(UserAchievement.achievement_code).where(UserAchievement.user_id == user.id)
            )
        ).scalars()
    )
    new: list[str] = []
    for a in ACHIEVEMENTS:
        if a.code in unlocked:
            continue
        if await a.check(db, user):
            db.add(UserAchievement(user_id=user.id, achievement_code=a.code))
            emit(db, user.id, "achievement.unlocked", payload={"code": a.code, "title": a.title})
            new.append(a.code)
    return new
