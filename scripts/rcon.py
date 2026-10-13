"""Minimal RCON client (stdlib only) for server admin scripts.

Usage: python -I scripts/rcon.py "/silent-command rcon.print(game.tick)"
Reads host/port/password from FACTORIO_RCON_* env vars, else runtime/factorio/config/rconpw.
"""
import os
import socket
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _send(sock, req_id, kind, body):
    data = body.encode("utf-8")
    sock.sendall(struct.pack("<iii", len(data) + 10, req_id, kind) + data + b"\x00\x00")


def _recv(sock):
    def exact(n):
        buf = b""
        while len(buf) < n:
            chunk = sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("RCON connection closed")
            buf += chunk
        return buf
    (size,) = struct.unpack("<i", exact(4))
    req_id, kind = struct.unpack("<ii", exact(8))
    return req_id, kind, exact(size - 8)[:-2].decode("utf-8", "replace")


def command(cmd: str, timeout: float = 30.0) -> str:
    host = os.environ.get("FACTORIO_RCON_HOST", "127.0.0.1")
    port = int(os.environ.get("FACTORIO_RCON_PORT", "27015"))
    pw = os.environ.get("FACTORIO_RCON_PASSWORD") or (ROOT / "runtime/factorio/config/rconpw").read_text().strip()
    with socket.create_connection((host, port), timeout=timeout) as s:
        _send(s, 1, 3, pw)
        if _recv(s)[0] == -1:
            raise PermissionError("RCON auth failed")
        _send(s, 2, 2, cmd)
        return _recv(s)[2]


if __name__ == "__main__":
    print(command(" ".join(sys.argv[1:])))
