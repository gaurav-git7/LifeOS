"""Deterministic event handlers — no LLM calls here. ARCHITECTURE.md §10.3."""

from sqlalchemy.ext.asyncio import AsyncSession

from ..models import ActivityEvent, AgentMemory, Goal, User, UserPreferences
from ..modules.progression.service import check_achievements, level_info
from ..notifications.push import notify
from .dispatcher import on


async def _remember(
    db: AsyncSession, user: User, content: str, ev: ActivityEvent, importance: int = 3
) -> None:
    """Template-based episodic memory (no AI). Skipped if memory is disabled."""
    prefs = await db.get(UserPreferences, user.id)
    if prefs and not prefs.ai_memory_enabled:
        return
    db.add(
        AgentMemory(
            user_id=user.id,
            memory_type="episodic",
            content=content,
            importance=importance,
            source_type=ev.entity_type,
            source_id=ev.entity_id,
            status="active",
        )
    )


@on(
    "task.completed",
    "habit.logged",
    "study.session_completed",
    "learning.topic_completed",
    "learning.path_completed",
    "project.completed",
    "journal.created",
    "goal.completed",
)
async def achievements(db: AsyncSession, user: User, ev: ActivityEvent) -> None:
    await check_achievements(db, user)


@on("task.completed")
async def goal_tasks_done(db: AsyncSession, user: User, ev: ActivityEvent) -> None:
    """When every task of a task-based goal is done, nudge — never auto-complete."""
    goal_id = ev.payload.get("goal_id")
    if not goal_id:
        return
    import uuid

    from ..modules.goals.router import goal_progress

    goal = await db.get(Goal, uuid.UUID(goal_id))
    if (
        goal
        and goal.status == "active"
        and goal.progress_type == "tasks"
        and await goal_progress(db, goal) >= 1
    ):
        await notify(
            db,
            user,
            "celebration",
            "All tasks done 🎯",
            f"Every task for “{goal.title}” is complete. Mark the goal as achieved?",
            dedupe_key=f"goal_tasks_done:{goal.id}",
            data={"goal_id": str(goal.id)},
        )


@on("goal.completed")
async def goal_completed(db: AsyncSession, user: User, ev: ActivityEvent) -> None:
    title = ev.payload.get("title", "your goal")
    await notify(
        db,
        user,
        "celebration",
        "Goal achieved 🎉",
        f"You completed “{title}”.",
        dedupe_key=f"goal_completed:{ev.entity_id}",
    )
    await _remember(db, user, f"Completed the goal “{title}” on {ev.occurred_at.date()}.", ev, 4)


@on("goal.milestone_reached")
async def milestone(db: AsyncSession, user: User, ev: ActivityEvent) -> None:
    title = ev.payload.get("title", "a milestone")
    await notify(
        db,
        user,
        "celebration",
        "Milestone reached",
        f"“{title}” is done.",
        dedupe_key=f"milestone:{ev.entity_id}",
    )
    await _remember(db, user, f"Reached milestone “{title}” on {ev.occurred_at.date()}.", ev)


@on("learning.path_completed")
async def path_completed(db: AsyncSession, user: User, ev: ActivityEvent) -> None:
    title = ev.payload.get("title", "a roadmap")
    await notify(
        db,
        user,
        "celebration",
        "Roadmap complete 🧭",
        f"You finished “{title}”.",
        dedupe_key=f"path_completed:{ev.entity_id}",
    )
    await _remember(db, user, f"Finished the learning roadmap “{title}” on {ev.occurred_at.date()}.", ev, 4)


@on("project.completed")
async def project_completed(db: AsyncSession, user: User, ev: ActivityEvent) -> None:
    name = ev.payload.get("name", "a project")
    await notify(
        db, user, "celebration", "Shipped 🚀", f"“{name}” is done.", dedupe_key=f"project:{ev.entity_id}"
    )
    await _remember(db, user, f"Completed the project “{name}” on {ev.occurred_at.date()}.", ev, 4)


@on("level.up")
async def level_up(db: AsyncSession, user: User, ev: ActivityEvent) -> None:
    info = level_info(user.total_xp)
    lvl = ev.payload.get("to", info["level"])
    await notify(
        db,
        user,
        "level_up",
        f"Level {lvl}",
        f"You reached level {lvl} · {info['rank']}.",
        dedupe_key=f"level:{user.id}:{lvl}",
    )


@on("achievement.unlocked")
async def achievement_unlocked(db: AsyncSession, user: User, ev: ActivityEvent) -> None:
    await notify(
        db,
        user,
        "achievement",
        "Achievement unlocked",
        ev.payload.get("title", ""),
        dedupe_key=f"achievement:{user.id}:{ev.payload.get('code')}",
    )
