"""SQLite access. RECONSTRUCTED: the original file was overwritten by accident.

Compatibility contract (from surviving callers):
  * `Database` is defined here (db/migrations.py does `from . import Database`)
  * Database(path); .connect() -> sqlite3.Connection in autocommit mode (callers issue
    explicit BEGIN/COMMIT; migrations.py runs executescript with its own BEGIN IMMEDIATE)
  * .write() / .read() context managers yielding a connection (activity.py, workspace.py)

Writers use BEGIN IMMEDIATE so read-check-write sequences (claims, handoff accepts,
precondition checks) are atomic across threads AND processes.
"""

from __future__ import annotations

import contextlib
import sqlite3
from pathlib import Path
from typing import Iterator


class Database:
    def __init__(self, path: Path) -> None:
        self.path = Path(path)

    def connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path, timeout=15, isolation_level=None)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA busy_timeout=15000")  # first: later pragmas may need the lock
        conn.execute("PRAGMA journal_mode=WAL")    # persistent; no-op once the file is WAL
        conn.execute("PRAGMA foreign_keys=ON")
        conn.execute("PRAGMA synchronous=NORMAL")
        return conn

    @contextlib.contextmanager
    def write(self) -> Iterator[sqlite3.Connection]:
        conn = self.connect()
        try:
            conn.execute("BEGIN IMMEDIATE")
            try:
                yield conn
            except BaseException:
                conn.execute("ROLLBACK")
                raise
            else:
                conn.execute("COMMIT")
        finally:
            conn.close()

    @contextlib.contextmanager
    def read(self) -> Iterator[sqlite3.Connection]:
        conn = self.connect()
        try:
            conn.execute("BEGIN")
            try:
                yield conn
            finally:
                conn.execute("ROLLBACK")
        finally:
            conn.close()
