"""Roll map seeds until the start area has healthy resources (run on the game host).

Usage: python3 pick_seed.py <factorio-dir> <config-dir> <out-save.zip> [max_tries]

For each seed: create a map with the run's map-gen/map-settings, host it headless on a scratch port, generate
the chunks around spawn over RCON, total each resource within 200 tiles and the distance of its nearest tile,
then stop it. The first map that meets MIN_* wins and is copied to <out-save.zip>. Every try is logged to
stdout (one JSON line) so the choice can be audited. The live run server must be stopped first.
"""
import json
import os
import random
import re
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# amount totals within 200 tiles of spawn, and nearest-tile distance (tiles)
MIN_TOTAL = {"iron-ore": 80_000, "copper-ore": 60_000, "coal": 60_000, "stone": 40_000}
MAX_NEAREST = {"iron-ore": 110, "copper-ore": 110, "coal": 110, "stone": 130}
MIN_WATER_TILES = 400
GAME_PORT, RCON_PORT = 34998, 27998

LUA = r"""
local s = game.surfaces.nauvis
s.request_to_generate_chunks({0, 0}, 8)
s.force_generate_chunk_requests()
local tot, near = {}, {}
for _, e in pairs(s.find_entities_filtered{type = "resource", area = {{-200, -200}, {200, 200}}}) do
  local n = e.name
  tot[n] = (tot[n] or 0) + e.amount
  local d = math.sqrt(e.position.x ^ 2 + e.position.y ^ 2)
  if not near[n] or d < near[n] then near[n] = d end
end
local water = s.count_tiles_filtered{name = {"water", "deepwater"}, area = {{-200, -200}, {200, 200}}}
rcon.print(helpers.table_to_json({total = tot, nearest = near, water = water}))
"""


def _pkt(sock, rid, kind, body):
    b = body.encode()
    sock.sendall(struct.pack("<iii", len(b) + 10, rid, kind) + b + b"\x00\x00")


def _recv(sock):
    def exact(n):
        buf = b""
        while len(buf) < n:
            c = sock.recv(n - len(buf))
            if not c:
                raise ConnectionError("rcon closed")
            buf += c
        return buf
    (size,) = struct.unpack("<i", exact(4))
    rid, kind = struct.unpack("<ii", exact(8))
    return rid, kind, exact(size - 8)[:-2].decode("utf-8", "replace")


def rcon(pw, cmd, timeout=120):
    with socket.create_connection(("127.0.0.1", RCON_PORT), timeout=timeout) as s:
        _pkt(s, 1, 3, pw)
        _recv(s)
        _pkt(s, 2, 2, cmd)
        return _recv(s)[2]


def evaluate(fdir, cfg, seed, work):
    save = work / f"s{seed}.zip"
    ini = work / "config.ini"
    ini.write_text(f"[path]\nread-data={fdir}/data\nwrite-data={work}\n[other]\ncheck_updates=false\n")
    exe = f"{fdir}/bin/x64/factorio"
    mg = json.loads((cfg / "map-gen-settings.json").read_text())
    mg["seed"] = seed
    (work / "mg.json").write_text(json.dumps(mg))
    subprocess.run([exe, "-c", str(ini), "--create", str(save), "--map-gen-settings", str(work / "mg.json"),
                    "--map-settings", str(cfg / "map-settings.json")], check=True, capture_output=True)
    pw = "pick"
    proc = subprocess.Popen([exe, "-c", str(ini), "--start-server", str(save), "--port", str(GAME_PORT),
                             "--rcon-bind", f"127.0.0.1:{RCON_PORT}", "--rcon-password", pw,
                             "--server-settings", str(cfg / "server-settings.json")],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
    try:
        out = None
        for _ in range(60):
            time.sleep(1)
            try:
                out = rcon(pw, "/silent-command " + re.sub(r"\s+", " ", LUA))
                if out.strip():
                    break
                out = None  # RCON listens before the map is ready; it answers with nothing until then
            except OSError:
                continue
        if out is None:
            raise RuntimeError("rcon never came up")
        try:
            return save, json.loads(out)
        except ValueError:
            raise RuntimeError(f"unexpected rcon reply: {out[:300]!r}")
    finally:
        proc.terminate()
        proc.wait(timeout=30)


def ok(r):
    tot, near = r.get("total", {}), r.get("nearest", {})
    for k, need in MIN_TOTAL.items():
        if tot.get(k, 0) < need or near.get(k, 1e9) > MAX_NEAREST[k]:
            return False
    return r.get("water", 0) >= MIN_WATER_TILES


def main():
    fdir, cfg, out = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
    tries = int(sys.argv[4]) if len(sys.argv) > 4 else 12
    work = Path(tempfile.mkdtemp(prefix="pickseed-"))
    rng = random.Random()
    try:
        for _ in range(tries):
            seed = rng.randrange(1, 2**32 - 1)
            save, r = evaluate(fdir, cfg, seed, work)
            good = ok(r)
            print(json.dumps({"seed": seed, "ok": good, **r}), flush=True)
            if good:
                shutil.copyfile(save, out)
                print(f"picked seed {seed} -> {out}")
                return 0
            save.unlink(missing_ok=True)
        print("no seed met the thresholds", file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
