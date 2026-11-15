"""Transport-independent tool registry.

Every tool call goes through ToolRegistry.call_sync:
  validate input -> authenticate the bound agent session -> run handler -> envelope + notices.
The MCP adapter and the tests both use this single entry point, so what is tested is what is served.

Envelope
  success: {"ok": true,  "data": {...}, "notices": {...}}
  failure: {"ok": false, "error": {"code","message","details"?,"hint"?}, "notices": {...}}
`notices` is present whenever the caller is a registered agent and tells it, on EVERY call, about state it
would otherwise miss while idle: unread messages, pending handoffs, task leases about to expire.
"""

from __future__ import annotations

import asyncio
import logging
import sqlite3
import threading
from dataclasses import dataclass, field
from typing import Any, Callable

from ..errors import (AGENT_NOT_REGISTERED, AUTH_FAILED, BUSY, INTERNAL, PATH_DENIED, PERMISSION_DENIED, UNKNOWN_TOOL,
                      HiveError)
from ..util import in_minutes
from .schema import coerce_args, validate

log = logging.getLogger("hive.tools")
SECURITY_CODES = {PATH_DENIED, AUTH_FAILED, PERMISSION_DENIED}


@dataclass(frozen=True)
class ToolSpec:
    name: str
    group: str
    description: str
    input_schema: dict
    output_schema: dict                     # shape of envelope["data"]
    handler: Callable[[Any, "ToolContext", dict], dict]
    requires_agent: bool = True
    read_only: bool = False
    destructive: bool = False
    idempotent: bool = False

    @property
    def annotations(self) -> dict[str, bool]:
        return {"readOnlyHint": self.read_only, "destructiveHint": self.destructive,
                "idempotentHint": self.idempotent, "openWorldHint": False}


@dataclass
class ToolContext:
    app: Any
    session_key: str
    registry: "ToolRegistry"
    agent: dict | None = None
    session_id: str | None = None
    client_info: dict = field(default_factory=dict)
    transport: str = "stdio"

    @property
    def agent_id(self) -> str:
        assert self.agent is not None
        return self.agent["id"]

    def bind(self, agent_id: str, session_id: str) -> None:
        self.registry._bind(self.session_key, agent_id, session_id)


@dataclass
class ToolResult:
    ok: bool
    payload: dict[str, Any]

    @property
    def data(self) -> dict[str, Any]:
        return self.payload.get("data", {})

    @property
    def error(self) -> dict[str, Any]:
        return self.payload.get("error", {})


class ToolRegistry:
    def __init__(self, app, specs: list[ToolSpec] | None = None, *, validate_outputs: bool = False) -> None:
        from .catalog import ALL_TOOLS
        self.app = app
        self._specs = {s.name: s for s in (specs if specs is not None else ALL_TOOLS)}
        self.validate_outputs = validate_outputs
        self._sessions: dict[str, tuple[str, str]] = {}
        self._lock = threading.Lock()

    def specs(self) -> list[ToolSpec]:
        return list(self._specs.values())

    def spec(self, name: str) -> ToolSpec | None:
        s = self._specs.get(name)
        if s is not None:
            return s
        if name in ("terminal", "bash", "execute_command"):
            return self._specs.get("run_command")
        if name == "run_command":
            return self._specs.get("terminal")
        return None

    # ------------------------------------------------------------- session map
    def _bind(self, key: str, agent_id: str, session_id: str) -> None:
        with self._lock:
            old = self._sessions.get(key)
            self._sessions[key] = (agent_id, session_id)
        if old and old[1] != session_id:
            self.app.agents.disconnect(old[1], "re-registered on the same connection")

    def session_of(self, key: str) -> tuple[str, str] | None:
        with self._lock:
            return self._sessions.get(key)

    def close_session(self, key: str, reason: str = "connection closed") -> None:
        with self._lock:
            s = self._sessions.pop(key, None)
        if s:
            try:
                self.app.agents.disconnect(s[1], reason)
            except Exception:                                  # shutdown path: never raise
                log.exception("failed to record disconnect for %s", s[1])

    def close_all(self, reason: str = "server shutdown") -> None:
        for key in list(self._sessions):
            self.close_session(key, reason)

    # ------------------------------------------------------------------- calls
    async def call(self, name: str, arguments: dict | None, session_key: str = "default", *,
                   client_info: dict | None = None, transport: str = "stdio") -> ToolResult:
        return await asyncio.to_thread(self.call_sync, name, arguments, session_key, client_info=client_info,
                                       transport=transport)

    def call_sync(self, name: str, arguments: dict | None, session_key: str = "default", *,
                  client_info: dict | None = None, transport: str = "stdio") -> ToolResult:
        ctx = ToolContext(self.app, session_key, self, client_info=client_info or {}, transport=transport)
        try:
            spec = self.spec(name)
            if spec is None:
                raise HiveError(UNKNOWN_TOOL, f"unknown tool '{name}'", hint="List tools with tools/list.")
            args = coerce_args(spec.input_schema, {} if arguments is None else arguments)
            validate(spec.input_schema, args)
            if spec.requires_agent:
                bound = self.session_of(session_key)
                if bound is None:
                    raise HiveError(AGENT_NOT_REGISTERED, "this connection has no registered agent",
                                    hint="Call agent_register first (pass agent_id + resume_token to keep your identity).")
                ctx.agent = self.app.agents.verify_session(bound[1], bound[0])
                ctx.session_id = bound[1]
            data = spec.handler(self.app, ctx, args)
            if self.validate_outputs:
                try:
                    validate(spec.output_schema, data, f"{name}.data")
                except HiveError as exc:
                    raise HiveError(INTERNAL, f"tool output violates its schema: {exc.message}") from None
            return ToolResult(True, self._envelope(ctx, {"ok": True, "data": data}))
        except HiveError as exc:
            self._audit_denied(ctx, name, exc)
            return ToolResult(False, self._envelope(ctx, {"ok": False, "error": exc.to_dict()}))
        except sqlite3.OperationalError as exc:
            log.warning("database busy/unavailable in %s: %s", name, exc)
            err = HiveError(BUSY, "the database is busy; retry shortly", hint="Retry the same call.")
            return ToolResult(False, self._envelope(ctx, {"ok": False, "error": err.to_dict()}))
        except Exception:
            log.exception("unhandled error in tool %s", name)
            err = HiveError(INTERNAL, "internal error (details are in the Hive log)")
            return ToolResult(False, self._envelope(ctx, {"ok": False, "error": err.to_dict()}))

    # ----------------------------------------------------------------- helpers
    def _envelope(self, ctx: ToolContext, env: dict) -> dict:
        if ctx.agent is not None:
            try:
                env["notices"] = self._notices(ctx.agent["id"])
            except Exception:
                log.exception("failed to compute notices")
        return env

    def _notices(self, agent_id: str) -> dict[str, Any]:
        app = self.app
        with app.db.read() as c:
            soon = c.execute("SELECT id FROM tasks WHERE owner_id=? AND status IN ('claimed','in_progress','blocked','review')"
                             " AND claim_expires_at <= ? ORDER BY claim_expires_at", (agent_id, in_minutes(5))).fetchall()
        return {"unread_messages": app.messages.unread_count(agent_id),
                "pending_handoffs": app.handoffs.pending_for(agent_id),
                "leases_expiring": [r["id"] for r in soon]}

    def _audit_denied(self, ctx: ToolContext, tool: str, exc: HiveError) -> None:
        if exc.code not in SECURITY_CODES:
            return
        try:
            self.app.activity.record(agent_id=ctx.agent["id"] if ctx.agent else None, action="security.denied",
                                     summary=f"{tool} denied: {exc.code}", target_type="tool", target_id=tool,
                                     details={"code": exc.code, "message": exc.message[:200]})
        except Exception:
            log.exception("failed to audit security denial")
