import fcntl
import os
import re
from importlib import resources
from pathlib import Path

from ..util import now_iso
from . import Database

_NAME = re.compile(r"^(\d{3})_([a-z0-9_]+)\.sql$")


def _discover():
    out = []
    for entry in resources.files("hive.db").joinpath("migrations").iterdir():
        m = _NAME.match(entry.name)
        if m:
            out.append((int(m.group(1)), m.group(2), entry.read_text(encoding="utf-8")))
    return sorted(out)


def apply_migrations(db: Database, lock_path: Path) -> list[int]:
    """Apply pending migrations, each in its own transaction. Cross-process safe (flock)."""
    applied_now = []
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        conn = db.connect()
        try:
            conn.execute(
                "CREATE TABLE IF NOT EXISTS schema_migrations("
                "version INTEGER PRIMARY KEY, name TEXT NOT NULL, applied_at TEXT NOT NULL)"
            )
            done = {r[0] for r in conn.execute("SELECT version FROM schema_migrations")}
            for version, name, sql in _discover():
                if version in done:
                    continue
                script = (
                    f"BEGIN IMMEDIATE;\n{sql}\n"
                    f"INSERT INTO schema_migrations(version,name,applied_at) "
                    f"VALUES({int(version)}, '{name}', '{now_iso()}');\nCOMMIT;"
                )
                try:
                    conn.executescript(script)
                except Exception:
                    if conn.in_transaction:
                        conn.execute("ROLLBACK")
                    raise
                applied_now.append(version)
        finally:
            conn.close()
    finally:
        os.close(fd)  # releases the flock
    return applied_now
