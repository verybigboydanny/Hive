"""SwiftUI-facing HTTP API: framework-independent routes (versioned under /v1).

The macOS app talks ONLY to this API (never to SQLite). The MCP surface (agents) and this API (human/UI) are
separate: agents use tools; the UI uses these endpoints, whose writes are attributed to the human actor 'user'.
Handlers return (status, body); the HTTP layer (server.py) owns sockets, auth and streaming.
"""

from __future__ import annotations

import re
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Callable
from urllib.parse import parse_qs

from .. import CONTRACT_VERSION, __version__
from ..app import HiveApp
from ..errors import (ALREADY_EXISTS, AMBIGUOUS_AGENT, BUSY, CONFIRMATION_REQUIRED, CONFLICT, DEPENDENCY_CYCLE,
                      DEPENDENCY_UNMET, FILE_TOO_LARGE, HANDOFF_ALREADY_ACCEPTED, INTERNAL, INVALID_ARGUMENT,
                      NO_WORKSPACE, NOT_FOUND, NOT_INITIALIZED, NOT_TEXT, PATH_DENIED, PERMISSION_DENIED,
                      PRECONDITION_REQUIRED, PROJECT_MISMATCH, PROJECT_REQUIRED, PROJECT_UNKNOWN, TASK_ALREADY_CLAIMED, TASK_CLOSED, TASK_LIMIT_REACHED, TASK_NOT_OWNED,
                      UNAUTHORIZED, HiveError)

HUMAN = "user"
STATUS_FOR_CODE = {INVALID_ARGUMENT: 400, NOT_TEXT: 400, AMBIGUOUS_AGENT: 400, UNAUTHORIZED: 401, PERMISSION_DENIED: 403,
                   PATH_DENIED: 403, NOT_FOUND: 404, FILE_TOO_LARGE: 413, BUSY: 503, INTERNAL: 500, NO_WORKSPACE: 409,
                   NOT_INITIALIZED: 409, CONFLICT: 409, ALREADY_EXISTS: 409, PRECONDITION_REQUIRED: 428,
                   CONFIRMATION_REQUIRED: 428, TASK_ALREADY_CLAIMED: 409, TASK_CLOSED: 409, TASK_NOT_OWNED: 403,
                   TASK_LIMIT_REACHED: 409, DEPENDENCY_UNMET: 409, DEPENDENCY_CYCLE: 409, HANDOFF_ALREADY_ACCEPTED: 409,
                   PROJECT_MISMATCH: 409, PROJECT_UNKNOWN: 404, PROJECT_REQUIRED: 400}


def status_for(code: str) -> int:
    return STATUS_FOR_CODE.get(code, 400)


@dataclass
class Request:
    method: str
    path: str
    query: dict[str, str] = field(default_factory=dict)
    body: dict[str, Any] | None = None


class ApiState:
    """Holds the currently opened workspace (swappable at runtime: the app may open several projects)."""

    def __init__(self) -> None:
        self._app: HiveApp | None = None
        self._lock = threading.RLock()
        self.stopping = threading.Event()
        self.started_at = time.time()

    @property
    def app(self) -> HiveApp | None:
        with self._lock:
            return self._app

    def require_app(self) -> HiveApp:
        app = self.app
        if app is None:
            raise HiveError(NO_WORKSPACE, "no workspace is open", hint="POST /v1/workspace/open or /v1/workspace/init first.")
        return app

    def swap(self, new: HiveApp | None) -> None:
        with self._lock:
            old, self._app = self._app, new
        if old is not None:
            old.close()


Handler = Callable[[ApiState, Request, dict], tuple[int, dict]]
ROUTES: list[tuple[str, re.Pattern, Handler, bool]] = []     # method, pattern, handler, public?


def route(method: str, pattern: str, public: bool = False):
    rx = re.compile("^" + re.sub(r"\{(\w+)\}", r"(?P<\1>[^/]+)", pattern) + "$")

    def deco(fn: Handler) -> Handler:
        ROUTES.append((method, rx, fn, public))
        return fn
    return deco


def match(method: str, path: str):
    allowed = []
    for m, rx, fn, public in ROUTES:
        mt = rx.match(path)
        if mt:
            if m == method:
                return fn, mt.groupdict(), public, None
            allowed.append(m)
    return None, {}, False, allowed


def ok(data: Any, status: int = 200) -> tuple[int, dict]:
    return status, {"ok": True, "data": data}


# ------------------------------------------------------------------ argument helpers
def q_int(req: Request, name: str, default: int | None, lo: int, hi: int) -> int | None:
    raw = req.query.get(name)
    if raw is None:
        return default
    try:
        v = int(raw)
    except ValueError:
        raise HiveError(INVALID_ARGUMENT, f"query parameter '{name}' must be an integer") from None
    if not lo <= v <= hi:
        raise HiveError(INVALID_ARGUMENT, f"query parameter '{name}' must be between {lo} and {hi}")
    return v


def q_bool(req: Request, name: str, default: bool = False) -> bool:
    raw = req.query.get(name)
    if raw is None:
        return default
    if raw.lower() in ("1", "true", "yes"):
        return True
    if raw.lower() in ("0", "false", "no"):
        return False
    raise HiveError(INVALID_ARGUMENT, f"query parameter '{name}' must be true or false")


def body_of(req: Request, allowed: set[str], required: set[str] = frozenset()) -> dict[str, Any]:
    b = req.body
    if not isinstance(b, dict):
        raise HiveError(INVALID_ARGUMENT, "request body must be a JSON object")
    extra = sorted(set(b) - allowed)
    if extra:
        raise HiveError(INVALID_ARGUMENT, f"unknown field(s) {extra}", {"allowed": sorted(allowed)})
    missing = sorted(k for k in required if k not in b)
    if missing:
        raise HiveError(INVALID_ARGUMENT, f"missing field(s) {missing}")
    return b


# ---------------------------------------------------------------------- health
@route("GET", "/v1/health", public=True)
def health(st: ApiState, req: Request, p: dict):
    return ok({"status": "ok", "backend_version": __version__, "contract_version": CONTRACT_VERSION,
               "workspace_open": st.app is not None, "uptime_seconds": round(time.time() - st.started_at, 1)})


@route("GET", "/v1/health/details")
def health_details(st: ApiState, req: Request, p: dict):
    app = st.app
    return ok({"api": {"status": "ok", "uptime_seconds": round(time.time() - st.started_at, 1)},
               "workspace": app.health() if app else None, "workspace_open": app is not None})


# ------------------------------------------------------------------- workspace
def _open(st: ApiState, factory) -> tuple[int, dict]:
    new = factory()
    st.swap(new)
    from ..logging_setup import setup_logging
    setup_logging(new.ws.hive_dir, to_stderr=True)
    return ok(new.project.info())


@route("POST", "/v1/workspace/init")
def ws_init(st: ApiState, req: Request, p: dict):
    b = body_of(req, {"path", "name"}, {"path"})
    return _open(st, lambda: HiveApp.init(b["path"], b.get("name")))


@route("POST", "/v1/workspace/open")
def ws_open(st: ApiState, req: Request, p: dict):
    b = body_of(req, {"path"}, {"path"})
    return _open(st, lambda: HiveApp.open(b["path"]))


@route("POST", "/v1/workspace/close")
def ws_close(st: ApiState, req: Request, p: dict):
    st.swap(None)
    return ok({"closed": True})


@route("GET", "/v1/workspace")
def ws_info(st: ApiState, req: Request, p: dict):
    return ok(st.require_app().project.info())


@route("GET", "/v1/project/status")
def project_status(st: ApiState, req: Request, p: dict):
    return ok(st.require_app().project.status())


@route("GET", "/v1/project/context")
def project_context(st: ApiState, req: Request, p: dict):
    return ok(st.require_app().project.context(None))


# ------------------------------------------------------------------ set up agent
@route("POST", "/v1/onboarding/prompt")
def onboarding_prompt(st: ApiState, req: Request, p: dict):
    """Set Up Agent: the complete onboarding instruction for one agent in the OPEN project.
    `project_id` (optional but always sent by the app) must equal the open project's id, so a window that shows
    project B can never receive an instruction for project A while the backend still has A open."""
    from ..onboarding import build_onboarding, clean_request
    b = body_of(req, {"agent_name", "role", "capabilities", "client", "project_id"}, {"agent_name"})
    app = st.require_app()
    info = app.project.info()
    wanted = b.get("project_id")
    if wanted is not None and wanted != info["id"]:
        raise HiveError(PROJECT_MISMATCH, "the open workspace is not the project you selected",
                        {"requested_project_id": wanted, "open_project": {"id": info["id"], "name": info["name"]}},
                        hint="Reopen the project in Hive and try again.")
    clean = clean_request(agent_name=b.get("agent_name"), role=b.get("role"), capabilities=b.get("capabilities"),
                          client=b.get("client"))
    status = app.project.status()
    same_name = [a for a in status["agents"] if a["kind"] == "agent" and a["name"].casefold() == clean["name"].casefold()]
    warnings = []
    if same_name:
        warnings.append(f"{len(same_name)} agent(s) named '{clean['name']}' already exist in this project. "
                        "Names are labels; the new agent still gets its own id, but pick a distinct name to tell them apart.")
    text = build_onboarding(info, status, clean)
    app.activity.record(agent_id=HUMAN, action="agent.setup_prepared",
                        summary=f"Set Up Agent: instruction prepared for {clean['name']} ({clean['client']})",
                        target_type="project", target_id=info["id"],
                        details={"name": clean["name"], "role": clean["role"], "client": clean["client"],
                                 "capabilities": clean["capabilities"]})
    return ok({"prompt": text, "project": {"id": info["id"], "name": info["name"], "created_at": info["created_at"]},
               "agent": clean, "warnings": warnings})


# ---------------------------------------------------------------------- agents
@route("GET", "/v1/agents")
def agents_list(st: ApiState, req: Request, p: dict):
    return ok({"agents": st.require_app().agents.list(include_offline=q_bool(req, "include_offline", True))})


@route("GET", "/v1/agents/{agent_id}")
def agent_get(st: ApiState, req: Request, p: dict):
    return ok({"agent": st.require_app().agents.get(p["agent_id"])})


@route("POST", "/v1/agents/{agent_id}/remove")
def agent_remove(st: ApiState, req: Request, p: dict):
    """Human action: take an agent out of the project. Its sessions end, the tasks it holds go back to the backlog and
    it can no longer reconnect. Its history stays. (POST rather than DELETE: the record is kept.)"""
    return ok(st.require_app().agents.remove(HUMAN, p["agent_id"]))


# ----------------------------------------------------------------------- tasks
@route("GET", "/v1/tasks")
def tasks_list(st: ApiState, req: Request, p: dict):
    status = [s for s in req.query.get("status", "").split(",") if s] or None
    return ok(st.require_app().tasks.list(None, status=status, owner=req.query.get("owner"), label=req.query.get("label"),
                                          claimable_only=q_bool(req, "claimable_only"), include_closed=q_bool(req, "include_closed"),
                                          limit=q_int(req, "limit", 100, 1, 500)))


@route("GET", "/v1/tasks/{task_id}")
def task_get(st: ApiState, req: Request, p: dict):
    return ok({"task": st.require_app().tasks.get(p["task_id"])})


@route("POST", "/v1/tasks")
def task_create(st: ApiState, req: Request, p: dict):
    b = body_of(req, {"title", "description", "priority", "labels", "depends_on", "parent_id"}, {"title"})
    return ok({"task": st.require_app().tasks.create(HUMAN, **{"priority": "normal", **b})}, 201)


@route("POST", "/v1/tasks/{task_id}/cancel")
def task_cancel(st: ApiState, req: Request, p: dict):
    b = body_of(req, {"reason"}, {"reason"})
    return ok(st.require_app().tasks.cancel(HUMAN, p["task_id"], b["reason"]))


@route("POST", "/v1/tasks/{task_id}/release")
def task_release(st: ApiState, req: Request, p: dict):
    """Human override: free a stuck task so another agent can claim it."""
    return ok({"task": st.require_app().tasks.update(HUMAN, p["task_id"], status="open")})


# -------------------------------------------------------------------- activity
@route("GET", "/v1/activity")
def activity(st: ApiState, req: Request, p: dict):
    return ok(st.require_app().project.activity_feed(after_id=q_int(req, "after_id", None, 0, 2**62),
                                                     limit=q_int(req, "limit", 100, 1, 500), agent_ref=req.query.get("agent"),
                                                     action_prefix=req.query.get("action_prefix")))


# -------------------------------------------------------- messages and handoffs
@route("GET", "/v1/messages")
def messages(st: ApiState, req: Request, p: dict):
    return ok(st.require_app().messages.history(after_seq=q_int(req, "after_seq", 0, 0, 2**62),
                                                limit=q_int(req, "limit", 100, 1, 500), thread_id=req.query.get("thread_id"),
                                                agent_ref=req.query.get("agent")))


@route("POST", "/v1/messages")
def message_send(st: ApiState, req: Request, p: dict):
    b = body_of(req, {"to", "body", "subject", "kind", "task_id"}, {"to", "body"})
    return ok({"message": st.require_app().messages.send(HUMAN, to=b["to"], body=b["body"], subject=b.get("subject"),
                                                         kind=b.get("kind", "message"), task_id=b.get("task_id"))}, 201)


@route("GET", "/v1/handoffs")
def handoffs(st: ApiState, req: Request, p: dict):
    return ok(st.require_app().handoffs.list(None, status=req.query.get("status"), scope="all", task_id=req.query.get("task_id"),
                                             limit=q_int(req, "limit", 100, 1, 500)))


@route("GET", "/v1/handoffs/{handoff_id}")
def handoff_get(st: ApiState, req: Request, p: dict):
    return ok({"handoff": st.require_app().handoffs.get(p["handoff_id"])})


# ------------------------------------------------------------ memory, decisions
@route("GET", "/v1/memory")
def memory(st: ApiState, req: Request, p: dict):
    return ok(st.require_app().memory.read(query=req.query.get("query"), category=req.query.get("category"),
                                           limit=q_int(req, "limit", 50, 1, 200)))


@route("GET", "/v1/decisions")
def decisions(st: ApiState, req: Request, p: dict):
    return ok(st.require_app().memory.list_decisions(status=req.query.get("status", "active"), query=req.query.get("query"),
                                                     limit=q_int(req, "limit", 100, 1, 500)))


# ----------------------------------------------------------------------- files
@route("GET", "/v1/files")
def files_list(st: ApiState, req: Request, p: dict):
    return ok(st.require_app().files.list(req.query.get("path", "."), q_bool(req, "recursive"), q_int(req, "max_depth", None, 1, 10),
                                          q_bool(req, "include_hidden"), q_int(req, "limit", None, 1, 1000)))


@route("GET", "/v1/files/content")
def file_content(st: ApiState, req: Request, p: dict):
    if "path" not in req.query:
        raise HiveError(INVALID_ARGUMENT, "query parameter 'path' is required")
    return ok(st.require_app().files.read(req.query["path"], q_int(req, "start_line", 1, 1, 2**31), q_int(req, "max_lines", 2000, 1, 10000)))


@route("GET", "/v1/trash")
def trash_list(st: ApiState, req: Request, p: dict):
    return ok(st.require_app().files.list_trash())


@route("POST", "/v1/trash/{trash_id}/restore")
def trash_restore(st: ApiState, req: Request, p: dict):
    b = body_of(req, {"to_path"}) if req.body else {}
    return ok(st.require_app().files.restore(HUMAN, p["trash_id"], b.get("to_path")))


# the SSE stream is served by server.py (needs the socket); registered here so it is routed/authenticated/documented
@route("GET", "/v1/events")
def events(st: ApiState, req: Request, p: dict):                  # pragma: no cover - replaced by streaming in server.py
    raise HiveError(INTERNAL, "streaming endpoint")


def parse_query(raw: str) -> dict[str, str]:
    return {k: v[-1] for k, v in parse_qs(raw, keep_blank_values=True).items()}
