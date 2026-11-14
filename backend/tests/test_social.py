"""Friends see only what's shared; groups work; the group streak rule."""

from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from app.modules.social.router import group_streak

from .conftest import API, auth, register


async def test_friends_see_only_shared_habits(client, user):
    friend = auth(await register(client, "m@example.com", "Maitrey"))
    stranger = auth(await register(client, "s@example.com", "Stranger"))
    code = (await client.get(f"{API}/social/me", headers=friend)).json()["friend_code"]

    r = await client.post(f"{API}/social/friends", json={"code": code}, headers=user["h"])
    assert r.json()["status"] == "pending"
    me_id = (await client.get(f"{API}/users/me", headers=user["h"])).json()["id"]
    assert (await client.post(f"{API}/social/friends/{me_id}/accept", headers=friend)).status_code == 200

    await client.post(f"{API}/habits", json={"title": "AI study", "visibility": "friends"}, headers=friend)
    await client.post(f"{API}/habits", json={"title": "Therapy"}, headers=friend)  # private

    feed = (await client.get(f"{API}/social/feed", headers=user["h"])).json()
    assert [h["title"] for h in feed[0]["habits"]] == ["AI study"]
    assert (await client.get(f"{API}/social/feed", headers=stranger)).json() == []

    hid = feed[0]["habits"][0]["id"]
    body = {"to_user_id": feed[0]["id"], "kind": "nudge", "habit_id": hid}
    assert (await client.post(f"{API}/social/react", json=body, headers=user["h"])).status_code == 201
    assert (await client.post(f"{API}/social/react", json=body, headers=user["h"])).status_code == 429
    assert (await client.post(f"{API}/social/react", json=body, headers=stranger)).status_code == 404


async def test_group_habit_checkins(client, user):
    friend = auth(await register(client, "m@example.com", "Maitrey"))
    g = (await client.post(f"{API}/social/groups", json={"name": "DSA squad"}, headers=user["h"])).json()
    assert (
        await client.post(f"{API}/social/groups/join", json={"code": g["invite_code"]}, headers=friend)
    ).status_code == 200
    g = (
        await client.post(
            f"{API}/social/groups/{g['id']}/habits", json={"title": "2 problems"}, headers=friend
        )
    ).json()
    hid = g["habits"][0]["id"]
    day = datetime.now(ZoneInfo("Asia/Kolkata")).date()  # the test user's timezone
    r = await client.put(
        f"{API}/social/group-habits/{hid}/checkins/{day}", json={"done": True}, headers=user["h"]
    )
    assert len(r.json()["habits"][0]["done_today"]) == 1
    other = auth(await register(client, "x@example.com", "X"))
    assert (await client.get(f"{API}/social/groups", headers=other)).json() == []


def test_group_streak_allows_one_miss_a_week():
    today = date(2026, 11, 18)  # Wednesday
    members = {"a", "b"}
    start = today - timedelta(days=30)
    days = {today - timedelta(days=i): {"a", "b"} for i in range(1, 10)}
    days[today - timedelta(days=2)] = {"a"}  # one miss (Monday): forgiven
    assert group_streak("FREQ=DAILY", 1, start, today, members, days) == 9
    days[today - timedelta(days=1)] = {"a"}  # second miss the same week: only the newest is forgiven
    assert group_streak("FREQ=DAILY", 1, start, today, members, days) == 1
