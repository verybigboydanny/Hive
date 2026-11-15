"""Handoffs: structured transfer of work (and optionally task ownership) between agents.

  * create: records summary / completed / remaining work / modified files / next action, saves a
    linked checkpoint (full context snapshot), RESERVES the task (lease held for handoff_hold_hours
    so nobody grabs it meanwhile) and drops a persistent notification message in the inbox.
  * accept: one atomic transaction -> exactly one agent can accept; ownership of the task moves to
    the acceptor; the sender is notified. Re-accepting your own acceptance is idempotent.
  * History is never deleted (status: pending -> accepted | cancelled).
"""

from __future__ import annotations

import json
from typing import Any

from ..activity import log_in_txn
from ..db import Database
from ..errors import (CONFLICT, HANDOFF_ALREADY_ACCEPTED, INVALID_ARGUMENT, NOT_FOUND, PERMISSION_DENIED,
                      TASK_NOT_OWNED, HiveError)
from ..settings import HiveSettings
from ..util import clean_str_list, clean_text, in_minutes, new_id, now_iso
from .agents import AgentService, resolve_agent_ref
from .checkpoints import save_in_tx, serialize_checkpoint, _SEL as _CP_SEL
from .messages import MessageService
from .tasks import ACTIVE, CLOSED, TaskService

_SEL = ("SELECT h.*, fa.name AS from_name, ta.name AS to_name, ab.name AS accepted_by_name FROM handoffs h"
        " JOIN agents fa ON fa.id = h.from_agent_id LEFT JOIN agents ta ON ta.id = h.to_agent_id"
        " LEFT JOIN agents ab ON ab.id = h.accepted_by ")


def serialize_handoff(row, checkpoint: dict | None = None) -> dict[str, Any]:
    return {"id": row["id"], "status": row["status"], "from_id": row["from_agent_id"], "from_name": row["from_name"],
            "to_id": row["to_agent_id"], "to_name": row["to_name"], "task_id": row["task_id"],
            "checkpoint_id": row["checkpoint_id"], "summary": row["summary"],
            "completed_work": row["completed_work"], "remaining_work": row["remaining_work"],
            "files_modified": json.loads(row["files_modified"]), "next_action": row["next_action"],
            "context": row["context"], "accepted_by": row["accepted_by"], "accepted_by_name": row["accepted_by_name"],
            "created_at": row["created_at"], "accepted_at": row["accepted_at"], "checkpoint": checkpoint}


class HandoffService:
    def __init__(self, db: Database, settings: HiveSettings, agents: AgentService, tasks: TaskService,
                 messages: MessageService) -> None:
        self.db, self.settings, self.agents, self.tasks, self.messages = db, settings, agents, tasks, messages

    def _view(self, c, hid: str) -> dict[str, Any]:
        row = c.execute(_SEL + "WHERE h.id=?", (hid,)).fetchone()
        if row is None:
            raise HiveError(NOT_FOUND, f"handoff not found: {hid}")
        cp = None
        if row["checkpoint_id"]:
            cp = serialize_checkpoint(c.execute(_CP_SEL + "WHERE k.id=?", (row["checkpoint_id"],)).fetchone())
        return serialize_handoff(row, cp)

    def create(self, actor: str, *, summary, to: str | None = None, task_id: str | None = None,
               completed_work=None, remaining_work=None, files_modified=None, next_action=None, context=None,
               state=None) -> dict[str, Any]:
        mx = self.settings.max_text_chars
        summary = clean_text(summary, "summary", max_chars=mx, required=True).strip()
        completed = clean_text(completed_work, "completed_work", max_chars=mx)
        remaining = clean_text(remaining_work, "remaining_work", max_chars=mx)
        next_action = clean_text(next_action, "next_action", max_chars=mx)
        context = clean_text(context, "context", max_chars=mx)
        files = clean_str_list(files_modified, "files_modified", max_items=200, max_len=500)
        with self.db.write() as c:
            to_id = None if to in (None, "all") else resolve_agent_ref(c, to)
            if to_id == actor:
                raise HiveError(INVALID_ARGUMENT, "you cannot hand off to yourself")
            if task_id is not None:
                t = self.tasks._row(c, task_id)
                if not (t["owner_id"] == actor and t["status"] in ACTIVE):
                    raise HiveError(TASK_NOT_OWNED, "you can only hand off a task you own", {"owner_id": t["owner_id"]})
                if c.execute("SELECT 1 FROM handoffs WHERE task_id=? AND status='pending'", (task_id,)).fetchone():
                    raise HiveError(CONFLICT, "this task already has a pending handoff", {"task_id": task_id})
            snapshot = {"completed_work": completed, "remaining_work": remaining, "context": context,
                        "user_state": state or {}}
            cp = save_in_tx(c, self.settings, self.tasks, actor, summary=f"Handoff: {summary}", task_id=task_id,
                            state=snapshot, files_modified=files, next_action=next_action, action="checkpoint.save")
            hid = new_id("hnd")
            c.execute("INSERT INTO handoffs(id,from_agent_id,to_agent_id,task_id,checkpoint_id,summary,completed_work,"
                      "remaining_work,files_modified,next_action,context,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                      (hid, actor, to_id, task_id, cp["id"], summary, completed, remaining, json.dumps(files),
                       next_action, context, now_iso()))
            if task_id:           # keep the task reserved while the handoff waits
                c.execute("UPDATE tasks SET claim_expires_at=?, version=version+1, updated_at=? WHERE id=?",
                          (in_minutes(self.settings.handoff_hold_hours * 60), now_iso(), task_id))
            self.messages.send_in_tx(c, actor, to=to_id, kind="handoff", task_id=task_id,
                                     subject=f"Handoff: {summary[:100]}",
                                     body=f"Handoff {hid}: {summary}\n\nNext action: {next_action or '(not specified)'}\n"
                                          f"Accept it with handoff_accept(handoff_id='{hid}').")
            log_in_txn(c, agent_id=actor, action="handoff.create", summary=f"handoff: {summary[:100]}",
                       target_type="handoff", target_id=hid,
                       details={"to": to_id, "task_id": task_id, "checkpoint_id": cp["id"], "files": len(files)})
            return self._view(c, hid)

    def get(self, hid: str) -> dict[str, Any]:
        with self.db.read() as c:
            return self._view(c, hid)

    def list(self, me: str | None = None, *, status: str | None = None, scope: str = "all",
             task_id: str | None = None, limit: int = 50) -> dict[str, Any]:
        if scope not in ("all", "to_me", "from_me"):
            raise HiveError(INVALID_ARGUMENT, "scope must be all, to_me or from_me")
        if status is not None and status not in ("pending", "accepted", "cancelled"):
            raise HiveError(INVALID_ARGUMENT, "status must be pending, accepted or cancelled")
        if scope != "all" and not me:
            raise HiveError(INVALID_ARGUMENT, "scope needs an agent")
        where, args = [], []
        if status:
            where.append("h.status=?"); args.append(status)
        if task_id:
            where.append("h.task_id=?"); args.append(task_id)
        if scope == "to_me":
            where.append("(h.to_agent_id=? OR h.to_agent_id IS NULL) AND h.from_agent_id<>?"); args += [me, me]
        elif scope == "from_me":
            where.append("h.from_agent_id=?"); args.append(me)
        with self.db.read() as c:
            rows = c.execute(_SEL + (f"WHERE {' AND '.join(where)} " if where else "") +
                             "ORDER BY h.created_at DESC, h.id DESC LIMIT ?", (*args, min(max(limit, 1), 500))).fetchall()
        return {"handoffs": [serialize_handoff(r) for r in rows], "count": len(rows)}

    def pending_for(self, me: str) -> int:
        with self.db.read() as c:
            return c.execute("SELECT COUNT(*) FROM handoffs WHERE status='pending' AND from_agent_id<>?"
                             " AND (to_agent_id=? OR to_agent_id IS NULL)", (me, me)).fetchone()[0]

    def accept(self, actor: str, handoff_id: str) -> dict[str, Any]:
        with self.db.write() as c:
            row = c.execute(_SEL + "WHERE h.id=?", (handoff_id,)).fetchone()
            if row is None:
                raise HiveError(NOT_FOUND, f"handoff not found: {handoff_id}")
            if row["status"] == "accepted":
                if row["accepted_by"] == actor:
                    task = self.tasks._view(c, row["task_id"]) if row["task_id"] else None
                    return {"handoff": self._view(c, handoff_id), "task": task, "task_transfer": "already_accepted",
                            "already_accepted": True}
                raise HiveError(HANDOFF_ALREADY_ACCEPTED, f"already accepted by {row['accepted_by_name']}",
                                {"accepted_by": row["accepted_by"]})
            if row["status"] == "cancelled":
                raise HiveError(CONFLICT, "handoff was cancelled")
            if row["from_agent_id"] == actor:
                raise HiveError(INVALID_ARGUMENT, "you cannot accept your own handoff")
            if row["to_agent_id"] not in (None, actor):
                raise HiveError(PERMISSION_DENIED, "this handoff is addressed to another agent",
                                {"to": row["to_agent_id"]})
            transfer = "no_task"
            if row["task_id"]:
                t = self.tasks._row(c, row["task_id"])
                if t["status"] in CLOSED:
                    transfer = f"skipped: task is {t['status']}"
                elif t["owner_id"] == row["from_agent_id"] and t["status"] in ACTIVE:
                    c.execute("UPDATE tasks SET owner_id=?, status=CASE WHEN status='claimed' THEN 'claimed' ELSE status END,"
                              " claim_expires_at=?, version=version+1, updated_at=? WHERE id=?",
                              (actor, in_minutes(self.settings.lease_minutes), now_iso(), row["task_id"]))
                    log_in_txn(c, agent_id=actor, action="task.transfer", summary=f"took over '{t['title']}' via handoff",
                               target_type="task", target_id=row["task_id"],
                               details={"from": row["from_agent_id"], "handoff_id": handoff_id})
                    transfer = "transferred"
                else:
                    transfer = "skipped: task is no longer owned by the sender"
            cur = c.execute("UPDATE handoffs SET status='accepted', accepted_by=?, accepted_at=? WHERE id=? AND status='pending'",
                            (actor, now_iso(), handoff_id))
            if cur.rowcount != 1:
                raise HiveError(CONFLICT, "handoff changed during accept; retry")
            log_in_txn(c, agent_id=actor, action="handoff.accept", summary=f"accepted handoff {handoff_id}",
                       target_type="handoff", target_id=handoff_id, details={"from": row["from_agent_id"], "task_transfer": transfer})
            self.messages.send_in_tx(c, actor, to=row["from_agent_id"], kind="notice", task_id=row["task_id"],
                                     subject=f"Handoff {handoff_id} accepted", body=f"Your handoff '{row['summary'][:100]}' was accepted.")
            task = self.tasks._view(c, row["task_id"]) if row["task_id"] else None
            return {"handoff": self._view(c, handoff_id), "task": task, "task_transfer": transfer, "already_accepted": False}

    def cancel(self, actor: str, handoff_id: str) -> dict[str, Any]:
        with self.db.write() as c:
            row = c.execute(_SEL + "WHERE h.id=?", (handoff_id,)).fetchone()
            if row is None:
                raise HiveError(NOT_FOUND, f"handoff not found: {handoff_id}")
            if row["from_agent_id"] != actor and not self.agents.is_human(c, actor):
                raise HiveError(PERMISSION_DENIED, "only the sender or the user can cancel a handoff")
            if row["status"] != "pending":
                raise HiveError(CONFLICT, f"handoff is already {row['status']}")
            c.execute("UPDATE handoffs SET status='cancelled' WHERE id=?", (handoff_id,))
            if row["task_id"]:      # release the long reservation back to a normal lease
                c.execute("UPDATE tasks SET claim_expires_at=?, updated_at=? WHERE id=? AND owner_id=?",
                          (in_minutes(self.settings.lease_minutes), now_iso(), row["task_id"], row["from_agent_id"]))
            log_in_txn(c, agent_id=actor, action="handoff.cancel", summary=f"cancelled handoff {handoff_id}",
                       target_type="handoff", target_id=handoff_id)
            return self._view(c, handoff_id)
