"""ProjectRouter: decides which workspace an MCP connection talks to, explicitly and verifiably.

Two modes, one object:

  * PINNED (`hive mcp --workspace DIR`, the original behaviour, still supported): every call goes to that one
    workspace. `agent_register` still honours `project_id` and refuses a mismatch, so an old config that points
    at yesterday's folder can no longer silently register an agent there.

  * MULTI-PROJECT (`hive mcp` with no --workspace, what Hive now writes into client configs): the process is
    project-agnostic. The project is chosen by the `project_id` the agent passes to `agent_register` (given to it
    by Hive's Set Up Agent instruction). The id is resolved through the machine-wide ProjectRegistry and
    re-verified against the id stored inside that workspace's database. The connection is then bound to that
    project until it registers again; other tools are routed to the bound project only. Nothing about a
    previously used folder, a working directory or an earlier registration can influence the choice.
"""

from __future__ import annotations

import logging
import threading
from typing import Any, Callable

from ..app import HiveApp
from ..errors import (AGENT_NOT_REGISTERED, PROJECT_REQUIRED, PROJECT_UNKNOWN, HiveError)
from ..projects import ProjectRegistry
from ..tools.registry import ToolRegistry, ToolResult
from ..util import PROJECT_ID_RE
from .surface import McpSurface, prompts_list, resources_list, tools_list

log = logging.getLogger("hive.mcp.router")

_ONBOARD_HINT = ("Hive needs to know the project. Use the exact `project_id` from the instruction you were given in "
                 "Hive's Set Up Agent screen. If you have none, ask the user to open the project in Hive and send you "
                 "a new instruction. Do not guess a project from an earlier registration or the working directory.")


def _fail(exc: HiveError) -> ToolResult:
    return ToolResult(False, {"ok": False, "error": exc.to_dict()})


class ProjectRouter:
    def __init__(self, *, pinned: HiveApp | None = None, registry: ProjectRegistry | None = None,
                 opener: Callable[..., HiveApp] | None = None) -> None:
        self.registry = registry or ProjectRegistry()
        self._opener = opener or (lambda root: HiveApp.open(root, registry=self.registry))
        self._lock = threading.RLock()
        self._surfaces: dict[str, McpSurface] = {}      # project id -> surface (one HiveApp per project)
        self._bindings: dict[str, str] = {}             # connection key -> project id
        self.pinned_id: str | None = None
        if pinned is not None:
            surface = McpSurface(pinned)
            self.pinned_id = pinned.project.info()["id"]
            self._surfaces[self.pinned_id] = surface

    @property
    def multi(self) -> bool:
        return self.pinned_id is None

    # --------------------------------------------------------------- static views
    def tools(self) -> list[dict[str, Any]]:
        return tools_list(ToolRegistry(None).specs())

    def resources(self) -> list[dict[str, Any]]:
        return resources_list()

    def prompts(self) -> list[dict[str, Any]]:
        return prompts_list()

    # ------------------------------------------------------------------ resolving
    def _surface_for_project(self, project_id: Any) -> McpSurface:
        if not isinstance(project_id, str) or not project_id.strip():
            raise HiveError(PROJECT_REQUIRED, "agent_register needs a project_id on this connection", hint=_ONBOARD_HINT)
        project_id = project_id.strip()
        with self._lock:
            cached = self._surfaces.get(project_id)
            if cached is not None:
                if cached.app.ws.db_path.is_file():
                    return cached
                self._surfaces.pop(project_id, None)           # folder moved or deleted: resolve afresh
            unknown = HiveError(PROJECT_UNKNOWN, f"no Hive project with id '{project_id[:40]}' is available on this machine",
                                hint="Open that project in the Hive app once (this registers it) and ask for a new "
                                     "instruction from Set Up Agent. Do not try other ids or folders.")
            if not PROJECT_ID_RE.match(project_id):
                raise unknown
            root = self.registry.resolve(project_id)
            if root is None:
                raise unknown
            try:
                app = self._opener(root)
            except HiveError as exc:
                log.warning("project %s resolves to %s which cannot be opened: %s", project_id, root, exc.message)
                raise unknown from None
            if app.project.info()["id"] != project_id:
                log.warning("folder %s no longer holds project %s", root, project_id)
                app.close()
                raise unknown
            surface = McpSurface(app)
            self._surfaces[project_id] = surface
            return surface

    def _bound(self, key: str) -> McpSurface | None:
        if not self.multi:
            return self._surfaces[self.pinned_id]
        with self._lock:
            pid = self._bindings.get(key)
            return self._surfaces.get(pid) if pid else None

    def surface_of(self, key: str) -> McpSurface | None:
        return self._bound(key)

    def surfaces(self) -> list[McpSurface]:
        with self._lock:
            return list(self._surfaces.values())

    # ------------------------------------------------------------------------ calls
    def call_tool(self, name: str, arguments: dict | None, session_key: str, client_info: dict | None = None) -> ToolResult:
        if not self.multi:
            return self._surfaces[self.pinned_id].call_tool(name, arguments, session_key, client_info)
        if name == "agent_register":
            asked = arguments.get("project_id") if isinstance(arguments, dict) else None
            try:
                surface = self._surface_for_project(asked)
            except HiveError as exc:
                return _fail(exc)
            result = surface.call_tool(name, arguments, session_key, client_info)
            if result.ok:
                self._rebind(session_key, asked.strip(), surface)
            return result
        surface = self._bound(session_key)
        if surface is None:
            return _fail(HiveError(AGENT_NOT_REGISTERED, "this connection has no registered agent",
                                   hint="Call agent_register first with the project_id from your onboarding instruction "
                                        "(and agent_id + resume_token to keep an existing identity)."))
        return surface.call_tool(name, arguments, session_key, client_info)

    def _rebind(self, key: str, project_id: str, surface: McpSurface) -> None:
        with self._lock:
            previous = self._bindings.get(key)
            self._bindings[key] = project_id
            old = self._surfaces.get(previous) if previous and previous != project_id else None
        if old is not None:                                    # the connection moved projects: close its old session
            old.registry.close_session(key, "connection registered under another project")

    def read_resource(self, uri: str, session_key: str) -> dict[str, Any]:
        surface = self._bound(session_key)
        if surface is None:
            raise HiveError(PROJECT_REQUIRED, "resources become available after agent_register selects the project",
                            hint=_ONBOARD_HINT)
        return surface.read_resource(uri)

    def get_prompt(self, name: str, arguments: dict | None, session_key: str) -> dict[str, Any]:
        surface = self._bound(session_key)
        if surface is None and isinstance(arguments, dict) and name in ("hive_onboard", "hive_resume"):
            surface = self._surface_for_project(arguments.get("project_id"))
        if surface is None:
            raise HiveError(PROJECT_REQUIRED, f"prompt '{name}' needs a project_id on this connection", hint=_ONBOARD_HINT)
        return surface.get_prompt(name, arguments)

    def close_all(self, reason: str = "server shutdown") -> None:
        for surface in self.surfaces():
            surface.registry.close_all(reason)
        for surface in self.surfaces():
            surface.app.close()
