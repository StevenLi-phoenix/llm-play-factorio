"""One read-only KPI snapshot of the play server; prints a compact summary and appends it to
runtime/run/kpi.jsonl (milestones and production for the Sim A calibration).

  python -I scripts/kpi.py
"""
import json
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
os.environ.setdefault("FACTORIO_RCON_PORT", "27017")
os.environ.setdefault("FACTORIO_RCON_PASSWORD",
                      (ROOT / "runtime/run/factorio/config/rconpw").read_text().strip())
import rcon  # noqa: E402

LUA = r"""/silent-command
local f = game.forces.player
local s = game.surfaces.nauvis
local out = {tick = game.tick, research = f.current_research and f.current_research.name or nil,
  research_progress = f.research_progress, researched = {}, counts = {}, problems = {}, produced = {}, chars = {}}
for name, t in pairs(f.technologies) do if t.researched and t.enabled then out.researched[#out.researched+1] = name end end
local probs = {[defines.entity_status.no_fuel]="no_fuel", [defines.entity_status.no_power]="no_power",
  [defines.entity_status.low_power]="low_power", [defines.entity_status.no_ingredients]="no_ingredients",
  [defines.entity_status.waiting_for_space_in_destination]="output_blocked",
  [defines.entity_status.no_minable_resources]="depleted"}
for _, e in pairs(s.find_entities_filtered{force = f}) do
  if e.type == "character" then
    out.chars[#out.chars+1] = {e.name_tag or "", math.floor(e.position.x), math.floor(e.position.y)}
  else
    out.counts[e.name] = (out.counts[e.name] or 0) + 1
    local st = e.status and probs[e.status]
    if st then out.problems[st] = (out.problems[st] or 0) + 1 end
  end
end
local stats = f.get_item_production_statistics(s)
for _, item in pairs({"iron-plate","copper-plate","steel-plate","stone","coal","iron-gear-wheel","electronic-circuit",
  "automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack",
  "utility-science-pack","plastic-bar","advanced-circuit","processing-unit","low-density-structure","rocket-fuel",
  "rocket-part"}) do
  local n = stats.get_input_count(item)
  if n > 0 then out.produced[item] = n end
end
rcon.print(helpers.table_to_json(out))"""


def main() -> int:
    raw = rcon.command(" ".join(LUA.split("\n")))
    snap = json.loads(raw)
    snap["wall"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    with open(ROOT / "runtime/run/kpi.jsonl", "a", encoding="utf-8") as fh:
        fh.write(json.dumps(snap) + "\n")
    t = snap["tick"] // 60
    print(f"tick {snap['tick']} game {t // 3600}:{t // 60 % 60:02d}:{t % 60:02d} wall {snap['wall']}")
    print(f"research: {snap.get('research')} {snap.get('research_progress', 0):.0%}; done {len(snap['researched'])}")
    print("produced:", ", ".join(f"{k} {v}" for k, v in snap["produced"].items()))
    print("buildings:", ", ".join(f"{k} {v}" for k, v in sorted(snap["counts"].items(), key=lambda kv: -kv[1])))
    print("problems:", snap["problems"] or "none")
    return 0


if __name__ == "__main__":
    sys.exit(main())
