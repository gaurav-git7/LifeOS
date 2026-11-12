"""Thin LLM wrapper: Gemini in production, a deterministic fake for tests and
key-less development. Every call is logged to llm_calls with tokens and cost,
and blocked when the user's daily budget is spent. ARCHITECTURE.md §17."""

import json
import logging
import re
import time
from dataclasses import dataclass
from datetime import timedelta
from typing import Literal

from pydantic import BaseModel, ValidationError
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core.config import settings
from ...core.time import day_bounds_utc, local_today
from ...models import LlmCall, User, UserPreferences

log = logging.getLogger("lifeos.llm")
Tier = Literal["lite", "default", "pro"]

MAX_TOKENS = {
    "chat": 1500,
    "daily_review": 1200,
    "weekly_review": 2000,
    "learning_plan": 4000,
    "quick_capture": 400,
}


class BudgetExceeded(Exception):
    pass


class LLMFailed(Exception):
    pass


@dataclass
class LLMResult[T]:
    parsed: T
    call: LlmCall


def model_for(tier: Tier) -> str:
    return {
        "lite": settings.GEMINI_MODEL_LITE,
        "default": settings.GEMINI_MODEL_DEFAULT,
        "pro": settings.GEMINI_MODEL_PRO,
    }[tier]


def cost_usd(model: str, input_tokens: int, output_tokens: int) -> float:
    price_in, price_out = settings.GEMINI_PRICES.get(model, (0.0, 0.0))
    return (input_tokens * price_in + output_tokens * price_out) / 1_000_000


async def spent_today(db: AsyncSession, user: User) -> float:
    start, _ = day_bounds_utc(local_today(user.timezone), user.timezone)
    return float(
        await db.scalar(
            select(func.coalesce(func.sum(LlmCall.cost_usd), 0.0)).where(
                LlmCall.user_id == user.id, LlmCall.created_at >= start
            )
        )
        or 0.0
    )


async def daily_budget(db: AsyncSession, user: User) -> float:
    prefs = await db.get(UserPreferences, user.id)
    if prefs and prefs.ai_daily_budget_usd is not None:
        return prefs.ai_daily_budget_usd  # user's own cap (validated ≤ $5/day)
    return settings.AI_DAILY_BUDGET_USD


async def budget_left(db: AsyncSession, user: User) -> bool:
    return await spent_today(db, user) < await daily_budget(db, user)


# ---------- providers ----------


class _Raw(BaseModel):
    text: str
    input_tokens: int = 0
    output_tokens: int = 0
    cached_tokens: int = 0


async def _gemini(
    model: str, system: str, prompt: str, schema: type[BaseModel], max_tokens: int, tier: Tier
) -> _Raw:
    from google import genai
    from google.genai import types

    client = genai.Client(api_key=settings.GEMINI_API_KEY)
    config = types.GenerateContentConfig(
        system_instruction=system,
        response_mime_type="application/json",
        response_schema=schema,
        temperature=0.4,
        max_output_tokens=max_tokens,
        # thinking costs output tokens; keep it off for the cheap tiers
        thinking_config=types.ThinkingConfig(thinking_budget=0) if tier != "pro" else None,
    )
    resp = await client.aio.models.generate_content(model=model, contents=prompt, config=config)
    u = resp.usage_metadata
    return _Raw(
        text=resp.text or "",
        input_tokens=(u.prompt_token_count or 0) if u else 0,
        output_tokens=((u.candidates_token_count or 0) + (u.thoughts_token_count or 0)) if u else 0,
        cached_tokens=(u.cached_content_token_count or 0) if u else 0,
    )


def _fake(system: str, prompt: str, schema: type[BaseModel]) -> _Raw:
    """Deterministic stand-in so the whole agent flow works without an API key."""
    msg = prompt.rsplit("USER MESSAGE:", 1)[-1].strip() if "USER MESSAGE:" in prompt else ""
    today = re.search(r'"today": "(\d{4}-\d{2}-\d{2})"', prompt)
    day = today.group(1) if today else "2030-01-01"
    from datetime import date as _date

    tomorrow = (_date.fromisoformat(day) + timedelta(days=1)).isoformat()
    if schema.__name__ == "LLMReview":
        data = {
            "insight": "Solid day. Keep tomorrow focused on your top priority first.",
            "highlights": ["You made progress on your priorities."],
            "attention": ["Review anything overdue."],
            "actions": [],
        }
    elif re.search(r"\b(roadmap|learn|plan)\b", msg, re.I) or "learning roadmaps" in system:
        subject = (
            re.sub(r"(?i).*\b(learn|roadmap for|plan for|roadmap)\b", "", msg).strip(" .?!") or "New skill"
        )
        args = {
            "title": f"{subject[:60].title()} roadmap",
            "skill_name": subject[:40].title(),
            "topics": [
                {"title": f"{subject[:40]} basics", "difficulty": "easy", "estimated_minutes": 60},
                {"title": f"{subject[:40]} core concepts", "difficulty": "medium", "estimated_minutes": 90},
                {"title": f"{subject[:40]} hands-on project", "difficulty": "hard", "estimated_minutes": 120},
            ],
        }
        data = {
            "intent": "create_learning_path",
            "message": "Here's a starter roadmap. Approve it to add it.",
            "confidence": 0.8,
            "actions": [
                {
                    "tool": "propose_create_learning_path",
                    "arguments_json": json.dumps(args),
                    "reason": "Structured path",
                }
            ],
            "memory_suggestions": [],
            "follow_up_question": "",
        }
    elif msg:
        args = {"title": msg[:120], "priority": "medium", "due_date": tomorrow}
        data = {
            "intent": "create_task",
            "message": "I can add that as a task for tomorrow.",
            "confidence": 0.7,
            "actions": [
                {
                    "tool": "propose_create_task",
                    "arguments_json": json.dumps(args),
                    "reason": "You asked for it",
                }
            ],
            "memory_suggestions": [],
            "follow_up_question": "",
        }
    else:
        data = {
            "intent": "general",
            "message": "How can I help?",
            "confidence": 0.5,
            "actions": [],
            "memory_suggestions": [],
            "follow_up_question": "",
        }
    return _Raw(
        text=json.dumps(data), input_tokens=len(prompt) // 4, output_tokens=len(json.dumps(data)) // 4
    )


async def call_llm[T: BaseModel](
    db: AsyncSession,
    user: User,
    *,
    purpose: str,
    prompt_version: str,
    system: str,
    prompt: str,
    schema: type[T],
    tier: Tier = "default",
) -> LLMResult[T]:
    """One structured call (+ one retry on invalid output). Raises BudgetExceeded / LLMFailed."""
    provider = settings.llm_provider
    model = model_for(tier) if provider == "gemini" else f"fake-{tier}"
    if not await budget_left(db, user):
        db.add(
            LlmCall(
                user_id=user.id,
                purpose=purpose,
                model=model,
                prompt_version=prompt_version,
                status="blocked_by_budget",
            )
        )
        raise BudgetExceeded()

    attempt_prompt = prompt
    last_error = ""
    for _attempt in range(2):
        started = time.perf_counter()
        call = LlmCall(
            user_id=user.id, purpose=purpose, model=model, prompt_version=prompt_version, status="ok"
        )
        db.add(call)
        try:
            if provider == "gemini":
                raw = await _gemini(
                    model, system, attempt_prompt, schema, MAX_TOKENS.get(purpose, 1500), tier
                )
            else:
                raw = _fake(system, attempt_prompt, schema)
        except Exception as e:  # noqa: BLE001
            call.status, call.error = "error", str(e)[:1000]
            call.latency_ms = int((time.perf_counter() - started) * 1000)
            log.exception("LLM call failed")
            raise LLMFailed(str(e)) from e
        call.latency_ms = int((time.perf_counter() - started) * 1000)
        call.input_tokens, call.output_tokens, call.cached_tokens = (
            raw.input_tokens,
            raw.output_tokens,
            raw.cached_tokens,
        )
        call.cost_usd = cost_usd(model, raw.input_tokens, raw.output_tokens)
        try:
            return LLMResult(parsed=schema.model_validate_json(raw.text), call=call)
        except ValidationError as e:
            call.status, call.error = "invalid_output", str(e)[:1000]
            last_error = str(e)[:500]
            attempt_prompt = (
                f"{prompt}\n\nYour previous reply was not valid JSON for the schema "
                f"({last_error}). Reply again with valid JSON only."
            )
    raise LLMFailed(f"invalid output: {last_error}")
