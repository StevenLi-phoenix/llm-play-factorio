"""Read-only realtime status page for the opencode-go Factorio run (stdlib only).

  python3 dashboard.py            # DASH_HOST (default: this host's tailscale IPv4, else 127.0.0.1), DASH_PORT (8787)

GET /            the page (dashboard.html)
GET /events      Server-Sent Events: one JSON state snapshot every DASH_EVERY seconds (default 3)
GET /api/state   the same snapshot once
GET /healthz     "ok"
GET /mods        list of the mod zips players install to join the game (DASH_MODS, default ../downloads/mods)
GET /mods/X.zip  one of those zips; only an exact "<name>_<version>.zip" file name that exists in that folder is served

Reads RUNNER_ROOT (runner.json, history.jsonl, kpi.jsonl, board.md, status/, notes/, logs/). Never writes, takes no
path arguments from clients (the /mods file name is matched against a strict pattern and the folder listing), and
agent-written text is sent as data: the page renders it with textContent.
"""
from __future__ import annotations

import json
import logging
import html
import os
import re
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(os.environ.get("RUNNER_ROOT", Path.home() / "factorio-agent/state"))
PAGE = Path(__file__).with_name("dashboard.html")
EVERY = float(os.environ.get("DASH_EVERY", "3"))
MODS_DIR = Path(os.environ.get("DASH_MODS", ROOT.parent / "downloads" / "mods"))
MOD_ZIP = re.compile(r"[A-Za-z0-9_.\-]{1,80}\.zip")
LOG_TAIL_BYTES = 24_000
MAX_POINTS = 240


def tail_lines(path: Path, n: int) -> list[str]:
    try:
        with path.open("rb") as fh:
            fh.seek(0, 2)
            size = fh.tell()
            fh.seek(max(0, size - LOG_TAIL_BYTES))
            data = fh.read().decode("utf-8", "replace")
    except OSError:
        return []
    lines = data.splitlines()
    if size > LOG_TAIL_BYTES:
        lines = lines[1:]                       # first line is cut
    return [l[:400] for l in lines[-n:]]


def read_text(path: Path, limit: int) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")[:limit]
    except OSError:
        return ""


class JsonlCache:
    """Parsed jsonl, re-read only when the file's size or mtime changes."""

    def __init__(self, name: str):
        self.path, self.key, self.rows = ROOT / name, None, []

    def get(self) -> list[dict]:
        try:
            st = self.path.stat()
        except OSError:
            return []
        key = (st.st_size, st.st_mtime_ns)
        if key != self.key:
            rows = []
            for line in self.path.read_text(encoding="utf-8", errors="replace").splitlines():
                try:
                    rows.append(json.loads(line))
                except ValueError:
                    continue
            self.key, self.rows = key, rows
        return self.rows


HIST, KPI = JsonlCache("history.jsonl"), JsonlCache("kpi.jsonl")


def downsample(rows: list[dict], n: int = MAX_POINTS) -> list[dict]:
    if len(rows) <= n:
        return rows
    step = len(rows) / n
    out = [rows[int(i * step)] for i in range(n - 1)]
    out.append(rows[-1])
    return out


def snapshot() -> dict:
    try:
        runner = json.loads((ROOT / "runner.json").read_text())
        age = time.time() - (ROOT / "runner.json").stat().st_mtime
    except (OSError, ValueError):
        runner, age = None, None
    names = sorted((runner or {}).get("agents", {}))
    agents = {}
    for n in names:
        agents[n] = {"status": read_text(ROOT / "status" / f"{n}.txt", 300).strip(),
                     "notes": read_text(ROOT / "notes" / f"{n}.md", 2200),
                     "log": tail_lines(ROOT / "logs" / f"{n}.log", 40)}
    kpi_rows = [{k: r.get(k) for k in ("tick", "done", "produced", "ups", "research", "wall")} | {"bld": sum((r.get("counts") or {}).values())}
                for r in downsample(KPI.get())]
    return {"now": time.time(), "runner_age": age, "runner": runner, "board": read_text(ROOT / "board.md", 4000),
            "agents": agents, "history": downsample(HIST.get()), "kpi_history": kpi_rows,
            "runner_log": tail_lines(ROOT / "logs" / "runner.log", 14)}


def mod_file(name: str, mods_dir: Path = MODS_DIR) -> Path | None:
    """The zip `name` inside mods_dir, or None: only a plain file name matching MOD_ZIP that is a regular file there."""
    if not MOD_ZIP.fullmatch(name) or ".." in name:
        return None
    p = mods_dir / name
    return p if p.is_file() and p.parent == mods_dir else None


def mods_page(mods_dir: Path = MODS_DIR) -> bytes:
    rows = []
    for p in sorted(mods_dir.glob("*.zip")) if mods_dir.is_dir() else []:
        if mod_file(p.name, mods_dir):
            rows.append(f'<li><a href="/mods/{html.escape(p.name)}">{html.escape(p.name)}</a> ({p.stat().st_size // 1024} KB)</li>')
    body = "".join(rows) or "<li>no mod zips yet</li>"
    return ("<!doctype html><meta charset=utf-8><title>Mods</title><h1>Mods to join the game</h1>"
            "<p>Put the zip in your Factorio mods folder (Windows: %APPDATA%\\Factorio\\mods). Game version 2.1.24, "
            "plus the built-in base, space-age, quality, elevated-rails and recycler.</p>"
            f"<ul>{body}</ul>").encode()


class Handler(BaseHTTPRequestHandler):
    server_version = "factorio-dash"
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):  # quiet
        pass

    def _send(self, code: int, body: bytes, ctype: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path == "/":
            self._send(200, PAGE.read_bytes(), "text/html; charset=utf-8")
        elif path == "/api/state":
            self._send(200, json.dumps(snapshot()).encode(), "application/json")
        elif path == "/mods":
            self._send(200, mods_page(), "text/html; charset=utf-8")
        elif path.startswith("/mods/"):
            f = mod_file(path[len("/mods/"):])
            if f is None:
                self._send(404, b"not found", "text/plain")
            else:
                logging.info("mod download %s from %s", f.name, self.client_address[0])
                self._send(200, f.read_bytes(), "application/zip")
        elif path == "/healthz":
            self._send(200, b"ok", "text/plain")
        elif path == "/events":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            try:
                while True:
                    self.wfile.write(b"data: " + json.dumps(snapshot()).encode() + b"\n\n")
                    self.wfile.flush()
                    time.sleep(EVERY)
            except (BrokenPipeError, ConnectionResetError, OSError):
                return
        else:
            self._send(404, b"not found", "text/plain")


def default_host() -> str:
    try:
        out = subprocess.run(["tailscale", "ip", "-4"], capture_output=True, text=True, timeout=5).stdout.split()
        if out:
            return out[0]
    except (OSError, subprocess.SubprocessError):
        pass
    return "127.0.0.1"


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    host, port = os.environ.get("DASH_HOST") or default_host(), int(os.environ.get("DASH_PORT", "8787"))
    srv = Server((host, port), Handler)
    logging.info("dashboard on http://%s:%s root=%s", host, port, ROOT)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
