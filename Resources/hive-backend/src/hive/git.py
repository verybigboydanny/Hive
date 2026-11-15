"""Read-only git helpers. Git is run without a shell, with a timeout, and with fsmonitor
disabled: a malicious repo config can otherwise execute arbitrary commands during `git status`."""
import os
import subprocess
from pathlib import Path

_BASE = ["git", "-c", "core.fsmonitor=false", "-c", "protocol.ext.allow=never"]


def _git(root: Path, *args: str, timeout: float = 5.0) -> str:
    env = {**os.environ, "GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"}
    p = subprocess.run([*_BASE, "-C", str(root), *args], capture_output=True, text=True,
                       timeout=timeout, env=env, shell=False)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip() or f"git exited {p.returncode}")
    return p.stdout


def git_summary(root: Path) -> dict:
    try:
        if _git(root, "rev-parse", "--is-inside-work-tree").strip() != "true":
            return {"is_repo": False}
    except (RuntimeError, OSError, subprocess.TimeoutExpired):
        return {"is_repo": False}
    out: dict = {"is_repo": True}
    try:
        out["branch"] = _git(root, "rev-parse", "--abbrev-ref", "HEAD").strip()
        out["head"] = _git(root, "rev-parse", "HEAD").strip()
    except RuntimeError:          # repo with no commits yet
        out["branch"], out["head"] = None, None
    try:
        lines = [l for l in _git(root, "status", "--porcelain=v1").splitlines() if l]
        out["dirty_files"] = len(lines)
    except (RuntimeError, subprocess.TimeoutExpired):
        out["dirty_files"] = None
    return out
