#!/usr/bin/env python3
"""End-to-end check of Hive's MCP server through the REAL MCP SDK client over stdio.

Needs the SDK:   python3 -m venv .venv && .venv/bin/pip install 'mcp>=1.2,<2' && .venv/bin/python scripts/verify_mcp.py

It starts `python -m hive mcp` as a subprocess (exactly how an AI client does) in two modes, using throw-away
projects and a throw-away HIVE_HOME, and checks the behaviour that matters:

  project-agnostic server : registers under the EXPLICIT project, context is that project's, missing/unknown project
                            ids are refused, nothing is written to the other project
  pinned (legacy) server  : registering for a different project is refused
  tool schemas            : none of the constructs Gemini-based clients (Google Antigravity) reject

It does NOT test a specific client (Claude, Antigravity, ...). To test one, add Hive to that client, send the
instruction from Set Up Agent and confirm the agent appears under the project on Hive's Agents page.
"""

from __future__ import annotations

import asyncio
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Resources" / "hive-backend" / "src"
FORBIDDEN = {"additionalProperties", "propertyNames", "$ref", "$defs", "anyOf", "oneOf", "allOf", "exclusiveMinimum", "exclusiveMaximum"}
results: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    results.append((name, bool(ok), detail))
    print(("PASS  " if ok else "FAIL  ") + name + (f"  [{detail}]" if detail and not ok else ""))


def hive(env, *args):
    return subprocess.run([sys.executable, "-m", "hive", *args], capture_output=True, text=True, env=env, check=True).stdout


def lint(node, path="$", top=True):
    bad = []
    if isinstance(node, dict):
        t = node.get("type")
        if isinstance(t, list): bad.append(f"{path}: type list")
        if t == "array" and "items" not in node: bad.append(f"{path}: array without items")
        if "enum" in node and t != "string": bad.append(f"{path}: non-string enum")
        if t == "object" and not top and not node.get("properties"): bad.append(f"{path}: object without properties")
        bad += [f"{path}: {k}" for k in node if k in FORBIDDEN]
        for k, v in node.items():
            if k == "properties":
                for n, sub in v.items(): bad += lint(sub, f"{path}.{n}", False)
            elif k == "items": bad += lint(v, f"{path}[]", False)
    return bad


def payload(result):
    text = result.content[0].text
    try:
        return json.loads(text)
    except ValueError:
        return {"raw": text}


async def run(env, projects):
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client
    (path_a, id_a), (path_b, id_b) = projects

    # ---------------------------------------------------------------- project-agnostic server
    params = StdioServerParameters(command=sys.executable, args=["-m", "hive", "mcp"], env=env)
    async with stdio_client(params) as (r, w), ClientSession(r, w) as s:
        await s.initialize()
        tools = (await s.list_tools()).tools
        check("lists 33 tools", len(tools) == 33, str(len(tools)))
        problems = [f"{t.name} {p}" for t in tools for p in lint(t.inputSchema)]
        check("advertised schemas are Gemini/Antigravity-portable", not problems, "; ".join(problems[:5]))

        r1 = await s.call_tool("agent_register", {"name": "NoProject"})
        check("registering without project_id is refused", r1.isError and "PROJECT_REQUIRED" in r1.content[0].text)
        r2 = await s.call_tool("agent_register", {"name": "Ghost", "project_id": "prj_0000000000000000"})
        check("unknown project_id is refused", r2.isError and "PROJECT_UNKNOWN" in r2.content[0].text)

        reg = await s.call_tool("agent_register", {"name": "Verifier", "client": "claude", "role": "e2e", "project_id": id_b})
        data = payload(reg).get("data", {})
        check("registers under the explicitly named project", not reg.isError and data.get("project", {}).get("id") == id_b, str(payload(reg))[:200])
        check("resume_token returned once", bool(data.get("resume_token")))
        ctx = payload(await s.call_tool("agent_get_context", {})).get("data", {})
        check("context is the selected project's", ctx.get("project", {}).get("id") == id_b)
        check("context has the fields the onboarding instruction names",
              {"rules", "my_tasks", "claimable_tasks", "inbox", "pending_handoffs"} <= set(ctx))
        cp = await s.call_tool("save_checkpoint", {"summary": "e2e", "state": {"k": 1}})
        check("object-valued `state` still accepted", not cp.isError, cp.content[0].text[:120])
        cp2 = await s.call_tool("save_checkpoint", {"summary": "e2e", "state": "{\"k\": 2}"})
        check("JSON-string `state` (as advertised) accepted", not cp2.isError, cp2.content[0].text[:120])

    # reconnect from a fresh process (persistence across restarts)
    async with stdio_client(params) as (r, w), ClientSession(r, w) as s:
        await s.initialize()
        again = await s.call_tool("agent_register", {"name": "Verifier", "project_id": id_b,
                                                     "agent_id": data["agent"]["id"], "resume_token": data["resume_token"]})
        check("reconnects after a server restart with the same identity", payload(again).get("data", {}).get("resumed") is True)

    # ---------------------------------------------------------------- pinned (legacy) server pinned to A
    params = StdioServerParameters(command=sys.executable, args=["-m", "hive", "mcp", "--workspace", str(path_a)], env=env)
    async with stdio_client(params) as (r, w), ClientSession(r, w) as s:
        await s.initialize()
        stale = await s.call_tool("agent_register", {"name": "Stale", "project_id": id_b})
        check("pinned server refuses another project's id", stale.isError and "PROJECT_MISMATCH" in stale.content[0].text)

    names_a = json.loads(hive(env, "status", "--workspace", str(path_a)))["status"]["agents"]
    check("nothing was registered in the other project", [a["name"] for a in names_a if a["kind"] == "agent"] == [])


def main() -> int:
    try:
        import mcp  # noqa: F401
    except ImportError:
        print("The MCP SDK is not installed: pip install 'mcp>=1.2,<2'", file=sys.stderr)
        return 3
    with tempfile.TemporaryDirectory(prefix="hive-verify-") as tmp:
        tmp = Path(tmp)
        env = {**os.environ, "PYTHONPATH": str(SRC), "HIVE_HOME": str(tmp / "home")}
        projects = []
        for name in ("verify-A", "verify-B"):
            p = tmp / name
            p.mkdir()
            projects.append((p, json.loads(hive(env, "init", str(p), "--name", name))["project_id"]))
        asyncio.run(run(env, projects))
    failed = [r for r in results if not r[1]]
    print(f"\n{len(results) - len(failed)}/{len(results)} checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
