"""Email delivery: Resend (HTTP API), SMTP (e.g. Gmail app password) or console (dev)."""

import logging
import smtplib
from email.message import EmailMessage

import httpx
from starlette.concurrency import run_in_threadpool

from ..core.config import settings

log = logging.getLogger("lifeos.email")


def _send_smtp(to: str, subject: str, html: str, text: str) -> None:
    msg = EmailMessage()
    msg["From"] = settings.EMAIL_FROM
    msg["To"] = to
    msg["Subject"] = subject
    msg.set_content(text)
    msg.add_alternative(html, subtype="html")
    with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=20) as s:
        s.starttls()
        s.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
        s.send_message(msg)


async def send_email(to: str, subject: str, html: str, text: str = "") -> bool:
    """Never raises — failures are logged so a request is never broken by email."""
    try:
        if settings.EMAIL_PROVIDER == "resend" and settings.RESEND_API_KEY:
            async with httpx.AsyncClient(timeout=20) as client:
                r = await client.post(
                    "https://api.resend.com/emails",
                    headers={"Authorization": f"Bearer {settings.RESEND_API_KEY}"},
                    json={
                        "from": settings.EMAIL_FROM,
                        "to": [to],
                        "subject": subject,
                        "html": html,
                        "text": text or None,
                    },
                )
                r.raise_for_status()
        elif settings.EMAIL_PROVIDER == "smtp" and settings.SMTP_USER:
            await run_in_threadpool(_send_smtp, to, subject, html, text or subject)
        else:
            log.warning("EMAIL (console) to=%s subject=%s\n%s", to, subject, text or html)
        return True
    except Exception:  # noqa: BLE001
        log.exception("Email to %s failed", to)
        return False


def _wrap(title: str, body_html: str) -> str:
    return f"""<div style="font-family:system-ui,sans-serif;max-width:520px;margin:auto;padding:24px;
color:#111"><h2 style="font-weight:600">{title}</h2>{body_html}
<p style="color:#888;font-size:12px;margin-top:32px">LifeOS</p></div>"""


async def send_verification_email(to: str, name: str, token: str) -> None:
    link = f"{settings.PUBLIC_APP_URL}/api/v1/auth/verify-email?token={token}"
    await send_email(
        to,
        "Verify your LifeOS email",
        _wrap(
            f"Hi {name}",
            f'<p>Confirm your email to finish setting up LifeOS.</p><p><a href="{link}">Verify email</a></p>',
        ),
        f"Hi {name}, verify your email: {link}",
    )


async def send_reset_email(to: str, name: str, token: str) -> None:
    link = f"{settings.PUBLIC_APP_URL}/api/v1/auth/reset-password?token={token}"
    await send_email(
        to,
        "Reset your LifeOS password",
        _wrap(
            f"Hi {name}",
            f"<p>Use this link within 1 hour to set a new password.</p>"
            f'<p><a href="{link}">Reset password</a></p>'
            "<p>If you didn't ask for this, ignore this email.</p>",
        ),
        f"Reset your password (valid 1 hour): {link}",
    )
