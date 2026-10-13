-- Offline tests for the blueprint provenance gate (0.2.23) in scripts/blueprint.lua
-- and actions/build_blueprint.lua: import_blueprint / build_blueprint refuse
-- strings that were not exported from the map or registered by the harness;
-- carried blueprints are not gated; export_blueprint registers what it hands
-- out. The game API (scratch inventories, stacks, strings) is stubbed.
local here = (arg and arg[0] or "."):match("^(.*)/[^/]+$") or "."
package.path = here .. "/../../mod/factorio-mcp/?.lua;" .. package.path

local failures = 0
local function check(cond, what)
  if cond then print("ok   " .. what) else failures = failures + 1 print("FAIL " .. what) end
end

local function js(v)
  if type(v) == "string" then return '"' .. v .. '"' end
  if type(v) == "number" then return tostring(v) end
  if #v == 0 then return "{}" end
  local parts = {}
  for i, x in ipairs(v) do parts[i] = js(x) end
  return "[" .. table.concat(parts, ",") .. "]"
end
_G.helpers = { table_to_json = js }
_G.game = { tick = 1000 }
_G.storage = {}
_G.settings = { global = {} }
_G.defines = { inventory = { item_main = 1 } }
require("scripts.state").init()

_G.prototypes = { entity = setmetatable({}, { __index = function(_, name)
  return { type = name:find("underground") and "underground-belt" or "x", items_to_place_this = { { name = name } } }
end }) }

-- ------------------------------------------------------------ the stubs

local STRINGS = {} -- export string -> { kind, entities, tiles, label }

local function new_stack()
  local s = { valid_for_read = false, is_blueprint = false, is_blueprint_book = false }
  function s.import_stack(str)
    local def = STRINGS[str]
    if not def then return 1 end
    s.valid_for_read = true
    s.is_blueprint = def.kind == "blueprint"
    s.is_blueprint_book = def.kind == "book"
    s.name = def.kind
    s.label = def.label
    s._entities, s._tiles = def.entities or {}, def.tiles or {}
    return 0
  end
  function s.get_blueprint_entities() return s._entities end
  function s.get_blueprint_tiles() return s._tiles end
  function s.get_blueprint_entity_count() return #s._entities end
  function s.set_stack() s.valid_for_read, s.is_blueprint = true, true end
  function s.create_blueprint(opts) s._entities, s._tiles = opts.surface._world, {} end
  function s.export_stack()
    local str = "EXPORT-" .. (s.label or "unlabelled") .. "-" .. tostring(#s._entities)
    STRINGS[str] = { kind = "blueprint", entities = s._entities, tiles = {}, label = s.label }
    return str
  end
  return s
end

_G.game.create_inventory = function()
  local inv = { new_stack() }
  inv.destroy = function() end
  return inv
end

local function belt(x, y, d) return { name = "transport-belt", position = { x = x, y = y }, direction = d } end

local character = {
  force = {},
  surface = { _world = { belt(10.5, 20.5, 4), belt(11.5, 20.5, 4), { name = "stone-furnace", position = { x = 14, y = 21 } } } },
  carried = {},
}
function character.get_main_inventory() return character.carried end
package.loaded["scripts.companion"] = {
  require_companion = function() return character end,
  context = function() return "test-1" end,
}
package.loaded["scripts.vision"] = { require_known = function() end }

local blueprint = require("scripts.blueprint")
local registry = require("scripts.bp_registry")

local function refused(fn, ...)
  local ok, err = pcall(fn, ...)
  return not ok and tostring(err):find("exported from the map", 1, true) ~= nil and tostring(err) or nil
end

-- three belts and a furnace nobody exported or compiled
STRINGS["FOREIGN-STRING"] = { kind = "blueprint", label = "memorized", entities = {
  belt(0.5, 0.5, 4), belt(1.5, 0.5, 4), belt(2.5, 0.5, 4), { name = "stone-furnace", position = { x = 5, y = 1 } } } }
STRINGS["BOOK-STRING-XYZ"] = { kind = "book" }

-- ---------------------------------------------------------- the gate

check(refused(blueprint.import, { string = "FOREIGN-STRING" }), "import_blueprint refuses an unregistered string")
check(refused(blueprint.resolve_for_build, { string = "FOREIGN-STRING" }), "build_blueprint's resolver refuses it too")
local ok, err = pcall(blueprint.import, { string = "nonsense-that-is-long" })
check(not ok and tostring(err):find("isn't a valid blueprint export string", 1, true),
  "a string that does not decode keeps its own error")
ok, err = pcall(blueprint.import, { string = "BOOK-STRING-XYZ" })
check(not ok and tostring(err):find("blueprint BOOK", 1, true), "a book is still refused as a book")

-- register_blueprint: validates, then the gate lets the string through
ok, err = pcall(blueprint.register, { string = "FOREIGN-STRING" })
check(not ok and tostring(err):find("source", 1, true), "register_blueprint requires a source")
ok, err = pcall(blueprint.register, { string = "BOOK-STRING-XYZ", source = "compiled" })
check(not ok and tostring(err):find("blueprint BOOK", 1, true), "register_blueprint refuses a book")
ok, err = pcall(blueprint.register, { string = "nonsense-that-is-long", source = "compiled" })
check(not ok, "register_blueprint refuses a string that does not decode")

local reg = blueprint.register({ string = "FOREIGN-STRING", source = "compiled", note = "layout.json", character = "planner" })
check(#reg.key_hash == 32 and reg.entity_count == 4 and reg.already_registered == false,
  "register_blueprint returns key_hash and entity_count")
check(blueprint.register({ string = "FOREIGN-STRING", source = "compiled" }).already_registered == true,
  "registering twice is harmless")
local imp = blueprint.import({ string = "FOREIGN-STRING" })
check(imp.total_entities == 4 and imp.label == "memorized", "after registration import_blueprint decodes it")
local built = blueprint.resolve_for_build({ string = "FOREIGN-STRING" })
check(#built.entities == 4, "after registration the build resolver accepts it")

-- the same layout re-encoded elsewhere (another string, another label) is the same entry
STRINGS["MOVED-STRING"] = { kind = "blueprint", label = "copy", entities = {
  { name = "stone-furnace", position = { x = 105, y = 51 } },
  belt(100.5, 50.5, 4), belt(102.5, 50.5, 4), belt(101.5, 50.5, 4) } }
check(blueprint.import({ string = "MOVED-STRING" }).total_entities == 4, "a re-encoded, moved copy passes by content")

-- a tampered copy does not
STRINGS["TAMPERED-STRING"] = { kind = "blueprint", entities = {
  belt(0.5, 0.5, 4), belt(1.5, 0.5, 8), belt(2.5, 0.5, 4), { name = "stone-furnace", position = { x = 5, y = 1 } } } }
check(refused(blueprint.import, { string = "TAMPERED-STRING" }), "one rotated belt makes it a different, unregistered layout")

-- the registry listing is the audit
local listing = blueprint.list_registered()
check(listing.enforced == true and listing.total == 1 and listing.blueprints[1].source == "compiled"
  and listing.blueprints[1].note == "layout.json" and listing.blueprints[1].character == "planner"
  and listing.blueprints[1].entity_count == 4, "list_registered_blueprints reports source, character, note and count")

-- ------------------------------------------------------- the setting

settings.global["factorio-mcp-enforce-blueprint-provenance"] = { value = false }
check(blueprint.import({ string = "TAMPERED-STRING" }).total_entities == 4, "with the setting off any valid string is accepted")
check(blueprint.list_registered().enforced == false, "the listing reports the gate as off")
settings.global["factorio-mcp-enforce-blueprint-provenance"] = { value = true }
check(refused(blueprint.import, { string = "TAMPERED-STRING" }), "and refused again when it is switched back on")

-- --------------------------------------------------- carried blueprints

local carried = new_stack()
carried.import_stack("TAMPERED-STRING") -- a blueprint in the inventory: made in-game, never registered
carried.label = "built in game"
character.carried = { carried }
local by_label = blueprint.resolve_for_build({ label = "built in game" })
check(#by_label.entities == 4 and by_label.where == "your inventory", "a carried blueprint builds by label without the gate")
check(blueprint.read({ label = "built in game" }).total_entities == 4, "read_blueprint of a carried blueprint is not gated")
character.carried = {}

-- -------------------------------------------------- export registers

local exported = blueprint.export({ area = { { x = 8, y = 18 }, { x = 20, y = 24 } }, label = "walls" })
check(exported.total_entities == 3 and exported.string:find("EXPORT-walls", 1, true) == 1, "export_blueprint returns its string")
check(blueprint.import({ string = exported.string }).total_entities == 3, "an exported string passes the gate")
check(blueprint.resolve_for_build({ string = exported.string }).entities[1] ~= nil, "and so does build_blueprint")
local found
for _, b in ipairs(blueprint.list_registered().blueprints) do
  if b.source == "export" then found = b end
end
check(found and found.character == "test-1" and found.entity_count == 3 and found.tick == 1000,
  "the export is in the registry with character, tick and count")

-- the same area exported again later registers nothing new
local n = blueprint.list_registered().total
local again = blueprint.export({ center = { x = 14, y = 21 }, radius = 10, label = "again" })
check(blueprint.list_registered().total == n, "exporting the same layout again adds no entry")
check(blueprint.import({ string = again.string }).total_entities == 3, "and its string passes too")

-- with the gate off exports are still recorded (turning it on later keeps them valid)
settings.global["factorio-mcp-enforce-blueprint-provenance"] = { value = false }
character.surface._world = { belt(1.5, 1.5, 0) }
local off = blueprint.export({ area = { { x = 0, y = 0 }, { x = 4, y = 4 } } })
settings.global["factorio-mcp-enforce-blueprint-provenance"] = { value = true }
check(blueprint.import({ string = off.string }).total_entities == 1, "exports made while the gate was off stay valid")

-- ---------------------------- build_blueprint: refused at enqueue time

package.loaded["scripts.actions.build_plan"] = {}
package.loaded["scripts.companion"].require_companion = function() return character end
local build_blueprint = require("scripts.actions.build_blueprint")
check(refused(build_blueprint.validate, { string = "TAMPERED-STRING", anchor = { x = 0, y = 0 } }),
  "build_blueprint refuses an unregistered string when the job is enqueued")
check(pcall(build_blueprint.validate, { string = "FOREIGN-STRING" }), "enqueue accepts a registered string")
check(pcall(build_blueprint.validate, { label = "built in game" }), "enqueue does not gate a carried blueprint (label)")
check(pcall(build_blueprint.validate, { string = "", label = "x" }), "an empty string is not a string")

print(failures == 0 and "\nALL TESTS PASSED" or ("\n" .. failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
