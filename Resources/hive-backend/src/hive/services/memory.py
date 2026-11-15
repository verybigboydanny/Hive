"""Shared project memory (versioned key/value knowledge) and architectural decisions.

  * Existing keys can only be updated with the version the caller read (no silent overwrite);
    every version is retained in memory_history.
  * Decisions are append-only records; a new decision may supersede an old one (history kept).
  * Search is term-based with simple relevance scoring (key hits weigh more).
"""

from __future__ import annotations

import json
import re
from typing import Any

from ..activity import log_in_txn
from ..db import Database
from ..errors import CONFLICT, INVALID_ARGUMENT, NOT_FOUND, PRECONDITION_REQUIRED, HiveError
from ..settings import HiveSettings
from ..util import clean_str_list, clean_text, new_id, now_iso

_KEY_RE = re.compile(r"^[a-z0-9][a-z0-9._:/-]{0,119}$")
_CAT_RE = re.compile(r"^[a-z0-9._-]{1,40}$")
_ESC = str.maketrans({"\\": "\\\\", "%": "\\%", "_": "\\_"})


def _entry(row) -> dict[str, Any]:
    return {"id": row["id"], "key": row["key"], "category": row["category"], "value": row["value"],
            "tags": json.loads(row["tags"]), "version": row["version"], "updated_by": row["updated_by"],
            "updated_by_name": row["by_name"], "created_at": row["created_at"], "updated_at": row["updated_at"]}


def _decision(row) -> dict[str, Any]:
    return {"id": row["id"], "title": row["title"], "decision": row["decision"], "rationale": row["rationale"],
            "tags": json.loads(row["tags"]), "status": row["status"], "supersedes_id": row["supersedes_id"],
            "decided_by": row["decided_by"], "decided_by_name": row["by_name"], "created_at": row["created_at"]}


_E_SEL = "SELECT m.*, a.name AS by_name FROM memory_entries m JOIN agents a ON a.id = m.updated_by "
_D_SEL = "SELECT d.*, a.name AS by_name FROM decisions d JOIN agents a ON a.id = d.decided_by "


def _terms(query: str) -> list[str]:
    return list(dict.fromkeys(re.findall(r"\w+", query.lower())))[:8]


class MemoryService:
    def __init__(self, db: Database, settings: HiveSettings) -> None:
        self.db, self.settings = db, settings

    # ------------------------------------------------------------------- memory
    def update(self, actor: str, *, key: str, value: str, category: str = "general", tags=None,
               expected_version: int | None = None) -> dict[str, Any]:
        key = clean_text(key, "key", max_chars=120, required=True).strip().lower()
        if not _KEY_RE.match(key):
            raise HiveError(INVALID_ARGUMENT, "key must be 1-120 chars of a-z 0-9 . _ : / - (case-insensitive)")
        value = clean_text(value, "value", max_chars=self.settings.max_memory_value_chars, required=True)
        category = (category or "general").strip().lower()
        if not _CAT_RE.match(category):
            raise HiveError(INVALID_ARGUMENT, "category must be 1-40 chars of a-z 0-9 . _ -")
        tag_list = clean_str_list(tags, "tags", max_items=20, max_len=40)
        now = now_iso()
        with self.db.write() as c:
            row = c.execute(_E_SEL + "WHERE m.key=?", (key,)).fetchone()
            if row is None:
                if expected_version is not None:
                    raise HiveError(CONFLICT, f"memory '{key}' does not exist (expected version {expected_version})")
                mid = new_id("mem")
                c.execute("INSERT INTO memory_entries(id,key,category,value,tags,version,updated_by,created_at,updated_at)"
                          " VALUES(?,?,?,?,?,1,?,?,?)", (mid, key, category, value, json.dumps(tag_list), actor, now, now))
                c.execute("INSERT INTO memory_history(entry_id,version,value,updated_by,updated_at) VALUES(?,1,?,?,?)",
                          (mid, value, actor, now))
                created = True
            else:
                mid = row["id"]
                if expected_version is None:
                    raise HiveError(PRECONDITION_REQUIRED, f"memory '{key}' exists; pass expected_version to update it",
                                    {"current_version": row["version"], "current_value": row["value"]},
                                    hint="Read it with memory_read, merge your change, retry with its version.")
                if expected_version != row["version"]:
                    raise HiveError(CONFLICT, f"memory '{key}' changed since you read it",
                                    {"current_version": row["version"], "current_value": row["value"]})
                if value == row["value"] and category == row["category"] and tag_list == json.loads(row["tags"]):
                    return {"entry": _entry(row), "created": False, "changed": False}
                ver = row["version"] + 1
                c.execute("UPDATE memory_entries SET value=?, category=?, tags=?, version=?, updated_by=?, updated_at=?"
                          " WHERE id=?", (value, category, json.dumps(tag_list), ver, actor, now, mid))
                c.execute("INSERT INTO memory_history(entry_id,version,value,updated_by,updated_at) VALUES(?,?,?,?,?)",
                          (mid, ver, value, actor, now))
                created = False
            log_in_txn(c, agent_id=actor, action="memory.create" if created else "memory.update",
                       summary=f"{'created' if created else 'updated'} memory '{key}'", target_type="memory",
                       target_id=key, details={"category": category, "chars": len(value)})
            return {"entry": _entry(c.execute(_E_SEL + "WHERE m.id=?", (mid,)).fetchone()), "created": created, "changed": True}

    def read(self, *, key: str | None = None, category: str | None = None, query: str | None = None,
             limit: int = 20, include_history: bool = False) -> dict[str, Any]:
        if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 200:
            raise HiveError(INVALID_ARGUMENT, "limit must be between 1 and 200")
        with self.db.read() as c:
            if key is not None:
                k = key.strip().lower()
                row = c.execute(_E_SEL + "WHERE m.key=?", (k,)).fetchone()
                if row is None:
                    raise HiveError(NOT_FOUND, f"no memory with key '{k}'", hint="Use memory_read with query to search.")
                out: dict[str, Any] = {"entries": [_entry(row)], "total": 1}
                if include_history:
                    out["history"] = [{"version": h["version"], "value": h["value"], "updated_by": h["updated_by"],
                                       "updated_at": h["updated_at"]} for h in c.execute(
                        "SELECT * FROM memory_history WHERE entry_id=? ORDER BY version", (row["id"],))]
                return out
            where, args = [], []
            if category:
                where.append("m.category=?"); args.append(category.strip().lower())
            terms = _terms(query) if query else []
            if query and not terms:
                return {"entries": [], "total": 0}
            if terms:
                where.append("(" + " OR ".join(
                    "lower(m.key || ' ' || m.value || ' ' || m.tags) LIKE ? ESCAPE '\\'" for _ in terms) + ")")
                args += [f"%{t.translate(_ESC)}%" for t in terms]
            rows = c.execute(_E_SEL + (f"WHERE {' AND '.join(where)} " if where else "") +
                             "ORDER BY m.updated_at DESC, m.key", args).fetchall()
        entries = [_entry(r) for r in rows]
        if terms:
            def score(e):
                k, v = e["key"].lower(), (e["value"] + " " + " ".join(e["tags"])).lower()
                return sum(3 * (t in k) + v.count(t) for t in terms)
            entries.sort(key=lambda e: (-score(e), e["key"]))
        return {"entries": entries[:limit], "total": len(entries)}

    # ---------------------------------------------------------------- decisions
    def record_decision(self, actor: str, *, title: str, decision: str, rationale: str | None = None, tags=None,
                        supersedes_id: str | None = None) -> dict[str, Any]:
        mx = self.settings.max_text_chars
        title = clean_text(title, "title", max_chars=200, required=True).strip()
        decision = clean_text(decision, "decision", max_chars=mx, required=True).strip()
        rationale = clean_text(rationale, "rationale", max_chars=mx)
        tag_list = clean_str_list(tags, "tags", max_items=20, max_len=40)
        did = new_id("dec")
        with self.db.write() as c:
            if supersedes_id is not None:
                old = c.execute("SELECT status FROM decisions WHERE id=?", (supersedes_id,)).fetchone()
                if old is None:
                    raise HiveError(NOT_FOUND, f"decision not found: {supersedes_id}")
                if old["status"] != "active":
                    raise HiveError(CONFLICT, "that decision is already superseded", {"decision_id": supersedes_id})
                c.execute("UPDATE decisions SET status='superseded' WHERE id=?", (supersedes_id,))
            c.execute("INSERT INTO decisions(id,title,decision,rationale,tags,supersedes_id,decided_by,created_at)"
                      " VALUES(?,?,?,?,?,?,?,?)", (did, title, decision, rationale, json.dumps(tag_list), supersedes_id,
                                                   actor, now_iso()))
            log_in_txn(c, agent_id=actor, action="decision.record", summary=f"decision: {title[:100]}",
                       target_type="decision", target_id=did, details={"supersedes": supersedes_id})
            return _decision(c.execute(_D_SEL + "WHERE d.id=?", (did,)).fetchone())

    def list_decisions(self, *, status: str = "active", query: str | None = None, limit: int = 50) -> dict[str, Any]:
        if status not in ("active", "superseded", "all"):
            raise HiveError(INVALID_ARGUMENT, "status must be active, superseded or all")
        where, args = [], []
        if status != "all":
            where.append("d.status=?"); args.append(status)
        terms = _terms(query) if query else []
        if query and not terms:
            return {"decisions": [], "count": 0}
        if terms:
            where.append("(" + " OR ".join("lower(d.title || ' ' || d.decision || ' ' || COALESCE(d.rationale,'') || ' ' || d.tags)"
                                           " LIKE ? ESCAPE '\\'" for _ in terms) + ")")
            args += [f"%{t.translate(_ESC)}%" for t in terms]
        with self.db.read() as c:
            rows = c.execute(_D_SEL + (f"WHERE {' AND '.join(where)} " if where else "") +
                             "ORDER BY d.created_at DESC, d.id DESC LIMIT ?", (*args, min(max(limit, 1), 500))).fetchall()
        return {"decisions": [_decision(r) for r in rows], "count": len(rows)}
