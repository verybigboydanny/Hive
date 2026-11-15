import json

from .db import Database
from .util import now_iso


def log_in_txn(conn, *, agent_id, action, summary, target_type=None, target_id=None, details=None) -> int:
    """Write an activity row inside the caller's transaction, so state change + audit are atomic."""
    cur = conn.execute(
        "INSERT INTO activity(ts,agent_id,action,target_type,target_id,summary,details) VALUES(?,?,?,?,?,?,?)",
        (now_iso(), agent_id, action, target_type, None if target_id is None else str(target_id),
         summary[:500], json.dumps(details or {}, ensure_ascii=False, sort_keys=True)),
    )
    return cur.lastrowid


def _entry(r) -> dict:
    return {"id": r["id"], "ts": r["ts"], "agent_id": r["agent_id"], "action": r["action"],
            "target_type": r["target_type"], "target_id": r["target_id"],
            "summary": r["summary"], "details": json.loads(r["details"])}


class ActivityService:
    def __init__(self, db: Database):
        self.db = db

    def record(self, **kw) -> int:
        with self.db.write() as c:
            return log_in_txn(c, **kw)

    def query(self, *, after_id=None, limit=50, agent_id=None, action_prefix=None) -> dict:
        where, args = [], []
        if agent_id:
            where.append("agent_id = ?"); args.append(agent_id)
        if action_prefix:
            esc = action_prefix.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
            where.append("action LIKE ? ESCAPE '\\'"); args.append(esc + "%")
        if after_id is not None:
            where.append("id > ?"); args.append(after_id)
        sql = "SELECT * FROM activity" + (" WHERE " + " AND ".join(where) if where else "")
        sql += " ORDER BY id ASC LIMIT ?" if after_id is not None else " ORDER BY id DESC LIMIT ?"
        with self.db.read() as c:
            rows = c.execute(sql, (*args, limit)).fetchall()
        if after_id is None:
            rows.reverse()  # newest N, returned oldest -> newest
        entries = [_entry(r) for r in rows]
        return {"entries": entries, "next_cursor": entries[-1]["id"] if entries else (after_id or 0)}
