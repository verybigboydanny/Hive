# Connecting AI apps to Hive

Hive runs a local MCP server over stdio: `python -m hive mcp`. Your AI app launches it; Hive never runs or proxies an
LLM. **The server is not tied to a project.** One entry in an app's config serves every Hive project.

## Add Hive to an app

1. Open Hive → **Settings → Apps & MCP**, tick the apps, press **Add Hive to …**. Hive creates `~/.hive-mcp-venv`
   (Python 3.11+, `mcp>=1.2,<2`), merges one `hive` entry into each app's config and backs up every file it changes
   (`*.hive-backup-<timestamp>`).
2. Quit and reopen each app once.
3. In Hive, open a project and use **Set Up Agent** (see [agent-onboarding.md](agent-onboarding.md)).

Re-running step 1 also upgrades an older entry that was pinned to a folder (`--workspace …`): it overwrites the entry
named `hive`. An entry you named differently stays pinned; it is safe (a mismatching `project_id` is refused with
`PROJECT_MISMATCH`, nothing is registered) but only usable for that folder.

## Where each app keeps its config

| App | File |
|---|---|
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` (profiles: `~/.claude-instances/<name>/…`) |
| Claude Code | `claude mcp add …` (see `examples/claude_code_add.example.txt`) |
| **Google Antigravity** (IDE, CLI, 2.0) | `~/.gemini/config/mcp_config.json`, shared by all three. A workspace-only file `.agents/mcp_config.json` also exists |
| Cursor / Windsurf / Copilot / VS Code / Zed / Codex | see `MCPClientTarget.swift` |

## Google Antigravity: what Hive does differently, and why

These are the failure modes investigated. Their causes come from Google's and third parties' public documentation
and issue reports; **none was reproduced against a real Antigravity install** (none was available).

| Risk | What Hive does | Evidence level |
|---|---|---|
| Gemini rejects a whole request if any tool declaration uses an unsupported schema construct (shows as a connected server and a failing agent) | Advertises a portable schema (no `additionalProperties`, no schema-less objects), keeps strict validation server-side. Linted by `tests/test_schema_portability.py` and `scripts/verify_mcp.py` | Audit of Hive's own 33 schemas: all 33 carried `additionalProperties`, 2 had schema-less objects. That Antigravity itself rejects them is **inferred** from Gemini-API reports |
| `env` may not reach the server process, so `import hive` fails | Antigravity's entry passes `PYTHONPATH` through `/usr/bin/env` instead of an `env` block | One third-party report; **unverified** |
| Antigravity IDE, CLI and 2.0 share `~/.gemini/config/mcp_config.json`; the CLI's own `mcp/` folder is generated | The duplicate `antigravity-cli/mcp_config.json` target was removed | Google codelab and community write-ups |
| Config baked one project folder in | Project-agnostic entry + explicit `project_id` | Same root cause as other clients; fixed and tested |

If Antigravity still misbehaves: Antigravity → agent panel → **MCP Servers → Manage MCP Servers** (check the server
and tool list), then run `PYTHONPATH=<backend src> python -m hive doctor` and `scripts/verify_mcp.py`.

## Troubleshooting

* `hive: The official MCP SDK is not installed` (exit 3): run the Add Hive step again, or `pip install 'mcp>=1.2,<2'`
  into the venv the entry points to. SDK 2.x is not supported.
* `PROJECT_UNKNOWN`: the project was never opened in Hive on this machine (the app registers a project when it opens
  it), or its folder moved and was not reopened. Open it in Hive, then generate a new instruction.
* `PROJECT_MISMATCH`: the entry is pinned to another folder. Re-add Hive from Apps & MCP.
* `python -m hive projects` lists the registered projects; `python -m hive doctor` checks the environment.
* The app shows no Hive tools: check the config file is valid JSON and the paths in it exist, then quit and reopen the
  app completely.
* The server stops right after it starts: run `python -m hive doctor`. If `mcp_sdk_installed` is `false` the SDK is
  missing from that environment. If the server complains about `list_tools`, the SDK is too new: reinstall
  `mcp>=1.2,<2`.
* `No module named hive`: `PYTHONPATH` does not point at the folder that contains the `hive` package
  (`…/hive-backend/src`).
* Python too old: Hive needs 3.11 or later. Recreate `~/.hive-mcp-venv` with a newer Python (for example Homebrew's).
* It worked, then stopped after rebuilding Hive: the backend path points inside the Xcode build folder. Run Hive from
  Applications (or copy `hive-backend` somewhere permanent) and run Add Hive again.
* Stdout of `hive mcp` carries the protocol: never add `print()` to the backend.
