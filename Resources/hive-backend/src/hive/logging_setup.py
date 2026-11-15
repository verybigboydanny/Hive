"""Logging. File + stderr ONLY: with the stdio MCP transport, stdout carries protocol frames and any
stray print() would corrupt the session."""

from __future__ import annotations

import logging
import logging.handlers
import sys
from pathlib import Path

_TAG = "_hive_handler"


def setup_logging(hive_dir: Path | None, *, level: str = "INFO", to_stderr: bool = True) -> logging.Logger:
    log = logging.getLogger("hive")
    log.setLevel(getattr(logging, level.upper(), logging.INFO))
    log.propagate = False
    for h in list(log.handlers):                       # idempotent: replace our own handlers only
        if getattr(h, _TAG, False):
            log.removeHandler(h); h.close()
    fmt = logging.Formatter("%(asctime)s %(levelname)s [%(process)d] %(name)s: %(message)s")
    handlers: list[logging.Handler] = []
    if hive_dir is not None:
        d = Path(hive_dir) / "logs"
        d.mkdir(parents=True, exist_ok=True)
        handlers.append(logging.handlers.RotatingFileHandler(d / "hive.log", maxBytes=1_000_000, backupCount=3,
                                                             encoding="utf-8"))
    if to_stderr:
        handlers.append(logging.StreamHandler(sys.stderr))
    for h in handlers:
        h.setFormatter(fmt); setattr(h, _TAG, True); log.addHandler(h)
    return log
