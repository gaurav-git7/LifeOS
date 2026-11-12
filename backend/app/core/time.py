"""Timezone helpers. Timestamps are stored in UTC; dates like habit log
days and summary dates are the *user's local* date. See ARCHITECTURE.md §8.1."""

from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from .types import utcnow


def tz(name: str | None) -> ZoneInfo:
    try:
        return ZoneInfo(name or "UTC")
    except (ZoneInfoNotFoundError, ValueError):
        return ZoneInfo("UTC")


def valid_timezone(name: str) -> bool:
    try:
        ZoneInfo(name)
        return True
    except (ZoneInfoNotFoundError, ValueError):
        return False


def local_now(tz_name: str | None) -> datetime:
    return utcnow().astimezone(tz(tz_name))


def local_today(tz_name: str | None) -> date:
    return local_now(tz_name).date()


def day_bounds_utc(day: date, tz_name: str | None) -> tuple[datetime, datetime]:
    """UTC [start, end) of a local calendar day."""
    z = tz(tz_name)
    start = datetime.combine(day, time.min, tzinfo=z)
    end = start + timedelta(days=1)
    return start.astimezone(UTC), end.astimezone(UTC)


def week_start(day: date, week_start_day: int = 1) -> date:
    """week_start_day: 1 = Monday … 7 = Sunday (ISO)."""
    offset = (day.isoweekday() - week_start_day) % 7
    return day - timedelta(days=offset)
