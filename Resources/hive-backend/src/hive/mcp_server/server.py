"""Adapter between the official MCP Python SDK (`pip install mcp`) and Hive's transport-independent surface.

VERIFICATION STATUS: written against the SDK's documented low-level Server API. Everything this file calls
(ProjectRouter / McpSurface / ToolRegistry) is covered by the test-suite, and tests/test_adapter_wiring.py drives
this file's handlers against a *stub* of the SDK API surface. It has NOT been run against the real SDK in the
build environment (no network): run `python scripts/verify_mcp.py` on a machine with `pip install 'mcp>=1.2,<2'`.

Transport: stdio, one server process per MCP client. Several clients (Claude, GPT-compatible clients, Gemini, ...)
therefore run as separate processes that share one workspace through SQLite (WAL, BEGIN IMMEDIATE) and the
workspace file lock; every process polls the shared activity log to emit resource-updated notifications, so a
change made by any agent reaches every subscribed client.
"""

from __future__ import annotations

import asyncio
import json
import logging

from .. import __version__
from ..errors import HiveError
from .router import ProjectRouter

log = logging.getLogger("hive.mcp")

INSTRUCTIONS = (
    "Hive is a shared workspace where several independent AI agents coordinate on one project. "
    "Call agent_register first with the project_id from your onboarding instruction, then agent_get_context. "
    "Claim tasks before working, read files before editing them "
    "and pass expected_sha256 when writing, checkpoint at milestones, and use handoffs to transfer work. Every tool "
    "result includes `notices` (unread messages, pending handoffs, expiring leases): act on them. Hive cannot wake "
    "other agents; messages and handoffs wait in their inbox.")


class SdkMissing(RuntimeError):
    pass


class HiveToolError(Exception):
    """Raised for failed tool calls; the SDK turns it into a CallToolResult with isError=true whose text is the JSON envelope."""


def _client_info(session) -> dict:
    try:
        ci = session.client_params.clientInfo
        return {"name": ci.name, "version": ci.version}
    except Exception:
        return {}


def build_server(router: ProjectRouter):
    try:
        from mcp import types
        from mcp.server import Server
        from pydantic import AnyUrl
    except ImportError as exc:
        raise SdkMissing("The official MCP SDK is not installed. Install it with: pip install 'mcp>=1.2,<2'") from exc

    server = Server("hive")
    subscribers: dict[str, set] = {}

    def key() -> str:
        return str(id(server.request_context.session))

    @server.list_tools()
    async def list_tools():
        return [types.Tool(name=t["name"], description=t["description"], inputSchema=t["inputSchema"],
                           annotations=types.ToolAnnotations(**t["annotations"])) for t in router.tools()]

    @server.call_tool()
    async def call_tool(name: str, arguments: dict | None):
        session = server.request_context.session
        result = await asyncio.to_thread(router.call_tool, name, arguments, key(), _client_info(session))
        text = json.dumps(result.payload, ensure_ascii=False)
        if not result.ok:
            raise HiveToolError(text)
        return [types.TextContent(type="text", text=text)]

    @server.list_resources()
    async def list_resources():
        return [types.Resource(uri=AnyUrl(r["uri"]), name=r["name"], description=r["description"],
                               mimeType=r["mimeType"]) for r in router.resources()]

    @server.read_resource()
    async def read_resource(uri):
        try:
            return (await asyncio.to_thread(router.read_resource, str(uri), key()))["text"]
        except HiveError as exc:
            raise ValueError(json.dumps(exc.to_dict())) from None

    @server.subscribe_resource()
    async def subscribe(uri):
        subscribers.setdefault(str(uri), set()).add(server.request_context.session)

    @server.unsubscribe_resource()
    async def unsubscribe(uri):
        subscribers.get(str(uri), set()).discard(server.request_context.session)

    @server.list_prompts()
    async def list_prompts():
        return [types.Prompt(name=p["name"], description=p["description"],
                             arguments=[types.PromptArgument(name=a["name"], description=a["description"],
                                                             required=a["required"]) for a in p["arguments"]])
                for p in router.prompts()]

    @server.get_prompt()
    async def get_prompt(name: str, arguments: dict | None):
        try:
            p = await asyncio.to_thread(router.get_prompt, name, arguments, key())
        except HiveError as exc:
            raise ValueError(json.dumps(exc.to_dict())) from None
        return types.GetPromptResult(description=p["description"], messages=[
            types.PromptMessage(role=m["role"], content=types.TextContent(type="text", text=m["content"]["text"]))
            for m in p["messages"]])

    return server, router, subscribers


async def notify_loop(router: ProjectRouter, subscribers: dict[str, set], interval: float = 1.0) -> None:
    """Poll each open project's shared activity log and tell the subscribed connections BOUND TO THAT PROJECT
    which resources changed (also catches changes made by OTHER agent processes)."""
    from pydantic import AnyUrl
    cursors: dict[int, int] = {}
    while True:
        await asyncio.sleep(interval)
        for surface in router.surfaces():
            try:
                sid = id(surface)
                if sid not in cursors:
                    cursors[sid] = await asyncio.to_thread(surface.activity_cursor)
                    continue
                cursors[sid], uris = await asyncio.to_thread(surface.changed_resources, cursors[sid])
                for uri in uris:
                    for session in list(subscribers.get(uri, ())):
                        if router.surface_of(str(id(session))) is not surface:
                            continue
                        try:
                            await session.send_resource_updated(AnyUrl(uri))
                        except Exception:
                            subscribers[uri].discard(session)
            except asyncio.CancelledError:
                raise
            except Exception:
                log.exception("notification poll failed")


def _init_options(server):
    from mcp.server import NotificationOptions
    from mcp.server.models import InitializationOptions
    caps = server.get_capabilities(notification_options=NotificationOptions(resources_changed=True),
                                   experimental_capabilities={})
    try:
        return InitializationOptions(server_name="hive", server_version=__version__, capabilities=caps,
                                     instructions=INSTRUCTIONS)
    except TypeError:                                   # older SDKs have no `instructions`
        return InitializationOptions(server_name="hive", server_version=__version__, capabilities=caps)


async def serve_stdio(router: ProjectRouter) -> None:
    try:
        from mcp.server.stdio import stdio_server
    except ImportError as exc:
        raise SdkMissing("The official MCP SDK is not installed. Install it with: pip install 'mcp>=1.2,<2'") from exc
    server, router, subscribers = build_server(router)
    options = _init_options(server)
    log.info("hive MCP server starting on stdio (%s)",
             "multi-project" if router.multi else f"pinned to project {router.pinned_id}")
    async with stdio_server() as (read, write):
        poller = asyncio.create_task(notify_loop(router, subscribers))
        try:
            await server.run(read, write, options)
        finally:
            poller.cancel()
            router.close_all("stdio transport closed")          # persists disconnect state
            log.info("hive MCP server stopped")
