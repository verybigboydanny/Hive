# Hive backend contract

Contract version **0.1.0**. Two surfaces share one workspace database:

* the **MCP surface** (`hive mcp`, stdio) used by AI agents, and
* the **HTTP API** (`hive api`, loopback only) used by the macOS app.

## Project identity

Every workspace has a stable **project id** (`prj_` + 16 hex characters), stored in `.hive/hive.db` and returned as
`id` by `GET /v1/workspace` and as `project.id` by `agent_register` and `agent_get_context`.

* Pinned server (`hive mcp --workspace DIR`): bound to one folder. `agent_register(project_id=...)` is refused with
  `PROJECT_MISMATCH` when the id is not that folder's project. Nothing is written.
* Project-agnostic server (`hive mcp`, what Hive writes into client configs): `agent_register` **requires**
  `project_id`. The id is resolved through the machine-wide registry (`$HIVE_HOME` or `~/.hive/projects.json`) and
  re-verified against the id stored in the workspace. Errors: `PROJECT_REQUIRED`, `PROJECT_UNKNOWN`.
* Other tools on a project-agnostic server run against the project the connection registered in.

Error codes added for this: `PROJECT_MISMATCH` (HTTP 409), `PROJECT_UNKNOWN` (404), `PROJECT_REQUIRED` (400).

## Advertised schemas vs. enforced schemas

`tools/list` advertises a portable JSON-Schema subset (no `additionalProperties`; free-form objects such as `state`
are advertised as JSON-encoded strings; empty `required` omitted) because Gemini-based clients such as Google
Antigravity reject a whole request when one declaration uses an unsupported construct. Validation on every call is
unchanged and strict: unknown parameters are rejected and the valid ones are listed. A real object is still accepted
where a JSON string is advertised.

## HTTP API (`/v1`)

All routes need `Authorization: Bearer <token>` (printed once in the `ready` line) unless marked public. Responses
are `{"ok": true, "data": ...}` or `{"ok": false, "error": {"code", "message", "hint"?}}`.

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `GET` | `/v1/activity` | yes | Activity log (cursor `after_id`, newest `limit`) |
| `GET` | `/v1/agents` | yes | Registered agents with presence |
| `GET` | `/v1/agents/{agent_id}` | yes | One agent |
| `POST` | `/v1/agents/{agent_id}/remove` | yes | Human action: remove an agent from the project. History is kept. |
| `GET` | `/v1/decisions` | yes | Active decisions |
| `GET` | `/v1/events` | yes | Server-sent stream of new activity |
| `GET` | `/v1/files` | yes | List one directory |
| `GET` | `/v1/files/content` | yes | A page of a UTF-8 text file |
| `GET` | `/v1/handoffs` | yes | Handoffs (filter by status) |
| `GET` | `/v1/handoffs/{handoff_id}` | yes | One handoff |
| `GET` | `/v1/health` | no | Liveness (public) |
| `GET` | `/v1/health/details` | yes | Database and workspace health |
| `GET` | `/v1/memory` | yes | Shared memory entries |
| `GET` | `/v1/messages` | yes | Messages (cursor `after_seq`) |
| `POST` | `/v1/messages` | yes | Send a message as the human user |
| `POST` | `/v1/onboarding/prompt` | yes | Set Up Agent: the complete onboarding instruction for one agent in the OPEN project. |
| `GET` | `/v1/project/context` | yes | Rules, decisions, memory |
| `GET` | `/v1/project/status` | yes | Task counts, agents, handoffs, git, recent activity |
| `GET` | `/v1/tasks` | yes | Tasks |
| `POST` | `/v1/tasks` | yes | Create a task as the human user |
| `GET` | `/v1/tasks/{task_id}` | yes | One task |
| `POST` | `/v1/tasks/{task_id}/cancel` | yes | Cancel a task |
| `POST` | `/v1/tasks/{task_id}/release` | yes | Human override: free a stuck task so another agent can claim it. |
| `GET` | `/v1/trash` | yes | Soft-deleted files |
| `POST` | `/v1/trash/{trash_id}/restore` | yes | Restore a deleted file |
| `GET` | `/v1/workspace` | yes | The open project (includes the stable project `id`) |
| `POST` | `/v1/workspace/close` | yes | Close the open project |
| `POST` | `/v1/workspace/init` | yes | Initialise a folder and open it |
| `POST` | `/v1/workspace/open` | yes | Open an initialised folder (switches the open project) |

`POST /v1/onboarding/prompt` (Set Up Agent) body: `agent_name` (required), `role`, `capabilities`, `client`,
`project_id`. If `project_id` is given it must equal the open project's id (`PROJECT_MISMATCH` otherwise). Returns
`prompt`, `project`, `agent`, `warnings`.

`POST /v1/agents/{agent_id}/remove` (no body) takes an agent out of the project. It is a soft delete: the agent
disappears from `GET /v1/agents`, `agent_list` and message addressing, its open sessions end, tasks it holds
(`claimed`, `in_progress`, `blocked`) return to `open`, pending handoffs addressed to it are cancelled, and its resume
token stops working, so it cannot reconnect (it can register again as a new agent). Its messages, tasks, checkpoints and
activity stay and keep showing its name. Returns `removed`, `agent_id`, `name`, `released_tasks`, `cancelled_handoffs`.
`NOT_FOUND` if the agent does not exist or is already removed, `INVALID_ARGUMENT` for the human user. There is
deliberately no MCP tool for this: removing an agent is the human's decision.

## MCP tools

<!-- BEGIN TOOLS (generated by `hive gen-contract`; do not edit) -->

### Agents

#### `agent_register`

Register this connection as an agent and receive your identity. Call this FIRST. Pass `project_id` exactly as given in your onboarding instruction: Hive then registers you in that project or refuses (never elsewhere). Save `agent_id` and `resume_token`: pass both next time to keep the same identity after a disconnect. `name` is only a display label (not unique); `agent_id` is your identity.

*no flags*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `project_id` | string | no | Hive project id from your onboarding instruction (looks like prj_ followed by 16 hex characters). Hive refuses to register you under any other project. Never guess it from an earlier registration or the working directory. (max 64 chars) |
| `name` | string | yes | Display name, e.g. 'Claude (backend)'. (max 64 chars) |
| `client` | string | no | Provider/client: claude, gpt, gemini, ... (defaults from the MCP client name). (max 32 chars) |
| `model` | string | no | Model identifier, if known. (max 100 chars) |
| `role` | string | no | What you are doing in this project. (max 200 chars) |
| `capabilities` | array of string | no | Skills/tools you offer. |
| `agent_id` | string | no | Your previous agent_id (reconnect). Requires resume_token. (max 120 chars) |
| `resume_token` | string | no | Secret returned at first registration. (max 200 chars) |

**Returns** (`data`): `agent`: object, `session_id`: string, `resumed`: boolean, `resume_token`: string/null, `contract_version`: string, `project`: object, `next_step`: string

#### `agent_update_status`

Set your status (active, idle, blocked, offline) with an optional short message others can see.

*idempotent, needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `status` | string (active \| idle \| blocked \| offline) | yes | New status. |
| `message` | string | no | What you are doing / waiting for. (max 300 chars) |

**Returns** (`data`): `agent`: object

#### `agent_get_context`

Everything you need to start or resume work: your tasks, claimable tasks, unread messages, pending handoffs addressed to you, your last checkpoint, project rules, decisions, shared memory, other agents and recent activity.

*read-only, needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `activity_limit` | integer | no | How many recent activity entries (default 15). (min 1, max 100) |

**Returns** (`data`): `project`: object, `rules`: object, `decisions`: array of object, `memory`: array of object, `agents`: array of object, `recent_activity`: array of object, `agent`: object, `my_tasks`: array of object, `claimable_tasks`: array of object, `inbox`: object, `pending_handoffs`: array of object, `last_checkpoint`: object/null

#### `agent_list`

List the agents (and the human user) in this project with presence, status and current tasks.

*read-only, needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `include_offline` | boolean | no | Include offline agents (default true). |

**Returns** (`data`): `agents`: array of object

### Filesystem

#### `read_file`

Read a UTF-8 text file (paged by lines). Returns `sha256` of the whole file: pass it as `expected_sha256` to write_file when you modify the file.

*read-only, needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | yes | Workspace-relative path using '/'. Absolute paths, '..', and .hive/.git are rejected. (max 1024 chars) |
| `start_line` | integer | no | First line, 1-based (default 1). (min 1) |
| `max_lines` | integer | no | Max lines to return (default 2000). (min 1, max 10000) |

**Returns** (`data`): `path`: string, `content`: string, `sha256`: string, `size`: integer, `total_lines`: integer, `start_line`: integer, `end_line`: integer, `truncated`: boolean, `next_start_line`: integer/null

#### `write_file`

Create or overwrite a text file atomically. Overwriting an existing file REQUIRES `expected_sha256` from your latest read_file; if the file changed meanwhile you get CONFLICT (re-read, merge, retry). Never overwrite blindly.

*needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | yes | Workspace-relative path using '/'. Absolute paths, '..', and .hive/.git are rejected. (max 1024 chars) |
| `content` | string | yes | Complete new file content. (max 5242880 chars) |
| `expected_sha256` | string | no | sha256 returned by read_file/write_file for the version you edited. (max 64 chars) |
| `create_parents` | boolean | no | Create missing parent folders (default true). |

**Returns** (`data`): `path`: string, `created`: boolean, `sha256`: string, `previous_sha256`: string/null, `size`: integer

#### `create_file`

Create a NEW file; fails with ALREADY_EXISTS if the path exists (never overwrites).

*needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | yes | Workspace-relative path using '/'. Absolute paths, '..', and .hive/.git are rejected. (max 1024 chars) |
| `content` | string | yes | File content (may be empty). (max 5242880 chars) |
| `create_parents` | boolean | no | Create missing parent folders (default true). |

**Returns** (`data`): `path`: string, `created`: boolean, `sha256`: string, `previous_sha256`: string/null, `size`: integer

#### `create_folder`

Create a folder (idempotent: created=false if it already exists).

*idempotent, needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | yes | Workspace-relative path using '/'. Absolute paths, '..', and .hive/.git are rejected. (max 1024 chars) |
| `parents` | boolean | no | Create parents (default true). |

**Returns** (`data`): `path`: string, `created`: boolean

#### `list_files`

List a directory (default: the workspace root). Hidden files and node_modules are skipped unless include_hidden. Symlinks are listed but never followed. .hive and .git are never shown.

*read-only, needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | no | Directory, workspace-relative ('.' = root). (max 1024 chars) |
| `recursive` | boolean | no | Recurse into subfolders (default false). |
| `max_depth` | integer | no | Recursion depth (default 4, max 10). (min 1, max 10) |
| `include_hidden` | boolean | no | Include dotfiles and ignored folders. |
| `limit` | integer | no | Max entries (default/max 1000). (min 1, max 1000) |

**Returns** (`data`): `path`: string, `entries`: array of object, `truncated`: boolean

#### `move_file`

Move or rename a file or folder. Never overwrites an existing destination.

*needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `from_path` | string | yes | Workspace-relative path using '/'. Absolute paths, '..', and .hive/.git are rejected. (max 1024 chars) |
| `to_path` | string | yes | Workspace-relative path using '/'. Absolute paths, '..', and .hive/.git are rejected. (max 1024 chars) |
| `create_parents` | boolean | no | Create destination parents (default false). |

**Returns** (`data`): `from`: string, `to`: string

#### `delete_file`

Delete a file or folder. Destructive-but-recoverable: requires confirm=true and a reason, moves the item to trash (restore with restore_file using the returned trash_id). Non-empty folders need recursive=true.

*destructive, needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | string | yes | Workspace-relative path using '/'. Absolute paths, '..', and .hive/.git are rejected. (max 1024 chars) |
| `confirm` | boolean | yes | Must be true. |
| `reason` | string | yes | Why it is being deleted. (max 500 chars) |
| `recursive` | boolean | no | Required for non-empty folders. |

**Returns** (`data`): `path`: string, `kind`: string, `entries`: integer, `trash_id`: string, `recoverable`: boolean

#### `restore_file`

Restore a deleted item from trash (never overwrites; use to_path to restore elsewhere).

*needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `trash_id` | string | yes | trash_xxxxxxxxxx from delete_file or list_trash. (max 40 chars) |
| `to_path` | string | no | Alternative destination. (max 1024 chars) |

**Returns** (`data`): `path`: string, `kind`: string, `entries`: integer, `restored_from`: string

#### `list_trash`

List recoverable deleted items (trash_id, original path, who deleted, why).

*read-only, needs registered agent*

No parameters.

**Returns** (`data`): `items`: array of object, `count`: integer

### Tasks

#### `task_create`

Create a task (optionally depending on other tasks). Others can then claim it.

*needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `title` | string | yes | Short title. (max 200 chars) |
| `description` | string | no | Details / acceptance criteria. (max 20000 chars) |
| `priority` | string (low \| normal \| high \| urgent) | no | Default normal. |
| `labels` | array of string | no | Free-form labels. |
| `depends_on` | array of string | no | Task ids that must be done first. |
| `parent_id` | string | no | Parent task id. (max 120 chars) |

**Returns** (`data`): `task`: object

#### `task_list`

List tasks (closed ones hidden by default), highest priority first. Each task shows owner, lease state, `blocked_by` and whether it is `claimable` now.

*read-only, needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `task_id` | string | no | Return just this task (even if closed). (max 120 chars) |
| `status` | array of string | no | Filter by status. |
| `owner` | string | no | 'me', 'unassigned' or an agent id. (max 120 chars) |
| `label` | string | no | Only tasks with this label. (max 40 chars) |
| `claimable_only` | boolean | no | Only tasks you could claim right now. |
| `include_closed` | boolean | no | Include done/cancelled. |
| `limit` | integer | no | Max tasks (default 50). (min 1, max 500) |

**Returns** (`data`): `tasks`: array of object, `count`: integer, `total_matching`: integer

#### `task_claim`

Claim a task atomically (only one agent can win). The claim is a lease (default 30 min): renew it with task_update/save_checkpoint, or it can be reclaimed by others after it expires. Fails with TASK_ALREADY_CLAIMED or DEPENDENCY_UNMET.

*needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `task_id` | string | yes | Task id. (max 120 chars) |
| `lease_minutes` | integer | no | Lease length (default 30). (min 1, max 240) |

**Returns** (`data`): `task`: object, `reclaimed_from`: string/null, `renewed`: boolean

#### `task_update`

Record progress or change a task. Owner-only for status/progress (status: in_progress, blocked, review, or open to release it). Any update by the owner renews the lease. Use expected_version to detect concurrent edits.

*needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `task_id` | string | yes | Task id. (max 120 chars) |
| `status` | string (in_progress \| blocked \| review \| open) | no | New status. |
| `progress_note` | string | no | What you did / what is next. (max 20000 chars) |
| `title` | string | no | New title. (max 200 chars) |
| `description` | string | no | New description. (max 20000 chars) |
| `priority` | string (low \| normal \| high \| urgent) | no | New priority. |
| `labels` | array of string | no | Free-form labels. |
| `expected_version` | integer | no | Fail with CONFLICT if the task version differs. (min 1) |
| `add_depends_on` | array of string | no | Add dependencies (cycles rejected). |
| `remove_depends_on` | array of string | no | Remove dependencies. |
| `extend_lease_minutes` | integer | no | Renew the lease for this many minutes. (min 1, max 240) |

**Returns** (`data`): `task`: object

#### `task_complete`

Mark your task done with a result summary (idempotent). Reports tasks it unblocked.

*idempotent, needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `task_id` | string | yes | Task id. (max 120 chars) |
| `summary` | string | yes | What was delivered. (max 20000 chars) |
| `expected_version` | integer | no | Optional concurrency check. (min 1) |

**Returns** (`data`): `task`: object, `already_completed`: boolean, `unblocked_tasks`: array of string

#### `task_cancel`

Cancel a task (owner, creator or the user). Requires a reason. Dependents stay blocked.

*destructive, idempotent, needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `task_id` | string | yes | Task id. (max 120 chars) |
| `reason` | string | yes | Why. (max 500 chars) |

**Returns** (`data`): `task`: object, `already_cancelled`: boolean

### Messaging

#### `send_message`

Send a persistent message to one agent (by agent id, or a name that is unique) or to everyone (to='all'). It waits in their inbox even if they are disconnected; Hive cannot wake an idle client.

*needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `to` | string | yes | Agent id, unique agent name, or 'all'. (max 120 chars) |
| `body` | string | yes | Message text. (max 20000 chars) |
| `subject` | string | no | Optional subject. (max 200 chars) |
| `kind` | string (message \| question \| answer \| notice) | no | Default message. |
| `reply_to` | string | no | Message id you are replying to (keeps the thread). (max 120 chars) |
| `task_id` | string | no | Related task id. (max 120 chars) |

**Returns** (`data`): `message`: object

#### `message_inbox`

Read your messages (unread by default, oldest first). Reading does NOT mark them read; call message_mark_read after you have handled them. Includes handoff notifications.

*read-only, needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `unread_only` | boolean | no | Default true. |
| `limit` | integer | no | Default 20. (min 1, max 200) |
| `after_seq` | integer | no | Only messages with seq greater than this (paging). (min 0) |
| `from_agent` | string | no | Only messages from this agent. (max 120 chars) |

**Returns** (`data`): `messages`: array of object, `unread_total`: integer, `next_after_seq`: integer

#### `message_mark_read`

Mark messages read: give exactly one of message_ids, up_to_seq, or all=true.

*idempotent, needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `message_ids` | array of string | no | Specific message ids. |
| `up_to_seq` | integer | no | Everything up to and including this seq. (min 0) |
| `all` | boolean | no | Mark every visible message read. |

**Returns** (`data`): `marked`: integer, `not_found`: array of string, `unread_total`: integer

### Handoffs

#### `handoff_create`

Hand work to another agent (or leave it open for any agent with to omitted). Records completed work, remaining work, modified files and the next action, saves a checkpoint, keeps your task reserved for the recipient and notifies them. Ownership moves when they accept.

*needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `summary` | string | yes | One-line summary. (max 20000 chars) |
| `to` | string | no | Agent id/unique name; omit = any agent. (max 120 chars) |
| `task_id` | string | no | Task you own that is being handed over. (max 120 chars) |
| `completed_work` | string | no | What is done. (max 20000 chars) |
| `remaining_work` | string | no | What is left. (max 20000 chars) |
| `files_modified` | array of string | no | Workspace-relative paths. |
| `next_action` | string | no | The very next step. (max 20000 chars) |
| `context` | string | no | Background the next agent needs. (max 20000 chars) |
| `state` | object | no | Free-form JSON state to preserve. |

**Returns** (`data`): `handoff`: object

#### `handoff_list`

List handoffs. scope: to_me (addressed to you or open), from_me, or all.

*read-only, needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `status` | string (pending \| accepted \| cancelled) | no | Filter. |
| `scope` | string (to_me \| from_me \| all) | no | Default to_me. |
| `task_id` | string | no | Filter by task. (max 120 chars) |
| `limit` | integer | no | Default 50. (min 1, max 500) |

**Returns** (`data`): `handoffs`: array of object, `count`: integer

#### `handoff_accept`

Accept a handoff atomically (only one agent can). You receive its full context and checkpoint, and the task becomes yours. Idempotent for the same agent.

*idempotent, needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `handoff_id` | string | yes | Handoff id. (max 120 chars) |

**Returns** (`data`): `handoff`: object, `task`: object/null, `task_transfer`: string, `already_accepted`: boolean

### Memory and decisions

#### `memory_read`

Read shared project memory: one key, a category, or a free-text query (relevance-ranked). Optionally include version history or matching decisions.

*read-only, needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `key` | string | no | Exact key. (max 120 chars) |
| `query` | string | no | Search terms. (max 200 chars) |
| `category` | string | no | Category filter (e.g. rules, architecture). (max 40 chars) |
| `limit` | integer | no | Default 20. (min 1, max 200) |
| `include_history` | boolean | no | With key: every past version. |
| `include_decisions` | boolean | no | Also return active decisions matching the query. |

**Returns** (`data`): `entries`: array of object, `total`: integer

#### `memory_update`

Create or update a shared memory entry. Updating an existing key REQUIRES expected_version from memory_read (CONFLICT/PRECONDITION_REQUIRED otherwise); all versions are kept.

*needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `key` | string | yes | e.g. 'architecture/db' (a-z 0-9 . _ : / -). (max 120 chars) |
| `value` | string | yes | Content. (max 20000 chars) |
| `category` | string | no | Default general; use 'rules' for project rules. (max 40 chars) |
| `tags` | array of string | no | Free-form labels. |
| `expected_version` | integer | no | Version you read (existing keys). (min 1) |

**Returns** (`data`): `entry`: object, `created`: boolean, `changed`: boolean

#### `record_decision`

Record an architectural/project decision (optionally superseding an earlier one).

*needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `title` | string | yes | Short title. (max 200 chars) |
| `decision` | string | yes | What was decided. (max 20000 chars) |
| `rationale` | string | no | Why. (max 20000 chars) |
| `tags` | array of string | no | Free-form labels. |
| `supersedes_id` | string | no | Decision id this replaces. (max 120 chars) |

**Returns** (`data`): `decision`: object

### Project, activity and checkpoints

#### `get_project_status`

Project dashboard: task counts, agents, pending handoffs, git state, recent activity.

*read-only, needs registered agent*

No parameters.

**Returns** (`data`): `project`: object, `tasks`: object, `agents`: array of object, `handoffs`: object, `messages`: object, `memory`: object, `git`: object, `recent_activity`: array of object

#### `get_project_context`

Shared project context (rules, active decisions, memory, online agents, activity) without agent-specific state. Use agent_get_context for your own resume point.

*read-only, needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `activity_limit` | integer | no | Default 15. (min 1, max 100) |

**Returns** (`data`): `project`: object, `rules`: object, `decisions`: array of object, `memory`: array of object, `agents`: array of object, `recent_activity`: array of object

#### `get_activity`

Shared activity history (who did what, when). Poll with after_id=<next_cursor> to receive only new events.

*read-only, needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `after_id` | integer | no | Only events with id greater than this. (min 0) |
| `limit` | integer | no | Default 50. (min 1, max 500) |
| `agent` | string | no | Only this actor (agent id). (max 120 chars) |
| `action_prefix` | string | no | e.g. 'task.' or 'file.'. (max 60 chars) |

**Returns** (`data`): `entries`: array of object, `next_cursor`: integer/null

#### `save_checkpoint`

Save a resumable checkpoint (summary, JSON state, modified files, next action). With task_id (a task you own) it also renews your lease. Another agent can resume from it with restore_checkpoint.

*needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `summary` | string | yes | Where you are. (max 20000 chars) |
| `task_id` | string | no | Task this belongs to. (max 120 chars) |
| `state` | object | no | Free-form JSON state (max 64 KB). |
| `files_modified` | array of string | no | Workspace-relative paths. |
| `next_action` | string | no | What to do next. (max 20000 chars) |

**Returns** (`data`): `checkpoint`: object

#### `restore_checkpoint`

Load a checkpoint (by id, the latest for a task, or your latest). With claim_task=true (default) it also tries to claim the task for you if it is free or its lease expired; a live owner is never displaced.

*needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `checkpoint_id` | string | no | Specific checkpoint. (max 120 chars) |
| `task_id` | string | no | Latest checkpoint for this task. (max 120 chars) |
| `claim_task` | boolean | no | Default true. |

**Returns** (`data`): `checkpoint`: object, `task`: object/null, `claim`: object

### Terminal and execution

#### `run_command`

Run a terminal command (e.g. pip install, git status, swift build) in the workspace directory. Returns stdout, stderr, exit code and duration.

*needs registered agent*

| Parameter | Type | Required | Description |
|---|---|---|---|
| `command` | string | yes | Shell command to run in the workspace directory. (max 4000 chars) |
| `working_directory` | string | no | Subdirectory relative to workspace root (optional, defaults to root). (max 500 chars) |
| `timeout_seconds` | integer | no | Maximum execution time in seconds (default 60, max 600). (min 1, max 600) |

**Returns** (`data`): `stdout`: string, `stderr`: string, `exit_code`: integer, `duration_seconds`: number, `timed_out`: boolean

<!-- END TOOLS -->
