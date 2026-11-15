"""Structured errors. RECONSTRUCTED: the original file was overwritten by accident.

Compatibility contract (from surviving callers in workspace.py):
  * HiveError(code, message, details_dict)  -- details is the 3rd positional argument
  * module-level code constants INVALID_ARGUMENT, NOT_INITIALIZED, PATH_DENIED
Codes are plain strings equal to their constant names; they are part of the client contract.
"""

from __future__ import annotations

from typing import Any

# --- codes required by surviving original code ---
INVALID_ARGUMENT = "INVALID_ARGUMENT"
NOT_INITIALIZED = "NOT_INITIALIZED"
PATH_DENIED = "PATH_DENIED"

# --- codes added for new work (additive) ---
NOT_FOUND = "NOT_FOUND"
ALREADY_EXISTS = "ALREADY_EXISTS"
CONFLICT = "CONFLICT"
PRECONDITION_REQUIRED = "PRECONDITION_REQUIRED"
CONFIRMATION_REQUIRED = "CONFIRMATION_REQUIRED"
PERMISSION_DENIED = "PERMISSION_DENIED"
FILE_TOO_LARGE = "FILE_TOO_LARGE"
NOT_TEXT = "NOT_TEXT"
AGENT_NOT_REGISTERED = "AGENT_NOT_REGISTERED"
UNKNOWN_TOOL = "UNKNOWN_TOOL"
INTERNAL = "INTERNAL"
AUTH_FAILED = "AUTH_FAILED"
AMBIGUOUS_AGENT = "AMBIGUOUS_AGENT"
TASK_NOT_OWNED = "TASK_NOT_OWNED"
TASK_ALREADY_CLAIMED = "TASK_ALREADY_CLAIMED"
TASK_CLOSED = "TASK_CLOSED"
TASK_LIMIT_REACHED = "TASK_LIMIT_REACHED"
DEPENDENCY_UNMET = "DEPENDENCY_UNMET"
DEPENDENCY_CYCLE = "DEPENDENCY_CYCLE"
HANDOFF_ALREADY_ACCEPTED = "HANDOFF_ALREADY_ACCEPTED"
BUSY = "BUSY"
NO_WORKSPACE = "NO_WORKSPACE"
UNAUTHORIZED = "UNAUTHORIZED"

# --- project identity (explicit agent <-> project association) ---
PROJECT_MISMATCH = "PROJECT_MISMATCH"    # the connection is bound to a different project than the one requested
PROJECT_REQUIRED = "PROJECT_REQUIRED"    # multi-project connection: agent_register needs a project_id
PROJECT_UNKNOWN = "PROJECT_UNKNOWN"      # project_id is not registered, moved, or no longer matches its folder


class HiveError(Exception):
    def __init__(
        self,
        code: str,
        message: str,
        details: dict[str, Any] | None = None,
        *,
        hint: str | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.details = details or {}
        self.hint = hint

    def to_dict(self) -> dict[str, Any]:
        out: dict[str, Any] = {"code": self.code, "message": self.message}
        if self.details:
            out["details"] = self.details
        if self.hint:
            out["hint"] = self.hint
        return out
