"""Project-level read models: status, per-agent context, enriched activity feed."""

from __future__ import annotations

from typing import Any

from ..activity import ActivityService, log_in_txn
from ..db import Database
from ..errors import NOT_INITIALIZED, HiveError
from ..git import git_summary
from ..settings import HiveSettings
from .agents import AgentService, resolve_agent_ref
from .checkpoints import CheckpointService
from .handoffs import HandoffService
from .memory import MemoryService
from .messages import MessageService
from ..util import new_project_id
from .tasks import ACTIVE, ALL_STATUSES, TaskService

PROTOCOL_RULES = """\
# Hive working rules (built in)
1. Register once with `agent_register`; keep the returned `agent_id` and `resume_token` to reconnect.
2. Start every session with `agent_get_context`: it shows your tasks, unread messages and pending handoffs.
3. Claim a task (`task_claim`) before working on it; renew by updating progress or saving checkpoints.
4. Read a file before changing it and pass its `sha256` as `expected_sha256` to `write_file`;
   on CONFLICT re-read and merge, never overwrite blindly. Use `create_file` for new files.
5. Deleting is explicit (`confirm=true` + reason) and recoverable with `restore_file`.
6. Save a checkpoint (`save_checkpoint`) at meaningful milestones so another agent can resume.
7. Hand work over with `handoff_create` (completed/remaining work, files, next action).
8. Record lasting knowledge with `memory_update` and architectural choices with `record_decision`.
9. Hive cannot wake other agents: check `message_inbox` regularly and acknowledge with `message_mark_read`.
10. Every tool result carries `notices` (unread messages, pending handoffs); act on them.
"""


class ProjectService:
    def __init__(self, db: Database, settings: HiveSettings, root, activity: ActivityService, agents: AgentService,
                 tasks: TaskService, messages: MessageService, handoffs: HandoffService,
                 memory: MemoryService, checkpoints: CheckpointService) -> None:
        self.db, self.settings, self.root, self.activity = db, settings, root, activity
        self.agents, self.tasks, self.messages = agents, tasks, messages
        self.handoffs, self.memory, self.checkpoints = handoffs, memory, checkpoints

    # ------------------------------------------------------------------ identity
    def ensure_uid(self) -> str:
        """Return the project's stable id, creating it on first open (also upgrades pre-003 workspaces).
        Atomic across processes: only one concurrent opener can win the UPDATE."""
        with self.db.write() as c:
            row = c.execute("SELECT uid FROM project WHERE id=1").fetchone()
            if row is None:
                raise HiveError(NOT_INITIALIZED, "workspace has no project row", hint="Run `hive init` first.")
            if row["uid"]:
                return row["uid"]
            uid = new_project_id()
            c.execute("UPDATE project SET uid=? WHERE id=1 AND uid IS NULL", (uid,))
            uid = c.execute("SELECT uid FROM project WHERE id=1").fetchone()["uid"]
            log_in_txn(c, agent_id=None, action="project.identified", summary=f"project id assigned: {uid}",
                       target_type="project", target_id=uid, details={})
            return uid

    def reassign_uid(self, reason: str) -> str:
        """Give this workspace a NEW id (used when a folder was copied: the copy is a different project)."""
        with self.db.write() as c:
            old = c.execute("SELECT uid FROM project WHERE id=1").fetchone()["uid"]
            uid = new_project_id()
            c.execute("UPDATE project SET uid=? WHERE id=1", (uid,))
            log_in_txn(c, agent_id=None, action="project.identified", summary=f"project id reassigned ({reason})",
                       target_type="project", target_id=uid, details={"previous_id": old, "reason": reason})
            return uid

    def info(self) -> dict[str, Any]:
        from .. import CONTRACT_VERSION, __version__
        with self.db.read() as c:
            p = c.execute("SELECT name, created_at, uid FROM project WHERE id=1").fetchone()
            schema = c.execute("SELECT MAX(version) FROM schema_migrations").fetchone()[0]
        return {"id": p["uid"], "name": p["name"], "created_at": p["created_at"], "root": str(self.root),
                "schema_version": schema, "backend_version": __version__, "contract_version": CONTRACT_VERSION}

    def activity_feed(self, *, after_id: int | None = None, limit: int = 50, agent_ref: str | None = None,
                      action_prefix: str | None = None) -> dict[str, Any]:
        if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 500:
            from ..errors import HiveError, INVALID_ARGUMENT
            raise HiveError(INVALID_ARGUMENT, "limit must be between 1 and 500")
        agent_id = None
        if agent_ref:
            with self.db.read() as c:
                agent_id = resolve_agent_ref(c, agent_ref)
        res = self.activity.query(after_id=after_id, limit=limit, agent_id=agent_id, action_prefix=action_prefix)
        ids = sorted({e["agent_id"] for e in res["entries"] if e["agent_id"]})
        actors: dict[str, dict] = {}
        if ids:
            with self.db.read() as c:
                for r in c.execute(f"SELECT id, name, kind, client FROM agents WHERE id IN ({','.join('?' * len(ids))})", ids):
                    actors[r["id"]] = {"id": r["id"], "name": r["name"], "kind": r["kind"], "client": r["client"]}
        for e in res["entries"]:
            e["actor"] = actors.get(e["agent_id"]) or {"id": e["agent_id"], "name": "system", "kind": "system", "client": None}
        return res

    def status(self) -> dict[str, Any]:
        with self.db.read() as c:
            counts = {s: 0 for s in ALL_STATUSES}
            for r in c.execute("SELECT status, COUNT(*) n FROM tasks GROUP BY status"):
                counts[r["status"]] = r["n"]
            msgs = c.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
            mem = c.execute("SELECT COUNT(*) FROM memory_entries").fetchone()[0]
            dec = c.execute("SELECT COUNT(*) FROM decisions WHERE status='active'").fetchone()[0]
            pending = c.execute("SELECT COUNT(*) FROM handoffs WHERE status='pending'").fetchone()[0]
        return {"project": self.info(),
                "tasks": {"counts": counts, "expired_leases": self.tasks.expired_claims()},
                "agents": self.agents.list(),
                "handoffs": {"pending": pending}, "messages": {"total": msgs},
                "memory": {"entries": mem, "active_decisions": dec},
                "git": git_summary(self.root),
                "recent_activity": self.activity_feed(limit=10)["entries"]}

    def rules(self) -> dict[str, Any]:
        entries = self.memory.read(category="rules", limit=200)["entries"]
        return {"protocol": PROTOCOL_RULES, "project_rules": entries}

    def context(self, agent_id: str | None = None, *, activity_limit: int = 15) -> dict[str, Any]:
        ctx: dict[str, Any] = {
            "project": self.info(), "rules": self.rules(),
            "decisions": self.memory.list_decisions(status="active", limit=10)["decisions"],
            "memory": self.memory.read(limit=15)["entries"],
            "agents": self.agents.list(include_offline=False),
            "recent_activity": self.activity_feed(limit=activity_limit)["entries"],
        }
        if agent_id:
            ctx["agent"] = self.agents.get(agent_id)
            ctx["my_tasks"] = self.tasks.list(agent_id, owner="me")["tasks"]
            ctx["claimable_tasks"] = self.tasks.list(agent_id, claimable_only=True, limit=5)["tasks"]
            inbox = self.messages.inbox(agent_id, limit=5)
            ctx["inbox"] = {"unread_total": inbox["unread_total"], "preview": inbox["messages"]}
            ctx["pending_handoffs"] = self.handoffs.list(agent_id, status="pending", scope="to_me")["handoffs"]
            last = self.checkpoints.list(agent_id=agent_id, limit=1)
            ctx["last_checkpoint"] = last[0] if last else None
        return ctx
