"""Schematic timelapse of the play server: one rendered frame every --every seconds, then ffmpeg.

  python -I scripts/timelapse.py capture [--every 30] [--area X1 Y1 X2 Y2]   # loop until Ctrl+C
  python -I scripts/timelapse.py once [--area ...]                         # one frame
  python -I scripts/timelapse.py encode [--fps 24]                        # frames -> mp4

Without --area the window follows the player force's buildings (bounding box + margin, capped at 200
tiles by the snapshot RPC). Frames go to runtime/run/timelapse/frames/, the video next to them.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "lpf" / "src"))
sys.path.insert(0, str(ROOT / "scripts"))

from PIL import Image, ImageDraw  # noqa: E402

from lpf.cli import fetch_snapshot  # noqa: E402
from lpf.protos import Protos  # noqa: E402
from lpf.render import render  # noqa: E402
from lpf.scene import from_snapshot  # noqa: E402
import rcon  # noqa: E402

OUT = ROOT / "runtime" / "run" / "timelapse"
FRAME = (1280, 1280)
MAX_SIDE = 200


def _env():
    os.environ.setdefault("FACTORIO_RCON_PORT", "27017")
    pw = ROOT / "runtime" / "run" / "factorio" / "config" / "rconpw"
    os.environ.setdefault("FACTORIO_RCON_PASSWORD", pw.read_text().strip())


def base_bounds() -> tuple[int, int, int, int]:
    q = ("/silent-command local l,t,r,b local n=0 for _,e in pairs(game.surfaces.nauvis.find_entities_filtered{force='player'}) "
         "do if e.type~='character' then local p=e.position n=n+1 l=math.min(l or p.x,p.x) t=math.min(t or p.y,p.y) "
         "r=math.max(r or p.x,p.x) b=math.max(b or p.y,p.y) end end rcon.print(n..' '..(l or 0)..' '..(t or 0)..' '..(r or 0)..' '..(b or 0))")
    n, l, t, r, b = (float(v) for v in rcon.command(q).split())
    if n == 0:
        return -40, -40, 40, 40
    cx, cy = (l + r) / 2, (t + b) / 2
    half = min(MAX_SIDE, max(r - l, b - t) + 30) / 2
    return int(cx - half), int(cy - half), int(cx + half), int(cy + half)


def frame(area, protos, idx: int) -> Path:
    snap = fetch_snapshot(*area)
    rendered = render(from_snapshot(snap, protos), max_px=FRAME[0] - 60)
    canvas = Image.new("RGB", FRAME, (255, 255, 255))
    canvas.paste(rendered.image, (0, 30))
    tick = snap.get("tick", 0)
    secs = tick // 60
    ImageDraw.Draw(canvas).text((8, 8), f"tick {tick}  game time {secs // 3600}:{secs // 60 % 60:02d}:{secs % 60:02d}"
                                f"  area {area}", fill=(0, 0, 0))
    path = OUT / "frames" / f"{idx:06d}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path)
    return path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["capture", "once", "encode"])
    ap.add_argument("--every", type=float, default=30)
    ap.add_argument("--area", type=float, nargs=4)
    ap.add_argument("--fps", type=int, default=24)
    args = ap.parse_args()
    if args.cmd == "encode":
        out = OUT / "timelapse.mp4"
        subprocess.run(["ffmpeg", "-y", "-framerate", str(args.fps), "-i", str(OUT / "frames" / "%06d.png"),
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", str(out)],
                       check=True)
        print(out)
        return 0
    _env()
    protos = Protos.load()
    existing = sorted((OUT / "frames").glob("*.png")) if (OUT / "frames").exists() else []
    idx = int(existing[-1].stem) + 1 if existing else 0
    while True:
        try:
            area = tuple(args.area) if args.area else base_bounds()
            print(frame(area, protos, idx), flush=True)
            idx += 1
        except Exception as e:  # server restart or transient RCON error: keep going
            print(f"frame {idx} failed: {e}", file=sys.stderr, flush=True)
        if args.cmd == "once":
            return 0
        time.sleep(args.every)


if __name__ == "__main__":
    sys.exit(main())
