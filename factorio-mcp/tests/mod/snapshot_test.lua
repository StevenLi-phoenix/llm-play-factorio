-- Offline tests for scripts/snapshot.lua (0.2.23): the area_snapshot RPC, a JSON
-- picture of a rectangle for a schematic renderer. Entities, tiles and the
-- explored-chunk set are stubs.
local here = (arg and arg[0] or "."):match("^(.*)/[^/]+$") or "."
package.path = here .. "/../../mod/factorio-mcp/?.lua;" .. package.path

local failures = 0
local function check(cond, what)
  if cond then print("ok   " .. what) else failures = failures + 1 print("FAIL " .. what) end
end

local S = { working = 2, no_power = 3, no_fuel = 5, full_output = 6, waiting_for_space_in_destination = 7 }
_G.defines = { entity_status = S }
_G.game = { tick = 4242, surfaces = {}, forces = { player = { name = "player" } } }

-- chunks (cx,cy) in this set are explored; the stub vision decides by chunk
local explored = {}
for cx = -2, 1 do for cy = -2, 1 do explored[cx .. "," .. cy] = true end end
package.loaded["scripts.vision"] = {
  is_known = function(_, _, pos)
    return explored[math.floor(pos.x / 32) .. "," .. math.floor(pos.y / 32)] == true
  end,
}
package.loaded["scripts.companion"] = {
  name_of = function(e) return e.agent_name end,
}
local water_probed = {}
package.loaded["scripts.spatial"] = {
  is_water_at = function(_, x, y) water_probed[#water_probed + 1] = x .. "," .. y return x == 3 and y == 3 end,
}

local queried = {}
local entities, tiles = {}, {}
local surface = {
  find_entities_filtered = function(filter)
    queried.entities = filter
    return entities
  end,
  find_tiles_filtered = function(filter)
    queried.tiles = filter
    return tiles
  end,
}
game.surfaces.nauvis = surface

local snapshot = require("scripts.snapshot")

local force_player = { name = "player" }
local function ent(name, type, x, y, extra)
  local half = 0.35
  local e = {
    valid = true, name = name, type = type, position = { x = x, y = y }, direction = 0, force = force_player,
    bounding_box = { left_top = { x = x - half, y = y - half }, right_bottom = { x = x + half, y = y + half } },
  }
  for k, v in pairs(extra or {}) do e[k] = v end
  return e
end

entities = {
  ent("stone-furnace", "furnace", 3, 3, { status = S.working, previous_recipe = { name = "iron-plate", quality = "normal" },
    get_recipe = function() return nil end }),
  ent("assembling-machine-1", "assembling-machine", 6.5, 3.5, { status = S.no_power, direction = 4,
    get_recipe = function() return { name = "iron-gear-wheel" } end }),
  ent("assembling-machine-1", "assembling-machine", 9.5, 3.5, { get_recipe = function() return nil end }),
  ent("underground-belt", "underground-belt", 0.5, 0.5, { direction = 8, belt_to_ground_type = "input", status = S.working }),
  ent("inserter", "inserter", 1.5, 0.5, { direction = 4, pickup_position = { x = 0.5, y = 0.5 },
    drop_position = { x = 2.5, y = 0.5 }, status = S.waiting_for_space_in_destination }),
  ent("burner-mining-drill", "mining-drill", 4, 8, { direction = 4, status = S.no_fuel, drop_position = { x = 5.3, y = 8.5 } }),
  ent("transport-belt", "entity-ghost", 20.5, 20.5, { ghost_name = "transport-belt", ghost_type = "transport-belt", direction = 4 }),
  ent("character", "character", 0, 5, { direction = 2, agent_name = "coal" }),
  ent("character", "character", 1, 5, { direction = 2 }), -- a human player
  ent("small-biter", "unit", 8, 8, { force = { name = "enemy" } }),
  -- not entities: obstacles, resources, ground litter
  ent("tree-01", "tree", 12, 12),
  ent("rock-big", "simple-entity", 14, 14),
  ent("cliff", "cliff", 16, 16),
  ent("item-on-ground", "item-entity", 2, 2),
  ent("iron-ore", "resource", 30.5, 40.5, { amount = 120 }),
  ent("iron-ore", "resource", 31.5, 40.5, { amount = 80 }),
  ent("crude-oil", "resource", 33.5, 41.5, { amount = 300000 }),
  ent("copper-ore", "resource", 45.5, 45.5, { amount = 7 }), -- explored, but past the area
  -- on unexplored ground (chunk 3,0 is not explored): left out
  ent("stone-furnace", "furnace", 100.5, 8, { status = S.working }),
  ent("iron-ore", "resource", 100.5, 8.5, { amount = 9 }),
  ent("tree-01", "tree", 101, 9),
}
tiles = { { position = { x = 3, y = 3 } }, { position = { x = 4, y = 3 } }, { position = { x = 500, y = 3 } } }

local snap = snapshot.area_snapshot({ x1 = 40, y1 = 50, x2 = -10, y2 = -10 }) -- corners in any order
check(snap.tick == 4242, "snapshot: carries the tick")
check(snap.area[1] == -10 and snap.area[2] == -10 and snap.area[3] == 40 and snap.area[4] == 50, "snapshot: area is normalized")
check(queried.entities.area[1][1] == -10 and queried.entities.area[2][2] == 50, "snapshot: queries the whole area once")
check(queried.tiles.collision_mask == "water_tile", "snapshot: water through the water_tile collision mask")

-- unexplored chunks: x -10..40 is chunks -1..1, y -10..50 is chunks -1..1; all explored here
check(#snap.unexplored_chunks == 0, "snapshot: fully explored area lists no unexplored chunks")

check(#snap.entities == 10, "snapshot: 10 entities (furnace, 2 assemblers, ug, inserter, drill, ghost, 2 characters, biter); got "
  .. #snap.entities)
local function find(pred)
  for _, e in ipairs(snap.entities) do if pred(e) then return e end end
end

local furnace = find(function(e) return e.type == "furnace" end)
check(furnace and furnace.x == 3 and furnace.y == 3 and furnace.dir == 0 and furnace.force == "player", "entity: name/type/x/y/dir/force")
check(furnace.box[1] == 2.65 and furnace.box[2] == 2.65 and furnace.box[3] == 3.35 and furnace.box[4] == 3.35,
  "entity: box is the world-space bounding box, two decimals")
check(furnace.status == "working", "entity: status is the defines.entity_status key")
check(furnace.recipe == "iron-plate", "furnace: previous_recipe when there is no current recipe")

local gear = find(function(e) return e.recipe == "iron-gear-wheel" end)
check(gear and gear.status == "no_power" and gear.dir == 4, "assembler: recipe and status")
local idle = find(function(e) return e.name == "assembling-machine-1" and e.recipe == nil end)
check(idle and idle.recipe == nil and idle.status == nil, "optional keys are left out (no recipe, no status)")

local ug = find(function(e) return e.type == "underground-belt" end)
check(ug and ug.ug == "input" and ug.dir == 8, "underground belt: ug = input/output")
local ins = find(function(e) return e.type == "inserter" end)
check(ins and ins.pickup[1] == 0.5 and ins.pickup[2] == 0.5 and ins.drop[1] == 2.5 and ins.drop[2] == 0.5,
  "inserter: pickup and drop world positions")
check(ins.status == "waiting_for_space_in_destination", "inserter: long status key names pass through")
local drill = find(function(e) return e.type == "mining-drill" end)
check(drill and drill.out[1] == 5.3 and drill.out[2] == 8.5 and drill.status == "no_fuel", "mining drill: out = drop_position")
check(drill.ug == nil and drill.pickup == nil and drill.ghost == nil and drill.label == nil, "drill: no keys of other kinds")

local ghost = find(function(e) return e.ghost end)
check(ghost and ghost.ghost == true and ghost.name == "transport-belt" and ghost.type == "transport-belt",
  "ghost: name and type are the ghost's, ghost = true")

local agent = find(function(e) return e.label == "coal" end)
check(agent and agent.type == "character", "character: label is the agent's name")
local human = find(function(e) return e.type == "character" and e.label == nil end)
check(human ~= nil, "character: a player has no label")
local biter = find(function(e) return e.type == "unit" end)
check(biter and biter.force == "enemy", "other forces' entities are included with their force")

-- sorted by y, x for stable diffs
local sorted = true
for i = 2, #snap.entities do
  local a, b = snap.entities[i - 1], snap.entities[i]
  if a.y > b.y or (a.y == b.y and a.x > b.x) then sorted = false end
end
check(sorted, "entities are sorted by y then x")

-- obstacles, resources, water
check(#snap.obstacles == 3, "obstacles: tree, rock and cliff only (and not the unexplored tree)")
local kinds = {}
for _, o in ipairs(snap.obstacles) do kinds[o[5]] = o end
check(kinds.tree and kinds.rock and kinds.cliff, "obstacles: kinds tree / rock / cliff")
check(kinds.tree[1] == 11.65 and kinds.tree[3] == 12.35 and #kinds.tree == 5, "obstacles: [left, top, right, bottom, kind]")

check(snap.resources["iron-ore"] and #snap.resources["iron-ore"] == 2, "resources: grouped by name; unexplored and out-of-area ore dropped")
check(snap.resources["iron-ore"][1][1] == 30 and snap.resources["iron-ore"][1][2] == 40
  and snap.resources["iron-ore"][1][3] == 120, "resources: [tile x, tile y, amount] with top-left integer tile coordinates")
check(snap.resources["crude-oil"][1][1] == 33 and snap.resources["crude-oil"][1][2] == 41
  and snap.resources["crude-oil"][1][3] == 300000, "resources: crude oil included")
check(snap.resources["copper-ore"] == nil, "resources: ore outside the area is not reported")

check(#snap.water == 2 and snap.water[1][1] == 3 and snap.water[2][1] == 4, "water: the tiles found on explored ground, no tiles from unexplored chunks")

-- unexplored chunks are listed, and nothing on them is reported
local wide = snapshot.area_snapshot({ x1 = 40, y1 = 0, x2 = 130, y2 = 10 })
local found = {}
for _, c in ipairs(wide.unexplored_chunks) do found[#found + 1] = c[1] .. "," .. c[2] end
check(table.concat(found, " ") == "2,0 3,0 4,0", "unexplored_chunks: the chunks of the area that are not explored: " .. table.concat(found, " "))
check(#wide.entities == 0 or wide.entities[1].x ~= 100.5, "unexplored ground reports no entities")

-- a rectangle ending exactly on a chunk border does not claim the next chunk
local exact = snapshot.area_snapshot({ x1 = 0, y1 = 0, x2 = 32, y2 = 32 })
check(#exact.unexplored_chunks == 0, "the area's far edge on a chunk border does not count the next chunk")

-- the size limit is export_blueprint's
local ok, err = pcall(snapshot.area_snapshot, { x1 = 0, y1 = 0, x2 = 201, y2 = 10 })
check(not ok and tostring(err):find("limited to 200x200", 1, true), "an area wider than 200 tiles is refused")
check(pcall(snapshot.area_snapshot, { x1 = 0, y1 = 0, x2 = 200, y2 = 200 }), "exactly 200x200 is allowed")
ok, err = pcall(snapshot.area_snapshot, { x1 = 0, y1 = 0, x2 = "x", y2 = 10 })
check(not ok and tostring(err):find("numeric", 1, true), "non-numeric corners are refused")

-- a snapshot of an empty area still has every key
local empty = (function()
  entities, tiles = {}, {}
  return snapshot.area_snapshot({ x1 = 0, y1 = 0, x2 = 10, y2 = 10 })
end)()
check(empty.entities and empty.water and empty.obstacles and empty.resources and empty.unexplored_chunks and empty.tick
  and empty.area, "an empty area returns the full shape")

-- the water fallback (no find_tiles_filtered): per-tile probe on explored ground only
surface.find_tiles_filtered = function() error("unsupported mask") end
water_probed = {}
local fallback = snapshot.area_snapshot({ x1 = 2, y1 = 2, x2 = 5, y2 = 4 })
check(#fallback.water == 1 and fallback.water[1][1] == 3 and fallback.water[1][2] == 3,
  "water: falls back to probing tiles when the tile query fails")
check(#water_probed == 6, "water fallback: probes each tile of the area once (" .. #water_probed .. ")")

print(failures == 0 and "\nALL TESTS PASSED" or ("\n" .. failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
