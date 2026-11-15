"""Shared output-schema fragments (shape of `data` in the success envelope)."""

from __future__ import annotations

from .schema import B, I, NI, NOBJ, NS, OBJ, S, arr, obj_out

AGENT = obj_out({"id": S, "name": S, "kind": S, "client": S, "model": NS, "role": NS, "capabilities": arr(S),
                 "status": S, "status_message": NS, "presence": S, "registered_at": S, "last_seen_at": S})
TASK = obj_out({"id": S, "title": S, "description": S, "status": S, "priority": S, "labels": arr(S), "parent_id": NS,
                "created_by": S, "owner_id": NS, "owner_name": NS, "claim_expires_at": NS, "lease_expired": B,
                "version": I, "progress_note": NS, "result_summary": NS, "cancel_reason": NS, "depends_on": arr(S),
                "blocked_by": arr(obj_out({"id": S, "status": S})), "claimable": B, "created_at": S,
                "updated_at": S, "completed_at": NS})
MESSAGE = obj_out({"id": S, "seq": I, "thread_id": S, "kind": S, "from_id": S, "from_name": S, "from_kind": S,
                   "to_id": NS, "to_name": NS, "subject": NS, "body": S, "task_id": NS, "created_at": S,
                   "read": B, "read_at": NS})
CHECKPOINT = obj_out({"id": S, "agent_id": S, "agent_name": S, "task_id": NS, "summary": S, "state": OBJ,
                      "files_modified": arr(S), "next_action": NS, "created_at": S})
HANDOFF = obj_out({"id": S, "status": S, "from_id": S, "from_name": S, "to_id": NS, "to_name": NS, "task_id": NS,
                   "checkpoint_id": NS, "summary": S, "completed_work": NS, "remaining_work": NS,
                   "files_modified": arr(S), "next_action": NS, "context": NS, "accepted_by": NS,
                   "accepted_by_name": NS, "created_at": S, "accepted_at": NS, "checkpoint": NOBJ})
MEMORY = obj_out({"id": S, "key": S, "category": S, "value": S, "tags": arr(S), "version": I, "updated_by": S,
                  "updated_by_name": S, "created_at": S, "updated_at": S})
DECISION = obj_out({"id": S, "title": S, "decision": S, "rationale": NS, "tags": arr(S), "status": S,
                    "supersedes_id": NS, "decided_by": S, "decided_by_name": S, "created_at": S})
ACTIVITY = obj_out({"id": I, "ts": S, "agent_id": NS, "action": S, "target_type": NS, "target_id": NS, "summary": S,
                    "details": OBJ, "actor": obj_out({"id": NS, "name": S, "kind": S})})
FILE_ENTRY = obj_out({"name": S, "path": S, "type": S, "size": NI, "modified": S})

_CONTEXT_COMMON = {"project": OBJ, "rules": OBJ, "decisions": arr(DECISION), "memory": arr(MEMORY),
                   "agents": arr(AGENT), "recent_activity": arr(ACTIVITY)}
PROJECT_CONTEXT = obj_out(_CONTEXT_COMMON)
AGENT_CONTEXT = obj_out({**_CONTEXT_COMMON, "agent": AGENT, "my_tasks": arr(TASK), "claimable_tasks": arr(TASK),
                         "inbox": obj_out({"unread_total": I, "preview": arr(MESSAGE)}),
                         "pending_handoffs": arr(HANDOFF), "last_checkpoint": NOBJ})
