"""Backend settings. Read from the optional `settings` object in .hive/config.json
(the original config.json only has `schema` and `created_at`; this module never rewrites it)."""

from __future__ import annotations

import json
from dataclasses import dataclass, fields
from pathlib import Path


@dataclass(frozen=True)
class HiveSettings:
    lease_minutes: int = 30                  # task claim lease; renewed by owner activity
    max_lease_minutes: int = 240
    handoff_hold_hours: int = 24             # a task stays reserved while its handoff is pending
    max_active_tasks_per_agent: int = 5
    max_agents: int = 200
    presence_online_seconds: int = 120
    presence_away_seconds: int = 900
    touch_interval_seconds: int = 5          # last_seen write throttle
    max_message_chars: int = 20000
    max_memory_value_chars: int = 20000
    max_text_chars: int = 20000              # descriptions, summaries, contexts

    @classmethod
    def from_dict(cls, data: dict) -> "HiveSettings":
        known = {f.name for f in fields(cls)}
        clean = {k: v for k, v in data.items()
                 if k in known and isinstance(v, int) and not isinstance(v, bool) and v > 0}
        return cls(**clean)


def load_settings(hive_dir: Path) -> HiveSettings:
    try:
        data = json.loads((Path(hive_dir) / "config.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return HiveSettings()
    s = data.get("settings") if isinstance(data, dict) else None
    return HiveSettings.from_dict(s) if isinstance(s, dict) else HiveSettings()
