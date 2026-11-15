-- Offline tests for scripts/ghosts.lua: ghost_build / ghost_clear on the character's own surface (0.3.14).
local here = (arg and arg[0] or "."):match("^(.*)/[^/]+$") or "."
package.path = here .. "/../../mod/factorio-mcp/?.lua;" .. package.path

local failures = 0
local function check(cond, what)
  if cond then print("ok   " .. what) else failures = failures + 1 print("FAIL " .. what) end
end

local created, destroyed = {}, 0
local existing = {}
local surface = {
  can_place_entity = function(spec)
    return spec.position[1] ~= 99 and spec.build_check_type ~= nil
  end,
  create_entity = function(spec)
    local g = { valid = true, name = "entity-ghost", spec = spec, recipe = nil }
    g.set_recipe = function(r) g.recipe = r end
    created[#created + 1] = g
    return g
  end,
  find_entities_filtered = function(filter)
    local out = {}
    for _, g in ipairs(existing) do
      out[#out + 1] = { name = g, valid = true, destroy = function() destroyed = destroyed + 1 end }
    end
    return out
  end,
}
local char = { surface = surface, force = "player", valid = true }
package.loaded["scripts.companion"] = { require_companion = function() return char end }

_G.defines = { build_check_type = { manual_ghost = 7 } }
_G.prototypes = {
  item = {
    ["electric-mining-drill"] = { place_result = { name = "electric-mining-drill" } },
    ["transport-belt"] = { place_result = { name = "transport-belt" } },
    ["stone-furnace"] = { place_result = { name = "stone-furnace" } },
  },
  entity = { ["electric-mining-drill"] = {}, ["transport-belt"] = {}, ["stone-furnace"] = {}, inserter = {} },
}

local ghosts = require("scripts.ghosts")

-- places ghosts for items and entity names; counts them by name
local r = ghosts.ghost_build({ steps = {
  { name = "electric-mining-drill", x = 1.5, y = 1.5, direction = 4 },
  { name = "transport-belt", x = 3.5, y = 0.5 },
  { name = "inserter", x = 5.5, y = 0.5, direction = 8 },
} })
check(r.placed == 3 and #created == 3, "three valid steps give three ghosts")
check(created[1].spec.name == "entity-ghost" and created[1].spec.inner_name == "electric-mining-drill",
  "a ghost wraps the entity the item places")
check(created[1].spec.direction == 4 and created[1].spec.force == "player", "direction and force are passed on")
check(r.placed_by_name["transport-belt"] == 1, "placed_by_name counts per name")

-- rejects carry the step index and the reason; the rest still goes through
created = {}
r = ghosts.ghost_build({ steps = {
  { name = "stone-furnace", x = 99, y = 0 },
  { name = "no-such-thing", x = 0, y = 0 },
  { name = "stone-furnace", y = 1 },
  { name = "stone-furnace", x = 2, y = 2 },
} })
check(r.placed == 1 and r.rejected_total == 3, "one placed, three rejected")
check(r.rejected[1].i == 1 and r.rejected[1].why:find("blocked", 1, true), "a blocked tile says blocked")
check(r.rejected[2].why:find("unknown", 1, true), "an unknown name says unknown")
check(r.rejected[3].why:find("x and y", 1, true), "missing coordinates are named")

-- recipe goes onto the ghost
created = {}
ghosts.ghost_build({ steps = { { name = "stone-furnace", x = 0, y = 0, recipe = "iron-plate" } } })
check(created[1].recipe == "iron-plate", "recipe is set on the ghost")

-- input checks
check(not pcall(ghosts.ghost_build, { steps = {} }), "empty steps is an error")
local many = {}
for i = 1, 1501 do many[i] = { name = "transport-belt", x = i, y = 0 } end
check(not pcall(ghosts.ghost_build, { steps = many }), "more than 1500 steps is an error")

-- ghost_clear removes ghosts in an area and reports how many
existing = { "entity-ghost", "entity-ghost", "tile-ghost" }
local c = ghosts.ghost_clear({ x1 = 0, y1 = 0, x2 = 10, y2 = 10 })
check(c.removed == 3 and destroyed == 3, "ghost_clear destroys every ghost in the area")
check(not pcall(ghosts.ghost_clear, { x1 = 0, y1 = 0 }), "ghost_clear needs all four corners")

os.exit(failures == 0 and 0 or 1)
