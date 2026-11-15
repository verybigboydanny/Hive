"""All MCP tools. Each tool = ToolSpec(input schema, output schema, handler). Handlers are thin:
they translate arguments and delegate to services (which own validation, transactions and auditing)."""

from __future__ import annotations

import os
import re
import subprocess
import time

from .. import CONTRACT_VERSION
from ..errors import NOT_FOUND, PATH_DENIED, PROJECT_MISMATCH, HiveError
from . import outputs as O
from .registry import ToolSpec
from .schema import (B, I, NI, NOBJ, NS, OBJ, S, arr, ident, obj_in, obj_out, prop, text)

TOOLS: list[ToolSpec] = []


def tool(name, group, description, inputs, output, *, requires_agent=True, read_only=False, destructive=False,
         idempotent=False):
    def deco(fn):
        TOOLS.append(ToolSpec(name, group, description, inputs, output, fn, requires_agent, read_only, destructive,
                              idempotent))
        return fn
    return deco


EMPTY = obj_in({})
STATUS_ENUM = ["open", "claimed", "in_progress", "blocked", "review", "done", "cancelled"]
PRIORITY_ENUM = ["low", "normal", "high", "urgent"]
LABELS = prop("array", "Free-form labels.", items={"type": "string", "maxLength": 40}, maxItems=20)
FILES = prop("array", "Workspace-relative paths.", items={"type": "string", "maxLength": 500}, maxItems=200)


def _client_from(info: dict) -> str:
    raw = re.sub(r"[^A-Za-z0-9._-]+", "-", str(info.get("name") or "")).strip("-")[:32]
    return raw or "other"


# =============================================================== AGENTS
@tool("agent_register", "agents",
      "Register this connection as an agent and receive your identity. Call this FIRST. Pass `project_id` exactly as "
      "given in your onboarding instruction: Hive then registers you in that project or refuses (never elsewhere). "
      "Save `agent_id` and `resume_token`: pass both next time to keep the same identity after a disconnect. `name` is "
      "only a display label (not unique); `agent_id` is your identity.",
      obj_in({"project_id": prop("string", "Hive project id from your onboarding instruction (looks like prj_ followed by "
                                           "16 hex characters). Hive refuses to register you under any other project. "
                                           "Never guess it from an earlier registration or the working directory.",
                                 minLength=1, maxLength=64),
              "name": prop("string", "Display name, e.g. 'Claude (backend)'.", minLength=1, maxLength=64),
              "client": prop("string", "Provider/client: claude, gpt, gemini, ... (defaults from the MCP client name).",
                             maxLength=32),
              "model": prop("string", "Model identifier, if known.", maxLength=100),
              "role": prop("string", "What you are doing in this project.", maxLength=200),
              "capabilities": prop("array", "Skills/tools you offer.", items={"type": "string", "maxLength": 40}, maxItems=20),
              "agent_id": ident("Your previous agent_id (reconnect). Requires resume_token."),
              "resume_token": prop("string", "Secret returned at first registration.", minLength=8, maxLength=200)},
             required=["name"]),
      obj_out({"agent": O.AGENT, "session_id": S, "resumed": B, "resume_token": NS, "contract_version": S,
               "project": obj_out({"id": S, "name": S, "root": S}), "next_step": S}),
      requires_agent=False)
def agent_register(app, ctx, a):
    info = app.project.info()
    requested = a.get("project_id")
    if requested is not None and requested != info["id"]:
        # Refuse BEFORE anything is written: a stale or pinned connection must never create an identity in the wrong project.
        app.activity.record(agent_id=None, action="agent.register_refused",
                            summary=f"registration refused: asked for project {str(requested)[:40]}, connection is bound to {info['id']}",
                            target_type="project", target_id=info["id"],
                            details={"requested_project_id": str(requested)[:64], "client": ctx.client_info})
        raise HiveError(PROJECT_MISMATCH,
                        "this Hive connection belongs to a different project than the one you asked to join",
                        {"requested_project_id": requested, "bound_project": {"id": info["id"], "name": info["name"]}},
                        hint=(f"Stop. Do not register or edit files here. Tell the user this MCP server entry is pinned to "
                              f"project '{info['name']}'. They can re-add Hive from its Apps & MCP settings (the new entry "
                              f"works for every project) or send you a fresh instruction from Set Up Agent."))
    client = a.get("client") or _client_from(ctx.client_info)
    r = app.agents.register(name=a["name"], client=client, model=a.get("model"), role=a.get("role"),
                            capabilities=a.get("capabilities"), transport=ctx.transport, client_info=ctx.client_info,
                            agent_id=a.get("agent_id"), resume_token=a.get("resume_token"))
    ctx.bind(r["agent"]["id"], r["session_id"])
    step = ("Check that project.id matches the project id you were given. Then call agent_get_context to load your "
            "tasks, inbox, handoffs and project rules.")
    if r["resume_token"]:
        step = "Save agent_id and resume_token now (needed to reconnect). " + step
    return {"agent": r["agent"], "session_id": r["session_id"], "resumed": r["resumed"],
            "resume_token": r["resume_token"], "contract_version": CONTRACT_VERSION,
            "project": {"id": info["id"], "name": info["name"], "root": info["root"]}, "next_step": step}


@tool("agent_update_status", "agents",
      "Set your status (active, idle, blocked, offline) with an optional short message others can see.",
      obj_in({"status": prop("string", "New status.", enum=["active", "idle", "blocked", "offline"]),
              "message": prop("string", "What you are doing / waiting for.", maxLength=300)}, required=["status"]),
      obj_out({"agent": O.AGENT}), idempotent=True)
def agent_update_status(app, ctx, a):
    return {"agent": app.agents.update_status(ctx.agent_id, a["status"], a.get("message"))}


@tool("agent_get_context", "agents",
      "Everything you need to start or resume work: your tasks, claimable tasks, unread messages, pending handoffs "
      "addressed to you, your last checkpoint, project rules, decisions, shared memory, other agents and recent activity.",
      obj_in({"activity_limit": prop("integer", "How many recent activity entries (default 15).", minimum=1, maximum=100)}),
      O.AGENT_CONTEXT, read_only=True)
def agent_get_context(app, ctx, a):
    return app.project.context(ctx.agent_id, activity_limit=a.get("activity_limit", 15))


@tool("agent_list", "agents", "List the agents (and the human user) in this project with presence, status and current tasks.",
      obj_in({"include_offline": prop("boolean", "Include offline agents (default true).")}),
      obj_out({"agents": arr(O.AGENT)}), read_only=True)
def agent_list(app, ctx, a):
    return {"agents": app.agents.list(include_offline=a.get("include_offline", True))}


# =============================================================== FILES
PATH = text("Workspace-relative path using '/'. Absolute paths, '..', and .hive/.git are rejected.", 1024, minLength=1)


@tool("read_file", "files",
      "Read a UTF-8 text file (paged by lines). Returns `sha256` of the whole file: pass it as `expected_sha256` "
      "to write_file when you modify the file.",
      obj_in({"path": PATH, "start_line": prop("integer", "First line, 1-based (default 1).", minimum=1),
              "max_lines": prop("integer", "Max lines to return (default 2000).", minimum=1, maximum=10000)}, ["path"]),
      obj_out({"path": S, "content": S, "sha256": S, "size": I, "total_lines": I, "start_line": I, "end_line": I,
               "truncated": B, "next_start_line": NI}), read_only=True)
def read_file(app, ctx, a):
    return app.files.read(a["path"], a.get("start_line", 1), a.get("max_lines", 2000))


_WRITE_OUT = obj_out({"path": S, "created": B, "sha256": S, "previous_sha256": NS, "size": I})


@tool("write_file", "files",
      "Create or overwrite a text file atomically. Overwriting an existing file REQUIRES `expected_sha256` from your "
      "latest read_file; if the file changed meanwhile you get CONFLICT (re-read, merge, retry). Never overwrite blindly.",
      obj_in({"path": PATH, "content": text("Complete new file content.", 5 * 1024 * 1024),
              "expected_sha256": prop("string", "sha256 returned by read_file/write_file for the version you edited.",
                                      minLength=64, maxLength=64),
              "create_parents": prop("boolean", "Create missing parent folders (default true).")}, ["path", "content"]),
      _WRITE_OUT, idempotent=False)
def write_file(app, ctx, a):
    return app.files.write(ctx.agent_id, a["path"], a["content"], a.get("expected_sha256"), a.get("create_parents", True))


@tool("create_file", "files", "Create a NEW file; fails with ALREADY_EXISTS if the path exists (never overwrites).",
      obj_in({"path": PATH, "content": text("File content (may be empty).", 5 * 1024 * 1024),
              "create_parents": prop("boolean", "Create missing parent folders (default true).")}, ["path", "content"]),
      _WRITE_OUT)
def create_file(app, ctx, a):
    return app.files.create(ctx.agent_id, a["path"], a["content"], a.get("create_parents", True))


@tool("create_folder", "files", "Create a folder (idempotent: created=false if it already exists).",
      obj_in({"path": PATH, "parents": prop("boolean", "Create parents (default true).")}, ["path"]),
      obj_out({"path": S, "created": B}), idempotent=True)
def create_folder(app, ctx, a):
    return app.files.create_folder(ctx.agent_id, a["path"], a.get("parents", True))


@tool("list_files", "files",
      "List a directory (default: the workspace root). Hidden files and node_modules are skipped unless include_hidden. "
      "Symlinks are listed but never followed. .hive and .git are never shown.",
      obj_in({"path": text("Directory, workspace-relative ('.' = root).", 1024),
              "recursive": prop("boolean", "Recurse into subfolders (default false)."),
              "max_depth": prop("integer", "Recursion depth (default 4, max 10).", minimum=1, maximum=10),
              "include_hidden": prop("boolean", "Include dotfiles and ignored folders."),
              "limit": prop("integer", "Max entries (default/max 1000).", minimum=1, maximum=1000)}),
      obj_out({"path": S, "entries": arr(O.FILE_ENTRY), "truncated": B}), read_only=True)
def list_files(app, ctx, a):
    return app.files.list(a.get("path", "."), a.get("recursive", False), a.get("max_depth"),
                          a.get("include_hidden", False), a.get("limit"))


@tool("move_file", "files", "Move or rename a file or folder. Never overwrites an existing destination.",
      obj_in({"from_path": PATH, "to_path": PATH,
              "create_parents": prop("boolean", "Create destination parents (default false).")}, ["from_path", "to_path"]),
      obj_out({"from": S, "to": S}))
def move_file(app, ctx, a):
    return app.files.move(ctx.agent_id, a["from_path"], a["to_path"], a.get("create_parents", False))


@tool("delete_file", "files",
      "Delete a file or folder. Destructive-but-recoverable: requires confirm=true and a reason, moves the item to "
      "trash (restore with restore_file using the returned trash_id). Non-empty folders need recursive=true.",
      obj_in({"path": PATH, "confirm": prop("boolean", "Must be true."), "reason": text("Why it is being deleted.", 500, minLength=1),
              "recursive": prop("boolean", "Required for non-empty folders.")}, ["path", "confirm", "reason"]),
      obj_out({"path": S, "kind": S, "entries": I, "trash_id": S, "recoverable": B}), destructive=True)
def delete_file(app, ctx, a):
    return app.files.delete(ctx.agent_id, a["path"], a["confirm"], a["reason"], a.get("recursive", False))


@tool("restore_file", "files", "Restore a deleted item from trash (never overwrites; use to_path to restore elsewhere).",
      obj_in({"trash_id": prop("string", "trash_xxxxxxxxxx from delete_file or list_trash.", minLength=1, maxLength=40),
              "to_path": text("Alternative destination.", 1024, minLength=1)}, ["trash_id"]),
      obj_out({"path": S, "kind": S, "entries": I, "restored_from": S}))
def restore_file(app, ctx, a):
    return app.files.restore(ctx.agent_id, a["trash_id"], a.get("to_path"))


@tool("list_trash", "files", "List recoverable deleted items (trash_id, original path, who deleted, why).", EMPTY,
      obj_out({"items": arr(obj_out({"trash_id": S, "original_path": S, "kind": S, "entries": I, "deleted_at": S,
                                     "deleted_by": S, "reason": S})), "count": I}), read_only=True)
def list_trash(app, ctx, a):
    return app.files.list_trash()


# =============================================================== TASKS
@tool("task_create", "tasks", "Create a task (optionally depending on other tasks). Others can then claim it.",
      obj_in({"title": text("Short title.", 200, minLength=1), "description": text("Details / acceptance criteria."),
              "priority": prop("string", "Default normal.", enum=PRIORITY_ENUM), "labels": LABELS,
              "depends_on": prop("array", "Task ids that must be done first.", items={"type": "string"}, maxItems=50),
              "parent_id": ident("Parent task id.")}, ["title"]),
      obj_out({"task": O.TASK}))
def task_create(app, ctx, a):
    return {"task": app.tasks.create(ctx.agent_id, title=a["title"], description=a.get("description"),
                                     priority=a.get("priority", "normal"), labels=a.get("labels"),
                                     depends_on=a.get("depends_on"), parent_id=a.get("parent_id"))}


@tool("task_list", "tasks",
      "List tasks (closed ones hidden by default), highest priority first. Each task shows owner, lease state, "
      "`blocked_by` and whether it is `claimable` now.",
      obj_in({"task_id": ident("Return just this task (even if closed)."),
              "status": prop("array", "Filter by status.", items={"type": "string", "enum": STATUS_ENUM}),
              "owner": prop("string", "'me', 'unassigned' or an agent id.", maxLength=120),
              "label": prop("string", "Only tasks with this label.", maxLength=40),
              "claimable_only": prop("boolean", "Only tasks you could claim right now."),
              "include_closed": prop("boolean", "Include done/cancelled."),
              "limit": prop("integer", "Max tasks (default 50).", minimum=1, maximum=500)}),
      obj_out({"tasks": arr(O.TASK), "count": I, "total_matching": I}), read_only=True)
def task_list(app, ctx, a):
    return app.tasks.list(ctx.agent_id, task_id=a.get("task_id"), status=a.get("status"), owner=a.get("owner"),
                          label=a.get("label"), claimable_only=a.get("claimable_only", False),
                          include_closed=a.get("include_closed", False), limit=a.get("limit", 50))


@tool("task_claim", "tasks",
      "Claim a task atomically (only one agent can win). The claim is a lease (default 30 min): renew it with "
      "task_update/save_checkpoint, or it can be reclaimed by others after it expires. Fails with TASK_ALREADY_CLAIMED "
      "or DEPENDENCY_UNMET.",
      obj_in({"task_id": ident("Task id."), "lease_minutes": prop("integer", "Lease length (default 30).", minimum=1, maximum=240)},
             ["task_id"]),
      obj_out({"task": O.TASK, "reclaimed_from": NS, "renewed": B}))
def task_claim(app, ctx, a):
    return app.tasks.claim(ctx.agent_id, a["task_id"], a.get("lease_minutes"))


@tool("task_update", "tasks",
      "Record progress or change a task. Owner-only for status/progress (status: in_progress, blocked, review, or open to "
      "release it). Any update by the owner renews the lease. Use expected_version to detect concurrent edits.",
      obj_in({"task_id": ident("Task id."), "status": prop("string", "New status.", enum=["in_progress", "blocked", "review", "open"]),
              "progress_note": text("What you did / what is next."), "title": text("New title.", 200, minLength=1),
              "description": text("New description."), "priority": prop("string", "New priority.", enum=PRIORITY_ENUM),
              "labels": LABELS, "expected_version": prop("integer", "Fail with CONFLICT if the task version differs.", minimum=1),
              "add_depends_on": prop("array", "Add dependencies (cycles rejected).", items={"type": "string"}, maxItems=50),
              "remove_depends_on": prop("array", "Remove dependencies.", items={"type": "string"}, maxItems=50),
              "extend_lease_minutes": prop("integer", "Renew the lease for this many minutes.", minimum=1, maximum=240)},
             ["task_id"]),
      obj_out({"task": O.TASK}))
def task_update(app, ctx, a):
    kw = {k: v for k, v in a.items() if k != "task_id"}
    return {"task": app.tasks.update(ctx.agent_id, a["task_id"], **kw)}


@tool("task_complete", "tasks", "Mark your task done with a result summary (idempotent). Reports tasks it unblocked.",
      obj_in({"task_id": ident("Task id."), "summary": text("What was delivered.", minLength=1),
              "expected_version": prop("integer", "Optional concurrency check.", minimum=1)}, ["task_id", "summary"]),
      obj_out({"task": O.TASK, "already_completed": B, "unblocked_tasks": arr(S)}), idempotent=True)
def task_complete(app, ctx, a):
    return app.tasks.complete(ctx.agent_id, a["task_id"], a["summary"], a.get("expected_version"))


@tool("task_cancel", "tasks", "Cancel a task (owner, creator or the user). Requires a reason. Dependents stay blocked.",
      obj_in({"task_id": ident("Task id."), "reason": text("Why.", 500, minLength=1)}, ["task_id", "reason"]),
      obj_out({"task": O.TASK, "already_cancelled": B}), destructive=True, idempotent=True)
def task_cancel(app, ctx, a):
    return app.tasks.cancel(ctx.agent_id, a["task_id"], a["reason"])


# =============================================================== MESSAGES
@tool("send_message", "messages",
      "Send a persistent message to one agent (by agent id, or a name that is unique) or to everyone (to='all'). "
      "It waits in their inbox even if they are disconnected; Hive cannot wake an idle client.",
      obj_in({"to": prop("string", "Agent id, unique agent name, or 'all'.", minLength=1, maxLength=120),
              "body": text("Message text.", minLength=1), "subject": text("Optional subject.", 200),
              "kind": prop("string", "Default message.", enum=["message", "question", "answer", "notice"]),
              "reply_to": ident("Message id you are replying to (keeps the thread)."), "task_id": ident("Related task id.")},
             ["to", "body"]),
      obj_out({"message": O.MESSAGE}))
def send_message(app, ctx, a):
    return {"message": app.messages.send(ctx.agent_id, to=a["to"], body=a["body"], subject=a.get("subject"),
                                         kind=a.get("kind", "message"), reply_to=a.get("reply_to"), task_id=a.get("task_id"))}


@tool("message_inbox", "messages",
      "Read your messages (unread by default, oldest first). Reading does NOT mark them read; call message_mark_read "
      "after you have handled them. Includes handoff notifications.",
      obj_in({"unread_only": prop("boolean", "Default true."), "limit": prop("integer", "Default 20.", minimum=1, maximum=200),
              "after_seq": prop("integer", "Only messages with seq greater than this (paging).", minimum=0),
              "from_agent": prop("string", "Only messages from this agent.", maxLength=120)}),
      obj_out({"messages": arr(O.MESSAGE), "unread_total": I, "next_after_seq": I}), read_only=True)
def message_inbox(app, ctx, a):
    return app.messages.inbox(ctx.agent_id, unread_only=a.get("unread_only", True), limit=a.get("limit", 20),
                              after_seq=a.get("after_seq", 0), from_ref=a.get("from_agent"))


@tool("message_mark_read", "messages", "Mark messages read: give exactly one of message_ids, up_to_seq, or all=true.",
      obj_in({"message_ids": prop("array", "Specific message ids.", items={"type": "string"}, minItems=1, maxItems=200),
              "up_to_seq": prop("integer", "Everything up to and including this seq.", minimum=0),
              "all": prop("boolean", "Mark every visible message read.")}),
      obj_out({"marked": I, "not_found": arr(S), "unread_total": I}), idempotent=True)
def message_mark_read(app, ctx, a):
    return app.messages.mark_read(ctx.agent_id, message_ids=a.get("message_ids"), up_to_seq=a.get("up_to_seq"),
                                  all_messages=bool(a.get("all", False)))


# =============================================================== HANDOFFS
@tool("handoff_create", "handoffs",
      "Hand work to another agent (or leave it open for any agent with to omitted). Records completed work, remaining "
      "work, modified files and the next action, saves a checkpoint, keeps your task reserved for the recipient and "
      "notifies them. Ownership moves when they accept.",
      obj_in({"summary": text("One-line summary.", minLength=1), "to": prop("string", "Agent id/unique name; omit = any agent.", maxLength=120),
              "task_id": ident("Task you own that is being handed over."), "completed_work": text("What is done."),
              "remaining_work": text("What is left."), "files_modified": FILES, "next_action": text("The very next step."),
              "context": text("Background the next agent needs."),
              "state": prop("object", "Free-form JSON state to preserve.")}, ["summary"]),
      obj_out({"handoff": O.HANDOFF}))
def handoff_create(app, ctx, a):
    return {"handoff": app.handoffs.create(ctx.agent_id, summary=a["summary"], to=a.get("to"), task_id=a.get("task_id"),
                                           completed_work=a.get("completed_work"), remaining_work=a.get("remaining_work"),
                                           files_modified=a.get("files_modified"), next_action=a.get("next_action"),
                                           context=a.get("context"), state=a.get("state"))}


@tool("handoff_list", "handoffs", "List handoffs. scope: to_me (addressed to you or open), from_me, or all.",
      obj_in({"status": prop("string", "Filter.", enum=["pending", "accepted", "cancelled"]),
              "scope": prop("string", "Default to_me.", enum=["to_me", "from_me", "all"]), "task_id": ident("Filter by task."),
              "limit": prop("integer", "Default 50.", minimum=1, maximum=500)}),
      obj_out({"handoffs": arr(O.HANDOFF), "count": I}), read_only=True)
def handoff_list(app, ctx, a):
    return app.handoffs.list(ctx.agent_id, status=a.get("status"), scope=a.get("scope", "to_me"),
                             task_id=a.get("task_id"), limit=a.get("limit", 50))


@tool("handoff_accept", "handoffs",
      "Accept a handoff atomically (only one agent can). You receive its full context and checkpoint, and the task "
      "becomes yours. Idempotent for the same agent.",
      obj_in({"handoff_id": ident("Handoff id.")}, ["handoff_id"]),
      obj_out({"handoff": O.HANDOFF, "task": NOBJ, "task_transfer": S, "already_accepted": B}), idempotent=True)
def handoff_accept(app, ctx, a):
    return app.handoffs.accept(ctx.agent_id, a["handoff_id"])


# =============================================================== MEMORY
@tool("memory_read", "memory",
      "Read shared project memory: one key, a category, or a free-text query (relevance-ranked). Optionally include "
      "version history or matching decisions.",
      obj_in({"key": prop("string", "Exact key.", maxLength=120), "query": prop("string", "Search terms.", maxLength=200),
              "category": prop("string", "Category filter (e.g. rules, architecture).", maxLength=40),
              "limit": prop("integer", "Default 20.", minimum=1, maximum=200),
              "include_history": prop("boolean", "With key: every past version."),
              "include_decisions": prop("boolean", "Also return active decisions matching the query.")}),
      obj_out({"entries": arr(O.MEMORY), "total": I}, required=["entries", "total"]), read_only=True)
def memory_read(app, ctx, a):
    out = app.memory.read(key=a.get("key"), category=a.get("category"), query=a.get("query"), limit=a.get("limit", 20),
                          include_history=a.get("include_history", False))
    if a.get("include_decisions"):
        out["decisions"] = app.memory.list_decisions(status="active", query=a.get("query"), limit=a.get("limit", 20))["decisions"]
    return out


@tool("memory_update", "memory",
      "Create or update a shared memory entry. Updating an existing key REQUIRES expected_version from memory_read "
      "(CONFLICT/PRECONDITION_REQUIRED otherwise); all versions are kept.",
      obj_in({"key": prop("string", "e.g. 'architecture/db' (a-z 0-9 . _ : / -).", minLength=1, maxLength=120),
              "value": text("Content.", minLength=1), "category": prop("string", "Default general; use 'rules' for project rules.", maxLength=40),
              "tags": LABELS, "expected_version": prop("integer", "Version you read (existing keys).", minimum=1)}, ["key", "value"]),
      obj_out({"entry": O.MEMORY, "created": B, "changed": B}))
def memory_update(app, ctx, a):
    return app.memory.update(ctx.agent_id, key=a["key"], value=a["value"], category=a.get("category", "general"),
                             tags=a.get("tags"), expected_version=a.get("expected_version"))


@tool("record_decision", "memory", "Record an architectural/project decision (optionally superseding an earlier one).",
      obj_in({"title": text("Short title.", 200, minLength=1), "decision": text("What was decided.", minLength=1),
              "rationale": text("Why."), "tags": LABELS, "supersedes_id": ident("Decision id this replaces.")}, ["title", "decision"]),
      obj_out({"decision": O.DECISION}))
def record_decision(app, ctx, a):
    return {"decision": app.memory.record_decision(ctx.agent_id, title=a["title"], decision=a["decision"],
                                                   rationale=a.get("rationale"), tags=a.get("tags"),
                                                   supersedes_id=a.get("supersedes_id"))}


# =============================================================== PROJECT
@tool("get_project_status", "project", "Project dashboard: task counts, agents, pending handoffs, git state, recent activity.",
      EMPTY, obj_out({"project": OBJ, "tasks": OBJ, "agents": arr(O.AGENT), "handoffs": OBJ, "messages": OBJ,
                      "memory": OBJ, "git": OBJ, "recent_activity": arr(O.ACTIVITY)}), read_only=True)
def get_project_status(app, ctx, a):
    return app.project.status()


@tool("get_project_context", "project", "Shared project context (rules, active decisions, memory, online agents, activity) "
      "without agent-specific state. Use agent_get_context for your own resume point.",
      obj_in({"activity_limit": prop("integer", "Default 15.", minimum=1, maximum=100)}), O.PROJECT_CONTEXT, read_only=True)
def get_project_context(app, ctx, a):
    return app.project.context(None, activity_limit=a.get("activity_limit", 15))


@tool("get_activity", "project",
      "Shared activity history (who did what, when). Poll with after_id=<next_cursor> to receive only new events.",
      obj_in({"after_id": prop("integer", "Only events with id greater than this.", minimum=0),
              "limit": prop("integer", "Default 50.", minimum=1, maximum=500),
              "agent": prop("string", "Only this actor (agent id).", maxLength=120),
              "action_prefix": prop("string", "e.g. 'task.' or 'file.'.", maxLength=60)}),
      obj_out({"entries": arr(O.ACTIVITY), "next_cursor": NI}), read_only=True)
def get_activity(app, ctx, a):
    return app.project.activity_feed(after_id=a.get("after_id"), limit=a.get("limit", 50), agent_ref=a.get("agent"),
                                     action_prefix=a.get("action_prefix"))


@tool("save_checkpoint", "project",
      "Save a resumable checkpoint (summary, JSON state, modified files, next action). With task_id (a task you own) it "
      "also renews your lease. Another agent can resume from it with restore_checkpoint.",
      obj_in({"summary": text("Where you are.", minLength=1), "task_id": ident("Task this belongs to."),
              "state": prop("object", "Free-form JSON state (max 64 KB)."), "files_modified": FILES,
              "next_action": text("What to do next.")}, ["summary"]),
      obj_out({"checkpoint": O.CHECKPOINT}))
def save_checkpoint(app, ctx, a):
    return {"checkpoint": app.checkpoints.save(ctx.agent_id, summary=a["summary"], task_id=a.get("task_id"),
                                               state=a.get("state"), files_modified=a.get("files_modified"),
                                               next_action=a.get("next_action"))}


@tool("restore_checkpoint", "project",
      "Load a checkpoint (by id, the latest for a task, or your latest). With claim_task=true (default) it also tries to "
      "claim the task for you if it is free or its lease expired; a live owner is never displaced.",
      obj_in({"checkpoint_id": ident("Specific checkpoint."), "task_id": ident("Latest checkpoint for this task."),
              "claim_task": prop("boolean", "Default true.")}),
      obj_out({"checkpoint": O.CHECKPOINT, "task": NOBJ, "claim": OBJ}))
def restore_checkpoint(app, ctx, a):
    return app.checkpoints.restore(ctx.agent_id, checkpoint_id=a.get("checkpoint_id"), task_id=a.get("task_id"),
                                   claim_task=a.get("claim_task", True))


# =============================================================== TERMINAL
@tool("run_command", "terminal",
      "Run a terminal command (e.g. pip install, git status, swift build) in the workspace directory. "
      "Returns stdout, stderr, exit code and duration.",
      obj_in({"command": text("Shell command to run in the workspace directory.", 4000, minLength=1),
              "working_directory": prop("string", "Subdirectory relative to workspace root (optional, defaults to root).", maxLength=500),
              "timeout_seconds": prop("integer", "Maximum execution time in seconds (default 60, max 600).", minimum=1, maximum=600)},
             ["command"]),
      obj_out({"stdout": S, "stderr": S, "exit_code": I,
               "duration_seconds": prop("number", "Execution duration in seconds."),
               "timed_out": B}),
      requires_agent=True)
def run_command(app, ctx, a):
    cmd = a["command"]
    timeout = a.get("timeout_seconds", 60)
    root = app.ws.root.resolve()
    cwd = root
    rel_cwd = a.get("working_directory")
    if rel_cwd:
        target = (root / rel_cwd).resolve()
        try:
            target.relative_to(root)
        except ValueError:
            raise HiveError(PATH_DENIED, f"working directory must be inside workspace: {rel_cwd}")
        if not target.is_dir():
            raise HiveError(NOT_FOUND, f"working directory does not exist: {rel_cwd}")
        cwd = target

    env = dict(os.environ)
    paths = env.get("PATH", "").split(os.pathsep)
    for extra in ("/opt/homebrew/bin", "/usr/local/bin", os.path.expanduser("~/.local/bin"), "/usr/bin", "/bin"):
        if extra not in paths:
            paths.insert(0, extra)
    env["PATH"] = os.pathsep.join(paths)

    start_time = time.time()
    try:
        proc = subprocess.run(
            cmd,
            shell=True,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env
        )
        duration = round(time.time() - start_time, 3)
        res = {
            "stdout": proc.stdout or "",
            "stderr": proc.stderr or "",
            "exit_code": proc.returncode,
            "duration_seconds": duration,
            "timed_out": False
        }
    except subprocess.TimeoutExpired as exc:
        duration = round(time.time() - start_time, 3)
        res = {
            "stdout": exc.stdout if isinstance(exc.stdout, str) else (exc.stdout.decode() if exc.stdout else ""),
            "stderr": (exc.stderr if isinstance(exc.stderr, str) else (exc.stderr.decode() if exc.stderr else "")) + f"\nCommand timed out after {timeout} seconds.",
            "exit_code": -1,
            "duration_seconds": duration,
            "timed_out": True
        }
    app.activity.record(
        agent_id=ctx.agent_id,
        action="command.run",
        summary=f"ran command '{cmd[:100]}'",
        details={"command": cmd, "exit_code": res["exit_code"], "timed_out": res["timed_out"], "duration": duration}
    )
    return res


ALL_TOOLS = TOOLS
