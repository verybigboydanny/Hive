"""Persistent agent messaging. Messages are stored forever; delivery is pull-based (inbox).

  * Hive cannot wake an idle LLM client; messages wait in the inbox until the agent asks.
  * Reading is explicit: message_inbox never marks anything read; message_mark_read does
    (at-least-once delivery: a lost response means the message is simply returned again).
  * Broadcast (to=None) messages are visible to every agent except the sender, from the moment
    that agent registered. Read state is per recipient (message_receipts).
"""

from __future__ import annotations

from typing import Any

from ..activity import log_in_txn
from ..db import Database
from ..errors import INVALID_ARGUMENT, NOT_FOUND, HiveError
from ..settings import HiveSettings
from ..util import clean_text, new_id, now_iso
from .agents import resolve_agent_ref

USER_KINDS = ("message", "question", "answer", "notice")
_VISIBLE = ("(m.to_agent_id = :me OR (m.to_agent_id IS NULL AND m.from_agent_id <> :me"
            " AND m.created_at >= :reg))")
_SELECT = ("SELECT m.*, fa.name AS from_name, fa.kind AS from_kind, ta.name AS to_name, r.read_at AS read_at "
           "FROM messages m JOIN agents fa ON fa.id = m.from_agent_id "
           "LEFT JOIN agents ta ON ta.id = m.to_agent_id "
           "LEFT JOIN message_receipts r ON r.message_id = m.id AND r.agent_id = :me ")


def serialize_message(row) -> dict[str, Any]:
    return {"id": row["id"], "seq": row["seq"], "thread_id": row["thread_id"], "kind": row["kind"],
            "from_id": row["from_agent_id"], "from_name": row["from_name"], "from_kind": row["from_kind"],
            "to_id": row["to_agent_id"], "to_name": row["to_name"], "subject": row["subject"],
            "body": row["body"], "task_id": row["task_id"], "created_at": row["created_at"],
            "read": row["read_at"] is not None, "read_at": row["read_at"]}


class MessageService:
    def __init__(self, db: Database, settings: HiveSettings) -> None:
        self.db, self.settings = db, settings

    # --------------------------------------------------------------------- send
    def send(self, actor: str, *, to: str | None, body: str, subject: str | None = None, kind: str = "message",
             reply_to: str | None = None, task_id: str | None = None) -> dict[str, Any]:
        if kind not in USER_KINDS:
            raise HiveError(INVALID_ARGUMENT, f"kind must be one of {', '.join(USER_KINDS)}")
        with self.db.write() as c:
            return self.send_in_tx(c, actor, to=to, body=body, subject=subject, kind=kind, reply_to=reply_to,
                                   task_id=task_id)

    def send_in_tx(self, c, actor: str, *, to: str | None, body: str, subject: str | None = None,
                   kind: str = "message", reply_to: str | None = None, task_id: str | None = None) -> dict[str, Any]:
        body = clean_text(body, "body", max_chars=self.settings.max_message_chars, required=True)
        subject = clean_text(subject, "subject", max_chars=200)
        to_id = None if to in (None, "all") else resolve_agent_ref(c, to)
        if to_id == actor:
            raise HiveError(INVALID_ARGUMENT, "you cannot message yourself")
        if task_id is not None and not c.execute("SELECT 1 FROM tasks WHERE id=?", (task_id,)).fetchone():
            raise HiveError(NOT_FOUND, f"task not found: {task_id}")
        mid = new_id("msg")
        thread = mid
        if reply_to is not None:
            parent = c.execute("SELECT thread_id FROM messages WHERE id=?", (reply_to,)).fetchone()
            if parent is None:
                raise HiveError(NOT_FOUND, f"message not found: {reply_to}")
            thread = parent["thread_id"]
        cur = c.execute("INSERT INTO messages(id,thread_id,from_agent_id,to_agent_id,kind,subject,body,task_id,"
                        "created_at) VALUES(?,?,?,?,?,?,?,?,?)",
                        (mid, thread, actor, to_id, kind, subject, body, task_id, now_iso()))
        target = "all agents" if to_id is None else to_id
        log_in_txn(c, agent_id=actor, action="message.send",
                   summary=f"{kind} to {target}: {(subject or body)[:80]}", target_type="message", target_id=mid,
                   details={"to": to_id, "thread_id": thread, "task_id": task_id, "kind": kind})
        row = c.execute(_SELECT + "WHERE m.seq = :seq", {"me": actor, "seq": cur.lastrowid}).fetchone()
        return serialize_message(row)

    # -------------------------------------------------------------------- inbox
    def _reg(self, c, me: str) -> str:
        row = c.execute("SELECT registered_at FROM agents WHERE id=?", (me,)).fetchone()
        if row is None:
            raise HiveError(NOT_FOUND, f"agent not found: {me}")
        return row["registered_at"]

    def inbox(self, me: str, *, unread_only: bool = True, limit: int = 20, after_seq: int = 0,
              from_ref: str | None = None) -> dict[str, Any]:
        if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 200:
            raise HiveError(INVALID_ARGUMENT, "limit must be between 1 and 200")
        with self.db.read() as c:
            p: dict[str, Any] = {"me": me, "reg": self._reg(c, me), "after": after_seq, "limit": limit}
            extra = ""
            if unread_only:
                extra += " AND r.read_at IS NULL"
            if from_ref:
                p["from"] = resolve_agent_ref(c, from_ref); extra += " AND m.from_agent_id = :from"
            rows = c.execute(_SELECT + f"WHERE {_VISIBLE} AND m.seq > :after{extra} ORDER BY m.seq LIMIT :limit", p).fetchall()
            unread = self._unread(c, me, p["reg"])
        msgs = [serialize_message(r) for r in rows]
        return {"messages": msgs, "unread_total": unread, "next_after_seq": msgs[-1]["seq"] if msgs else after_seq}

    def _unread(self, c, me: str, reg: str) -> int:
        return c.execute("SELECT COUNT(*) FROM messages m LEFT JOIN message_receipts r ON r.message_id=m.id AND"
                         f" r.agent_id=:me WHERE {_VISIBLE} AND r.read_at IS NULL", {"me": me, "reg": reg}).fetchone()[0]

    def unread_count(self, me: str) -> int:
        with self.db.read() as c:
            return self._unread(c, me, self._reg(c, me))

    def mark_read(self, me: str, *, message_ids=None, up_to_seq: int | None = None, all_messages: bool = False) -> dict[str, Any]:
        modes = sum(x is not None and x is not False for x in (message_ids, up_to_seq, all_messages or None))
        if modes != 1:
            raise HiveError(INVALID_ARGUMENT, "provide exactly one of message_ids, up_to_seq, all")
        with self.db.write() as c:
            reg, now = self._reg(c, me), now_iso()
            p: dict[str, Any] = {"me": me, "reg": reg}
            if message_ids is not None:
                if not isinstance(message_ids, list) or not message_ids or len(message_ids) > 200:
                    raise HiveError(INVALID_ARGUMENT, "message_ids must be a list of 1-200 ids")
                wanted = [str(i) for i in message_ids]
                found = {r["id"] for r in c.execute(
                    f"SELECT m.id FROM messages m WHERE {_VISIBLE} AND m.id IN ({','.join(':i%d' % i for i in range(len(wanted)))})",
                    {**p, **{f"i{i}": w for i, w in enumerate(wanted)}})}
                targets = [w for w in wanted if w in found]
                missing = [w for w in wanted if w not in found]
            else:
                cond = "" if all_messages else " AND m.seq <= :upto"
                if not all_messages:
                    p["upto"] = up_to_seq
                targets = [r["id"] for r in c.execute(f"SELECT m.id FROM messages m WHERE {_VISIBLE}{cond}", p)]
                missing = []
            marked = 0
            for mid in targets:
                marked += c.execute("INSERT OR IGNORE INTO message_receipts(message_id,agent_id,read_at) VALUES(?,?,?)",
                                    (mid, me, now)).rowcount
            return {"marked": marked, "not_found": missing, "unread_total": self._unread(c, me, reg)}

    # ----------------------------------------------------------- oversight views
    def history(self, *, after_seq: int = 0, limit: int = 100, thread_id: str | None = None,
                agent_ref: str | None = None, viewer: str = "user") -> dict[str, Any]:
        """Unfiltered view for the human/UI (read state shown for `viewer`)."""
        if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 500:
            raise HiveError(INVALID_ARGUMENT, "limit must be between 1 and 500")
        with self.db.read() as c:
            where, p = ["m.seq > :after"], {"me": viewer, "after": after_seq, "limit": limit}
            if thread_id:
                where.append("m.thread_id = :thread"); p["thread"] = thread_id
            if agent_ref:
                p["ag"] = resolve_agent_ref(c, agent_ref)
                where.append("(m.from_agent_id = :ag OR m.to_agent_id = :ag OR m.to_agent_id IS NULL)")
            rows = c.execute(_SELECT + f"WHERE {' AND '.join(where)} ORDER BY m.seq LIMIT :limit", p).fetchall()
        msgs = [serialize_message(r) for r in rows]
        return {"messages": msgs, "next_after_seq": msgs[-1]["seq"] if msgs else after_seq}
