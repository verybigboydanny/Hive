"""Checkpoints: durable, resumable snapshots of an agent's progress on a task.

  * save: summary + free-form JSON state + modified files + next action. If tied to a task the
    caller must own it; saving renews the lease (a checkpointing agent is alive).
  * restore: returns the checkpoint (and task). With claim_task=true it also claims the task for
    the caller when it is free or its lease expired, so a different agent can resume the work.
"""

from __future__ import annotations

import json
from typing import Any

from ..activity import log_in_txn
from ..db import Database
from ..errors import INVALID_ARGUMENT, NOT_FOUND, TASK_NOT_OWNED, HiveError
from ..settings import HiveSettings
from ..util import clean_str_list, clean_text, in_minutes, new_id, now_iso
from .tasks import ACTIVE, TaskService

MAX_STATE_BYTES = 64 * 1024


def serialize_checkpoint(row) -> dict[str, Any]:
    return {"id": row["id"], "agent_id": row["agent_id"], "agent_name": row["agent_name"], "task_id": row["task_id"],
            "summary": row["summary"], "state": json.loads(row["state"]),
            "files_modified": json.loads(row["files_modified"]), "next_action": row["next_action"],
            "created_at": row["created_at"]}


_SEL = "SELECT k.*, a.name AS agent_name FROM checkpoints k JOIN agents a ON a.id = k.agent_id "


def save_in_tx(c, settings: HiveSettings, tasks: TaskService, actor: str, *, summary, task_id=None, state=None,
               files_modified=None, next_action=None, action: str = "checkpoint.save") -> dict[str, Any]:
    summary = clean_text(summary, "summary", max_chars=settings.max_text_chars, required=True).strip()
    next_action = clean_text(next_action, "next_action", max_chars=settings.max_text_chars)
    files = clean_str_list(files_modified, "files_modified", max_items=200, max_len=500)
    if state is None:
        state = {}
    if not isinstance(state, dict):
        raise HiveError(INVALID_ARGUMENT, "state must be a JSON object")
    try:
        blob = json.dumps(state, ensure_ascii=False)
    except (TypeError, ValueError):
        raise HiveError(INVALID_ARGUMENT, "state must be JSON-serialisable") from None
    if len(blob.encode()) > MAX_STATE_BYTES:
        raise HiveError(INVALID_ARGUMENT, f"state exceeds {MAX_STATE_BYTES} bytes")
    if task_id is not None:
        t = tasks._row(c, task_id)
        human = tasks.agents.is_human(c, actor)
        if not (human or (t["owner_id"] == actor and t["status"] in ACTIVE)):
            raise HiveError(TASK_NOT_OWNED, "you can only checkpoint a task you own",
                            {"owner_id": t["owner_id"]}, hint="Claim the task first with task_claim.")
        if t["owner_id"] == actor:       # a checkpointing owner is alive: never shorten, always renew
            c.execute("UPDATE tasks SET claim_expires_at=MAX(COALESCE(claim_expires_at,''), ?) WHERE id=?",
                      (in_minutes(settings.lease_minutes), task_id))
    cid = new_id("ckp")
    c.execute("INSERT INTO checkpoints(id,agent_id,task_id,summary,state,files_modified,next_action,created_at)"
              " VALUES(?,?,?,?,?,?,?,?)", (cid, actor, task_id, summary, blob, json.dumps(files), next_action, now_iso()))
    log_in_txn(c, agent_id=actor, action=action, summary=f"checkpoint: {summary[:100]}",
               target_type="checkpoint", target_id=cid, details={"task_id": task_id, "files": len(files)})
    return serialize_checkpoint(c.execute(_SEL + "WHERE k.id=?", (cid,)).fetchone())


class CheckpointService:
    def __init__(self, db: Database, settings: HiveSettings, tasks: TaskService) -> None:
        self.db, self.settings, self.tasks = db, settings, tasks

    def save(self, actor: str, *, summary, task_id=None, state=None, files_modified=None, next_action=None):
        with self.db.write() as c:
            return save_in_tx(c, self.settings, self.tasks, actor, summary=summary, task_id=task_id, state=state,
                              files_modified=files_modified, next_action=next_action)

    def get(self, checkpoint_id: str) -> dict[str, Any]:
        with self.db.read() as c:
            row = c.execute(_SEL + "WHERE k.id=?", (checkpoint_id,)).fetchone()
        if row is None:
            raise HiveError(NOT_FOUND, f"checkpoint not found: {checkpoint_id}")
        return serialize_checkpoint(row)

    def list(self, *, task_id: str | None = None, agent_id: str | None = None, limit: int = 20) -> list[dict]:
        where, args = [], []
        if task_id:
            where.append("k.task_id=?"); args.append(task_id)
        if agent_id:
            where.append("k.agent_id=?"); args.append(agent_id)
        with self.db.read() as c:
            rows = c.execute(_SEL + (f"WHERE {' AND '.join(where)} " if where else "")
                             + "ORDER BY k.created_at DESC, k.id DESC LIMIT ?", (*args, min(max(limit, 1), 200))).fetchall()
        return [serialize_checkpoint(r) for r in rows]

    def restore(self, actor: str, *, checkpoint_id: str | None = None, task_id: str | None = None,
                claim_task: bool = True) -> dict[str, Any]:
        with self.db.write() as c:
            if checkpoint_id:
                row = c.execute(_SEL + "WHERE k.id=?", (checkpoint_id,)).fetchone()
            elif task_id:
                row = c.execute(_SEL + "WHERE k.task_id=? ORDER BY k.created_at DESC, k.id DESC LIMIT 1", (task_id,)).fetchone()
            else:
                row = c.execute(_SEL + "WHERE k.agent_id=? ORDER BY k.created_at DESC, k.id DESC LIMIT 1", (actor,)).fetchone()
            if row is None:
                raise HiveError(NOT_FOUND, "no matching checkpoint", {"checkpoint_id": checkpoint_id, "task_id": task_id})
            cp = serialize_checkpoint(row)
            task, claim = None, {"attempted": False, "claimed": False, "error": None}
            if cp["task_id"]:
                if claim_task:
                    claim["attempted"] = True
                    try:
                        res = self.tasks.claim_in_tx(c, actor, cp["task_id"])
                        claim.update(claimed=True, reclaimed_from=res["reclaimed_from"], renewed=res["renewed"])
                    except HiveError as e:      # raised before any write; the restore itself still succeeds
                        claim["error"] = e.to_dict()
                task = self.tasks._view(c, cp["task_id"])
            log_in_txn(c, agent_id=actor, action="checkpoint.restore", summary=f"restored checkpoint {cp['id']}",
                       target_type="checkpoint", target_id=cp["id"],
                       details={"task_id": cp["task_id"], "claimed": claim["claimed"], "saved_by": cp["agent_id"]})
            return {"checkpoint": cp, "task": task, "claim": claim}
