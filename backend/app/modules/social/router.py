"""Friends, sharing, reactions and group habits.

Privacy rules (enforced here, not in the app):
- You only see people you're friends with (accepted both ways) or share a group with.
- A friend sees only your habits marked visibility="friends": title, streak and
  whether it's done today. Never logs, notes, journal, mood, tasks or goals.
- Group habits are visible to group members only.
"""

import secrets
import uuid
from datetime import date, timedelta
from typing import Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import and_, delete, func, or_, select

from ...core.deps import DB, CurrentUser
from ...core.errors import AppError, not_found
from ...core.rate_limit import limiter
from ...core.recurrence import is_due_on, is_weekly_target, validate_rrule
from ...core.time import local_today
from ...core.types import utcnow
from ...models import (
    FriendGroup,
    Friendship,
    GroupCheckin,
    GroupHabit,
    GroupMember,
    Habit,
    HabitLog,
    Reaction,
    User,
    UserAchievement,
)
from ...notifications.push import notify
from ..progression.service import ACHIEVEMENTS, level_info

router = APIRouter(prefix="/social", tags=["social"])

MAX_FRIENDS = 50
MAX_GROUP_MEMBERS = 20
_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I


def _code(n: int = 8) -> str:
    return "".join(secrets.choice(_CODE_ALPHABET) for _ in range(n))


async def _friend_code(db, user: User) -> str:
    if not user.friend_code:
        user.friend_code = _code()
        await db.commit()
    return user.friend_code


async def _friend_ids(db, user_id: uuid.UUID) -> set[uuid.UUID]:
    rows = await db.execute(
        select(Friendship.user_id, Friendship.friend_id).where(
            Friendship.status == "accepted",
            or_(Friendship.user_id == user_id, Friendship.friend_id == user_id),
        )
    )
    return {b if a == user_id else a for a, b in rows}


def _person(u: User) -> dict:
    lv = level_info(u.total_xp)
    return {"id": u.id, "name": u.display_name, "level": lv["level"], "rank": lv["rank"]}


# ---------- friends ----------


class AddFriendIn(BaseModel):
    code: str = Field(min_length=4, max_length=12)


@router.get("/me")
async def me(db: DB, user: CurrentUser):
    """Your friend code (share it so friends can add you)."""
    return {"friend_code": await _friend_code(db, user), "name": user.display_name}


@router.post("/friends", status_code=201)
@limiter.limit("20/hour")
async def add_friend(request: Request, body: AddFriendIn, db: DB, user: CurrentUser):
    other = await db.scalar(select(User).where(User.friend_code == body.code.strip().upper()))
    if other is None or other.id == user.id:
        raise AppError("not_found", "No one has that friend code.", 404)
    existing = await db.scalar(
        select(Friendship).where(
            or_(
                and_(Friendship.user_id == user.id, Friendship.friend_id == other.id),
                and_(Friendship.user_id == other.id, Friendship.friend_id == user.id),
            )
        )
    )
    if existing is not None:
        if existing.status == "pending" and existing.user_id == other.id:  # they asked first: accept
            existing.status, existing.accepted_at = "accepted", utcnow()
            await notify(
                db, other, "social", f"{user.display_name} accepted your request", "You're now friends."
            )
            await db.commit()
            return {"status": "accepted", "friend": _person(other)}
        return {"status": existing.status, "friend": _person(other)}
    if len(await _friend_ids(db, user.id)) >= MAX_FRIENDS:
        raise AppError("limit", "You've reached the friend limit.", 409)
    db.add(Friendship(user_id=user.id, friend_id=other.id))
    await notify(db, other, "social", "Friend request", f"{user.display_name} wants to be friends on LifeOS.")
    await db.commit()
    return {"status": "pending", "friend": _person(other)}


@router.get("/friends")
async def friends(db: DB, user: CurrentUser):
    rows = (
        await db.execute(
            select(Friendship).where(or_(Friendship.user_id == user.id, Friendship.friend_id == user.id))
        )
    ).scalars()
    out: dict[str, list] = {"friends": [], "incoming": [], "outgoing": []}
    for f in rows:
        other_id = f.friend_id if f.user_id == user.id else f.user_id
        other = await db.get(User, other_id)
        if other is None:
            continue
        key = "friends" if f.status == "accepted" else ("outgoing" if f.user_id == user.id else "incoming")
        out[key].append(_person(other))
    return out


@router.post("/friends/{friend_id}/accept")
async def accept(friend_id: uuid.UUID, db: DB, user: CurrentUser):
    f = await db.scalar(
        select(Friendship).where(
            Friendship.user_id == friend_id, Friendship.friend_id == user.id, Friendship.status == "pending"
        )
    )
    if f is None:
        raise not_found("Request")
    f.status, f.accepted_at = "accepted", utcnow()
    other = await db.get(User, friend_id)
    if other:
        await notify(db, other, "social", f"{user.display_name} accepted your request", "You're now friends.")
    await db.commit()
    return {"status": "accepted"}


@router.delete("/friends/{friend_id}", status_code=204)
async def remove_friend(friend_id: uuid.UUID, db: DB, user: CurrentUser):
    """Decline, cancel or unfriend."""
    await db.execute(
        delete(Friendship).where(
            or_(
                and_(Friendship.user_id == user.id, Friendship.friend_id == friend_id),
                and_(Friendship.user_id == friend_id, Friendship.friend_id == user.id),
            )
        )
    )
    await db.commit()


# ---------- feed ----------


async def _done_today(db, habit_ids: list[uuid.UUID], day: date) -> set[uuid.UUID]:
    if not habit_ids:
        return set()
    rows = await db.execute(
        select(HabitLog.habit_id).where(
            HabitLog.habit_id.in_(habit_ids), HabitLog.log_date == day, HabitLog.status == "done"
        )
    )
    return {r for (r,) in rows}


@router.get("/feed")
async def feed(db: DB, user: CurrentUser):
    """Friends with their shared habits (streak, done today) and recent badges."""
    ids = await _friend_ids(db, user.id)
    titles = {a.code: a.title for a in ACHIEVEMENTS}
    since = utcnow() - timedelta(days=7)
    out = []
    for fid in ids:
        friend = await db.get(User, fid)
        if friend is None or friend.status != "active":
            continue
        today = local_today(friend.timezone)
        habits = list(
            (
                await db.execute(
                    select(Habit).where(
                        Habit.user_id == fid,
                        Habit.visibility == "friends",
                        Habit.active.is_(True),
                        Habit.deleted_at.is_(None),
                    )
                )
            ).scalars()
        )
        done = await _done_today(db, [h.id for h in habits], today)
        badges = (
            await db.execute(
                select(UserAchievement).where(
                    UserAchievement.user_id == fid, UserAchievement.unlocked_at >= since
                )
            )
        ).scalars()
        out.append(
            {
                **_person(friend),
                "habits": [
                    {
                        "id": h.id,
                        "title": h.title,
                        "streak": h.current_streak,
                        "streak_unit": "week" if is_weekly_target(h.recurrence_rule) else "day",
                        "done_today": h.id in done,
                    }
                    for h in habits
                ],
                "badges": [
                    {"title": titles.get(b.achievement_code, b.achievement_code), "at": b.unlocked_at}
                    for b in badges
                ],
            }
        )
    out.sort(key=lambda f: -sum(h["streak"] for h in f["habits"]))
    return out


class ReactIn(BaseModel):
    to_user_id: uuid.UUID
    kind: Literal["fire", "clap", "strong", "nudge"]
    habit_id: uuid.UUID | None = None
    group_habit_id: uuid.UUID | None = None


_EMOJI = {"fire": "🔥", "clap": "👏", "strong": "💪"}


@router.post("/react", status_code=201)
@limiter.limit("60/hour")
async def react(request: Request, body: ReactIn, db: DB, user: CurrentUser):
    """Cheer a friend's habit, or nudge them (once a day per habit)."""
    if body.to_user_id == user.id:
        raise AppError("invalid", "That's you.", 422)
    title = None
    if body.habit_id:
        h = await db.get(Habit, body.habit_id)
        if h is None or h.user_id != body.to_user_id or h.visibility != "friends":
            raise not_found("Habit")
        if body.to_user_id not in await _friend_ids(db, user.id):
            raise not_found("Friend")
        title, target = h.title, f"habit:{h.id}"
    elif body.group_habit_id:
        gh = await db.get(GroupHabit, body.group_habit_id)
        if (
            gh is None
            or not await _is_member(db, gh.group_id, user.id)
            or not await _is_member(db, gh.group_id, body.to_user_id)
        ):
            raise not_found("Group habit")
        title, target = gh.title, f"group_habit:{gh.id}"
    else:
        raise AppError("invalid", "Pick a habit.", 422)

    if body.kind == "nudge":
        recent = await db.scalar(
            select(func.count(Reaction.id)).where(
                Reaction.user_id == user.id,
                Reaction.to_user_id == body.to_user_id,
                Reaction.target == target,
                Reaction.kind == "nudge",
                Reaction.created_at >= utcnow() - timedelta(hours=20),
            )
        )
        if recent:
            raise AppError("limit", "You already nudged them today.", 429)
    db.add(Reaction(user_id=user.id, to_user_id=body.to_user_id, kind=body.kind, target=target))
    to = await db.get(User, body.to_user_id)
    if to:
        if body.kind == "nudge":
            await notify(db, to, "social", f"{user.display_name} nudged you", f"Time for {title} today?")
        else:
            await notify(
                db, to, "social", f"{_EMOJI[body.kind]} from {user.display_name}", f"For your {title} streak"
            )
    await db.commit()
    return {"ok": True}


# ---------- groups ----------


async def _is_member(db, group_id: uuid.UUID, user_id: uuid.UUID) -> bool:
    return (
        await db.scalar(
            select(GroupMember.user_id).where(
                GroupMember.group_id == group_id, GroupMember.user_id == user_id
            )
        )
        is not None
    )


async def _group_or_404(db, group_id: uuid.UUID, user: User) -> FriendGroup:
    g = await db.get(FriendGroup, group_id)
    if g is None or not await _is_member(db, g.id, user.id):
        raise not_found("Group")
    return g


class GroupIn(BaseModel):
    name: str = Field(min_length=1, max_length=60)


class JoinIn(BaseModel):
    code: str = Field(min_length=4, max_length=16)


class GroupHabitIn(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    recurrence_rule: str = "FREQ=DAILY"
    target_per_period: int = Field(default=1, ge=1, le=7)

    @field_validator("recurrence_rule")
    @classmethod
    def _rrule(cls, v):
        return validate_rrule(v) or "FREQ=DAILY"


class CheckinIn(BaseModel):
    done: bool = True


def group_streak(
    rule: str, target: int, start: date, today: date, members: set, done_by_day: dict[date, set]
) -> int:
    """Everyone does it; the group gets one free miss (one person, one day) per week.
    "N× a week" habits count weeks in which every member reached N."""
    if not members:
        return 0
    if is_weekly_target(rule):
        streak, wk = 0, today - timedelta(days=today.weekday())
        while wk + timedelta(days=6) >= start:
            counts = {m: 0 for m in members}
            for d in range(7):
                for m in done_by_day.get(wk + timedelta(days=d), set()):
                    if m in counts:
                        counts[m] += 1
            if all(c >= target for c in counts.values()):
                streak += 1
            elif wk + timedelta(days=6) < today:
                break
            wk -= timedelta(days=7)
        return streak
    streak, day, used_free = 0, today, set()
    while day >= start and (today - day).days < 400:
        if is_due_on(rule, start, day):
            missing = len(members - done_by_day.get(day, set()))
            week = day.isocalendar()[:2]
            if missing == 0:
                streak += 1
            elif day == today:
                pass  # still time today
            elif missing == 1 and week not in used_free:
                used_free.add(week)
                streak += 1
            else:
                break
        day -= timedelta(days=1)
    return streak


async def _group_out(db, g: FriendGroup, user: User) -> dict:
    members = list(
        (
            await db.execute(
                select(User)
                .join(GroupMember, GroupMember.user_id == User.id)
                .where(GroupMember.group_id == g.id)
            )
        ).scalars()
    )
    member_ids = {m.id for m in members}
    today = local_today(user.timezone)
    habits = list(
        (
            await db.execute(
                select(GroupHabit).where(GroupHabit.group_id == g.id, GroupHabit.deleted_at.is_(None))
            )
        ).scalars()
    )
    out_habits = []
    for h in habits:
        rows = await db.execute(
            select(GroupCheckin.day, GroupCheckin.user_id).where(
                GroupCheckin.group_habit_id == h.id, GroupCheckin.day >= today - timedelta(days=400)
            )
        )
        by_day: dict[date, set] = {}
        for d, uid in rows:
            by_day.setdefault(d, set()).add(uid)
        start = h.created_at.date()
        out_habits.append(
            {
                "id": h.id,
                "title": h.title,
                "recurrence_rule": h.recurrence_rule,
                "target_per_period": h.target_per_period,
                "due_today": is_due_on(h.recurrence_rule, start, today),
                "done_today": [str(u) for u in by_day.get(today, set()) & member_ids],
                "week_done": {
                    str(m): sum(
                        1
                        for d, us in by_day.items()
                        if d >= today - timedelta(days=today.weekday()) and m in us
                    )
                    for m in member_ids
                },
                "group_streak": group_streak(
                    h.recurrence_rule, h.target_per_period, start, today, member_ids, by_day
                ),
            }
        )
    return {
        "id": g.id,
        "name": g.name,
        "invite_code": g.invite_code,
        "is_owner": g.owner_id == user.id,
        "members": [_person(m) for m in members],
        "habits": out_habits,
    }


@router.get("/groups")
async def groups(db: DB, user: CurrentUser):
    gs = (
        await db.execute(
            select(FriendGroup)
            .join(GroupMember, GroupMember.group_id == FriendGroup.id)
            .where(GroupMember.user_id == user.id)
        )
    ).scalars()
    return [await _group_out(db, g, user) for g in gs]


@router.post("/groups", status_code=201)
@limiter.limit("10/hour")
async def create_group(request: Request, body: GroupIn, db: DB, user: CurrentUser):
    g = FriendGroup(name=body.name.strip(), owner_id=user.id, invite_code=_code(8))
    db.add(g)
    await db.flush()
    db.add(GroupMember(group_id=g.id, user_id=user.id))
    await db.commit()
    return await _group_out(db, g, user)


@router.post("/groups/join")
@limiter.limit("20/hour")
async def join_group(request: Request, body: JoinIn, db: DB, user: CurrentUser):
    g = await db.scalar(select(FriendGroup).where(FriendGroup.invite_code == body.code.strip().upper()))
    if g is None:
        raise AppError("not_found", "No group has that code.", 404)
    if not await _is_member(db, g.id, user.id):
        count = await db.scalar(
            select(func.count()).select_from(GroupMember).where(GroupMember.group_id == g.id)
        )
        if count >= MAX_GROUP_MEMBERS:
            raise AppError("limit", "That group is full.", 409)
        db.add(GroupMember(group_id=g.id, user_id=user.id))
        for m in (
            await db.execute(
                select(User)
                .join(GroupMember, GroupMember.user_id == User.id)
                .where(GroupMember.group_id == g.id)
            )
        ).scalars():
            if m.id != user.id:
                await notify(db, m, "social", g.name, f"{user.display_name} joined the group.")
        await db.commit()
    return await _group_out(db, g, user)


@router.post("/groups/{group_id}/leave", status_code=204)
async def leave_group(group_id: uuid.UUID, db: DB, user: CurrentUser):
    g = await _group_or_404(db, group_id, user)
    await db.execute(delete(GroupMember).where(GroupMember.group_id == g.id, GroupMember.user_id == user.id))
    left = await db.scalar(select(func.count()).select_from(GroupMember).where(GroupMember.group_id == g.id))
    if not left:
        await db.delete(g)
    elif g.owner_id == user.id:
        g.owner_id = await db.scalar(select(GroupMember.user_id).where(GroupMember.group_id == g.id).limit(1))
    await db.commit()


@router.post("/groups/{group_id}/habits", status_code=201)
async def add_group_habit(group_id: uuid.UUID, body: GroupHabitIn, db: DB, user: CurrentUser):
    g = await _group_or_404(db, group_id, user)
    db.add(
        GroupHabit(
            group_id=g.id,
            title=body.title.strip(),
            recurrence_rule=body.recurrence_rule,
            target_per_period=body.target_per_period,
            created_by=user.id,
        )
    )
    await db.commit()
    return await _group_out(db, g, user)


@router.delete("/groups/{group_id}/habits/{habit_id}", status_code=204)
async def remove_group_habit(group_id: uuid.UUID, habit_id: uuid.UUID, db: DB, user: CurrentUser):
    g = await _group_or_404(db, group_id, user)
    h = await db.get(GroupHabit, habit_id)
    if h is None or h.group_id != g.id:
        raise not_found("Group habit")
    h.deleted_at = utcnow()
    await db.commit()


@router.put("/group-habits/{habit_id}/checkins/{day}")
async def checkin(habit_id: uuid.UUID, day: date, body: CheckinIn, db: DB, user: CurrentUser):
    h = await db.get(GroupHabit, habit_id)
    if h is None or h.deleted_at is not None or not await _is_member(db, h.group_id, user.id):
        raise not_found("Group habit")
    today = local_today(user.timezone)
    if day > today or day < today - timedelta(days=7):
        raise AppError("invalid", "You can check in for today or the past week.", 422)
    existing = await db.scalar(
        select(GroupCheckin).where(
            GroupCheckin.group_habit_id == h.id, GroupCheckin.user_id == user.id, GroupCheckin.day == day
        )
    )
    if body.done and existing is None:
        db.add(GroupCheckin(group_habit_id=h.id, user_id=user.id, day=day))
        await db.flush()
        # Celebrate once when the whole group has done it today.
        members = set(
            (
                await db.execute(select(GroupMember.user_id).where(GroupMember.group_id == h.group_id))
            ).scalars()
        )
        done = set(
            (
                await db.execute(
                    select(GroupCheckin.user_id).where(
                        GroupCheckin.group_habit_id == h.id, GroupCheckin.day == day
                    )
                )
            ).scalars()
        )
        if len(members) > 1 and members <= done:
            for m in (await db.execute(select(User).where(User.id.in_(members)))).scalars():
                await notify(
                    db,
                    m,
                    "social",
                    f"Everyone did {h.title} 🎉",
                    "The whole group finished it today.",
                    dedupe_key=f"group-all:{h.id}:{day}:{m.id}",
                )
    elif not body.done and existing is not None:
        await db.delete(existing)
    await db.commit()
    g = await db.get(FriendGroup, h.group_id)
    return await _group_out(db, g, user)
