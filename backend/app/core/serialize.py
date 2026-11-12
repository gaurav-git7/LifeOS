import uuid
from datetime import date, datetime, time
from decimal import Decimal

from sqlalchemy import inspect


def jsonable(value):
    if isinstance(value, uuid.UUID):
        return str(value)
    if isinstance(value, datetime | date | time):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, dict):
        return {k: jsonable(v) for k, v in value.items()}
    if isinstance(value, list | tuple):
        return [jsonable(v) for v in value]
    return value


def row_to_dict(obj) -> dict:
    """All mapped columns of an ORM object as JSON-safe values (keyed by attribute name)."""
    mapper = inspect(obj).mapper
    return {attr.key: jsonable(getattr(obj, attr.key)) for attr in mapper.column_attrs}
