"""Filesystem service: the only way agents touch project files.

Built on the original design: every path goes through Workspace.resolve (single choke point,
rejects absolute/.. /reserved/.hive/.git/escaping symlinks); every mutation runs under
Workspace.fs_lock (cross-process) and is recorded through ActivityService.

Safeguards
  * overwrite requires expected_sha256 from a prior read (optimistic concurrency; no lost updates)
  * writes are atomic (temp file + fsync + rename in the same directory)
  * delete requires confirm=true and a reason; it MOVES to .hive/trash/<id>/ (recoverable)
  * recursive delete needs recursive=true and is capped
  * text files only (UTF-8, no NUL), with size caps
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
import shutil
import stat
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ..activity import ActivityService
from ..errors import (
    ALREADY_EXISTS, CONFIRMATION_REQUIRED, CONFLICT, FILE_TOO_LARGE, INVALID_ARGUMENT,
    NOT_FOUND, NOT_TEXT, PRECONDITION_REQUIRED, HiveError,
)
from ..util import iso, new_id, now_iso
from ..workspace import PROTECTED, Workspace


@dataclass(frozen=True)
class FileLimits:
    max_read_bytes: int = 2 * 1024 * 1024
    max_write_bytes: int = 5 * 1024 * 1024
    max_list_entries: int = 1000
    max_list_depth: int = 10
    max_recursive_delete_entries: int = 2000


IGNORED_NAMES = frozenset({"node_modules", "__pycache__", "DerivedData"})


def _lstat(p: Path):
    try:
        return os.lstat(p)
    except (FileNotFoundError, NotADirectoryError):   # missing, or a parent component is a file
        return None


def _sha_file(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


class FileService:
    def __init__(self, ws: Workspace, activity: ActivityService, limits: FileLimits = FileLimits()):
        self.ws, self.activity, self.limits = ws, activity, limits

    # ------------------------------------------------------------------ read
    def read(self, path: str, start_line: int = 1, max_lines: int = 2000) -> dict[str, Any]:
        if not (isinstance(start_line, int) and not isinstance(start_line, bool) and start_line >= 1):
            raise HiveError(INVALID_ARGUMENT, "start_line must be an integer >= 1")
        if not (isinstance(max_lines, int) and not isinstance(max_lines, bool) and 1 <= max_lines <= 10000):
            raise HiveError(INVALID_ARGUMENT, "max_lines must be an integer between 1 and 10000")
        r = self.ws.resolve(path)
        st = _lstat(r.path)
        if st is None:
            raise HiveError(NOT_FOUND, f"file not found: {r.rel}", {"path": r.rel})
        if stat.S_ISDIR(st.st_mode):
            raise HiveError(INVALID_ARGUMENT, f"{r.rel} is a directory; use list_files", {"path": r.rel})
        if not stat.S_ISREG(st.st_mode):
            raise HiveError(INVALID_ARGUMENT, f"{r.rel} is not a regular file", {"path": r.rel})
        if st.st_size > self.limits.max_read_bytes:
            raise HiveError(FILE_TOO_LARGE, f"{r.rel} is {st.st_size} bytes; limit is "
                            f"{self.limits.max_read_bytes}", {"path": r.rel, "size": st.st_size})
        data = r.path.read_bytes()
        if len(data) > self.limits.max_read_bytes:
            raise HiveError(FILE_TOO_LARGE, f"{r.rel} grew beyond the read limit", {"path": r.rel})
        try:
            if b"\x00" in data:
                raise UnicodeDecodeError("utf-8", b"", 0, 1, "NUL byte")
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            raise HiveError(NOT_TEXT, f"{r.rel} is not a UTF-8 text file", {"path": r.rel}) from None
        lines = text.splitlines(keepends=True)
        total = len(lines)
        chunk = lines[start_line - 1: start_line - 1 + max_lines]
        end = start_line - 1 + len(chunk)
        return {
            "path": r.rel, "content": "".join(chunk), "sha256": hashlib.sha256(data).hexdigest(),
            "size": len(data), "total_lines": total, "start_line": start_line,
            "end_line": end if chunk else start_line - 1,
            "truncated": end < total, "next_start_line": end + 1 if end < total else None,
        }

    # ----------------------------------------------------------------- write
    def create(self, agent_id: str, path: str, content: str, create_parents: bool = True) -> dict[str, Any]:
        """Create a NEW file; fails with ALREADY_EXISTS instead of overwriting."""
        return self.write(agent_id, path, content, None, create_parents, exclusive=True)

    def write(self, agent_id: str, path: str, content: str, expected_sha256: str | None = None,
              create_parents: bool = True, exclusive: bool = False) -> dict[str, Any]:
        if not isinstance(content, str):
            raise HiveError(INVALID_ARGUMENT, "content must be a string")
        data = content.encode("utf-8")
        if len(data) > self.limits.max_write_bytes:
            raise HiveError(FILE_TOO_LARGE, f"content is {len(data)} bytes; limit is "
                            f"{self.limits.max_write_bytes}", {"size": len(data)})
        r = self.ws.resolve(path)
        with self.ws.fs_lock():
            st = _lstat(r.path)
            previous = None
            if st is not None:
                if exclusive:
                    raise HiveError(ALREADY_EXISTS, f"{r.rel} already exists", {"path": r.rel},
                                    hint="Use write_file with expected_sha256 to modify it.")
                if stat.S_ISDIR(st.st_mode):
                    raise HiveError(INVALID_ARGUMENT, f"{r.rel} is a directory", {"path": r.rel})
                if not stat.S_ISREG(st.st_mode):
                    raise HiveError(INVALID_ARGUMENT, f"{r.rel} is not a regular file", {"path": r.rel})
                previous = _sha_file(r.path)
                if expected_sha256 is None:
                    raise HiveError(PRECONDITION_REQUIRED,
                                    f"{r.rel} already exists; pass expected_sha256 from read_file to overwrite it",
                                    {"path": r.rel, "current_sha256": previous},
                                    hint="Call read_file first, merge your change, then retry with its sha256.")
                if expected_sha256 != previous:
                    raise HiveError(CONFLICT, f"{r.rel} changed since you read it",
                                    {"path": r.rel, "current_sha256": previous, "expected_sha256": expected_sha256},
                                    hint="Re-read the file, re-apply your change on top of the current content, retry.")
            else:
                if expected_sha256 is not None:
                    raise HiveError(CONFLICT, f"{r.rel} no longer exists (expected an existing file)",
                                    {"path": r.rel, "expected_sha256": expected_sha256})
                self._ensure_parent(r.path, create_parents, r.rel)
            self._atomic_write(r.path, data, copy_mode_from=r.path if st is not None else None)
            sha = hashlib.sha256(data).hexdigest()
            created = st is None
            self.activity.record(
                agent_id=agent_id, action="file.create" if created else "file.write",
                summary=f"{'created' if created else 'wrote'} {r.rel} ({len(data)} bytes)",
                target_type="file", target_id=r.rel,
                details={"sha256": sha, "previous_sha256": previous, "size": len(data)})
        return {"path": r.rel, "created": created, "sha256": sha, "previous_sha256": previous,
                "size": len(data)}

    def _ensure_parent(self, target: Path, create: bool, rel: str) -> None:
        parent = target.parent
        if parent.is_dir():
            return
        if not create:
            raise HiveError(NOT_FOUND, f"parent directory of {rel} does not exist; "
                            "pass create_parents=true", {"path": rel})
        try:
            os.makedirs(parent, exist_ok=True)
        except (FileExistsError, NotADirectoryError):
            raise HiveError(ALREADY_EXISTS, f"a parent of {rel} is an existing file", {"path": rel}) from None

    @staticmethod
    def _atomic_write(target: Path, data: bytes, copy_mode_from: Path | None) -> None:
        tmp = target.with_name(f".{target.name}.hive-{secrets.token_hex(4)}.tmp")
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(data)
                f.flush()
                os.fsync(f.fileno())
            if copy_mode_from is not None:
                shutil.copymode(copy_mode_from, tmp)
            os.replace(tmp, target)
        except BaseException:
            try:
                os.unlink(tmp)
            except FileNotFoundError:
                pass
            raise

    # ----------------------------------------------------------- create_folder
    def create_folder(self, agent_id: str, path: str, parents: bool = True) -> dict[str, Any]:
        r = self.ws.resolve(path)
        with self.ws.fs_lock():
            st = _lstat(r.path)
            if st is not None:
                if stat.S_ISDIR(st.st_mode):
                    return {"path": r.rel, "created": False}
                raise HiveError(ALREADY_EXISTS, f"{r.rel} exists and is not a directory", {"path": r.rel})
            try:
                if parents:
                    os.makedirs(r.path)
                else:
                    os.mkdir(r.path)
            except FileNotFoundError:
                raise HiveError(NOT_FOUND, f"parent of {r.rel} does not exist; pass parents=true",
                                {"path": r.rel}) from None
            except (FileExistsError, NotADirectoryError):
                raise HiveError(ALREADY_EXISTS, f"a parent of {r.rel} is an existing file", {"path": r.rel}) from None
            self.activity.record(agent_id=agent_id, action="folder.create", summary=f"created folder {r.rel}",
                                 target_type="folder", target_id=r.rel)
        return {"path": r.rel, "created": True}

    # -------------------------------------------------------------------- list
    def list(self, path: str = ".", recursive: bool = False, max_depth: int | None = None,
             include_hidden: bool = False, limit: int | None = None) -> dict[str, Any]:
        r = self.ws.resolve(path, allow_root=True)
        st = _lstat(r.path)
        if st is None:
            raise HiveError(NOT_FOUND, f"directory not found: {r.rel}", {"path": r.rel})
        if not stat.S_ISDIR(st.st_mode):
            raise HiveError(INVALID_ARGUMENT, f"{r.rel} is not a directory", {"path": r.rel})
        depth_limit = 1 if not recursive else min(max_depth or 4, self.limits.max_list_depth)
        cap = min(limit or self.limits.max_list_entries, self.limits.max_list_entries)
        entries: list[dict] = []
        state = {"truncated": False}
        prefix = "" if r.rel == "." else r.rel

        def walk(dirpath: Path, rel_prefix: str, depth: int) -> None:
            try:
                with os.scandir(dirpath) as it:
                    items = sorted(it, key=lambda e: (not e.is_dir(follow_symlinks=False), e.name.casefold()))
            except (FileNotFoundError, NotADirectoryError, PermissionError):
                return
            for e in items:
                if e.name.casefold() in PROTECTED:
                    continue
                if not include_hidden and (e.name.startswith(".") or e.name in IGNORED_NAMES):
                    continue
                if len(entries) >= cap:
                    state["truncated"] = True
                    return
                try:
                    es = e.stat(follow_symlinks=False)
                except FileNotFoundError:
                    continue
                if e.is_symlink():
                    kind = "symlink"
                elif stat.S_ISDIR(es.st_mode):
                    kind = "dir"
                elif stat.S_ISREG(es.st_mode):
                    kind = "file"
                else:
                    kind = "other"
                rel = f"{rel_prefix}/{e.name}" if rel_prefix else e.name
                entries.append({"name": e.name, "path": rel, "type": kind,
                                "size": es.st_size if kind == "file" else None,
                                "modified": iso(datetime.fromtimestamp(es.st_mtime, timezone.utc))})
                if kind == "dir" and depth < depth_limit:
                    walk(Path(e.path), rel, depth + 1)
                    if state["truncated"]:
                        return

        walk(r.path, prefix, 1)
        return {"path": r.rel, "entries": entries, "truncated": state["truncated"]}

    # -------------------------------------------------------------------- move
    def move(self, agent_id: str, src: str, dst: str, create_parents: bool = False) -> dict[str, Any]:
        s = self.ws.resolve(src, follow_final=False)
        d = self.ws.resolve(dst, follow_final=False)
        if d.rel == s.rel or d.rel.startswith(s.rel + "/"):
            raise HiveError(INVALID_ARGUMENT, "cannot move a path onto or into itself", {"from": s.rel, "to": d.rel})
        with self.ws.fs_lock():
            if _lstat(s.path) is None:
                raise HiveError(NOT_FOUND, f"source not found: {s.rel}", {"path": s.rel})
            if os.path.lexists(d.path):
                same = False
                try:
                    same = os.path.samefile(s.path, d.path)   # case-only rename on case-insensitive volumes
                except OSError:
                    pass
                if not same:
                    raise HiveError(ALREADY_EXISTS, f"destination already exists: {d.rel}", {"path": d.rel})
            self._ensure_parent(d.path, create_parents, d.rel)
            os.rename(s.path, d.path)
            self.activity.record(agent_id=agent_id, action="file.move", summary=f"moved {s.rel} -> {d.rel}",
                                 target_type="file", target_id=d.rel, details={"from": s.rel, "to": d.rel})
        return {"from": s.rel, "to": d.rel}

    # ------------------------------------------------------------------ delete
    def delete(self, agent_id: str, path: str, confirm: bool, reason: str,
               recursive: bool = False) -> dict[str, Any]:
        if confirm is not True:
            raise HiveError(CONFIRMATION_REQUIRED, "delete requires confirm=true", hint=
                            "Deletion is recoverable (moved to .hive/trash) but must be explicit.")
        if not isinstance(reason, str) or not reason.strip() or len(reason) > 500:
            raise HiveError(INVALID_ARGUMENT, "reason is required (1-500 characters)")
        r = self.ws.resolve(path, follow_final=False)
        with self.ws.fs_lock():
            st = _lstat(r.path)
            if st is None:
                raise HiveError(NOT_FOUND, f"not found: {r.rel}", {"path": r.rel})
            is_dir = stat.S_ISDIR(st.st_mode)
            count = 1
            if is_dir:
                count = self._count_entries(r.path)
                if count > 0 and not recursive:
                    raise HiveError(CONFLICT, f"{r.rel} is a non-empty directory ({count} entries); "
                                    "pass recursive=true", {"path": r.rel, "entries": count})
                if count > self.limits.max_recursive_delete_entries:
                    raise HiveError(CONFLICT, f"{r.rel} has {count} entries; limit is "
                                    f"{self.limits.max_recursive_delete_entries}. Delete in smaller parts "
                                    "or ask the user.", {"path": r.rel, "entries": count})
            trash_id = new_id("trash")
            tdir = self.ws.trash_dir / trash_id
            tdir.mkdir(parents=True)
            kind = "dir" if is_dir else ("symlink" if stat.S_ISLNK(st.st_mode) else "file")
            try:
                os.rename(r.path, tdir / "item")
            except OSError as exc:
                shutil.rmtree(tdir, ignore_errors=True)
                raise HiveError(CONFLICT, f"could not move {r.rel} to trash: {exc.strerror}", {"path": r.rel}) from None
            (tdir / "meta.json").write_text(json.dumps({
                "original_path": r.rel, "kind": kind, "entries": count, "deleted_at": now_iso(),
                "deleted_by": agent_id, "reason": reason.strip()}, indent=2) + "\n", encoding="utf-8")
            self.activity.record(agent_id=agent_id, action="file.delete", summary=f"deleted {r.rel} ({kind})",
                                 target_type="file", target_id=r.rel,
                                 details={"trash_id": trash_id, "kind": kind, "entries": count,
                                          "reason": reason.strip()})
        return {"path": r.rel, "kind": kind, "entries": count, "trash_id": trash_id, "recoverable": True}

    # ----------------------------------------------------------------- trash
    _TRASH_RE = re.compile(r"^trash_[0-9a-f]{10}$")

    def list_trash(self) -> dict[str, Any]:
        items = []
        if self.ws.trash_dir.is_dir():
            for d in self.ws.trash_dir.iterdir():
                try:
                    if not self._TRASH_RE.match(d.name):
                        continue
                    meta = json.loads((d / "meta.json").read_text(encoding="utf-8"))
                    items.append({"trash_id": d.name, "original_path": meta["original_path"], "kind": meta["kind"],
                                  "entries": meta["entries"], "deleted_at": meta["deleted_at"],
                                  "deleted_by": meta["deleted_by"], "reason": meta["reason"]})
                except (OSError, ValueError, KeyError):
                    continue
        items.sort(key=lambda i: (i["deleted_at"], i["trash_id"]), reverse=True)
        return {"items": items, "count": len(items)}

    def restore(self, agent_id: str, trash_id: str, to_path: str | None = None) -> dict[str, Any]:
        if not isinstance(trash_id, str) or not self._TRASH_RE.match(trash_id):
            raise HiveError(INVALID_ARGUMENT, "trash_id must look like trash_xxxxxxxxxx (returned by delete_file)")
        tdir = self.ws.trash_dir / trash_id
        with self.ws.fs_lock():
            item = tdir / "item"
            try:
                meta = json.loads((tdir / "meta.json").read_text(encoding="utf-8"))
            except (OSError, ValueError):
                raise HiveError(NOT_FOUND, f"nothing in trash with id {trash_id}", {"trash_id": trash_id}) from None
            if not os.path.lexists(item):
                raise HiveError(NOT_FOUND, f"trash item {trash_id} has no content", {"trash_id": trash_id})
            r = self.ws.resolve(to_path or meta["original_path"], follow_final=False)
            if os.path.lexists(r.path):
                raise HiveError(ALREADY_EXISTS, f"{r.rel} already exists; nothing was restored",
                                {"path": r.rel, "trash_id": trash_id}, hint="Pass to_path to restore it elsewhere.")
            self._ensure_parent(r.path, True, r.rel)
            os.rename(item, r.path)
            shutil.rmtree(tdir, ignore_errors=True)
            self.activity.record(agent_id=agent_id, action="file.restore", summary=f"restored {r.rel} from trash",
                                 target_type="file", target_id=r.rel,
                                 details={"trash_id": trash_id, "original_path": meta["original_path"],
                                          "kind": meta["kind"]})
        return {"path": r.rel, "kind": meta["kind"], "entries": meta["entries"], "restored_from": trash_id}

    @staticmethod
    def _count_entries(p: Path) -> int:
        n = 0
        for _root, dirs, files in os.walk(p, followlinks=False):
            n += len(dirs) + len(files)
        return n
