"""Statistics — plain Python/SQL, never AI. ARCHITECTURE.md §3 principle 3."""

from datetime import date, timedelta

from sqlalchemy import and_, case, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core.recurrence import is_due_on
from ...core.time import day_bounds_utc, local_now, local_today
from ...models import (
    ActionProposal,
    DailySummary,
    Habit,
    HabitLog,
    LearningPath,
    LearningTopic,
    LlmCall,
    MoodEntry,
    Skill,
    StudySession,
    Task,
    User,
)
from ..habits.router import habit_start

PRIORITY_RANK = case((Task.priority == "high", 0), (Task.priority == "medium", 1), else_=2)


def _open_task_filter(user: User):
    return and_(Task.user_id == user.id, Task.deleted_at.is_(None), Task.status.in_(["todo", "in_progress"]))


def _due_by(day: date, user: User):
    _, end = day_bounds_utc(day, user.timezone)
    return or_(Task.due_at < end, Task.due_date <= day)


async def day_stats(db: AsyncSession, user: User, day: date) -> dict:
    start, end = day_bounds_utc(day, user.timezone)

    tasks_done = (
        await db.scalar(
            select(func.count()).where(
                Task.user_id == user.id,
                Task.deleted_at.is_(None),
                Task.status == "done",
                Task.completed_at >= start,
                Task.completed_at < end,
            )
        )
        or 0
    )
    tasks_open = await db.scalar(select(func.count()).where(_open_task_filter(user), _due_by(day, user))) or 0
    tasks_overdue = (
        await db.scalar(
            select(func.count()).where(_open_task_filter(user), or_(Task.due_at < start, Task.due_date < day))
        )
        or 0
    )

    habits = list(
        (
            await db.execute(
                select(Habit).where(
                    Habit.user_id == user.id, Habit.deleted_at.is_(None), Habit.active.is_(True)
                )
            )
        ).scalars()
    )
    due_ids = {h.id for h in habits if is_due_on(h.recurrence_rule, habit_start(h, user), day)}
    done_ids = set(
        (
            await db.execute(
                select(HabitLog.habit_id).where(
                    HabitLog.user_id == user.id,
                    HabitLog.log_date == day,
                    HabitLog.status == "done",
                    HabitLog.deleted_at.is_(None),
                )
            )
        ).scalars()
    )

    study = (
        await db.execute(
            select(
                func.coalesce(func.sum(StudySession.duration_minutes), 0),
                func.coalesce(
                    func.sum(
                        case((StudySession.source == "focus_timer", StudySession.duration_minutes), else_=0)
                    ),
                    0,
                ),
                func.coalesce(func.sum(StudySession.problems_solved), 0),
            ).where(
                StudySession.user_id == user.id,
                StudySession.deleted_at.is_(None),
                StudySession.started_at >= start,
                StudySession.started_at < end,
            )
        )
    ).one()

    mood = (
        await db.execute(
            select(func.avg(MoodEntry.mood), func.avg(MoodEntry.energy)).where(
                MoodEntry.user_id == user.id,
                MoodEntry.deleted_at.is_(None),
                MoodEntry.recorded_at >= start,
                MoodEntry.recorded_at < end,
            )
        )
    ).one()

    return {
        "date": day.isoformat(),
        "tasks_done": int(tasks_done),
        "tasks_open": int(tasks_open),
        "tasks_overdue": int(tasks_overdue),
        "habits_due": len(due_ids),
        "habits_done": len(due_ids & done_ids),
        "study_minutes": int(study[0]),
        "focus_minutes": int(study[1]),
        "problems_solved": int(study[2]),
        "mood_avg": round(float(mood[0]), 2) if mood[0] is not None else None,
        "energy_avg": round(float(mood[1]), 2) if mood[1] is not None else None,
    }


async def save_daily_summary(db: AsyncSession, user: User, day: date) -> DailySummary:
    stats = await day_stats(db, user, day)
    row = await db.scalar(
        select(DailySummary).where(DailySummary.user_id == user.id, DailySummary.summary_date == day)
    )
    if row is None:
        row = DailySummary(user_id=user.id, summary_date=day)
        db.add(row)
    for k in (
        "tasks_done",
        "tasks_open",
        "tasks_overdue",
        "habits_done",
        "habits_due",
        "study_minutes",
        "focus_minutes",
        "mood_avg",
        "energy_avg",
    ):
        setattr(row, k, stats[k])
    row.stats = {**(row.stats or {}), "problems_solved": stats["problems_solved"]}
    return row


async def priorities(db: AsyncSession, user: User, limit: int = 3) -> list[Task]:
    today = local_today(user.timezone)
    q = (
        select(Task)
        .where(_open_task_filter(user), Task.parent_task_id.is_(None), _due_by(today, user))
        .order_by(PRIORITY_RANK, Task.due_at.is_(None), Task.due_at, Task.sort_order)
        .limit(limit)
    )
    rows = list((await db.execute(q)).scalars())
    if len(rows) < limit:  # top up with undated high-priority tasks
        extra = (
            select(Task)
            .where(
                _open_task_filter(user),
                Task.parent_task_id.is_(None),
                Task.due_at.is_(None),
                Task.due_date.is_(None),
                Task.id.not_in([t.id for t in rows]),
            )
            .order_by(PRIORITY_RANK, Task.created_at)
            .limit(limit - len(rows))
        )
        rows += list((await db.execute(extra)).scalars())
    return rows


async def learning_overview(db: AsyncSession, user: User) -> list[dict]:
    paths = list(
        (
            await db.execute(
                select(LearningPath).where(
                    LearningPath.user_id == user.id,
                    LearningPath.deleted_at.is_(None),
                    LearningPath.status == "active",
                )
            )
        ).scalars()
    )
    out = []
    for p in paths:
        counts = (
            await db.execute(
                select(
                    func.count(),
                    func.coalesce(func.sum(case((LearningTopic.status == "done", 1), else_=0)), 0),
                ).where(LearningTopic.learning_path_id == p.id, LearningTopic.deleted_at.is_(None))
            )
        ).one()
        nxt = await db.scalar(
            select(LearningTopic)
            .where(
                LearningTopic.learning_path_id == p.id,
                LearningTopic.deleted_at.is_(None),
                LearningTopic.status.in_(["not_started", "in_progress"]),
            )
            .order_by(LearningTopic.sort_order)
            .limit(1)
        )
        out.append(
            {
                "path_id": p.id,
                "title": p.title,
                "topics_total": counts[0],
                "topics_done": int(counts[1]),
                "progress": round(counts[1] / counts[0], 4) if counts[0] else 0.0,
                "next_topic": {"id": nxt.id, "title": nxt.title, "difficulty": nxt.difficulty}
                if nxt
                else None,
            }
        )
    return out


async def pending_proposals_count(db: AsyncSession, user: User) -> int:
    from ...core.types import utcnow

    return int(
        await db.scalar(
            select(func.count()).where(
                ActionProposal.user_id == user.id,
                ActionProposal.status == "pending",
                ActionProposal.expires_at > utcnow(),
            )
        )
        or 0
    )


async def latest_insight(db: AsyncSession, user: User) -> dict | None:
    today = local_today(user.timezone)
    row = await db.scalar(
        select(DailySummary)
        .where(
            DailySummary.user_id == user.id,
            DailySummary.ai_insight.is_not(None),
            DailySummary.summary_date >= today - timedelta(days=1),
        )
        .order_by(DailySummary.summary_date.desc())
        .limit(1)
    )
    return {"date": row.summary_date, "text": row.ai_insight} if row else None


async def week_stats(db: AsyncSession, user: User, week_start: date) -> dict:
    days = [await day_stats(db, user, week_start + timedelta(days=i)) for i in range(7)]
    start, _ = day_bounds_utc(week_start, user.timezone)
    _, end = day_bounds_utc(week_start + timedelta(days=6), user.timezone)
    per_skill = (
        await db.execute(
            select(Skill.name, func.sum(StudySession.duration_minutes))
            .join(Skill, Skill.id == StudySession.skill_id)
            .where(
                StudySession.user_id == user.id,
                StudySession.deleted_at.is_(None),
                StudySession.started_at >= start,
                StudySession.started_at < end,
            )
            .group_by(Skill.name)
        )
    ).all()
    due = sum(d["habits_due"] for d in days)
    moods = [d["mood_avg"] for d in days if d["mood_avg"] is not None]
    return {
        "week_start": week_start.isoformat(),
        "days": days,
        "totals": {
            "tasks_done": sum(d["tasks_done"] for d in days),
            "study_minutes": sum(d["study_minutes"] for d in days),
            "problems_solved": sum(d["problems_solved"] for d in days),
            "habit_consistency": round(sum(d["habits_done"] for d in days) / due, 4) if due else None,
            "mood_avg": round(sum(moods) / len(moods), 2) if moods else None,
        },
        "study_by_skill": [{"skill": n, "minutes": int(m or 0)} for n, m in per_skill],
    }


async def ai_usage(db: AsyncSession, user: User) -> dict:
    now = local_now(user.timezone)
    today_start, _ = day_bounds_utc(now.date(), user.timezone)
    month_start, _ = day_bounds_utc(now.date().replace(day=1), user.timezone)

    async def agg(since):
        r = (
            await db.execute(
                select(
                    func.count(),
                    func.coalesce(func.sum(LlmCall.input_tokens + LlmCall.output_tokens), 0),
                    func.coalesce(func.sum(LlmCall.cost_usd), 0.0),
                ).where(LlmCall.user_id == user.id, LlmCall.created_at >= since)
            )
        ).one()
        return {"calls": r[0], "tokens": int(r[1]), "cost_usd": round(float(r[2]), 6)}

    return {"today": await agg(today_start), "month": await agg(month_start)}
