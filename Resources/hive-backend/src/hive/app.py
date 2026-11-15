"""HiveApp: one opened workspace with all services wired together (the unit the MCP server and
the SwiftUI API both use). Lifecycle: init/open -> (use) -> close."""

from __future__ import annotations

import logging
import os
import time
from pathlib import Path
from typing import Any

from .activity import ActivityService
from .db import Database
from .db.migrations import _discover, apply_migrations
from .errors import HiveError
from .projects import ProjectRegistry
from .services.agents import AgentService
from .services.checkpoints import CheckpointService
from .services.files import FileService
from .services.handoffs import HandoffService
from .services.memory import MemoryService
from .services.messages import MessageService
from .services.project import ProjectService
from .services.tasks import TaskService
from .settings import HiveSettings, load_settings
from .workspace import Workspace

log = logging.getLogger("hive.app")


class HiveApp:
    def __init__(self, ws: Workspace, registry: ProjectRegistry | None = None) -> None:
        self.ws = ws
        self.registry = registry if registry is not None else ProjectRegistry()
        self.db = Database(ws.db_path)
        self.settings: HiveSettings = load_settings(ws.hive_dir)
        self.started_at = time.time()
        self.activity = ActivityService(self.db)
        self.agents = AgentService(self.db, self.settings)
        self.tasks = TaskService(self.db, self.settings, self.agents)
        self.messages = MessageService(self.db, self.settings)
        self.checkpoints = CheckpointService(self.db, self.settings, self.tasks)
        self.handoffs = HandoffService(self.db, self.settings, self.agents, self.tasks, self.messages)
        self.memory = MemoryService(self.db, self.settings)
        self.files = FileService(ws, self.activity)
        self.project = ProjectService(self.db, self.settings, ws.root, self.activity, self.agents, self.tasks,
                                      self.messages, self.handoffs, self.memory, self.checkpoints)
        self._closed = False

    # ------------------------------------------------------------------ lifecycle
    @classmethod
    def init(cls, path, name: str | None = None, *, registry: ProjectRegistry | None = None) -> "HiveApp":
        """Create (or idempotently re-initialise) a workspace, run all migrations, open it."""
        ws = Workspace.init(path, name)
        app = cls(ws, registry)
        app.migrate()                                   # no-op unless Workspace.init predates new migrations
        log.info("initialised workspace %s", ws.root)
        return app

    @classmethod
    def open(cls, path, *, registry: ProjectRegistry | None = None) -> "HiveApp":
        """Open an existing workspace; applies pending migrations (safe, locked, transactional)."""
        ws = Workspace.open(path)
        app = cls(ws, registry)
        applied = app.migrate()
        log.info("opened workspace %s (migrations applied: %s)", ws.root, applied or "none")
        return app

    def migrate(self) -> list[int]:
        """Apply pending migrations, make sure the project has its stable id, and record it in the registry."""
        applied = apply_migrations(self.db, self.ws.hive_dir / "migrate.lock")
        self._register_identity(self.project.ensure_uid())
        return applied

    def _register_identity(self, uid: str) -> None:
        """Tell the machine-wide registry where this project lives. A failure never blocks the workspace (a pinned
        MCP connection works without the registry) but is logged and shown by `hive doctor`."""
        name = self.project.info()["name"]
        try:
            if not self.registry.claim(uid, self.ws.root, name):
                # Another live workspace already owns this id: this folder is a copy. Give it its own identity.
                new_uid = self.project.reassign_uid("duplicate of another workspace")
                log.warning("workspace %s duplicated project %s; it is now project %s", self.ws.root, uid, new_uid)
                self.registry.claim(new_uid, self.ws.root, name)
        except (OSError, ValueError) as exc:
            log.warning("could not update the project registry at %s: %s", self.registry.path, exc)

    def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        log.info("closed workspace %s", self.ws.root)

    # --------------------------------------------------------------------- health
    def health(self) -> dict[str, Any]:
        from . import CONTRACT_VERSION, __version__
        checks: dict[str, Any] = {}
        expected = max(m[0] for m in _discover())
        try:
            with self.db.read() as c:
                c.execute("SELECT 1").fetchone()
                v = c.execute("SELECT MAX(version) FROM schema_migrations").fetchone()[0]
                stats = {
                    "agents": c.execute("SELECT COUNT(*) FROM agents WHERE kind='agent'").fetchone()[0],
                    "open_sessions": c.execute("SELECT COUNT(*) FROM agent_sessions WHERE disconnected_at IS NULL").fetchone()[0],
                    "pending_handoffs": c.execute("SELECT COUNT(*) FROM handoffs WHERE status='pending'").fetchone()[0],
                    "open_tasks": c.execute("SELECT COUNT(*) FROM tasks WHERE status NOT IN ('done','cancelled')").fetchone()[0],
                }
            checks["database"] = {"ok": v == expected, "schema_version": v, "expected_schema_version": expected}
            stats["expired_leases"] = self.tasks.expired_claims()
        except Exception as exc:                          # health must never raise
            checks["database"] = {"ok": False, "error": type(exc).__name__}
            stats = {}
        root_ok = self.ws.root.is_dir() and self.ws.hive_dir.is_dir() and self.ws.trash_dir.is_dir()
        checks["workspace"] = {"ok": root_ok, "root": str(self.ws.root)}
        ok = all(ch["ok"] for ch in checks.values())
        return {"status": "ok" if ok else "degraded", "checks": checks, "stats": stats, "pid": os.getpid(),
                "uptime_seconds": round(time.time() - self.started_at, 1), "backend_version": __version__,
                "contract_version": CONTRACT_VERSION}
