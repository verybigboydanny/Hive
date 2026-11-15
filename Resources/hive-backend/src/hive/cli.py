"""`hive` command line: init, mcp (stdio server), api (SwiftUI backend), status, projects, tools, gen-contract, doctor.

stdout is reserved: in `mcp` mode it carries the protocol, in `api` mode a single JSON 'ready' line. Diagnostics
and logs always go to stderr (and .hive/logs/hive.log)."""

from __future__ import annotations

import argparse
import asyncio
import importlib.util
import json
import signal
import sqlite3
import sys
from pathlib import Path

from . import CONTRACT_VERSION, __version__
from .app import HiveApp
from .errors import NOT_INITIALIZED, HiveError
from .logging_setup import setup_logging
from .projects import ProjectRegistry, default_home

EXIT_OK, EXIT_ERROR, EXIT_SDK_MISSING = 0, 2, 3


def _fail(exc: HiveError) -> int:
    print(json.dumps({"ok": False, "error": exc.to_dict()}), file=sys.stderr)
    return EXIT_ERROR


def _cmd_init(a) -> int:
    app = HiveApp.init(Path(a.path), a.name)
    info = app.project.info()
    print(json.dumps({"ok": True, "workspace": info["root"], "name": info["name"], "project_id": info["id"],
                      "schema_version": info["schema_version"]}))
    return EXIT_OK


def _cmd_status(a) -> int:
    app = HiveApp.open(Path(a.workspace))
    print(json.dumps({"health": app.health(), "status": app.project.status()}, indent=2))
    return EXIT_OK


def _cmd_tools(a) -> int:
    from .tools.catalog import ALL_TOOLS
    from .tools.docgen import render_tools_markdown
    if a.format == "markdown":
        print(render_tools_markdown())
    else:
        print(json.dumps([{"name": t.name, "group": t.group, "description": t.description, "inputSchema": t.input_schema,
                           "outputSchema": t.output_schema, "annotations": t.annotations} for t in ALL_TOOLS], indent=2))
    return EXIT_OK


def _cmd_gen_contract(a) -> int:
    from .tools.docgen import render_tools_markdown, splice
    p = Path(a.file)
    p.write_text(splice(p.read_text(encoding="utf-8"), render_tools_markdown()), encoding="utf-8")
    print(f"updated {p}", file=sys.stderr)
    return EXIT_OK


def _cmd_doctor(a) -> int:
    checks = {"python": sys.version.split()[0], "sqlite": sqlite3.sqlite_version, "backend_version": __version__,
              "contract_version": CONTRACT_VERSION, "mcp_sdk_installed": importlib.util.find_spec("mcp") is not None,
              "fastapi_installed": importlib.util.find_spec("fastapi") is not None,
              "project_registry": str(ProjectRegistry().path), "hive_home": str(default_home())}
    try:
        checks["registered_projects"] = len(ProjectRegistry().list())
    except Exception as exc:                                    # doctor must report, not crash
        checks["registered_projects"] = f"error: {exc}"
    if a.workspace:
        try:
            checks["workspace_health"] = HiveApp.open(Path(a.workspace)).health()
        except HiveError as exc:
            checks["workspace_health"] = {"status": "error", "error": exc.to_dict()}
    print(json.dumps(checks, indent=2))
    return EXIT_OK


def _cmd_mcp(a) -> int:
    from .mcp_server.router import ProjectRouter
    try:
        if a.workspace:                                        # pinned mode (original behaviour)
            try:
                app = HiveApp.open(Path(a.workspace))
            except HiveError as exc:
                if exc.code == NOT_INITIALIZED and a.init:
                    app = HiveApp.init(Path(a.workspace))
                else:
                    return _fail(exc)
            setup_logging(app.ws.hive_dir, level=a.log_level, to_stderr=True)
            router = ProjectRouter(pinned=app)
        else:                                                  # project-agnostic: agents name their project explicitly
            setup_logging(None, level=a.log_level, to_stderr=True)
            router = ProjectRouter()
    except Exception as exc:                                    # pragma: no cover - startup safety net
        print(f"hive: cannot start: {exc}", file=sys.stderr)
        return EXIT_ERROR
    from .mcp_server.server import SdkMissing, serve_stdio

    async def run():
        task = asyncio.current_task()
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            try:
                loop.add_signal_handler(sig, task.cancel)       # graceful shutdown -> sessions marked disconnected
            except NotImplementedError:                          # pragma: no cover
                pass
        await serve_stdio(router)
    try:
        asyncio.run(run())
    except SdkMissing as exc:
        print(f"hive: {exc}", file=sys.stderr)
        return EXIT_SDK_MISSING
    except asyncio.CancelledError:
        pass
    finally:
        router.close_all("process exit")
    return EXIT_OK


def _cmd_projects(a) -> int:
    reg = ProjectRegistry()
    print(json.dumps({"registry": str(reg.path), "projects": reg.list()}, indent=2))
    return EXIT_OK


def _cmd_api(a) -> int:
    from .api.server import run_api
    return run_api(workspace=a.workspace, host=a.host, port=a.port, token=a.token, log_level=a.log_level)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="hive", description="Hive backend: shared workspace for independent AI agents (MCP).")
    p.add_argument("--version", action="version", version=f"hive {__version__} (contract {CONTRACT_VERSION})")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("init", help="initialise a workspace (.hive/, database, migrations)")
    s.add_argument("path"); s.add_argument("--name"); s.set_defaults(fn=_cmd_init)
    s = sub.add_parser("mcp", help="run the MCP server on stdio (launched by an MCP client)")
    s.add_argument("--workspace", help="pin this server to one project folder (legacy). Omit it for a project-agnostic "
                                       "server: agents then name their project with agent_register(project_id=...)")
    s.add_argument("--init", action="store_true", help="with --workspace: initialise the folder if it is not a workspace yet")
    s.add_argument("--log-level", default="INFO"); s.set_defaults(fn=_cmd_mcp)
    s = sub.add_parser("api", help="run the local HTTP API for the SwiftUI app")
    s.add_argument("--workspace"); s.add_argument("--host", default="127.0.0.1"); s.add_argument("--port", type=int, default=0)
    s.add_argument("--token", help="bearer token (default: random, printed once in the ready line)")
    s.add_argument("--log-level", default="INFO"); s.set_defaults(fn=_cmd_api)
    s = sub.add_parser("status", help="print health and project status as JSON")
    s.add_argument("--workspace", required=True); s.set_defaults(fn=_cmd_status)
    s = sub.add_parser("tools", help="print the tool catalogue")
    s.add_argument("--format", choices=["json", "markdown"], default="json"); s.set_defaults(fn=_cmd_tools)
    s = sub.add_parser("gen-contract", help="regenerate the tool reference inside docs/backend-contract.md")
    s.add_argument("--file", default="docs/backend-contract.md"); s.set_defaults(fn=_cmd_gen_contract)
    s = sub.add_parser("projects", help="list the projects registered on this machine (id, name, folder)")
    s.set_defaults(fn=_cmd_projects)
    s = sub.add_parser("doctor", help="check the environment (and optionally a workspace)")
    s.add_argument("--workspace"); s.set_defaults(fn=_cmd_doctor)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.fn(args)
    except HiveError as exc:
        return _fail(exc)


if __name__ == "__main__":      # pragma: no cover
    sys.exit(main())
