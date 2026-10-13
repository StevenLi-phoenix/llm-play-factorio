-- Offline tests for scripts/bp_registry.lua (0.2.23): the blueprint provenance
-- registry and its canonical content key. Blueprint holders are stubs exposing
-- get_blueprint_entities / get_blueprint_tiles like a LuaItemStack.
local here = (arg and arg[0] or "."):match("^(.*)/[^/]+$") or "."
package.path = here .. "/../../mod/factorio-mcp/?.lua;" .. package.path

local failures = 0
local function check(cond, what)
  if cond then print("ok   " .. what) else failures = failures + 1 print("FAIL " .. what) end
end

-- minimal helpers.table_to_json: arrays of strings/numbers, {} for empty
local function js(v)
  if type(v) == "string" then return '"' .. v .. '"' end
  if type(v) == "number" then return tostring(v) end
  if #v == 0 then return "{}" end
  local parts = {}
  for i, x in ipairs(v) do parts[i] = js(x) end
  return "[" .. table.concat(parts, ",") .. "]"
end
_G.helpers = { table_to_json = js }
_G.game = { tick = 500 }
_G.storage = {}
_G.settings = { global = {} }
require("scripts.state").init()

local registry = require("scripts.bp_registry")

local function holder(ents, tiles)
  return {
    get_blueprint_entities = function() return ents end,
    get_blueprint_tiles = function() return tiles or {} end,
  }
end

local function belt(x, y, dir)
  return { entity_number = 1, name = "transport-belt", position = { x = x, y = y }, direction = dir }
end

-- ------------------------------------------------------------ the key

local base = holder({
  belt(-20.5, 77.5, 8),
  belt(-21.5, 77.5, 4),
  { entity_number = 3, name = "burner-mining-drill", position = { x = -23, y = 78 }, direction = 4 },
})
local key = registry.key_of(base)
check(#key == 32 and key:match("^%x+$") ~= nil, "key: a 32-digit hex hash")

-- same layout somewhere else, other order, other entity numbers, other labels
local moved = holder({
  { entity_number = 9, name = "burner-mining-drill", position = { x = 7, y = 108 }, direction = 4 },
  belt(8.5, 107.5, 4),
  belt(9.5, 107.5, 8),
})
check(registry.key_of(moved) == key, "key: independent of position offset, entity order and entity numbers")
local labelled = holder(base.get_blueprint_entities())
labelled.label = "other name"
check(registry.key_of(labelled) == key, "key: independent of the label")

-- the direction field is absent for north
local north_a = holder({ { name = "stone-furnace", position = { x = 1, y = 1 } } })
local north_b = holder({ { name = "stone-furnace", position = { x = 5, y = 9 }, direction = 0 } })
check(registry.key_of(north_a) == registry.key_of(north_b), "key: a missing direction is north")

-- float noise below the rounding is ignored
local noisy = holder({
  belt(-20.5 + 1e-9, 77.5, 8), belt(-21.5, 77.5 - 1e-9, 4),
  { name = "burner-mining-drill", position = { x = -23, y = 78 }, direction = 4 },
})
check(registry.key_of(noisy) == key, "key: positions are compared at two decimals")

-- anything that changes the layout changes the key
local function differs(ents, what)
  check(registry.key_of(holder(ents)) ~= key, "key: " .. what .. " changes the key")
end
differs({ belt(-20.5, 77.5, 4), belt(-21.5, 77.5, 4),
  { name = "burner-mining-drill", position = { x = -23, y = 78 }, direction = 4 } }, "a rotated belt")
differs({ belt(-20.5, 77.5, 8), belt(-21.5, 77.5, 4) }, "a missing entity")
differs({ belt(-20.5, 77.5, 8), belt(-21.5, 77.5, 4),
  { name = "burner-mining-drill", position = { x = -23, y = 78.5 }, direction = 4 } }, "a moved entity")
differs({ belt(-20.5, 77.5, 8), belt(-21.5, 77.5, 4),
  { name = "burner-mining-drill", position = { x = -23, y = 78 }, direction = 4 }, belt(0.5, 0.5, 0) }, "an extra entity")

local function one(extra)
  local e = { name = "x", position = { x = 0, y = 0 }, direction = 4 }
  for k, v in pairs(extra or {}) do e[k] = v end
  return registry.key_of(holder({ e }))
end
check(one() == one(), "key: deterministic")
check(one({ recipe = "iron-gear-wheel" }) ~= one(), "key: the recipe counts")
check(one({ recipe = "iron-gear-wheel" }) ~= one({ recipe = "copper-cable" }), "key: which recipe counts")
check(one({ type = "input" }) ~= one({ type = "output" }), "key: underground input vs output counts")
check(one({ input_priority = "left" }) ~= one(), "key: splitter input priority counts")
check(one({ output_priority = "right" }) ~= one({ output_priority = "left" }), "key: splitter output priority counts")
check(one({ filter = { name = "iron-plate" } }) ~= one(), "key: a splitter filter counts")
check(one({ quality = "rare" }) ~= one() and one({ quality = "normal" }) == one(), "key: non-normal quality counts")

-- tiles
local with_tiles = holder(base.get_blueprint_entities(), { { name = "concrete", position = { x = -20, y = 77 } } })
check(registry.key_of(with_tiles) ~= key, "key: floor tiles count")
local shifted_tiles = holder({
  { name = "burner-mining-drill", position = { x = 7, y = 108 }, direction = 4 },
  belt(8.5, 107.5, 4), belt(9.5, 107.5, 8),
}, { { name = "concrete", position = { x = 10, y = 107 } } })
check(registry.key_of(shifted_tiles) == registry.key_of(with_tiles), "key: tiles move with the entities")

-- the canonical text itself: sorted lines, min corner at 0,0
local text, n = registry.canonical(base)
check(n == 3, "canonical: counts entities")
check(text == '[1,["burner-mining-drill|0.00|0.50|4||||||","transport-belt|1.50|0.00|4||||||",'
  .. '"transport-belt|2.50|0.00|8||||||"],{}]', "canonical: " .. text)

-- golden: this layout was exported from the live 2.0.77 server (a drill and three
-- belts) and the game reported this key hash, so stub and engine agree
local live = holder({
  belt(-20.5, 77.5, 8), belt(-21.5, 77.5, 4),
  { name = "burner-mining-drill", position = { x = -23, y = 78 }, direction = 4 },
  belt(-20.5, 78.5, 8),
})
check(registry.key_of(live) == "8aef4f6ff0b12b5c464152de9a14fbf4", "golden: the key hash matches the live game's")

-- the hash is stable
check(registry.hash("abc") == registry.hash("abc") and registry.hash("abc") ~= registry.hash("abd"),
  "hash: stable and sensitive to every character")
check(registry.hash("") ~= registry.hash("a"), "hash: the empty string differs from a character")

-- -------------------------------------------------------- the registry

check(not registry.is_registered(key), "registry: starts empty")
local r = registry.register(base, { source = "export", character = "coal" })
check(r.key_hash == key and r.entity_count == 3 and r.already_registered == false, "register: returns key and count")
check(registry.is_registered(key), "register: the layout is now known")
local again = registry.register(moved, { source = "compiled", note = "second" })
check(again.already_registered == true and again.key_hash == key, "register: the same layout elsewhere is the same entry")
local list = registry.list()
check(#list == 1 and list[1].source == "export" and list[1].character == "coal" and list[1].tick == 500
  and list[1].entity_count == 3 and list[1].note == nil, "register: the first registration wins; audit fields kept")

_G.game.tick = 900
registry.register(holder({ belt(0.5, 0.5, 0) }), { source = "compiled", note = string.rep("n", 500) })
list = registry.list()
check(#list == 2 and list[2].source == "compiled" and list[2].tick == 900 and #list[2].note == 300,
  "list: oldest first; notes are cut to 300 characters")

local ok, err = pcall(registry.register, holder({}), { source = "x" })
check(not ok and tostring(err):find("empty", 1, true), "register: an empty blueprint is refused")
ok = pcall(registry.register, holder({}, { { name = "concrete", position = { x = 1, y = 1 } } }), { source = "x" })
check(ok, "register: a tiles-only blueprint is allowed")

-- ----------------------------------------------------------- the gate

local stranger = holder({ belt(0.5, 0.5, 4), belt(1.5, 0.5, 4), belt(2.5, 0.5, 4) })
ok, err = pcall(registry.require_registered, stranger)
check(not ok and tostring(err):find("exported from the map", 1, true) and tostring(err):find("in-run layout", 1, true),
  "gate: an unregistered layout is refused with the run-rules message")
check(not tostring(err):find("registry.lua", 1, true), "gate: the message has no file:line prefix")
check(pcall(registry.require_registered, moved), "gate: a registered layout passes")

settings.global["factorio-mcp-enforce-blueprint-provenance"] = { value = false }
check(not registry.enforced() and pcall(registry.require_registered, stranger), "gate: the mod setting turns it off")
settings.global["factorio-mcp-enforce-blueprint-provenance"] = { value = true }
check(registry.enforced() and not pcall(registry.require_registered, stranger), "gate: on again with the setting on")
settings.global = {}
check(registry.enforced(), "gate: on by default (setting missing)")

print(failures == 0 and "\nALL TESTS PASSED" or ("\n" .. failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
