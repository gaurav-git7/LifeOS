"""RFC 5545 RRULE helpers (tasks, habits, reminders). ARCHITECTURE.md §8.1."""

from datetime import date, datetime, time, timedelta

from dateutil.rrule import rrulestr


def validate_rrule(rule: str | None) -> str | None:
    if rule is None:
        return None
    rule = rule.strip().removeprefix("RRULE:")
    if not rule:
        return None
    try:
        rrulestr(rule, dtstart=datetime(2026, 1, 1))
    except (ValueError, TypeError) as e:
        raise ValueError(f"Invalid recurrence rule: {e}") from e
    return rule


def next_after(rule: str, dtstart: datetime, after: datetime) -> datetime | None:
    """Next occurrence strictly after `after` (both may be tz-aware)."""
    return rrulestr(rule, dtstart=dtstart).after(after)


def is_due_on(rule: str, start: date, day: date) -> bool:
    """Is a habit with this rule (starting on `start`) scheduled on `day`?

    Weekly rules without BYDAY ("3 times a week") count as due every day,
    since any day can be used.
    """
    if day < start:
        return False
    upper = rule.upper()
    if "FREQ=WEEKLY" in upper and "BYDAY" not in upper:
        return True
    r = rrulestr(rule, dtstart=datetime.combine(start, time(12)))
    lo = datetime.combine(day, time.min)
    return bool(r.between(lo, lo + timedelta(days=1), inc=True))
