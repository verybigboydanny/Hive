"""Transport-independent MCP surface: tools, resources, prompts, change detection.

Everything the MCP server exposes is computed here as plain dicts so it can be tested without the SDK.
`server.py` only translates these structures into official-SDK types.
"""

from __future__ import annotations

import json
import re
from typing import Any

from ..app import HiveApp
from ..errors import INVALID_ARGUMENT, NOT_FOUND, PROJECT_MISMATCH, HiveError
from ..services.project import PROTOCOL_RULES
from ..tools.registry import ToolRegistry, ToolResult, ToolSpec
from ..tools.schema import client_schema

JSON = "application/json"
MD = "text/markdown"

_RESOURCES = [
    ("hive://project/status", "Project status", "Task counts, agents, handoffs, git state, recent activity.", JSON),
    ("hive://project/context", "Project context", "Rules, active decisions, shared memory, online agents, recent activity.", JSON),
    ("hive://project/rules", "Project rules", "Built-in Hive working rules plus project rules stored in memory (category 'rules').", MD),
    ("hive://tasks", "Tasks", "All open tasks (id, status, owner, lease, blockers).", JSON),
    ("hive://agents", "Agents", "Registered agents with presence and current tasks.", JSON),
    ("hive://decisions", "Decisions", "Active architectural/project decisions.", JSON),
    ("hive://memory", "Shared memory", "Most recently updated shared memory entries.", JSON),
    ("hive://activity", "Activity", "The latest 50 activity events (actor, action, timestamp).", JSON),
]

# which resources a given activity action invalidates (status/activity always change)
_INVALIDATES = {"task.": ["hive://tasks"], "agent.": ["hive://agents"], "memory.": ["hive://memory", "hive://project/rules", "hive://project/context"],
                "decision.": ["hive://decisions", "hive://project/context"], "handoff.": ["hive://tasks"],
                "checkpoint.": ["hive://tasks"]}

_PROMPTS = {
    "hive_onboard": ("Onboard yourself into a Hive project: register, load context, learn the rules.",
                     [("agent_name", "Display name to register with.", False), ("role", "What you will work on.", False),
                      ("project_id", "Hive project id (prj_...) from Set Up Agent.", False)]),
    "hive_resume": ("Resume after an interruption or disconnect: reconnect with your saved identity and pick up your work.",
                    [("agent_id", "Your saved agent_id.", False),
                     ("project_id", "Hive project id (prj_...) from Set Up Agent.", False)]),
    "hive_handoff": ("Hand your current work to another agent with complete context.",
                     [("task_id", "Task you are handing over.", False), ("to", "Recipient agent id (omit for any agent).", False)]),
}


def tools_list(specs: list[ToolSpec]) -> list[dict[str, Any]]:
    """tools/list payload. Schemas are the portable client form (see tools.schema.client_schema); the strict
    internal schema is still what validates every call."""
    return [{"name": s.name, "description": s.description, "inputSchema": client_schema(s.input_schema),
             "annotations": s.annotations} for s in specs]


def resources_list() -> list[dict[str, Any]]:
    return [{"uri": u, "name": n, "description": d, "mimeType": m} for u, n, d, m in _RESOURCES]


def prompts_list() -> list[dict[str, Any]]:
    return [{"name": n, "description": d, "arguments": [{"name": an, "description": ad, "required": req}
                                                         for an, ad, req in args]} for n, (d, args) in _PROMPTS.items()]


class McpSurface:
    def __init__(self, app: HiveApp, registry: ToolRegistry | None = None) -> None:
        self.app = app
        self.registry = registry or ToolRegistry(app)

    # ------------------------------------------------------------------- tools
    def tools(self) -> list[dict[str, Any]]:
        return tools_list(self.registry.specs())

    def call_tool(self, name: str, arguments: dict | None, session_key: str, client_info: dict | None = None) -> ToolResult:
        return self.registry.call_sync(name, arguments, session_key, client_info=client_info)

    # --------------------------------------------------------------- resources
    def resources(self) -> list[dict[str, Any]]:
        return resources_list()

    def read_resource(self, uri: str) -> dict[str, Any]:
        uri = str(uri)
        a = self.app
        if uri == "hive://project/status":
            body: Any = a.project.status()
        elif uri == "hive://project/context":
            body = a.project.context(None)
        elif uri == "hive://project/rules":
            r = a.project.rules()
            extra = "\n".join(f"## {e['key']}\n{e['value']}\n" for e in r["project_rules"])
            return {"uri": uri, "mimeType": MD, "text": r["protocol"] + ("\n# Project rules\n" + extra if extra else "")}
        elif uri == "hive://tasks":
            body = a.tasks.list(None, limit=500)
        elif uri.startswith("hive://tasks/"):
            body = {"task": a.tasks.get(uri[len("hive://tasks/"):])}
        elif uri == "hive://agents":
            body = {"agents": a.agents.list()}
        elif uri == "hive://decisions":
            body = a.memory.list_decisions(status="active", limit=200)
        elif uri == "hive://memory":
            body = a.memory.read(limit=50)
        elif uri == "hive://activity":
            body = a.project.activity_feed(limit=50)
        else:
            raise HiveError(NOT_FOUND, f"unknown resource {uri}", hint="Use resources/list.")
        return {"uri": uri, "mimeType": JSON, "text": json.dumps(body, ensure_ascii=False, indent=2)}

    def changed_resources(self, after_id: int) -> tuple[int, set[str]]:
        """Resource URIs invalidated by activity newer than `after_id` (for resources/updated notifications)."""
        feed = self.app.activity.query(after_id=after_id, limit=500)
        if not feed["entries"]:
            return after_id, set()
        uris = {"hive://project/status", "hive://activity"}
        for e in feed["entries"]:
            for prefix, targets in _INVALIDATES.items():
                if e["action"].startswith(prefix):
                    uris.update(targets)
        return feed["next_cursor"], uris

    def activity_cursor(self) -> int:
        with self.app.db.read() as c:
            return c.execute("SELECT COALESCE(MAX(id), 0) FROM activity").fetchone()[0]

    # ----------------------------------------------------------------- prompts
    def prompts(self) -> list[dict[str, Any]]:
        return prompts_list()

    def get_prompt(self, name: str, arguments: dict | None = None) -> dict[str, Any]:
        if name not in _PROMPTS:
            raise HiveError(NOT_FOUND, f"unknown prompt '{name}'")
        args = arguments or {}
        allowed = {an for an, _, _ in _PROMPTS[name][1]}
        for k, v in args.items():
            if k not in allowed or not isinstance(v, str) or len(v) > 200:
                raise HiveError(INVALID_ARGUMENT, f"bad prompt argument '{k}'", {"allowed": sorted(allowed)})
        info = self.app.project.info()
        asked = args.get("project_id")
        if asked is not None and asked != info["id"]:
            raise HiveError(PROJECT_MISMATCH, "this connection belongs to a different Hive project",
                            {"requested_project_id": asked, "bound_project": {"id": info["id"], "name": info["name"]}},
                            hint="Ask the user for a fresh instruction from Set Up Agent in the project they mean.")
        pid = info["id"]
        st = self.app.project.status()
        online = [x for x in st["agents"] if x["kind"] == "agent" and x["presence"] != "offline"]
        header = (f"You are joining the Hive project '{info['name']}' (project_id {pid}; {len(online)} other agent(s) online, "
                  f"{st['tasks']['counts']['open']} open task(s)). Hive coordinates several independent AI agents; "
                  "you keep your own model and client.\n\n")
        if name == "hive_onboard":
            who = args.get("agent_name") or "<your name>"
            role = args.get("role")
            text = (header + "Do this now:\n"
                    f"1. Call `agent_register` with project_id='{pid}', name='{who}'" + (f", role='{role}'" if role else "") +
                    ". Save the returned `agent_id` and `resume_token`.\n"
                    "2. Call `agent_get_context` and read your tasks, inbox, handoffs and rules.\n"
                    "3. Pick a task with `task_list` (claimable_only=true) and `task_claim` it, or ask the user.\n"
                    "4. Work through the file tools, record progress with `task_update`, and `save_checkpoint` at milestones.\n\n"
                    + PROTOCOL_RULES)
        elif name == "hive_resume":
            aid = args.get("agent_id")
            text = (header + "You are resuming after an interruption.\n"
                    f"1. Call `agent_register` with project_id='{pid}', agent_id='{aid or '<saved agent_id>'}' and your saved `resume_token` "
                    "(if you lost them, register again as a new agent).\n"
                    "2. Call `agent_get_context`; check `my_tasks`, `pending_handoffs` and `last_checkpoint`.\n"
                    "3. Call `message_inbox`, handle messages, then `message_mark_read`.\n"
                    "4. Call `restore_checkpoint` (claim_task=true) to continue, then re-read any file before editing it.\n")
        else:
            tid, to = args.get("task_id"), args.get("to")
            text = (header + "Prepare a handoff:\n"
                    "1. Finish or checkpoint what you can: `save_checkpoint`.\n"
                    f"2. Call `handoff_create` with summary, completed_work, remaining_work, files_modified, next_action, context"
                    + (f", task_id='{tid}'" if tid else "") + (f", to='{to}'" if to else "") + ".\n"
                    "3. Tell the recipient with `send_message` if urgent. Ownership moves when they call `handoff_accept`.\n")
        return {"description": _PROMPTS[name][0], "messages": [{"role": "user", "content": {"type": "text", "text": text}}]}


TOOL_NAME_RE = re.compile(r"`([a-z_]+)`")
