"""Global project registry: which Hive project id lives in which folder on this machine.

Why it exists: an MCP client configuration is global (one entry, shared by every project the user opens),
but a workspace is a folder. The registry lets ONE project-agnostic `hive mcp` process find the right folder
from the `project_id` an agent presents, so nothing about a previously used folder is ever baked into a client.

Properties
  * Location: `$HIVE_HOME` or `~/.hive` (directory 0700, file 0600). Contains only ids, names and folder paths.
  * Written by every `HiveApp.init/open` (the macOS app, the CLI and any pinned MCP process), never by agents.
  * Agents supply an *id*, never a path: they cannot point Hive at an arbitrary folder.
  * Every resolution is re-verified against the id stored inside the workspace database, so a moved, replaced
    or copied folder can never be mistaken for the project it used to be.
  * Cross-process safe: flock around read-modify-write, atomic replace on write.
"""

from __future__ import annotations

import contextlib
import fcntl
import json
import logging
import os
import sqlite3
from pathlib import Path
from typing import Any, Iterator

from .util import PROJECT_ID_RE, now_iso

log = logging.getLogger("hive.projects")


def default_home() -> Path:
    env = os.environ.get("HIVE_HOME")
    return Path(env).expanduser() if env else Path.home() / ".hive"


def read_workspace_uid(root: Path) -> str | None:
    """The project id stored inside a workspace database (read-only; None if unreadable or not yet assigned)."""
    db = Path(root) / ".hive" / "hive.db"
    if not db.is_file():
        return None
    try:
        conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True, timeout=5)
        try:
            row = conn.execute("SELECT uid FROM project WHERE id=1").fetchone()
        finally:
            conn.close()
    except sqlite3.Error:
        return None
    return row[0] if row and row[0] else None


class ProjectRegistry:
    def __init__(self, home: Path | str | None = None) -> None:
        self.home = Path(home).expanduser() if home else default_home()
        self.path = self.home / "projects.json"
        self._lock_path = self.home / "projects.lock"

    # ------------------------------------------------------------------ storage
    @contextlib.contextmanager
    def _locked(self) -> Iterator[None]:
        self.home.mkdir(parents=True, exist_ok=True)
        os.chmod(self.home, 0o700)
        fd = os.open(self._lock_path, os.O_CREAT | os.O_RDWR, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            yield
        finally:
            os.close(fd)

    def _load(self) -> dict[str, Any]:
        try:
            raw = self.path.read_text(encoding="utf-8")
        except FileNotFoundError:
            return {"schema": 1, "projects": {}}
        try:
            data = json.loads(raw)
            if not isinstance(data, dict) or not isinstance(data.get("projects"), dict):
                raise ValueError("unexpected structure")
            return data
        except ValueError as exc:
            backup = self.path.with_name(f"projects.json.corrupt-{now_iso().replace(':', '-')}")
            self.path.replace(backup)
            log.warning("project registry was unreadable (%s); moved to %s and started a new one", exc, backup)
            return {"schema": 1, "projects": {}}

    def _save(self, data: dict[str, Any]) -> None:
        tmp = self.path.with_name(f".projects.json.{os.getpid()}.tmp")
        fd = os.open(tmp, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, sort_keys=True)
            f.write("\n")
        os.replace(tmp, self.path)

    # --------------------------------------------------------------------- API
    def claim(self, uid: str, root: Path, name: str) -> bool:
        """Record that project `uid` lives at `root`. Returns False when another LIVE workspace already owns the
        id (the caller is a copy and must be given its own id); a moved workspace (old folder gone) takes over."""
        if not PROJECT_ID_RE.match(uid):
            raise ValueError(f"malformed project id: {uid!r}")
        root = Path(root)
        with self._locked():
            data = self._load()
            entry = data["projects"].get(uid)
            if entry and entry.get("root") != str(root):
                old = Path(entry["root"])
                if old.is_dir() and read_workspace_uid(old) == uid:
                    return False
            data["projects"][uid] = {"root": str(root), "name": name, "last_opened_at": now_iso()}
            self._save(data)
            return True

    def resolve(self, uid: str) -> Path | None:
        if not self.path.exists():
            return None
        with self._locked():
            entry = self._load()["projects"].get(uid)
        return Path(entry["root"]) if entry and isinstance(entry.get("root"), str) else None

    def list(self) -> list[dict[str, Any]]:
        if not self.path.exists():
            return []
        with self._locked():
            projects = self._load()["projects"]
        return [{"id": uid, **{k: v for k, v in e.items() if k in ("name", "root", "last_opened_at")}}
                for uid, e in sorted(projects.items(), key=lambda kv: kv[1].get("last_opened_at", ""), reverse=True)]
