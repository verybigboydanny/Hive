"""Agent identity, sessions, presence.

Identity rules
  * `agents.id` (ag_xxxxxxxxxx, generated) is the only identifier. `name` is a display label and
    may repeat. Message/task APIs address agents by id; a name is accepted only where it matches
    exactly one agent (otherwise AMBIGUOUS_AGENT lists the candidate ids).
  * Registration returns a secret `resume_token` once; only its sha256 is stored. Reconnecting
    after a disconnect requires agent_id + resume_token. Without them a new identity is created.
  * The human is the seeded row id='user', kind='human'; it never has a resume token.
  * The human can remove an agent. Removal is a soft delete (`removed_at`): the row stays so history keeps its
    names, but the agent leaves every list, cannot be addressed and cannot reconnect.
"""

from __future__ import annotations

import hmac
import json
import re
import secrets
from typing import Any

from ..activity import log_in_txn
from ..db import Database
from ..errors import (AGENT_NOT_REGISTERED, AMBIGUOUS_AGENT, AUTH_FAILED, INVALID_ARGUMENT, NOT_FOUND,
                      PERMISSION_DENIED, HiveError)
from ..settings import HiveSettings
from ..util import age_seconds, clean_str_list, clean_text, new_id, now_iso, sha256_hex

HUMAN_ID = "user"
STATUSES = ("active", "idle", "blocked", "offline")
# Tasks an agent holds while it works on them. A removed agent gives these back; 'review' work is finished and stays.
_RELEASED_ON_REMOVAL = ("claimed", "in_progress", "blocked")
_CLIENT_RE = re.compile(r"^[A-Za-z0-9._-]{1,32}$")
_DUMMY_HASH = sha256_hex(b"dummy")


def presence_of(row, settings: HiveSettings) -> str:
    if row["kind"] == "human":
        return "online"
    if row["status"] == "offline":
        return "offline"
    age = age_seconds(row["last_seen_at"])
    if age <= settings.presence_online_seconds:
        return "online"
    return "away" if age <= settings.presence_away_seconds else "offline"


def serialize_agent(row, settings: HiveSettings, **extra) -> dict[str, Any]:
    return {
        "id": row["id"], "name": row["name"], "kind": row["kind"], "client": row["client"],
        "model": row["model"], "role": row["role"], "capabilities": json.loads(row["capabilities"]),
        "status": row["status"], "status_message": row["status_message"],
        "presence": presence_of(row, settings), "registered_at": row["registered_at"],
        "last_seen_at": row["last_seen_at"], **extra,
    }


def resolve_agent_ref(conn, ref: str) -> str:
    """Resolve an agent id (preferred) or a display name matching exactly one agent. Returns the id.
    Removed agents are not addressable."""
    if not isinstance(ref, str) or not ref.strip():
        raise HiveError(INVALID_ARGUMENT, "agent reference must be a non-empty string")
    row = conn.execute("SELECT id FROM agents WHERE id = ? AND removed_at IS NULL", (ref,)).fetchone()
    if row:
        return row["id"]
    rows = conn.execute("SELECT id, name, client FROM agents WHERE name = ? COLLATE NOCASE AND removed_at IS NULL",
                        (ref,)).fetchall()
    if len(rows) == 1:
        return rows[0]["id"]
    if not rows:
        raise HiveError(NOT_FOUND, f"no agent matches '{ref}'", hint="Use agent_list to see agent ids.")
    raise HiveError(AMBIGUOUS_AGENT, f"{len(rows)} agents are named '{ref}'; use an agent id",
                    {"candidates": [{"id": r["id"], "name": r["name"], "client": r["client"]} for r in rows]})


class AgentService:
    def __init__(self, db: Database, settings: HiveSettings) -> None:
        self.db, self.settings = db, settings

    # --------------------------------------------------------------- registration
    def register(self, *, name: str, client: str = "other", model: str | None = None,
                 role: str | None = None, capabilities=None, transport: str = "stdio",
                 client_info: dict | None = None, agent_id: str | None = None,
                 resume_token: str | None = None) -> dict[str, Any]:
        name = clean_text(name, "name", max_chars=64, required=True).strip()
        client = (client or "other").strip().lower()
        if not _CLIENT_RE.match(client):
            raise HiveError(INVALID_ARGUMENT, "client must be 1-32 characters of letters, digits, . _ -")
        model = clean_text(model, "model", max_chars=100)
        role = clean_text(role, "role", max_chars=200)
        caps = clean_str_list(capabilities, "capabilities", max_items=20, max_len=40)
        info = json.dumps(client_info or {}, ensure_ascii=False)[:2000]
        if (agent_id is None) != (resume_token is None):
            raise HiveError(INVALID_ARGUMENT, "agent_id and resume_token must be supplied together to reconnect")
        now = now_iso()
        with self.db.write() as c:
            if agent_id is not None:
                row = c.execute("SELECT * FROM agents WHERE id=? AND kind='agent' AND removed_at IS NULL",
                                (agent_id,)).fetchone()
                stored = (row["resume_token_hash"] if row else None) or _DUMMY_HASH
                ok = hmac.compare_digest(stored, sha256_hex(str(resume_token).encode()))
                if row is None or not ok:
                    raise HiveError(AUTH_FAILED, "invalid agent_id or resume_token",
                                    hint="Register without them to create a new identity.")
                c.execute("UPDATE agents SET name=?, client=?, model=COALESCE(?,model), role=COALESCE(?,role),"
                          " capabilities=?, status='active', status_message=NULL, last_seen_at=? WHERE id=?",
                          (name, client, model, role, json.dumps(caps), now, agent_id))
                token, resumed, aid = None, True, agent_id
            else:
                n = c.execute("SELECT COUNT(*) FROM agents WHERE kind='agent' AND removed_at IS NULL").fetchone()[0]
                if n >= self.settings.max_agents:
                    raise HiveError(PERMISSION_DENIED, f"agent limit reached ({self.settings.max_agents})")
                aid = new_id("ag")
                token = secrets.token_urlsafe(24)
                c.execute("INSERT INTO agents(id,agent_key,name,client,kind,registered_at,last_seen_at,model,role,"
                          "capabilities,status,resume_token_hash) VALUES(?,?,?,?,'agent',?,?,?,?,?,'active',?)",
                          (aid, f"agent:{aid}", name, client, now, now, model, role, json.dumps(caps),
                           sha256_hex(token.encode())))
                resumed = False
            sid = new_id("ss")
            c.execute("INSERT INTO agent_sessions(id,agent_id,transport,client_info,connected_at,last_seen_at)"
                      " VALUES(?,?,?,?,?,?)", (sid, aid, transport, info, now, now))
            log_in_txn(c, agent_id=aid, action="agent.reconnect" if resumed else "agent.register",
                       summary=f"{name} ({client}) {'reconnected' if resumed else 'registered'}",
                       target_type="agent", target_id=aid, details={"session_id": sid, "transport": transport,
                                                                   "model": model})
            agent = serialize_agent(c.execute("SELECT * FROM agents WHERE id=?", (aid,)).fetchone(), self.settings)
        return {"agent": agent, "session_id": sid, "resume_token": token, "resumed": resumed}

    # ------------------------------------------------------------------ sessions
    def verify_session(self, session_id: str, agent_id: str) -> dict[str, Any]:
        """Validate a bound session and refresh last_seen (throttled). Raises AGENT_NOT_REGISTERED."""
        with self.db.read() as c:
            row = c.execute("SELECT a.*, s.disconnected_at AS s_disc, s.last_seen_at AS s_seen FROM agent_sessions s"
                            " JOIN agents a ON a.id = s.agent_id WHERE s.id=? AND s.agent_id=?"
                            " AND a.removed_at IS NULL",
                            (session_id, agent_id)).fetchone()
        if row is None or row["s_disc"] is not None:
            raise HiveError(AGENT_NOT_REGISTERED, "session is not active",
                            hint="Call agent_register (pass agent_id + resume_token to keep your identity).")
        if age_seconds(row["s_seen"]) >= self.settings.touch_interval_seconds or row["status"] == "offline":
            now = now_iso()
            with self.db.write() as c:
                c.execute("UPDATE agent_sessions SET last_seen_at=? WHERE id=?", (now, session_id))
                c.execute("UPDATE agents SET last_seen_at=?, status=CASE WHEN status='offline' THEN 'active' ELSE status END"
                          " WHERE id=?", (now, agent_id))
                row = c.execute("SELECT a.*, 0 AS s_disc FROM agents a WHERE a.id=?", (agent_id,)).fetchone()
        return serialize_agent(row, self.settings)

    def disconnect(self, session_id: str, reason: str = "closed") -> bool:
        with self.db.write() as c:
            s = c.execute("SELECT agent_id FROM agent_sessions WHERE id=? AND disconnected_at IS NULL",
                          (session_id,)).fetchone()
            if s is None:
                return False
            now = now_iso()
            c.execute("UPDATE agent_sessions SET disconnected_at=?, disconnect_reason=? WHERE id=?",
                      (now, reason[:200], session_id))
            still = c.execute("SELECT COUNT(*) FROM agent_sessions WHERE agent_id=? AND disconnected_at IS NULL",
                              (s["agent_id"],)).fetchone()[0]
            if still == 0:
                c.execute("UPDATE agents SET status='offline', status_message=NULL WHERE id=?", (s["agent_id"],))
            log_in_txn(c, agent_id=s["agent_id"], action="agent.disconnect", summary=f"session closed ({reason})",
                       target_type="agent", target_id=s["agent_id"],
                       details={"session_id": session_id, "remaining_sessions": still})
        return True

    # ------------------------------------------------------------------- status
    def update_status(self, agent_id: str, status: str, message: str | None = None) -> dict[str, Any]:
        if status not in STATUSES:
            raise HiveError(INVALID_ARGUMENT, f"status must be one of {', '.join(STATUSES)}")
        message = clean_text(message, "message", max_chars=300)
        with self.db.write() as c:
            now = now_iso()
            c.execute("UPDATE agents SET status=?, status_message=?, last_seen_at=? WHERE id=?",
                      (status, message, now, agent_id))
            log_in_txn(c, agent_id=agent_id, action="agent.status", summary=f"status -> {status}"
                       + (f": {message}" if message else ""), target_type="agent", target_id=agent_id,
                       details={"status": status})
            return serialize_agent(c.execute("SELECT * FROM agents WHERE id=?", (agent_id,)).fetchone(), self.settings)

    # ------------------------------------------------------------------- removal
    def remove(self, actor_id: str, agent_id: str) -> dict[str, Any]:
        """Take an agent out of the project (a human decision, so there is no MCP tool for it).

        In one transaction: close its open sessions, give its in-flight tasks back to the backlog, cancel handoffs
        addressed to it, and mark it removed so it vanishes from lists and cannot reconnect (its resume token is
        discarded). Messages, tasks it created, checkpoints and activity are kept and still show its name."""
        now = now_iso()
        with self.db.write() as c:
            row = c.execute("SELECT * FROM agents WHERE id=? AND removed_at IS NULL", (agent_id,)).fetchone()
            if row is None:
                raise HiveError(NOT_FOUND, f"agent not found: {agent_id}")
            if row["kind"] != "agent":
                raise HiveError(INVALID_ARGUMENT, "only agents can be removed, not the human user")
            marks = ",".join("?" * len(_RELEASED_ON_REMOVAL))
            released = [r["id"] for r in c.execute(
                f"SELECT id FROM tasks WHERE owner_id=? AND status IN ({marks}) ORDER BY created_at",
                (agent_id, *_RELEASED_ON_REMOVAL))]
            c.execute(f"UPDATE tasks SET status='open', owner_id=NULL, claim_expires_at=NULL,"
                      f" version=version+1, updated_at=? WHERE owner_id=? AND status IN ({marks})",
                      (now, agent_id, *_RELEASED_ON_REMOVAL))
            cancelled = c.execute("UPDATE handoffs SET status='cancelled' WHERE to_agent_id=? AND status='pending'",
                                  (agent_id,)).rowcount
            c.execute("UPDATE agent_sessions SET disconnected_at=?, disconnect_reason='removed'"
                      " WHERE agent_id=? AND disconnected_at IS NULL", (now, agent_id))
            c.execute("UPDATE agents SET removed_at=?, status='offline', status_message=NULL,"
                      " resume_token_hash=NULL WHERE id=?", (now, agent_id))
            log_in_txn(c, agent_id=actor_id, action="agent.remove", summary=f"removed agent {row['name']}",
                       target_type="agent", target_id=agent_id,
                       details={"name": row["name"], "client": row["client"], "released_tasks": released,
                                "cancelled_handoffs": cancelled})
        return {"removed": True, "agent_id": agent_id, "name": row["name"], "released_tasks": released,
                "cancelled_handoffs": cancelled}

    # -------------------------------------------------------------------- queries
    def get(self, agent_id: str) -> dict[str, Any]:
        with self.db.read() as c:
            row = c.execute("SELECT * FROM agents WHERE id=? AND removed_at IS NULL", (agent_id,)).fetchone()
            if row is None:
                raise HiveError(NOT_FOUND, f"agent not found: {agent_id}")
            return self._enrich(c, row)

    def list(self, *, include_offline: bool = True, include_human: bool = True) -> list[dict[str, Any]]:
        with self.db.read() as c:
            rows = c.execute("SELECT * FROM agents WHERE removed_at IS NULL"
                             " ORDER BY kind DESC, registered_at, id").fetchall()
            out = [self._enrich(c, r) for r in rows]
        if not include_human:
            out = [a for a in out if a["kind"] != "human"]
        if not include_offline:
            out = [a for a in out if a["presence"] != "offline"]
        return out

    def _enrich(self, c, row) -> dict[str, Any]:
        sessions = c.execute("SELECT COUNT(*) FROM agent_sessions WHERE agent_id=? AND disconnected_at IS NULL",
                             (row["id"],)).fetchone()[0]
        tasks = [r[0] for r in c.execute("SELECT id FROM tasks WHERE owner_id=? AND status IN "
                                         "('claimed','in_progress','blocked','review') ORDER BY created_at",
                                         (row["id"],))]
        return serialize_agent(row, self.settings, open_sessions=sessions, active_task_ids=tasks)

    def is_human(self, conn, agent_id: str) -> bool:
        r = conn.execute("SELECT kind FROM agents WHERE id=?", (agent_id,)).fetchone()
        return bool(r and r["kind"] == "human")
