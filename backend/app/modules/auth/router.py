import html

from fastapi import APIRouter, BackgroundTasks, Form, Request
from fastapi.responses import HTMLResponse

from ...core.deps import DB, CurrentUser
from ...core.errors import AppError
from ...core.rate_limit import limiter
from . import service
from .schemas import (
    ChangePasswordIn,
    EmailIn,
    LoginIn,
    Message,
    RefreshIn,
    RegisterIn,
    ResetIn,
    TokenIn,
    TokenPair,
)

router = APIRouter(prefix="/auth", tags=["auth"])


def _ip(request: Request) -> str | None:
    return request.client.host if request.client else None


@router.post("/register", response_model=TokenPair, status_code=201)
@limiter.limit("3/hour")
async def register(request: Request, body: RegisterIn, db: DB, bg: BackgroundTasks):
    return await service.register(db, body, bg, _ip(request))


@router.post("/login", response_model=TokenPair)
@limiter.limit("5/minute")
async def login(request: Request, body: LoginIn, db: DB):
    return await service.login(db, body.email, body.password, body.device_label, _ip(request))


@router.post("/refresh", response_model=TokenPair)
@limiter.limit("30/minute")
async def refresh(request: Request, body: RefreshIn, db: DB):
    return await service.refresh(db, body.refresh_token, _ip(request))


@router.post("/logout", response_model=Message)
async def logout(body: RefreshIn, db: DB, user: CurrentUser):
    await service.logout(db, user, body.refresh_token)
    return Message(message="Signed out.")


@router.post("/logout-all", response_model=Message)
async def logout_all(request: Request, db: DB, user: CurrentUser):
    await service.logout_all(db, user, _ip(request))
    return Message(message="Signed out on all devices.")


@router.post("/verify-email", response_model=Message)
async def verify_email(body: TokenIn, db: DB):
    await service.verify_email(db, body.token)
    return Message(message="Email verified.")


_PAGE = """<!doctype html><html><head><meta charset="utf-8"><meta name="viewport"
content="width=device-width,initial-scale=1"><title>LifeOS</title><style>body{{font-family:system-ui;
background:#07070B;color:#F5F5F7;display:grid;place-items:center;min-height:100vh;margin:0}}main{{max-width:360px;
padding:24px}}input,button{{width:100%;padding:12px;margin-top:10px;border-radius:12px;border:1px solid #333;
background:#14141B;color:#fff;font-size:15px}}button{{background:#fff;color:#000;font-weight:600}}</style></head>
<body><main>{body}</main></body></html>"""


@router.get("/verify-email", response_class=HTMLResponse, include_in_schema=False)
async def verify_email_page(token: str, db: DB):
    """Target of the link in the verification email."""
    try:
        await service.verify_email(db, token)
        body = "<h2>Email verified ✓</h2><p>You can go back to the LifeOS app.</p>"
    except AppError as e:
        body = f"<h2>Link not valid</h2><p>{html.escape(e.message)}</p>"
    return HTMLResponse(_PAGE.format(body=body))


@router.post("/resend-verification", response_model=Message)
@limiter.limit("3/hour")
async def resend_verification(request: Request, db: DB, user: CurrentUser, bg: BackgroundTasks):
    await service.resend_verification(db, user, bg)
    return Message(message="If your email isn't verified yet, a new link is on its way.")


@router.post("/forgot-password", response_model=Message)
@limiter.limit("3/hour")
async def forgot_password(request: Request, body: EmailIn, db: DB, bg: BackgroundTasks):
    await service.forgot_password(db, body.email, bg)
    return Message(message="If an account exists for this email, a reset link has been sent.")


@router.post("/reset-password", response_model=Message)
@limiter.limit("10/hour")
async def reset_password(request: Request, body: ResetIn, db: DB):
    await service.reset_password(db, body.token, body.new_password, _ip(request))
    return Message(message="Password updated. Sign in with your new password.")


@router.get("/reset-password", response_class=HTMLResponse, include_in_schema=False)
async def reset_password_page(token: str):
    """Target of the link in the reset email: a minimal form."""
    t = html.escape(token, quote=True)
    body = (
        "<h2>Set a new password</h2><form method='post' action='reset-password/form'>"
        f"<input type='hidden' name='token' value='{t}'>"
        "<input type='password' name='new_password' placeholder='New password (10+ characters)' "
        "minlength='10' required><button type='submit'>Update password</button></form>"
    )
    return HTMLResponse(_PAGE.format(body=body))


@router.post("/reset-password/form", response_class=HTMLResponse, include_in_schema=False)
@limiter.limit("10/hour")
async def reset_password_form(
    request: Request, db: DB, token: str = Form(...), new_password: str = Form(...)
):
    try:
        await service.reset_password(db, token, new_password, _ip(request))
        body = "<h2>Password updated ✓</h2><p>Sign in with your new password in the app.</p>"
    except AppError as e:
        body = f"<h2>Couldn't update password</h2><p>{html.escape(e.message)}</p>"
    return HTMLResponse(_PAGE.format(body=body))


@router.post("/change-password", response_model=Message)
async def change_password(request: Request, body: ChangePasswordIn, db: DB, user: CurrentUser):
    await service.change_password(db, user, body.current_password, body.new_password, _ip(request))
    return Message(message="Password changed.")
