"""Tasks: creation, dependency graph, atomic claims with leases, progress, completion, cancellation.

Ownership model
  * A claim is a LEASE (default 30 min). The owner renews it by updating the task, saving a
    checkpoint, or claiming again. Every state change happens inside BEGIN IMMEDIATE, so two
    agents (threads or processes) can never both win a claim.
  * An expired lease does not evict the owner by itself: the owner may still update/complete
    until ANOTHER agent reclaims the task (recoverable after a disconnect, never a silent steal
    while the owner is alive and renewing).
  * The human (kind='human') may edit/cancel/release any task.
"""

from __future__ import annotations

import json
from typing import Any

from ..activity import log_in_txn
from ..db import Database
from ..errors import (DEPENDENCY_CYCLE, DEPENDENCY_UNMET, INVALID_ARGUMENT, NOT_FOUND, TASK_ALREADY_CLAIMED,
                      TASK_CLOSED, TASK_LIMIT_REACHED, TASK_NOT_OWNED, CONFLICT, HiveError)
from ..settings import HiveSettings
from ..util import clean_str_list, clean_text, in_minutes, new_id, now_iso
from .agents import AgentService, resolve_agent_ref

ACTIVE = ("claimed", "in_progress", "blocked", "review")
CLOSED = ("done", "cancelled")
ALL_STATUSES = ("open",) + ACTIVE + CLOSED
PRIORITIES = {"low": 0, "normal": 1, "high": 2, "urgent": 3}
PRIORITY_NAMES = {v: k for k, v in PRIORITIES.items()}
UPDATABLE_STATUSES = ("in_progress", "blocked", "review", "open")


class TaskService:
    def __init__(self, db: Database, settings: HiveSettings, agents: AgentService) -> None:
        self.db, self.settings, self.agents = db, settings, agents

    # ------------------------------------------------------------- serialization
    def _row(self, c, task_id: str):
        row = c.execute("SELECT t.*, a.name AS owner_name FROM tasks t LEFT JOIN agents a ON a.id=t.owner_id"
                        " WHERE t.id=?", (task_id,)).fetchone()
        if row is None:
            raise HiveError(NOT_FOUND, f"task not found: {task_id}", {"task_id": task_id})
        return row

    def _serialize(self, c, row) -> dict[str, Any]:
        deps = c.execute("SELECT d.depends_on_id AS id, t.status AS status FROM task_dependencies d"
                         " JOIN tasks t ON t.id = d.depends_on_id WHERE d.task_id=? ORDER BY d.depends_on_id",
                         (row["id"],)).fetchall()
        blocked_by = [{"id": d["id"], "status": d["status"]} for d in deps if d["status"] != "done"]
        expired = (row["status"] in ACTIVE and row["claim_expires_at"] is not None
                   and row["claim_expires_at"] <= now_iso())
        return {
            "id": row["id"], "title": row["title"], "description": row["description"], "status": row["status"],
            "priority": PRIORITY_NAMES[row["priority"]], "labels": json.loads(row["labels"]),
            "parent_id": row["parent_id"], "created_by": row["created_by"], "owner_id": row["owner_id"],
            "owner_name": row["owner_name"], "claim_expires_at": row["claim_expires_at"],
            "lease_expired": expired, "version": row["version"], "progress_note": row["progress_note"],
            "result_summary": row["result_summary"], "cancel_reason": row["cancel_reason"],
            "depends_on": [d["id"] for d in deps], "blocked_by": blocked_by,
            "claimable": not blocked_by and (row["status"] == "open" or expired),
            "created_at": row["created_at"], "updated_at": row["updated_at"], "completed_at": row["completed_at"],
        }

    def _view(self, c, task_id: str) -> dict[str, Any]:
        return self._serialize(c, self._row(c, task_id))

    # ------------------------------------------------------------------- create
    def create(self, actor: str, *, title: str, description: str | None = None, priority: str = "normal",
               labels=None, depends_on=None, parent_id: str | None = None) -> dict[str, Any]:
        title = clean_text(title, "title", max_chars=200, required=True).strip()
        description = clean_text(description, "description", max_chars=self.settings.max_text_chars) or ""
        if priority not in PRIORITIES:
            raise HiveError(INVALID_ARGUMENT, f"priority must be one of {', '.join(PRIORITIES)}")
        labels = clean_str_list(labels, "labels", max_items=20, max_len=40)
        depends_on = clean_str_list(depends_on, "depends_on", max_items=50, max_len=40)
        tid, now = new_id("tsk"), now_iso()
        with self.db.write() as c:
            if parent_id is not None:
                self._row(c, parent_id)
            for dep in depends_on:
                self._row(c, dep)
            c.execute("INSERT INTO tasks(id,title,description,status,priority,labels,parent_id,created_by,"
                      "created_at,updated_at) VALUES(?,?,?,'open',?,?,?,?,?,?)",
                      (tid, title, description, PRIORITIES[priority], json.dumps(labels), parent_id, actor, now, now))
            for dep in depends_on:
                c.execute("INSERT INTO task_dependencies(task_id,depends_on_id) VALUES(?,?)", (tid, dep))
            log_in_txn(c, agent_id=actor, action="task.create", summary=f"created task '{title}'",
                       target_type="task", target_id=tid, details={"priority": priority, "depends_on": depends_on})
            return self._view(c, tid)

    # --------------------------------------------------------------------- read
    def get(self, task_id: str) -> dict[str, Any]:
        with self.db.read() as c:
            return self._view(c, task_id)

    def list(self, me: str | None = None, *, task_id: str | None = None, status=None, owner: str | None = None,
             label: str | None = None, claimable_only: bool = False, include_closed: bool = False,
             limit: int = 50) -> dict[str, Any]:
        if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 500:
            raise HiveError(INVALID_ARGUMENT, "limit must be between 1 and 500")
        statuses = clean_str_list(status, "status", max_items=7, max_len=20)
        for s in statuses:
            if s not in ALL_STATUSES:
                raise HiveError(INVALID_ARGUMENT, f"unknown status '{s}'")
        where, args = [], []
        with self.db.read() as c:
            if task_id:
                where.append("t.id=?"); args.append(task_id)
            if statuses:
                where.append(f"t.status IN ({','.join('?' * len(statuses))})"); args.extend(statuses)
            elif not include_closed and not task_id:
                where.append("t.status NOT IN ('done','cancelled')")
            if owner:
                if owner == "unassigned":
                    where.append("t.owner_id IS NULL")
                else:
                    oid = me if owner == "me" and me else resolve_agent_ref(c, owner)
                    where.append("t.owner_id=?"); args.append(oid)
            sql = ("SELECT t.*, a.name AS owner_name FROM tasks t LEFT JOIN agents a ON a.id=t.owner_id"
                   + (" WHERE " + " AND ".join(where) if where else "")
                   + " ORDER BY t.priority DESC, t.created_at ASC, t.id ASC")
            tasks = [self._serialize(c, r) for r in c.execute(sql, args)]
        if label:
            tasks = [t for t in tasks if label in t["labels"]]
        if claimable_only:
            tasks = [t for t in tasks if t["claimable"]]
        return {"tasks": tasks[:limit], "count": min(len(tasks), limit), "total_matching": len(tasks)}

    # -------------------------------------------------------------------- claim
    def claim(self, actor: str, task_id: str, lease_minutes: int | None = None) -> dict[str, Any]:
        with self.db.write() as c:
            return self.claim_in_tx(c, actor, task_id, lease_minutes)

    def claim_in_tx(self, c, actor: str, task_id: str, lease_minutes: int | None = None) -> dict[str, Any]:
        lease = self._lease(lease_minutes)
        row = self._row(c, task_id)
        now = now_iso()
        if row["status"] in CLOSED:
            raise HiveError(TASK_CLOSED, f"task is {row['status']}", {"task_id": task_id})
        unmet = [d["id"] for d in self._serialize(c, row)["blocked_by"]]
        if unmet:
            raise HiveError(DEPENDENCY_UNMET, "task has unfinished dependencies", {"blocked_by": unmet})
        reclaimed_from = None
        if row["owner_id"] == actor and row["status"] in ACTIVE:
            c.execute("UPDATE tasks SET claim_expires_at=?, updated_at=?, version=version+1 WHERE id=?",
                      (in_minutes(lease), now, task_id))
            log_in_txn(c, agent_id=actor, action="task.renew", summary=f"renewed lease on '{row['title']}'",
                       target_type="task", target_id=task_id, details={"lease_minutes": lease})
            return {"task": self._view(c, task_id), "reclaimed_from": None, "renewed": True}
        if row["status"] != "open":
            if row["claim_expires_at"] is not None and row["claim_expires_at"] <= now:
                reclaimed_from = row["owner_id"]
            else:
                raise HiveError(TASK_ALREADY_CLAIMED, f"task is claimed by {row['owner_name'] or row['owner_id']}",
                                {"owner_id": row["owner_id"], "claim_expires_at": row["claim_expires_at"]},
                                hint="Pick another task, message the owner, or wait for the lease to expire.")
        active = c.execute("SELECT COUNT(*) FROM tasks WHERE owner_id=? AND status IN "
                           "('claimed','in_progress','blocked','review') AND claim_expires_at > ?",
                           (actor, now)).fetchone()[0]
        if active >= self.settings.max_active_tasks_per_agent:
            raise HiveError(TASK_LIMIT_REACHED, f"you already hold {active} active tasks "
                            f"(limit {self.settings.max_active_tasks_per_agent})",
                            hint="Complete or release a task first.")
        cur = c.execute("UPDATE tasks SET status='claimed', owner_id=?, claim_expires_at=?, version=version+1,"
                        " updated_at=? WHERE id=? AND version=?", (actor, in_minutes(lease), now, task_id, row["version"]))
        if cur.rowcount != 1:                      # cannot happen under BEGIN IMMEDIATE; defence in depth
            raise HiveError(CONFLICT, "task changed during claim; retry")
        log_in_txn(c, agent_id=actor, action="task.reclaim" if reclaimed_from else "task.claim",
                   summary=f"claimed '{row['title']}'" + (" (expired lease)" if reclaimed_from else ""),
                   target_type="task", target_id=task_id,
                   details={"lease_minutes": lease, "reclaimed_from": reclaimed_from})
        return {"task": self._view(c, task_id), "reclaimed_from": reclaimed_from, "renewed": False}

    def _lease(self, minutes) -> int:
        if minutes is None:
            return self.settings.lease_minutes
        if not isinstance(minutes, int) or isinstance(minutes, bool) or not 1 <= minutes <= self.settings.max_lease_minutes:
            raise HiveError(INVALID_ARGUMENT, f"lease_minutes must be between 1 and {self.settings.max_lease_minutes}")
        return minutes

    # ------------------------------------------------------------------- update
    def update(self, actor: str, task_id: str, *, status: str | None = None, progress_note: str | None = None,
               title: str | None = None, description: str | None = None, priority: str | None = None,
               labels=None, expected_version: int | None = None, add_depends_on=None,
               remove_depends_on=None, extend_lease_minutes: int | None = None) -> dict[str, Any]:
        progress_note = clean_text(progress_note, "progress_note", max_chars=self.settings.max_text_chars)
        if title is not None:
            title = clean_text(title, "title", max_chars=200, required=True).strip()
        if description is not None:
            description = clean_text(description, "description", max_chars=self.settings.max_text_chars,
                                     allow_empty=True) or ""
        if priority is not None and priority not in PRIORITIES:
            raise HiveError(INVALID_ARGUMENT, f"priority must be one of {', '.join(PRIORITIES)}")
        if status is not None and status not in UPDATABLE_STATUSES:
            hint = {"done": "use task_complete", "cancelled": "use task_cancel", "claimed": "use task_claim"}.get(status)
            raise HiveError(INVALID_ARGUMENT, f"status must be one of {', '.join(UPDATABLE_STATUSES)}", hint=hint)
        new_labels = clean_str_list(labels, "labels", max_items=20, max_len=40) if labels is not None else None
        add_deps = clean_str_list(add_depends_on, "add_depends_on", max_items=50, max_len=40)
        rem_deps = clean_str_list(remove_depends_on, "remove_depends_on", max_items=50, max_len=40)
        lease = self._lease(extend_lease_minutes)
        with self.db.write() as c:
            row = self._row(c, task_id)
            if row["status"] in CLOSED:
                raise HiveError(TASK_CLOSED, f"task is {row['status']}", {"task_id": task_id})
            if expected_version is not None and expected_version != row["version"]:
                raise HiveError(CONFLICT, "task was modified since you read it",
                                {"current_version": row["version"], "expected_version": expected_version})
            human = self.agents.is_human(c, actor)
            is_owner = row["owner_id"] == actor and row["status"] in ACTIVE
            active = row["status"] in ACTIVE
            meta_change = any(v is not None for v in (title, description, priority, new_labels)) or add_deps or rem_deps
            state_change = status is not None or progress_note is not None
            if state_change and not (is_owner or human):
                raise HiveError(TASK_NOT_OWNED, "only the task owner can change status or progress",
                                {"owner_id": row["owner_id"]},
                                hint="Claim the task first with task_claim." if row["status"] == "open" else
                                "Message the owner or wait for the lease to expire.")
            if meta_change and active and not (is_owner or human or row["created_by"] == actor):
                raise HiveError(TASK_NOT_OWNED, "this task is owned by another agent", {"owner_id": row["owner_id"]})
            sets, args, changed = ["updated_at=?", "version=version+1"], [now_iso()], []
            if title is not None:
                sets.append("title=?"); args.append(title); changed.append("title")
            if description is not None:
                sets.append("description=?"); args.append(description); changed.append("description")
            if priority is not None:
                sets.append("priority=?"); args.append(PRIORITIES[priority]); changed.append("priority")
            if new_labels is not None:
                sets.append("labels=?"); args.append(json.dumps(new_labels)); changed.append("labels")
            if progress_note is not None:
                sets.append("progress_note=?"); args.append(progress_note); changed.append("progress_note")
            if status is not None and status != row["status"]:
                if status == "open":
                    sets += ["status='open'", "owner_id=NULL", "claim_expires_at=NULL"]
                elif not active:
                    raise HiveError(TASK_NOT_OWNED, "claim the task before changing its status", hint="Use task_claim.")
                else:
                    sets.append("status=?"); args.append(status)
                changed.append(f"status:{status}")
            if active and (is_owner or human) and status != "open" and state_change:
                sets.append("claim_expires_at=?"); args.append(in_minutes(lease))      # activity renews the lease
            for dep in add_deps:
                self._add_dependency(c, task_id, dep)
            for dep in rem_deps:
                c.execute("DELETE FROM task_dependencies WHERE task_id=? AND depends_on_id=?", (task_id, dep))
            if add_deps or rem_deps:
                changed.append("dependencies")
            if not changed:
                return self._view(c, task_id)
            c.execute(f"UPDATE tasks SET {', '.join(sets)} WHERE id=?", (*args, task_id))
            note = f": {progress_note[:120]}" if progress_note else ""
            log_in_txn(c, agent_id=actor, action="task.release" if status == "open" and row["status"] != "open"
                       else "task.update", summary=f"updated '{row['title']}' ({', '.join(changed)}){note}",
                       target_type="task", target_id=task_id, details={"changed": changed})
            return self._view(c, task_id)

    def _add_dependency(self, c, task_id: str, dep_id: str) -> None:
        if dep_id == task_id:
            raise HiveError(DEPENDENCY_CYCLE, "a task cannot depend on itself")
        self._row(c, dep_id)
        seen, stack = set(), [dep_id]                    # would dep_id (transitively) depend on task_id?
        while stack:
            cur = stack.pop()
            if cur == task_id:
                raise HiveError(DEPENDENCY_CYCLE, "dependency would create a cycle",
                                {"task_id": task_id, "depends_on": dep_id})
            if cur in seen:
                continue
            seen.add(cur)
            stack.extend(r[0] for r in c.execute("SELECT depends_on_id FROM task_dependencies WHERE task_id=?", (cur,)))
        c.execute("INSERT OR IGNORE INTO task_dependencies(task_id,depends_on_id) VALUES(?,?)", (task_id, dep_id))

    # ------------------------------------------------------------ complete/cancel
    def complete(self, actor: str, task_id: str, summary: str, expected_version: int | None = None) -> dict[str, Any]:
        summary = clean_text(summary, "summary", max_chars=self.settings.max_text_chars, required=True).strip()
        with self.db.write() as c:
            row = self._row(c, task_id)
            if row["status"] == "done":
                if row["owner_id"] == actor:
                    return {"task": self._view(c, task_id), "already_completed": True, "unblocked_tasks": []}
                raise HiveError(TASK_CLOSED, "task is already done", {"task_id": task_id})
            if row["status"] == "cancelled":
                raise HiveError(TASK_CLOSED, "task was cancelled", {"task_id": task_id})
            human = self.agents.is_human(c, actor)
            if not ((row["owner_id"] == actor and row["status"] in ACTIVE) or human):
                raise HiveError(TASK_NOT_OWNED, "only the task owner can complete it", {"owner_id": row["owner_id"]},
                                hint="Claim the task first with task_claim." if row["status"] == "open" else None)
            if expected_version is not None and expected_version != row["version"]:
                raise HiveError(CONFLICT, "task was modified since you read it", {"current_version": row["version"]})
            owner = row["owner_id"] or actor
            c.execute("UPDATE tasks SET status='done', owner_id=?, result_summary=?, completed_at=?, updated_at=?,"
                      " claim_expires_at=NULL, version=version+1 WHERE id=?",
                      (owner, summary, now_iso(), now_iso(), task_id))
            unblocked = [r[0] for r in c.execute(
                "SELECT t.id FROM tasks t JOIN task_dependencies d ON d.task_id=t.id WHERE d.depends_on_id=?"
                " AND t.status='open' AND NOT EXISTS (SELECT 1 FROM task_dependencies d2 JOIN tasks t2 ON"
                " t2.id=d2.depends_on_id WHERE d2.task_id=t.id AND t2.status<>'done') ORDER BY t.id", (task_id,))]
            log_in_txn(c, agent_id=actor, action="task.complete", summary=f"completed '{row['title']}': {summary[:120]}",
                       target_type="task", target_id=task_id, details={"unblocked": unblocked})
            return {"task": self._view(c, task_id), "already_completed": False, "unblocked_tasks": unblocked}

    def cancel(self, actor: str, task_id: str, reason: str) -> dict[str, Any]:
        reason = clean_text(reason, "reason", max_chars=500, required=True).strip()
        with self.db.write() as c:
            row = self._row(c, task_id)
            if row["status"] == "cancelled":
                return {"task": self._view(c, task_id), "already_cancelled": True}
            if row["status"] == "done":
                raise HiveError(TASK_CLOSED, "task is already done", {"task_id": task_id})
            human = self.agents.is_human(c, actor)
            if not (human or row["created_by"] == actor or (row["owner_id"] == actor and row["status"] in ACTIVE)):
                raise HiveError(TASK_NOT_OWNED, "only the owner, the creator or the user can cancel a task",
                                {"owner_id": row["owner_id"], "created_by": row["created_by"]})
            c.execute("UPDATE tasks SET status='cancelled', cancel_reason=?, claim_expires_at=NULL, updated_at=?,"
                      " version=version+1 WHERE id=?", (reason, now_iso(), task_id))
            log_in_txn(c, agent_id=actor, action="task.cancel", summary=f"cancelled '{row['title']}': {reason[:120]}",
                       target_type="task", target_id=task_id, details={"reason": reason})
            return {"task": self._view(c, task_id), "already_cancelled": False}

    # ------------------------------------------------------------------- health
    def expired_claims(self) -> int:
        with self.db.read() as c:
            return c.execute("SELECT COUNT(*) FROM tasks WHERE status IN ('claimed','in_progress','blocked','review')"
                             " AND claim_expires_at <= ?", (now_iso(),)).fetchone()[0]
