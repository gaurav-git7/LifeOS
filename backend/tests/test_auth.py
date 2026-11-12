from app.core.config import settings
from app.modules.auth import service as auth_service

from .conftest import API, PASSWORD, auth, register


async def test_first_user_is_admin_and_me_works(client):
    tokens = await register(client)
    assert tokens["user"]["role"] == "admin"
    r = await client.get(f"{API}/users/me", headers=auth(tokens))
    assert r.status_code == 200 and r.json()["email"] == "me@example.com"


async def test_requires_auth(client):
    r = await client.get(f"{API}/tasks")
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "not_authenticated"


async def test_weak_password_and_duplicate_email(client):
    await register(client)
    r = await client.post(
        f"{API}/auth/register", json={"email": "x@example.com", "password": "short", "display_name": "X"}
    )
    assert r.json()["error"]["code"] == "weak_password"
    r = await client.post(
        f"{API}/auth/register", json={"email": "ME@example.com", "password": PASSWORD, "display_name": "Dup"}
    )
    assert r.status_code == 409


async def test_invite_mode(client, monkeypatch):
    admin = await register(client)  # first user always allowed
    monkeypatch.setattr(settings, "REGISTRATION_MODE", "invite")
    body = {"email": "friend@example.com", "password": PASSWORD, "display_name": "Friend"}
    r = await client.post(f"{API}/auth/register", json=body)
    assert r.json()["error"]["code"] == "invite_required"

    code = (await client.post(f"{API}/admin/invites", json={}, headers=auth(admin))).json()["code"]
    r = await client.post(f"{API}/auth/register", json={**body, "invite_code": code})
    assert r.status_code == 201 and r.json()["user"]["role"] == "user"

    r = await client.post(
        f"{API}/auth/register", json={**body, "email": "other@example.com", "invite_code": code}
    )
    assert r.json()["error"]["code"] == "invalid_invite"  # single use


async def test_login(client):
    await register(client)
    bad = await client.post(
        f"{API}/auth/login", json={"email": "me@example.com", "password": "wrong-password-1"}
    )
    assert bad.status_code == 401
    ok = await client.post(f"{API}/auth/login", json={"email": "Me@Example.com", "password": PASSWORD})
    assert ok.status_code == 200 and ok.json()["access_token"]


async def test_refresh_rotation_and_reuse_detection(client):
    t1 = await register(client)
    r = await client.post(f"{API}/auth/refresh", json={"refresh_token": t1["refresh_token"]})
    assert r.status_code == 200
    t2 = r.json()
    assert t2["refresh_token"] != t1["refresh_token"]

    reuse = await client.post(f"{API}/auth/refresh", json={"refresh_token": t1["refresh_token"]})
    assert reuse.json()["error"]["code"] == "token_reused"
    # the whole family is revoked, including the newer token
    r = await client.post(f"{API}/auth/refresh", json={"refresh_token": t2["refresh_token"]})
    assert r.status_code == 401


async def test_logout_all_invalidates_access_tokens(client):
    t = await register(client)
    assert (await client.post(f"{API}/auth/logout-all", headers=auth(t))).status_code == 200
    assert (await client.get(f"{API}/users/me", headers=auth(t))).status_code == 401


async def test_verify_email_and_password_reset(client, monkeypatch):
    sent = {}

    async def capture(kind):
        async def _send(to, name, token):
            sent[kind] = token

        return _send

    monkeypatch.setattr(auth_service, "send_verification_email", await capture("verify"))
    monkeypatch.setattr(auth_service, "send_reset_email", await capture("reset"))

    t = await register(client)
    r = await client.post(f"{API}/auth/verify-email", json={"token": sent["verify"]})
    assert r.status_code == 200
    me = (await client.get(f"{API}/users/me", headers=auth(t))).json()
    assert me["email_verified_at"] is not None

    await client.post(f"{API}/auth/forgot-password", json={"email": "me@example.com"})
    unknown = await client.post(f"{API}/auth/forgot-password", json={"email": "nobody@example.com"})
    assert unknown.status_code == 200  # no account enumeration

    new_pw = "another-strong-password"
    r = await client.post(f"{API}/auth/reset-password", json={"token": sent["reset"], "new_password": new_pw})
    assert r.status_code == 200
    assert (await client.get(f"{API}/users/me", headers=auth(t))).status_code == 401  # old sessions ended
    r = await client.post(f"{API}/auth/login", json={"email": "me@example.com", "password": new_pw})
    assert r.status_code == 200
    again = await client.post(
        f"{API}/auth/reset-password", json={"token": sent["reset"], "new_password": new_pw}
    )
    assert again.status_code == 400  # single use
