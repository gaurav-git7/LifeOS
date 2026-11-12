"""Rule-based parsing — the cheap path before any LLM call. ARCHITECTURE.md §12.2.

Handles "add task …", "remind me …" and quick-capture lines like
"study graphs tomorrow 7pm". Mirrors mobile/lib/shell/quick_capture_parser.dart.
"""

import re
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

_TIME = re.compile(r"\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b", re.I)
_WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]


@dataclass
class Parsed:
    title: str
    due_date: date | None = None
    due_at: datetime | None = None  # tz-aware when a time was given


def parse_capture(text: str, now: datetime) -> Parsed:
    """`now` must be tz-aware in the user's timezone."""
    s = f" {text.strip()} "
    day: date | None = None
    if re.search(r"\btomorrow\b", s, re.I):
        day = now.date() + timedelta(days=1)
        s = re.sub(r"\btomorrow\b", " ", s, flags=re.I)
    elif re.search(r"\b(today|tonight)\b", s, re.I):
        day = now.date()
        s = re.sub(r"\b(today|tonight)\b", " ", s, flags=re.I)
    else:
        for i, name in enumerate(_WEEKDAYS):
            pat = rf"\b(on\s+)?(next\s+)?{name}\b"
            if re.search(pat, s, re.I):
                ahead = (i - now.weekday()) % 7 or 7
                day = now.date() + timedelta(days=ahead)
                s = re.sub(pat, " ", s, flags=re.I)
                break

    due_at = None
    for m in _TIME.finditer(s):
        if m.group(3) is None and m.group(2) is None:
            continue  # plain number ("3 problems"), not a time
        hour, minute = int(m.group(1)), int(m.group(2) or 0)
        ampm = (m.group(3) or "").lower()
        if ampm == "pm" and hour < 12:
            hour += 12
        if ampm == "am" and hour == 12:
            hour = 0
        if hour < 24 and minute < 60:
            day = day or now.date()
            due_at = datetime.combine(day, time(hour, minute), tzinfo=now.tzinfo or ZoneInfo("UTC"))
            s = s[: m.start()] + " " + s[m.end() :]
        break

    title = re.sub(r"\s+", " ", s).strip(" ,.-")
    title = title[:1].upper() + title[1:] if title else text.strip()
    return Parsed(title=title[:200], due_date=None if due_at else day, due_at=due_at)


_COMMAND = re.compile(r"^\s*(?:please\s+)?(add|create|new)\s+(?:a\s+)?task[:\s]+(?P<rest>.+)$", re.I)
_REMIND = re.compile(r"^\s*(?:please\s+)?remind\s+me\s+(?:to\s+)?(?P<rest>.+)$", re.I)


def parse_command(message: str, now: datetime) -> tuple[str, dict] | None:
    """Returns (tool_name, arguments) for simple commands, else None."""
    if m := _COMMAND.match(message):
        p = parse_capture(m.group("rest"), now)
        args: dict = {"title": p.title}
        if p.due_at:
            args["due_at"] = p.due_at.isoformat()
        elif p.due_date:
            args["due_date"] = p.due_date.isoformat()
        return "create_task", args
    if m := _REMIND.match(message):
        p = parse_capture(m.group("rest"), now)
        if p.due_at:
            return "create_reminder", {"title": p.title, "remind_at": p.due_at.isoformat()}
    return None
