"""Print research progress and what is left on the path to rocket-silo (read-only by default).
With --set, also replace the research queue with the first 7 techs of that path (prerequisites first).

  python -I scripts/research.py [TARGET_TECH] [--set]
"""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
os.environ.setdefault("FACTORIO_RCON_PORT", "27017")
os.environ.setdefault("FACTORIO_RCON_PASSWORD", (ROOT / "runtime/run/factorio/config/rconpw").read_text().strip())
import rcon  # noqa: E402

LUA = r"""/silent-command local f=game.forces.player local order={} local seen={}
local function visit(t) if seen[t.name] or t.researched then return end seen[t.name]=true for _,p in pairs(t.prerequisites) do visit(p) end order[#order+1]=t.name end
visit(f.technologies["%s"])
local function ready(t) for _,p in pairs(t.prerequisites) do if not p.researched then return false end end return true end
local q={} local inq={} for _,n in pairs(order) do if #q<7 then q[#q+1]=n inq[n]=true end end
if %s then pcall(function() f.research_queue=q end) end
local cur={} for _,t in pairs(f.research_queue) do cur[#cur+1]=t.name end
local cnt={} for _,n in pairs(order) do local t=f.technologies[n] for _,u in pairs(t.research_unit_ingredients) do cnt[u.name]=(cnt[u.name] or 0)+u.amount*t.research_unit_count end end
local c={} for k,v in pairs(cnt) do c[#c+1]=k:gsub("%%-science%%-pack","").."="..v end
rcon.print((f.current_research and (f.current_research.name.." "..math.floor(f.research_progress*100).."%%; ") or "idle; ")..#order.." techs left; queue: "..table.concat(cur," > ").." | packs left: "..table.concat(c," "))"""

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--set"]
    target = args[0] if args else "rocket-silo"
    setq = "true" if "--set" in sys.argv[1:] else "false"
    print(rcon.command(" ".join((LUA % (target, setq)).split("\n"))))
