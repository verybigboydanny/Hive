"""Local HTTP server for the SwiftUI app (stdlib only).

Security model (local desktop app, not a network service):
  * binds loopback only (127.0.0.1 / ::1 / localhost); refuses anything else
  * every endpoint except GET /v1/health needs `Authorization: Bearer <token>` (constant-time compare)
  * the token is random per process and printed once on stdout in the 'ready' line; it is never written to disk
  * requests carrying an `Origin` header (i.e. from a browser page) are rejected; the Host header must be loopback
    (defence against CSRF and DNS rebinding by web pages)
  * request bodies are capped (1 MiB), JSON objects only
"""

from __future__ import annotations

import hmac
import json
import logging
import os
import secrets
import signal
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

from .. import CONTRACT_VERSION, __version__
from ..app import HiveApp
from ..errors import INTERNAL, INVALID_ARGUMENT, NOT_FOUND, UNAUTHORIZED, HiveError
from ..logging_setup import setup_logging
from . import routes

log = logging.getLogger("hive.api")
MAX_BODY = 1024 * 1024
LOOPBACK = {"127.0.0.1", "localhost", "::1", "[::1]"}


class ApiServer:
    def __init__(self, workspace: str | None = None, host: str = "127.0.0.1", port: int = 0, token: str | None = None):
        if host not in LOOPBACK:
            raise HiveError(INVALID_ARGUMENT, f"refusing to bind '{host}': the API is loopback-only")
        if token is not None and len(token) < 16:
            raise HiveError(INVALID_ARGUMENT, "token must be at least 16 characters")
        self.state = routes.ApiState()
        self.token = token or secrets.token_urlsafe(32)
        if workspace:
            self.state.swap(HiveApp.open(Path(workspace)))
        outer = self

        class Handler(_Handler):
            server_ctx = outer

        self.httpd = ThreadingHTTPServer((host, port), Handler)
        self.httpd.daemon_threads = True
        self.host, self.port = host, self.httpd.server_address[1]
        self._thread: threading.Thread | None = None

    def start(self) -> "ApiServer":
        self._thread = threading.Thread(target=self.httpd.serve_forever, name="hive-api", daemon=True)
        self._thread.start()
        log.info("API listening on %s:%s", self.host, self.port)
        return self

    def shutdown(self) -> None:
        self.state.stopping.set()                        # ends SSE streams
        self.httpd.shutdown()
        self.httpd.server_close()
        self.state.swap(None)
        if self._thread:
            self._thread.join(timeout=5)
        log.info("API stopped")

    @property
    def allowed_hosts(self) -> set[str]:
        return {f"{h}:{self.port}" for h in LOOPBACK} | LOOPBACK


class _Handler(BaseHTTPRequestHandler):
    server_ctx: ApiServer
    protocol_version = "HTTP/1.1"
    timeout = 30

    def log_message(self, fmt, *args):             # stdlib access logs -> our logger (stderr/file), never stdout
        log.debug("%s %s", self.address_string(), fmt % args)

    def _send(self, status: int, body: dict, extra: dict | None = None) -> None:
        raw = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(raw)

    def _error(self, exc: HiveError, status: int | None = None, extra: dict | None = None) -> None:
        self._send(status or routes.status_for(exc.code), {"ok": False, "error": exc.to_dict()}, extra)

    def _authorized(self) -> bool:
        scheme, _, tok = self.headers.get("Authorization", "").partition(" ")
        return scheme.lower() == "bearer" and hmac.compare_digest(tok.strip().encode(), self.server_ctx.token.encode())

    def _guard(self) -> bool:
        if self.headers.get("Origin") is not None:
            self._error(HiveError("FORBIDDEN_ORIGIN", "browser-originated requests are not allowed"), 403)
            return False
        if (self.headers.get("Host") or "").lower() not in self.server_ctx.allowed_hosts:
            self._error(HiveError("FORBIDDEN_HOST", "unexpected Host header"), 403)
            return False
        return True

    def _dispatch(self, method: str) -> None:
        try:
            if not self._guard():
                return
            url = urlsplit(self.path)
            fn, params, public, allowed = routes.match(method, url.path)
            if fn is None:
                if allowed:
                    return self._send(405, {"ok": False, "error": {"code": "METHOD_NOT_ALLOWED", "message": "method not allowed"}},
                                      {"Allow": ", ".join(sorted(set(allowed)))})
                return self._error(HiveError(NOT_FOUND, f"no such endpoint: {method} {url.path}"))
            if not public and not self._authorized():
                return self._error(HiveError(UNAUTHORIZED, "missing or invalid bearer token"), 401, {"WWW-Authenticate": "Bearer"})
            body = None
            if method == "POST":
                length = int(self.headers.get("Content-Length") or 0)
                if length > MAX_BODY:
                    return self._error(HiveError("FILE_TOO_LARGE", f"body exceeds {MAX_BODY} bytes"), 413)
                raw = self.rfile.read(length) if length else b""
                try:
                    body = json.loads(raw.decode("utf-8")) if raw else None
                except (ValueError, UnicodeDecodeError):
                    return self._error(HiveError(INVALID_ARGUMENT, "request body is not valid JSON"))
            req = routes.Request(method, url.path, routes.parse_query(url.query), body)
            if url.path == "/v1/events":
                return self._stream_events(req)
            status, payload = fn(self.server_ctx.state, req, params)
            self._send(status, payload)
        except HiveError as exc:
            self._error(exc)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception:
            log.exception("unhandled error in %s %s", method, self.path)
            self._error(HiveError(INTERNAL, "internal error (see the Hive log)"))

    def do_GET(self):
        self._dispatch("GET")

    def do_POST(self):
        self._dispatch("POST")

    def do_PUT(self):
        self._dispatch("PUT")

    do_DELETE = do_PATCH = do_PUT

    def _stream_events(self, req: routes.Request) -> None:
        st = self.server_ctx.state
        app = st.require_app()
        cursor = routes.q_int(req, "after_id", None, 0, 2**62)
        if cursor is None:                              # default: only events from now on
            with app.db.read() as c:
                cursor = c.execute("SELECT COALESCE(MAX(id),0) FROM activity").fetchone()[0]
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        self.wfile.write(b"retry: 2000\n\n"); self.wfile.flush()
        last_beat = time.time()
        try:
            while not st.stopping.is_set() and st.app is app:
                feed = app.project.activity_feed(after_id=cursor, limit=200)
                for e in feed["entries"]:
                    self.wfile.write(f"id: {e['id']}\nevent: activity\ndata: {json.dumps(e, ensure_ascii=False)}\n\n".encode())
                if feed["entries"]:
                    cursor = feed["next_cursor"]; last_beat = time.time(); self.wfile.flush()
                elif time.time() - last_beat > 15:
                    self.wfile.write(b": keepalive\n\n"); self.wfile.flush(); last_beat = time.time()
                st.stopping.wait(0.3)
        except (BrokenPipeError, ConnectionResetError, TimeoutError, OSError):
            pass


def run_api(*, workspace: str | None, host: str, port: int, token: str | None, log_level: str = "INFO") -> int:
    try:
        setup_logging(None, level=log_level, to_stderr=True)
        srv = ApiServer(workspace, host, port, token)
    except HiveError as exc:
        print(json.dumps({"ok": False, "error": exc.to_dict()}), file=sys.stderr)
        return 2
    if workspace:
        setup_logging(srv.state.app.ws.hive_dir, level=log_level, to_stderr=True)
    stop = threading.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: stop.set())
    srv.start()
    print(json.dumps({"event": "ready", "host": srv.host, "port": srv.port, "token": srv.token, "pid": os.getpid(),
                      "workspace": str(srv.state.app.ws.root) if srv.state.app else None,
                      "backend_version": __version__, "contract_version": CONTRACT_VERSION}), flush=True)
    stop.wait()
    srv.shutdown()
    return 0
