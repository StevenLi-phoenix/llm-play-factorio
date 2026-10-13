"""Remove an idle agent's character from the run map, keeping its items: the inventory goes into chests
crafted from the character's own iron plates / wood / carried chests, placed next to it. A resumed agent
gets a new body (respawn) and collects the chest.

  python -I scripts/park_character.py NAME [NAME ...]
"""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
os.environ.setdefault("FACTORIO_RCON_PORT", "27017")
os.environ.setdefault("FACTORIO_RCON_PASSWORD", (ROOT / "runtime/run/factorio/config/rconpw").read_text().strip())
import rcon  # noqa: E402

LUA = r"""/silent-command __factorio-mcp__
local s=game.surfaces.nauvis local rec=storage.companions["%s"] local c=rec and rec.entity local out="%s: no body"
if c and c.valid then
  local inv=c.get_main_inventory() local placed=0
  while not inv.is_empty() and placed<20 do
    local cost
    if inv.get_item_count("iron-plate")>=8 then cost={"iron-plate",8,"iron-chest"}
    elseif inv.get_item_count("iron-chest")>=1 then cost={"iron-chest",1,"iron-chest"}
    elseif inv.get_item_count("wood")>=2 then cost={"wood",2,"wooden-chest"}
    elseif inv.get_item_count("wooden-chest")>=1 then cost={"wooden-chest",1,"wooden-chest"} end
    if not cost then break end
    local pos=s.find_non_colliding_position(cost[3],c.position,10,1)
    if not pos then break end
    inv.remove{name=cost[1],count=cost[2]}
    local ch=s.create_entity{name=cost[3],position=pos,force=c.force}
    local cinv=ch.get_inventory(defines.inventory.chest)
    for i=1,#inv do local st=inv[i] if st.valid_for_read then local k=cinv.insert(st) if k>0 then st.count=st.count-k end end end
    placed=placed+1
  end
  local left=inv.get_item_count()
  out="%s at "..math.floor(c.position.x)..","..math.floor(c.position.y).." chests="..placed.." leftover="..left
  if left==0 then c.destroy() out=out.." REMOVED" end
end
rcon.print(out)"""

if __name__ == "__main__":
    for name in sys.argv[1:]:
        print(rcon.command(" ".join((LUA % (name, name, name)).split("\n"))))
