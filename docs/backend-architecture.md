# Hive backend architecture

Hive is a shared workspace and coordination layer for **independent AI agents**. Claude, GPT-compatible clients, Gemini and others connect
to Hive's MCP server on their own and use its tools to work on the same project. Hive does **not** run, proxy or route LLMs.

```
  Claude client        GPT client         Gemini / Antigravity       SwiftUI macOS app (the human)
       |                    |                   |                            |
   hive mcp             hive mcp            hive mcp                    hive api  (loopback HTTP + SSE)
   (stdio proc)         (stdio proc)        (stdio proc)                 (one process, started by the app)
       \____________________|___________________|____________________________/
                                      |
                  HiveApp  (services, tool registry, project read-models)
                                      |
        .hive/hive.db (SQLite WAL)  +  real project files (atomic writes, flock)  +  .hive/trash, logs
```

Processes are independent: any number of `hive mcp` processes (one per MCP client) and at most one `hive api` process share a workspace through
SQLite (WAL, `BEGIN IMMEDIATE`) and a workspace file lock. None of them needs the others to be running.

## Layout (the original structure is preserved)

```
src/hive/
  errors.py            HiveError(code, message, details, hint=) + stable code constants           [reconstructed, extended]
  util.py              timestamps, ids, hashing, text validation helpers                          [reconstructed, extended]
  settings.py          HiveSettings from the optional "settings" object in .hive/config.json      [new]
  db/__init__.py       Database: WAL, foreign keys, write()=BEGIN IMMEDIATE, read()               [reconstructed]
  db/migrations.py     apply_migrations(): per-file transaction, schema_migrations, flock         [ORIGINAL, untouched]
  db/migrations/       001_initial.sql [reconstructed] · 002_coordination.sql [new] · 003_project_identity.sql [new]
  workspace.py         Workspace.init/open, resolve() path policy, fs_lock()                       [ORIGINAL, untouched]
  activity.py          log_in_txn() + ActivityService (append-only audit log + cursor)             [ORIGINAL, untouched]
  git.py               read-only git summary (fixed argv, timeout, no shell)                       [ORIGINAL, untouched]
  services/            agents, tasks, messages, handoffs, checkpoints, memory, files, project       [new; services/ was an empty dir]
  tools/               registry.py (validation, identity, notices, audit) · catalog.py (33 tools) · schema.py (validation + portable client schemas) · outputs.py · docgen.py
  mcp_server/          surface.py (tools/resources/prompts/change-detection, SDK-free) · server.py (official-SDK adapter)
  api/                 routes.py (framework-independent) · server.py (stdlib HTTP, auth, SSE)
  projects.py          ProjectRegistry: machine-wide map project id -> folder ($HIVE_HOME or ~/.hive)             [new]
  onboarding.py        Set Up Agent: builds the per-agent onboarding instruction from live state                  [new]
  mcp_server/router.py ProjectRouter: pinned or project-agnostic routing, explicit project per connection         [new]
  app.py               HiveApp: init/open/migrate/close/health, assigns the project id, wires every service
  cli.py, __main__.py  `hive init | mcp | api | status | projects | tools | gen-contract | doctor`
  logging_setup.py     file + stderr logging (never stdout)
```

## Project identity and explicit association

A project used to be identified only by its folder. An MCP client's config is global and, in the original design,
baked one `--workspace` folder into it, while `agent_register` had no way to name a project. An agent therefore
registered in whichever folder the config pointed at (often an earlier project), silently.

Now:

1. Every workspace has a stable project id (`project.uid`, migration 003, assigned on first open, atomic across
   processes). Copied folders are detected and given their own id; moved folders keep theirs.
2. `agent_register(project_id=...)` is the explicit association. A pinned server refuses a mismatch before writing
   anything (`PROJECT_MISMATCH`, audited as `agent.register_refused`).
3. Client configs use the project-agnostic `hive mcp` (no `--workspace`). `ProjectRouter` resolves the id through
   `ProjectRegistry` and re-verifies it against the id inside the workspace. One config entry serves every project.
4. Set Up Agent (`POST /v1/onboarding/prompt`) generates the instruction that carries the exact id.

Residual risk: a project id is a locator, not a secret. Any process running as the same OS user can already read
the workspace folders, so the registry adds no new capability, but an agent that is told another project's id can
register there. Agents never supply paths.

## Principles

1. **SQLite is the source of truth for coordination data**; project files stay real files in the workspace.
2. **One path choke point**: every file operation (agents and UI) goes through `Workspace.resolve`.
3. **Transactions everywhere**: a service call is one `BEGIN IMMEDIATE` transaction that includes its audit entry. Races are resolved by the
   database, not by in-process locks (which would not work across the per-client processes).
4. **Transport-independent core**: services -> tool registry -> `McpSurface`. The MCP SDK adapter and the HTTP API are thin layers, so almost everything
   is testable without third-party packages.
5. **Pull-based coordination**: nothing can wake an idle LLM client. Reliability comes from durable state plus `notices` on every tool result,
   the inbox, `agent_get_context`, resources, and resource-updated notifications for clients that subscribe.
6. **The human is an actor** (`user`, `kind=human`), never impersonating an agent and never impersonated by one.

## Security model

> **Verification note.** The "Proven by" column below cites test modules from an earlier snapshot of this project
> (`test_workspace`, `test_files`, `test_tools`, `test_api`, `test_agents`, `test_tasks`, `test_messages_memory`).
> Those files are **not part of this repository**. Treat rows that cite only them as design intent that is not
> re-verified here. Present tests are listed under *Testing* in the README; they cover project identity, registration,
> routing, collaboration (task ownership, messaging, handoffs, optimistic file writes), onboarding, schema
> portability, the HTTP API (auth, Origin and Host guards) and the CLI.

| Threat | Mitigation | Proven by |
|---|---|---|
| Path traversal, absolute paths, NUL/backslash tricks | `Workspace.resolve` rejects them before any I/O | `test_workspace`, `test_files`, `test_tools` (13 attack calls), `test_api` |
| Symlink escape (read, write, list, delete, restore) | symlinks resolving outside the workspace or into `.hive`/`.git` are refused; links are never followed when listing; deleting a link removes the link only | same |
| Touching Hive internals (`.hive`, `.git`) | reserved at any depth, case-insensitively | same |
| Forged trash metadata / trash-id traversal | strict `trash_xxxxxxxxxx` pattern + restore target re-validated by `resolve` | `test_files` |
| Lost updates / clobbering another agent | `expected_sha256` (files), `expected_version` (memory, tasks), atomic claims/accepts | `test_files`, `test_tasks`, `test_messages_memory`, `test_tools` (threads and processes) |
| Accidental destruction | `confirm: true` + reason, soft delete to `.hive/trash`, `restore_file`, recursion cap | `test_files`, `test_tools` |
| One agent acting as another | caller identity comes only from the connection's bound session; no tool accepts an actor id | `test_tools` |
| Stolen/forged resume | secret token, only SHA-256 stored, constant-time compare, identical error for unknown id and bad token, denial audited | `test_agents`, `test_tools` |
| Malformed or oversized input | strict JSON-schema validation (unknown params rejected) + service-level validation + size caps | `test_tools`, `test_*` |
| Information leaks | internal errors return a generic message; details only in the log | `test_tools` |
| Other web pages attacking the local API | loopback-only bind, bearer token, `Origin` rejected, `Host` allow-list, 1 MiB body cap | `test_api` |
| Cross-workspace access | one `HiveApp` per workspace; identities are workspace-local | `test_tools`, `test_api` |
| Arbitrary command execution / host access | **none exposed**: no shell, no process execution, no path outside the workspace; `git.py` runs fixed read-only commands | design + tests above |
| Unaudited actions | every mutation is in the activity log; refusals are logged as `security.denied` | `test_tools`, `test_api` |

Residual risks (by design or not yet addressed): MCP over stdio has no authentication beyond who can launch the process (the local user);
agents must keep their `resume_token` in their own context; `hive api --token <t>` exposes the token in the process list (the default random
token does not); a local process with write access to the workspace could race `resolve()`; file-size limits are constants, not settings.

## Deviations from the original brief (and why)

- **HTTP API uses the standard library, not FastAPI.** FastAPI could not be installed or tested here; the stdlib server is fully tested, has no dependencies to
  bundle in the app, and its route table (`api/routes.py`) is framework-independent, so a FastAPI front end can be added without touching handlers.
- **MCP transport is stdio only** (one process per client). Streamable HTTP for MCP was not added because it could not be verified here.
- **Structured output** is delivered as the JSON envelope in the tool result text; per-tool output schemas are enforced by tests but not emitted as MCP `outputSchema`.
- **Extra tool `list_trash`** (an agent that loses a `trash_id` could otherwise not recover its own deletions).

## Application lifecycle

- **Workspace**: `hive init <dir>` (or `POST /v1/workspace/init`) creates `.hive/`, the database, runs all migrations. `HiveApp.open` applies pending
  migrations (transactional, locked) so old workspaces upgrade in place.
- **MCP server**: launched and owned by each MCP client; exits when the client closes stdio or on SIGTERM; on exit every session is recorded as
  disconnected. A crashed client simply leaves its session open until `last_seen_at` ages it to offline; its task leases expire and can be reclaimed.
- **API server**: started by the macOS app (`hive api`), prints one JSON ready line on stdout, exits 0 on SIGTERM/SIGINT. See `backend-contract.md`.
- **Recovery**: all state is transactional; killing any process at any time loses at most the in-flight call. Health: `hive status`, `GET /v1/health/details`.
- **Logging**: `.hive/logs/hive.log` (rotating) and stderr; stdout is reserved for the protocol/ready line.

## Status

| Component | State |
|---|---|
| Database, migrations, workspace, activity, git summary | Implemented, tested |
| Agents, tasks, messages, handoffs, checkpoints, memory, decisions, files | Implemented, tested (unit + integration + concurrency, threads and processes) |
| Tool registry (33 tools), schemas, resources, prompts | Implemented, tested |
| HTTP API for SwiftUI (27 routes, SSE) and CLI | Implemented, tested over real sockets and real processes |
| Project identity, registry, router, Set Up Agent endpoint | Implemented, tested (`tests/`) |
| **MCP SDK adapter** (`mcp_server/server.py`) | Wiring tested against a **stub** of the SDK API. **NOT verified against the real SDK or any real client**: run `scripts/verify_mcp.py` |
| Google Antigravity and other real clients | **NOT verified** in this repository (no client available in the build environment) |
| SwiftUI app changes | Written and statically checked; **not compiled or run** in the build environment |
