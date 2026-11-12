#!/usr/bin/env python3
"""HEXhand connector for Linux and macOS.

Runs next to the folder you want ChatGPT to work in, and lets a HEXhand server
somewhere else drive that folder. Same ten tools and the same wire format as the
Windows connector (connector/windows/hexhand-connect.ps1).

    ./hexhand-here.sh /path/to/folder          # or just: ./hexhand-here.sh

The workspace is the folder you start it in. Paths outside it are refused.
"""

from __future__ import annotations

import fnmatch
import glob
import json
import os
import re
import shlex
import signal
import subprocess
import sys
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = int(os.environ.get("HEXHAND_CONNECTOR_PORT", "3210"))
TOKEN = os.environ.get("HEXHAND_CONNECTOR_TOKEN", "")
WORKSPACE = Path(os.environ.get("HEXHAND_WORKSPACE", os.getcwd())).resolve()

JOBS: dict[str, dict] = {}
JOBS_LOCK = threading.Lock()


# --------------------------------------------------------------------------- helpers
def text_result(text: str, error: bool = False) -> dict:
    return {"content": [{"type": "text", "text": text}], "isError": error}


def in_workspace(rel: str) -> Path:
    """Resolve rel inside the workspace; raise if it escapes."""
    target = (WORKSPACE / str(rel).lstrip("/\\")).resolve()
    try:
        target.relative_to(WORKSPACE)
    except ValueError:
        raise ValueError("Path is outside the workspace")
    return target


# --------------------------------------------------------------------------- tools
def tool_instruction(_args: dict) -> dict:
    return text_result(
        f"You are working in {WORKSPACE} through the HEXhand connector. "
        "Paths are relative to that folder and nothing outside it is reachable."
    )


def tool_run_command(args: dict) -> dict:
    cmd = str(args.get("command", ""))
    if not cmd:
        return text_result("command is required", True)
    proc = subprocess.run(cmd, shell=True, cwd=WORKSPACE, capture_output=True, text=True)
    out = (proc.stdout or "") + (proc.stderr or "")
    return text_result(f"{out}exit={proc.returncode}")


def _pump(job: dict) -> None:
    proc = job["proc"]
    assert proc.stdout is not None
    for line in proc.stdout:
        with JOBS_LOCK:
            job["output"].append(line)
            if len(job["output"]) > 5000:
                del job["output"][:1000]
    proc.wait()
    with JOBS_LOCK:
        job["status"] = "finished"
        job["exit"] = proc.returncode


def tool_start_command(args: dict) -> dict:
    cmd = str(args.get("command", ""))
    if not cmd:
        return text_result("command is required", True)
    job_id = f"job-{uuid.uuid4().hex[:8]}"
    proc = subprocess.Popen(
        cmd, shell=True, cwd=WORKSPACE, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, bufsize=1,
        # own session: cancel_command kills the job's process group, and without
        # this the connector itself sits in that group and dies with the job
        start_new_session=True,
    )
    job = {"id": job_id, "proc": proc, "output": [], "status": "running", "exit": None}
    with JOBS_LOCK:
        JOBS[job_id] = job
    threading.Thread(target=_pump, args=(job,), daemon=True).start()
    return text_result(f"started {job_id} pid={proc.pid}")


def tool_poll_command(args: dict) -> dict:
    job_id = str(args.get("job_id", ""))
    with JOBS_LOCK:
        job = JOBS.get(job_id)
        if not job:
            return text_result(f"unknown job: {job_id}", True)
        lines = "".join(job["output"])
        # reading drains what we have already returned
        job["output"].clear()
        status = job["status"]
        code = job["exit"]
    tail = "" if code is None else f" (exit={code})"
    return text_result(f"[{status}{tail}]\n{lines}".rstrip())


def tool_cancel_command(args: dict) -> dict:
    job_id = str(args.get("job_id", ""))
    with JOBS_LOCK:
        job = JOBS.get(job_id)
        if not job:
            return text_result(f"unknown job: {job_id}", True)
        proc = job["proc"]
    if proc.poll() is None:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except Exception:
            proc.terminate()
        job["status"] = "cancelled"
    return text_result(f"cancelled {job_id}")


def tool_read(args: dict) -> dict:
    paths = args.get("paths") or []
    if isinstance(paths, str):
        paths = [paths]
    parts = []
    for p in paths:
        try:
            full = in_workspace(p)
        except ValueError as exc:
            parts.append(f"--- {p} ---\n{exc}")
            continue
        if not full.exists():
            parts.append(f"--- {p} ---\n(not found)")
            continue
        try:
            parts.append(f"--- {p} ---\n{full.read_text(errors='replace')}")
        except IsADirectoryError:
            parts.append(f"--- {p} ---\n(directory)")
    return text_result("\n\n".join(parts))


def tool_write(args: dict) -> dict:
    rel = str(args.get("path", ""))
    content = str(args.get("content", ""))
    try:
        full = in_workspace(rel)
    except ValueError as exc:
        return text_result(str(exc), True)
    if args.get("create_dirs"):
        full.parent.mkdir(parents=True, exist_ok=True)
    elif not full.parent.exists():
        return text_result(f"parent folder does not exist: {full.parent}", True)
    full.write_text(content)
    return text_result(f"wrote {full} ({len(content)} chars)")


def tool_edit(args: dict) -> dict:
    rel = str(args.get("path", ""))
    try:
        full = in_workspace(rel)
    except ValueError as exc:
        return text_result(str(exc), True)
    if not full.exists():
        return text_result(f"not found: {rel}", True)
    body = full.read_text()
    applied = 0
    for edit in args.get("edits") or []:
        if edit.get("type") != "replace":
            return text_result(f"unsupported edit type: {edit.get('type')}", True)
        old = str(edit.get("old_string", ""))
        new = str(edit.get("new_string", ""))
        if old not in body:
            return text_result(f"old_string not found in {rel}", True)
        body = body.replace(old, new) if edit.get("replace_all") else body.replace(old, new, 1)
        applied += 1
    full.write_text(body)
    return text_result(f"applied {applied} edit(s) to {full}")


def tool_search(args: dict) -> dict:
    pattern = str(args.get("pattern", ""))
    if not pattern:
        return text_result("pattern is required", True)
    base = args.get("path") or "."
    try:
        root = in_workspace(base)
    except ValueError as exc:
        return text_result(str(exc), True)
    glob_pat = args.get("glob") or "*"
    limit = int(args.get("max_matches") or 100)
    rx = re.compile(pattern)
    hits = []
    for path in glob.iglob(str(root / "**" / glob_pat), recursive=True):
        p = Path(path)
        if not p.is_file() or p.stat().st_size > 4_000_000:
            continue
        try:
            for n, line in enumerate(p.read_text(errors="replace").splitlines(), 1):
                if rx.search(line):
                    hits.append(f"{p}:{n}: {line.strip()}")
                    if len(hits) >= limit:
                        raise StopIteration
        except StopIteration:
            break
        except Exception:
            continue
    return text_result("\n".join(hits) if hits else "no matches")


def tool_delete(args: dict) -> dict:
    rel = str(args.get("path", ""))
    try:
        full = in_workspace(rel)
    except ValueError as exc:
        return text_result(str(exc), True)
    if not full.exists():
        return text_result(f"not found: {rel}", True)
    if full.is_dir():
        if not args.get("recursive"):
            return text_result("path is a directory; pass recursive: true", True)
        import shutil
        shutil.rmtree(full)
    else:
        full.unlink()
    return text_result(f"deleted {full}")


TOOLS = {
    "run_command": tool_run_command,
    "start_command": tool_start_command,
    "poll_command": tool_poll_command,
    "cancel_command": tool_cancel_command,
    "catdesk_instruction": tool_instruction,
    "read": tool_read,
    "write": tool_write,
    "edit": tool_edit,
    "search": tool_search,
    "delete": tool_delete,
}

SCHEMAS = [
    {"name": "run_command", "description": "Run a shell command in the workspace",
     "inputSchema": {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}},
    {"name": "start_command", "description": "Start a long-running command in the background",
     "inputSchema": {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}},
    {"name": "poll_command", "description": "Read output from a background command",
     "inputSchema": {"type": "object", "properties": {"job_id": {"type": "string"}}, "required": ["job_id"]}},
    {"name": "cancel_command", "description": "Stop a background command",
     "inputSchema": {"type": "object", "properties": {"job_id": {"type": "string"}}, "required": ["job_id"]}},
    {"name": "catdesk_instruction", "description": "Workspace instructions",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "read", "description": "Read files in the workspace",
     "inputSchema": {"type": "object", "properties": {"paths": {"type": "array", "items": {"type": "string"}}}, "required": ["paths"]}},
    {"name": "write", "description": "Write a file",
     "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}, "create_dirs": {"type": "boolean"}}, "required": ["path", "content"]}},
    {"name": "edit", "description": "Replace text in a file",
     "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}, "edits": {"type": "array"}}, "required": ["path", "edits"]}},
    {"name": "search", "description": "Search text in the workspace",
     "inputSchema": {"type": "object", "properties": {"pattern": {"type": "string"}, "path": {"type": "string"}, "glob": {"type": "string"}, "max_matches": {"type": "integer"}}, "required": ["pattern"]}},
    {"name": "delete", "description": "Delete a file or folder",
     "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}, "recursive": {"type": "boolean"}}, "required": ["path"]}},
]


# --------------------------------------------------------------------------- server
class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):  # keep the console quiet
        pass

    def _send(self, obj: dict, code: int = 200) -> None:
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _rpc(self) -> dict | None:
        length = int(self.headers.get("Content-Length") or 0)
        payload = json.loads(self.rfile.read(length) or b"{}")
        method = payload.get("method")
        rid = payload.get("id")
        params = payload.get("params") or {}

        if method == "tools/list":
            return {"jsonrpc": "2.0", "id": rid, "result": {"tools": SCHEMAS}}
        if method == "tools/call":
            name = str(params.get("name") or "")
            fn = TOOLS.get(name)
            if not fn:
                return {"jsonrpc": "2.0", "id": rid, "result": text_result(f"unknown tool: {name}", True)}
            try:
                return {"jsonrpc": "2.0", "id": rid, "result": fn(params.get("arguments") or {})}
            except Exception as exc:  # never kill the listener
                return {"jsonrpc": "2.0", "id": rid, "result": text_result(f"{type(exc).__name__}: {exc}", True)}
        if method in ("initialize", "ping"):
            return {"jsonrpc": "2.0", "id": rid, "result": {"protocolVersion": "2026-07-28",
                    "serverInfo": {"name": "hexhand-connector", "version": "0.10.1"},
                    "capabilities": {"tools": {}}}}
        return {"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": "unknown method"}}

    def do_POST(self) -> None:
        auth = self.headers.get("Authorization") or ""
        if TOKEN and auth != f"Bearer {TOKEN}":
            self._send({"error": "unauthorized"}, 401)
            return
        try:
            self._send(self._rpc() or {})
        except Exception as exc:
            self._send({"error": str(exc)}, 500)


def main() -> None:
    if not TOKEN:
        print("HEXHAND_CONNECTOR_TOKEN is not set — refusing to start unauthenticated", file=sys.stderr)
        sys.exit(2)
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"HEXhand connector — workspace {WORKSPACE}")
    print(f"listening on 0.0.0.0:{PORT} (bearer token required)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")


if __name__ == "__main__":
    main()
