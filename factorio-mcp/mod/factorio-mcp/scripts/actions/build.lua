-- Building actions: place, rotate, set_recipe. Each approaches its target
-- first (build_distance for place, reach_distance otherwise).
local companion = require("scripts.companion")
local placement = require("scripts.placement")
local items = require("scripts.items")
local approach = require("scripts.actions.approach")
local build_plan = require("scripts.actions.build_plan")
local belts = require("scripts.belts")
local provenance = require("scripts.provenance")

local M = {}

local direction_names = {}
for name, value in pairs(defines.direction) do
  direction_names[value] = name
end

local function dir_name(d)
  return direction_names[d] or tostring(d)
end

local function validate_position(pos, action)
  if type(pos) ~= "table" or type(pos.x) ~= "number" or type(pos.y) ~= "number" then
    error(action .. " requires target = {x, y}")
  end
end

local function gone()
  return { status = "failed", detail = "the companion character is gone" }
end

-- ------------------------------------------------------------------ place


M.place = {}

function M.place.start(task)
  local c = companion.require_companion()
  if type(task.item) ~= "string" then
    error("place requires item = <item name>")
  end
  if type(task.position) ~= "table" or type(task.position.x) ~= "number" or type(task.position.y) ~= "number" then
    error("place requires position = {x, y}")
  end
  local item_name, item_quality = items.parse(task.item)
  local proto = prototypes.item[item_name]
  if not proto then
    error("no item called '" .. task.item .. "'")
  end
  local result = proto.place_result
  if not result then
    error(task.item .. " is not a placeable item")
  end
  task._quality = item_quality
  if items.count(c, task.item) == 0 then
    error("I don't have any " .. task.item .. " in my inventory — craft or collect one first")
  end
  task.direction = math.floor(tonumber(task.direction) or 0) % 16
  task._entity_name = result.name
  local bad_dir = placement.check_direction(result.name, task.direction)
  if bad_dir then error(bad_dir) end
  task.position = placement.snap(result, task.position, task.direction)
  if task.recipe ~= nil then
    -- checked before walking, like set_recipe
    local r = c.force.recipes[tostring(task.recipe)]
    if not r then error("unknown recipe: '" .. tostring(task.recipe) .. "'") end
    if not r.enabled then error("recipe " .. tostring(task.recipe) .. " isn't unlocked yet — research it first") end
  end
end

function M.place.tick(task)
  local c = companion.get()
  if not c then return gone() end

  local reached = approach.ensure(task, c, task.position, c.build_distance)
  if type(reached) == "table" then return reached end
  if reached ~= "ok" then return nil end

  if items.count(c, task.item) == 0 then
    return { status = "failed", detail = "I no longer have any " .. task.item .. " in my inventory" }
  end

  local aside = approach.step_aside(task, c,
    placement.footprint(prototypes.entity[task._entity_name], task.position, task.direction))
  if type(aside) == "table" then return aside end
  if aside ~= "ok" then return nil end

  local occ, occ_items = placement.occupant(c, task._entity_name, task.position, task.direction)
  if occ and not task.fast_replace then
    return {
      status = "failed",
      detail = string.format("the %s at (%.1f, %.1f)%s is in the way — deconstruct it first, or pass fast_replace=true "
        .. "to swap it like a player does (its contents move over)", occ.name, occ.position.x, occ.position.y,
        occ_items > 0 and string.format(" holding %d items", occ_items) or ""),
    }
  end

  -- The engine has no same-name fast replace: its manual build check refuses
  -- a tile held by an identical entity (the real game does nothing when you
  -- place a wall over a wall), so a same-item fast_replace always died at
  -- "blocked by stone-wall" at the target's own position, never reaching
  -- create_entity. Same item + fast_replace is a REFRESH: hand the old one
  -- back (like deconstruct) and place the new one fresh — damaged-wall
  -- maintenance is the standing use.
  local refresh, refresh_note = nil, ""
  if occ and task.fast_replace == true then
    local q = (occ.quality and occ.quality.name) or "normal"
    if occ.name == task._entity_name and q == (task._quality or "normal") then refresh = occ end
  end
  local swap = false
  if refresh then
    local inv = c.get_main_inventory()
    local removed = false
    if inv then pcall(function() removed = refresh.mine({ inventory = inv, raise_destroyed = true }) end) end
    if not removed then
      return {
        status = "failed",
        detail = string.format("couldn't take down the old %s at (%.1f, %.1f) to replace it — my inventory is probably full",
          refresh.name, refresh.position.x, refresh.position.y),
      }
    end
    refresh_note = " — replaced the old one (returned to my inventory)"
  else
    local can_place = c.surface.can_place_entity({
      name = task._entity_name,
      position = task.position,
      direction = task.direction,
      force = c.force,
      build_check_type = defines.build_check_type.manual,
    })
    if not can_place then
      return {
        status = "failed",
        detail = string.format("can't place %s at (%.1f, %.1f) — %s",
          task.item, task.position.x, task.position.y, placement.explain(c, task._entity_name, task.position, task.direction)),
      }
    end
    swap = occ ~= nil
  end

  local built = c.surface.create_entity({
    name = task._entity_name,
    position = task.position,
    direction = task.direction,
    force = c.force,
    quality = task._quality,
    type = task.underground_type, -- underground belts: "input" or "output"
    raise_built = true,
    -- a player-style fast replace: the old building goes to this character
    -- and its contents into the new one (what fits)
    fast_replace = swap and task.fast_replace == true or nil,
    character = (swap and task.fast_replace == true) and c or nil,
  })
  if not built then
    return {
      status = "failed",
      detail = string.format("placing %s at (%.1f, %.1f) failed unexpectedly — try a slightly different spot",
        task.item, task.position.x, task.position.y),
    }
  end
  c.remove_item(items.spec(task.item, 1))
  provenance.record(built, string.format("placed%s", task.direction ~= 0
    and (" facing " .. dir_name(task.direction)) or ""), task)
  local recipe_note = ""
  if task.recipe ~= nil and built.valid then
    local why = build_plan.apply_recipe(c, built, tostring(task.recipe), task)
    if why then
      return { status = "failed", detail = string.format("placed %s at (%.1f, %.1f), but %s",
        task.item, built.position.x, built.position.y, why) }
    end
    recipe_note = ", recipe " .. tostring(task.recipe)
  end
  if built.valid and built.type == "underground-belt" then
    -- say whether it paired: an unpaired entrance swallows nothing and passes nothing
    local note, paired = belts.underground_note(built)
    recipe_note = recipe_note .. " — underground " .. note
      .. ((not paired and built.belt_to_ground_type == "input") and " (normal until you place its exit)" or "")
  end
  return {
    status = "done",
    detail = string.format("placed %s at (%.1f, %.1f)%s%s%s",
      task.item, built.position.x, built.position.y,
      task.direction ~= 0 and (" facing " .. dir_name(task.direction)) or "", refresh_note, recipe_note),
  }
end

-- ----------------------------------------------------------------- rotate

M.rotate = {}

function M.rotate.start(task)
  companion.require_companion()
  validate_position(task.target, "rotate")
  if task.direction ~= nil then
    task.direction = math.floor(tonumber(task.direction) or 0) % 16
  end
end

function M.rotate.tick(task)
  local c = companion.get()
  if not c then return gone() end

  local reached = approach.ensure(task, c, task.target, c.reach_distance)
  if type(reached) == "table" then return reached end
  if reached ~= "ok" then return nil end

  local e, pick_note = approach.find_entity_near(c, task.target)
  task._pick_note = pick_note
  if not e then
    return {
      status = "failed",
      detail = string.format("nothing to rotate at (%.1f, %.1f)", task.target.x, task.target.y),
    }
  end

  if task.direction then
    local ok = pcall(function() e.direction = task.direction end)
    if not ok or e.direction ~= task.direction then
      return { status = "failed", detail = "the " .. e.name .. " can't face that way" }
    end
    provenance.record(e, string.format("rotated to face %s", dir_name(task.direction)), task)
    return {
      status = "done",
      detail = string.format("turned the %s at (%.1f, %.1f) to face %s",
        e.name, e.position.x, e.position.y, dir_name(task.direction)),
    }
  end

  if not e.rotate() then
    return { status = "failed", detail = "the " .. e.name .. " can't be rotated" }
  end
  provenance.record(e, string.format("rotated to face %s", dir_name(e.direction)), task)
  return {
    status = "done",
    detail = string.format("rotated the %s at (%.1f, %.1f) — it now faces %s",
      e.name, e.position.x, e.position.y, dir_name(e.direction)),
  }
end

-- ------------------------------------------------------------- set_recipe

M.set_recipe = {}

function M.set_recipe.start(task)
  local c = companion.require_companion()
  validate_position(task.target, "set_recipe")
  if type(task.recipe) ~= "string" then
    error("set_recipe requires recipe = <recipe name>")
  end
  local r = c.force.recipes[task.recipe]
  if not r then
    error("unknown recipe: '" .. task.recipe .. "'")
  end
  if not r.enabled then
    error("recipe " .. task.recipe .. " isn't unlocked yet — research it first")
  end
end

function M.set_recipe.tick(task)
  local c = companion.get()
  if not c then return gone() end

  local reached = approach.ensure(task, c, task.target, c.reach_distance)
  if type(reached) == "table" then return reached end
  if reached ~= "ok" then return nil end

  local e, pick_note = approach.find_entity_near(c, task.target)
  task._pick_note = pick_note
  if not e then
    return {
      status = "failed",
      detail = string.format("nothing at (%.1f, %.1f) to set a recipe on", task.target.x, task.target.y),
    }
  end
  if e.type ~= "assembling-machine" then
    if e.type == "furnace" then
      return {
        status = "failed",
        detail = "the " .. e.name .. " is a furnace — it picks its recipe automatically from what you insert",
      }
    end
    return { status = "failed", detail = "the " .. e.name .. " can't have a recipe set — only crafting machines can" }
  end

  local ok, removed = pcall(e.set_recipe, task.recipe)
  if not ok then
    return {
      status = "failed",
      detail = string.format("couldn't set %s on the %s — that machine probably can't craft it",
        task.recipe, e.name),
    }
  end

  -- Ingredients of the previous recipe come back to us; overflow spills.
  local taken, dropped = 0, 0
  if type(removed) == "table" then
    for _, stack in ipairs(removed) do
      if stack.name and (stack.count or 0) > 0 then
        local d = items.give(c, { name = stack.name, count = stack.count, quality = stack.quality })
        taken = taken + stack.count - d
        dropped = dropped + d
      end
    end
  end
  provenance.record(e, string.format("set recipe to %s", task.recipe), task)
  return {
    status = "done",
    detail = string.format("set %s's recipe to %s%s%s", e.name, task.recipe,
      taken > 0 and string.format(" (took %d leftover items into my inventory)", taken) or "",
      dropped > 0 and string.format("; %d didn't fit and are on the ground at my feet", dropped) or ""),
  }
end

-- ------------------------------------------------------------ set_filters

-- Filters of an inserter (item whitelist/blacklist) or a splitter (one item
-- filter plus input/output priority), like clicking it open.
M.set_filters = {}

function M.set_filters.start(task)
  companion.require_companion()
  validate_position(task.target, "set_filters")
  if task.filters ~= nil and type(task.filters) ~= "table" then
    error("filters must be a list of item names ([] clears)")
  end
  for _, f in ipairs(task.filters or {}) do
    if type(f) ~= "string" or not prototypes.item[f] then error("unknown item: '" .. tostring(f) .. "'") end
  end
  if task.mode and task.mode ~= "whitelist" and task.mode ~= "blacklist" then
    error("mode must be whitelist or blacklist")
  end
end

local PRIORITIES = { left = true, right = true, none = true }

function M.set_filters.tick(task)
  local c = companion.get()
  if not c then return gone() end

  local reached = approach.ensure(task, c, task.target, c.reach_distance)
  if type(reached) == "table" then return reached end
  if reached ~= "ok" then return nil end

  local e, pick_note = approach.find_entity_near(c, task.target)
  task._pick_note = pick_note
  if not e then
    return { status = "failed",
      detail = string.format("nothing at (%.1f, %.1f) to set filters on", task.target.x, task.target.y) }
  end
  local done = {}
  if e.type == "inserter" then
    local slots = e.filter_slot_count or 0
    if slots == 0 then
      return { status = "failed", detail = "the " .. e.name .. " has no filter slots — use a fast or bulk inserter" }
    end
    if task.filters then
      if #task.filters > slots then
        return { status = "failed", detail = string.format("the %s has only %d filter slots", e.name, slots) }
      end
      e.use_filters = #task.filters > 0
      for i = 1, slots do
        local f = task.filters[i]
        e.set_filter(i, f and { name = f } or nil)
      end
      done[#done + 1] = #task.filters > 0 and ("filters " .. table.concat(task.filters, ", ")) or "filters cleared"
    end
    if task.mode then
      e.inserter_filter_mode = task.mode
      done[#done + 1] = task.mode
    end
  elseif e.type == "splitter" then
    if task.filters then
      if #task.filters > 1 then
        return { status = "failed", detail = "a splitter takes one item filter" }
      end
      local f = task.filters[1]
      e.splitter_filter = f and { name = f } or nil
      done[#done + 1] = f and ("filter " .. f .. " (it goes to the " .. (task.output_priority or e.splitter_output_priority) .. " output)")
        or "filter cleared"
    end
    for _, k in ipairs({ "input_priority", "output_priority" }) do
      local v = task[k]
      if v then
        if not PRIORITIES[v] then return { status = "failed", detail = k .. " must be left, right or none" } end
        e["splitter_" .. k] = v
        done[#done + 1] = k:gsub("_", " ") .. " " .. v
      end
    end
    if task.filters and task.filters[1] and e.splitter_output_priority == "none" then
      e.splitter_output_priority = "left"
      done[#done + 1] = "output priority left (a filter needs a side)"
    end
  else
    return { status = "failed", detail = "the " .. e.name .. " has no filters — inserters and splitters do" }
  end
  if #done == 0 then return { status = "failed", detail = "nothing to set: give filters, mode or a priority" } end
  provenance.record(e, "set " .. table.concat(done, "; "), task)
  return { status = "done", detail = string.format("%s at (%.1f, %.1f): %s", e.name, e.position.x, e.position.y,
    table.concat(done, "; ")) }
end

-- ------------------------------------------------------------- place_tiles

M.place_tiles = {}

local MAX_TILES = 400

function M.place_tiles.start(task)
  local c = companion.require_companion()
  if type(task.item) ~= "string" then error("place_tiles requires item = <tile item name>") end
  local proto = prototypes.item[task.item]
  if not proto then error("no item called '" .. task.item .. "'") end
  local pat = proto.place_as_tile_result
  if not pat then error(task.item .. " is not a tile item (landfill, concrete, artificial soil, ...)") end
  local tiles, seen = {}, {}
  local function add(x, y)
    x, y = math.floor(x), math.floor(y)
    local k = x .. "," .. y
    if not seen[k] then seen[k] = true tiles[#tiles + 1] = { x = x, y = y } end
  end
  if type(task.positions) == "table" then
    for _, p in ipairs(task.positions) do
      if type(p) ~= "table" or type(p.x) ~= "number" or type(p.y) ~= "number" then
        error("positions must be a list of {x, y}")
      end
      add(p.x, p.y)
    end
  end
  if type(task.area) == "table" then
    local a = task.area
    for _, k in ipairs({ "x1", "y1", "x2", "y2" }) do
      if type(a[k]) ~= "number" then error("area needs x1, y1, x2, y2") end
    end
    local x1, x2 = math.floor(math.min(a.x1, a.x2)), math.floor(math.max(a.x1, a.x2))
    local y1, y2 = math.floor(math.min(a.y1, a.y2)), math.floor(math.max(a.y1, a.y2))
    if (x2 - x1 + 1) * (y2 - y1 + 1) > MAX_TILES then error("area is more than " .. MAX_TILES .. " tiles") end
    for y = y1, y2 do for x = x1, x2 do add(x, y) end end
  end
  if #tiles == 0 then error("give positions or an area") end
  if #tiles > MAX_TILES then error("at most " .. MAX_TILES .. " tiles per call") end
  if items.count(c, task.item) == 0 then
    error("I don't have any " .. task.item .. " — craft or collect some first")
  end
  -- walk order: nearest-neighbour from the character
  local ordered, pos = {}, c.position
  while #tiles > 0 do
    local bi, bd = 1, math.huge
    for i, t in ipairs(tiles) do
      local d = (t.x + 0.5 - pos.x) ^ 2 + (t.y + 0.5 - pos.y) ^ 2
      if d < bd then bi, bd = i, d end
    end
    pos = { x = tiles[bi].x + 0.5, y = tiles[bi].y + 0.5 }
    ordered[#ordered + 1] = table.remove(tiles, bi)
  end
  task._tiles, task._i, task._placed, task._skipped = ordered, 1, 0, {}
  task._result = pat.result.name
end

-- Why the tile at t can't take this item, or nil.
local function tile_refusal(surface, pat, t)
  local cur = surface.get_tile(t.x, t.y)
  if not cur.valid then return "outside the map" end
  if cur.name == pat.result.name then return "already " .. pat.result.name end
  if pat.tile_condition then
    local ok = false
    for _, tp in pairs(pat.tile_condition) do if tp.name == cur.name then ok = true break end end
    if pat.invert then ok = not ok end
    if not ok then
      local names = {}
      for _, tp in pairs(pat.tile_condition) do names[#names + 1] = tp.name end
      return "can't go on " .. cur.name .. (pat.invert and "" or (" — only on " .. table.concat(names, ", ")))
    end
  end
  local cond = pat.condition and pat.condition.layers or {}
  local mask = cur.prototype.collision_mask and cur.prototype.collision_mask.layers or {}
  for layer in pairs(cond) do
    if mask[layer] then return "can't go on " .. cur.name end
  end
  return nil
end

function M.place_tiles.tick(task)
  local c = companion.get()
  if not c then return gone() end
  local pat = prototypes.item[task.item].place_as_tile_result
  local surface = c.surface
  local tiles = task._tiles

  while task._i <= #tiles do
    local t = tiles[task._i]
    local center = { x = t.x + 0.5, y = t.y + 0.5 }
    local reached = approach.ensure(task, c, center, c.build_distance)
    if type(reached) == "table" then
      task._skipped[#task._skipped + 1] = string.format("(%d, %d): %s", t.x, t.y, reached.detail)
      task._i = task._i + 1
      return nil
    end
    if reached ~= "ok" then return nil end
    -- place every remaining tile already within reach, then walk on
    local batch, hidden = {}, {}
    local j = task._i
    while j <= #tiles do
      local u = tiles[j]
      local dx, dy = u.x + 0.5 - c.position.x, u.y + 0.5 - c.position.y
      if dx * dx + dy * dy > c.build_distance * c.build_distance then break end
      if items.count(c, task.item) - #batch <= 0 then break end
      local why = tile_refusal(surface, pat, u)
      if why then
        task._skipped[#task._skipped + 1] = string.format("(%d, %d): %s", u.x, u.y, why)
      else
        local cur = surface.get_tile(u.x, u.y)
        local tile = { name = task._result, position = { u.x, u.y } }
        -- a minable floor (concrete, soil) keeps the ground under it
        local res = prototypes.tile[task._result]
        if res.mineable_properties and res.mineable_properties.minable and not cur.prototype.mineable_properties.minable then
          tile.hidden_tile = cur.name
        end
        batch[#batch + 1] = tile
      end
      j = j + 1
    end
    if #batch > 0 then
      surface.set_tiles(batch, true, "abort_on_collision", true, true)
      local n = 0
      for _, tile in ipairs(batch) do
        if surface.get_tile(tile.position[1], tile.position[2]).name == task._result then
          n = n + 1
        else
          task._skipped[#task._skipped + 1] = string.format("(%d, %d): something stands there",
            tile.position[1], tile.position[2])
        end
      end
      if n > 0 then c.remove_item({ name = task.item, count = n }) end
      task._placed = task._placed + n
    end
    task._i = j
    if items.count(c, task.item) == 0 and task._i <= #tiles then
      task._skipped[#task._skipped + 1] = string.format("%d tile(s) not placed: out of %s", #tiles - task._i + 1, task.item)
      break
    end
  end

  local detail = string.format("placed %d %s tile(s)", task._placed, task._result)
  if #task._skipped > 0 then
    local shown = {}
    for i = 1, math.min(#task._skipped, 12) do shown[i] = task._skipped[i] end
    detail = detail .. "; skipped " .. #task._skipped .. ": " .. table.concat(shown, "; ")
      .. (#task._skipped > 12 and "; ..." or "")
  end
  return { status = task._placed > 0 and "done" or "failed", detail = detail }
end

return M
