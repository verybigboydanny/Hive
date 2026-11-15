from __future__ import annotations

import hashlib
import re
import secrets
from datetime import datetime, timedelta, timezone

_PARSE_FMT = "%Y-%m-%dT%H:%M:%S.%fZ"


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime) -> str:
    """Fixed-width UTC timestamp with millisecond precision; sorts lexicographically."""
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def now_iso() -> str:
    return iso(utcnow())


def in_minutes(minutes: float) -> str:
    return iso(utcnow() + timedelta(minutes=minutes))


def parse_iso(value: str) -> datetime:
    return datetime.strptime(value, _PARSE_FMT).replace(tzinfo=timezone.utc)


def age_seconds(value: str) -> float:
    return (utcnow() - parse_iso(value)).total_seconds()


def new_id(prefix: str) -> str:
    return f"{prefix}_{secrets.token_hex(5)}"


PROJECT_ID_RE = re.compile(r"^prj_[0-9a-f]{16}$")


def new_project_id() -> str:
    """Stable, unguessable project identity (64 random bits). Stored in the workspace database."""
    return f"prj_{secrets.token_hex(8)}"


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def clean_text(value, field: str, *, max_chars: int, required: bool = False, allow_empty: bool = False):
    """Validate a free-text argument. Returns str or None. Rejects non-strings and NUL bytes."""
    from .errors import HiveError, INVALID_ARGUMENT
    if value is None:
        if required:
            raise HiveError(INVALID_ARGUMENT, f"{field} is required")
        return None
    if not isinstance(value, str) or "\x00" in value:
        raise HiveError(INVALID_ARGUMENT, f"{field} must be a string without NUL bytes")
    if (required or not allow_empty) and not value.strip():
        if required:
            raise HiveError(INVALID_ARGUMENT, f"{field} must not be empty")
        return None
    if len(value) > max_chars:
        raise HiveError(INVALID_ARGUMENT, f"{field} exceeds {max_chars} characters")
    return value


def clean_str_list(value, field: str, *, max_items: int = 50, max_len: int = 200) -> list[str]:
    from .errors import HiveError, INVALID_ARGUMENT
    if value is None:
        return []
    if not isinstance(value, (list, tuple)) or len(value) > max_items:
        raise HiveError(INVALID_ARGUMENT, f"{field} must be a list of at most {max_items} strings")
    out: list[str] = []
    for v in value:
        if not isinstance(v, str) or not v.strip() or len(v) > max_len or "\x00" in v:
            raise HiveError(INVALID_ARGUMENT, f"{field} entries must be non-empty strings up to {max_len} characters")
        if v not in out:
            out.append(v)
    return out
