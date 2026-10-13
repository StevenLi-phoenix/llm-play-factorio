"""Print the running map's exchange string (seed + no-enemy settings) for creating a replay save.

Headless Factorio cannot create a save with replay recording, so each run's map is made in a
full client: Single player -> New game -> tick "Record replay" -> Import map exchange string
(this output) -> Play -> save -> scripts/new_run.sh --save <that file>.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rcon import ROOT, command  # noqa: E402

s = command("/silent-command rcon.print(game.get_map_exchange_string())").strip()
seed = command("/silent-command rcon.print(game.surfaces.nauvis.map_gen_settings.seed)").strip()
if not s.startswith(">>>"):
    sys.exit(f"unexpected reply: {s[:200]}")
out = ROOT / "runtime" / "map-exchange.txt"
out.write_text(s + "\n", encoding="utf-8")
print(f"seed {seed}\n{s}\n(saved to {out})")
