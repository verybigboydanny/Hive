"""Workspace: the only part of the filesystem Hive exposes.

Path policy (enforced in `resolve`, the single choke point for every file tool):
  * relative POSIX-style paths only; no absolute paths, '~', backslashes, NUL bytes, or '..'
  * any path segment named .hive or .git (case-insensitive: macOS is case-insensitive by default)
    is reserved: agents can never read or modify Hive's own database/trash or git internals
  * symlinks are resolved and the *real* location must remain inside the workspace root
"""
import fcntl
import json
import os
import re
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

from .db import Database
from .db.migrations import apply_migrations
from .errors import HiveError, INVALID_ARGUMENT, NOT_INITIALIZED, PATH_DENIED
from .util import now_iso

PROTECTED = frozenset({".hive", ".git"})
HUMAN_ID = "user"
_DRIVE = re.compile(r"^[A-Za-z]:")


@dataclass(frozen=True)
class Resolved:
    path: Path   # real absolute path (inside root)
    rel: str     # posix path relative to root ('.' for root)


def _denied(msg: str, rel: str | None = None) -> HiveError:
    return HiveError(PATH_DENIED, msg, {"path": rel} if rel is not None else {})


class Workspace:
    def __init__(self, root: Path):
        self.root = Path(root).resolve(strict=True)
        self.hive_dir = self.root / ".hive"
        self.db_path = self.hive_dir / "hive.db"
        self.trash_dir = self.hive_dir / "trash"

    # ---- lifecycle -------------------------------------------------------------------
    @classmethod
    def init(cls, root, project_name: str | None = None) -> "Workspace":
        p = Path(root).expanduser()
        if not p.is_dir():
            raise HiveError(INVALID_ARGUMENT, f"workspace is not a directory: {root}")
        real = p.resolve(strict=True)
        if real == Path(real.anchor) or real == Path.home().resolve():
            raise HiveError(
                PATH_DENIED,
                "refusing to use the filesystem root or your home directory as a workspace; "
                "choose a project folder",
            )
        hive = real / ".hive"
        if hive.is_symlink():
            raise HiveError(PATH_DENIED, ".hive must be a real directory, not a symlink")
        (hive / "trash").mkdir(parents=True, exist_ok=True)
        (hive / "checkpoints").mkdir(exist_ok=True)
        ws = cls(real)
        cfg = hive / "config.json"
        if not cfg.exists():
            cfg.write_text(json.dumps({"schema": 1, "created_at": now_iso()}, indent=2) + "\n")
        db = Database(ws.db_path)
        apply_migrations(db, hive / "migrate.lock")
        with db.write() as c:
            c.execute(
                "INSERT OR IGNORE INTO project(id,name,created_at) VALUES(1,?,?)",
                (project_name or real.name, now_iso()),
            )
            c.execute(
                "INSERT OR IGNORE INTO agents(id,agent_key,name,client,kind,registered_at,last_seen_at)"
                " VALUES(?,?,?,?,?,?,?)",
                (HUMAN_ID, "human:user", "You", "human", "human", now_iso(), now_iso()),
            )
        ws._git_exclude()
        return ws

    @classmethod
    def open(cls, root) -> "Workspace":
        p = Path(root).expanduser()
        if not (p / ".hive" / "hive.db").is_file():
            raise HiveError(NOT_INITIALIZED, f"{root} is not a Hive workspace; run `hive init` first")
        ws = cls(p)
        if ws.hive_dir.is_symlink():
            raise HiveError(PATH_DENIED, ".hive must be a real directory, not a symlink")
        return ws

    def _git_exclude(self) -> None:
        """Keep .hive/ out of the user's git status without editing their .gitignore."""
        git = self.root / ".git"
        if not git.is_dir():
            return
        exclude = git / "info" / "exclude"
        exclude.parent.mkdir(exist_ok=True)
        existing = exclude.read_text() if exclude.exists() else ""
        if ".hive/" not in existing.splitlines():
            with open(exclude, "a") as f:
                f.write(("" if existing.endswith("\n") or not existing else "\n") + ".hive/\n")

    # ---- cross-process mutation lock ------------------------------------------------
    @contextmanager
    def fs_lock(self):
        """Serializes file mutations across threads AND processes (stdio clients spawn one
        server process each). flock is per open-file-description, so it also serializes threads."""
        fd = os.open(self.hive_dir / "fs.lock", os.O_CREAT | os.O_RDWR, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            yield
        finally:
            os.close(fd)

    # ---- path resolution ---------------------------------------------------------------
    def resolve(self, rel, *, follow_final: bool = True, allow_root: bool = False) -> Resolved:
        if not isinstance(rel, str) or not rel.strip():
            raise _denied("path must be a non-empty string")
        if "\x00" in rel or "\\" in rel:
            raise _denied("path contains forbidden characters", rel)
        if rel.startswith(("/", "~")) or _DRIVE.match(rel):
            raise _denied("absolute paths are not allowed; use a path relative to the workspace", rel)
        parts = [p for p in rel.split("/") if p not in ("", ".")]
        if ".." in parts:
            raise _denied("'..' is not allowed in paths", rel)
        for p in parts:
            if p.casefold() in PROTECTED:
                raise _denied(f"'{p}' is reserved and cannot be accessed", rel)
        if not parts:
            if allow_root:
                return Resolved(self.root, ".")
            raise _denied("path refers to the workspace root", rel)
        lexical = self.root.joinpath(*parts)
        # follow_final=False: operate on a symlink itself (delete/rename) instead of its target
        real = lexical.resolve(strict=False) if follow_final else lexical.parent.resolve(strict=False) / lexical.name
        try:
            rel_real = real.relative_to(self.root)
        except ValueError:
            raise _denied("path resolves outside the workspace", rel) from None
        for p in rel_real.parts:
            if p.casefold() in PROTECTED:
                raise _denied("path resolves into a reserved location", rel)
        return Resolved(real, rel_real.as_posix() or ".")
