-- area_snapshot: a JSON picture of a rectangle for a schematic renderer. Not a
-- tool for agents — a harness RPC (unscoped, so it needs no bound character).
-- Instant and read-only. Like every perception query it reports only
-- EXPLORED ground (scripts/vision.lua: the engine charts nothing for
-- player-less characters), and lists the chunks of the area it had to skip.
--
-- Shape (compact keys; optional keys are left out when absent):
--   { tick, area = [x1,y1,x2,y2], unexplored_chunks = [[cx,cy]...],
--     entities = [{name,type,x,y,dir,box=[l,t,r,b],force, status?,recipe?,ug?,
--                  pickup?,drop?,out?,ghost?,label?}...],
--     resources = {name = [[x,y,amount]...]}, water = [[x,y]...],
--     obstacles = [[l,t,r,b,"tree"|"rock"|"cliff"]...] }
-- Resource and water coordinates are tile top-left integers; entity and
-- obstacle boxes are world-space bounding boxes (already rotated).
local companion = require("scripts.companion")
local vision = require("scripts.vision")
local spatial = require("scripts.spatial")

local M = {}

local MAX_SIDE = 200 -- tiles, the same limit as export_blueprint

-- Never reported as entities: resources and obstacles get their own lists;
-- the rest is ground litter and engine effects, not part of a factory.
local SKIP = {
  resource = true, tree = true, cliff = true, ["simple-entity"] = true,
  ["item-entity"] = true, corpse = true, ["character-corpse"] = true,
  ["tile-ghost"] = true, ["item-request-proxy"] = true, fish = true,
  ["rail-remnants"] = true, ["particle-source"] = true, explosion = true,
  ["smoke-with-trigger"] = true, fire = true, ["flying-text"] = true,
  sticker = true, stream = true, projectile = true, ["highlight-box"] = true,
  ["speech-bubble"] = true, ["deconstructible-tile-proxy"] = true,
}
local CRAFTERS = { ["assembling-machine"] = true, furnace = true, ["rocket-silo"] = true }

local function try(fn)
  local ok, v = pcall(fn)
  if ok then return v end
  return nil
end

-- Two decimals through text, so the JSON shows -0.47 and not -0.4699999999999999
-- (a divide-by-100 leaves float dust).
local function r2(v)
  local r = tonumber(string.format("%.2f", v))
  if r == 0 then r = 0 end -- never -0
  return r
end

local function box_of(e)
  local bb = e.bounding_box
  return { r2(bb.left_top.x), r2(bb.left_top.y), r2(bb.right_bottom.x), r2(bb.right_bottom.y) }
end

local function point_of(v)
  if type(v) ~= "table" then return nil end
  local x, y = tonumber(v.x or v[1]), tonumber(v.y or v[2])
  if x == nil or y == nil then return nil end
  return { r2(x), r2(y) }
end

-- A recipe given as a name, a LuaRecipe or a {name=, quality=} pair -> its name.
local function recipe_name(v)
  if v == nil then return nil end
  if type(v) == "string" then return v end
  local n = try(function() return v.name end)
  if type(n) == "string" then return n end
  if n ~= nil then return recipe_name(n) end
  return nil
end

local status_names -- value -> key of defines.entity_status
local function status_name(value)
  if value == nil then return nil end
  if not status_names then
    status_names = {}
    for key, v in pairs(defines.entity_status) do status_names[v] = key end
  end
  return status_names[value]
end

local function parse_area(params)
  local x1, y1 = tonumber(params.x1), tonumber(params.y1)
  local x2, y2 = tonumber(params.x2), tonumber(params.y2)
  if not (x1 and y1 and x2 and y2) then
    error("area_snapshot needs numeric x1, y1, x2, y2")
  end
  if x1 > x2 then x1, x2 = x2, x1 end
  if y1 > y2 then y1, y2 = y2, y1 end
  if x2 - x1 > MAX_SIDE or y2 - y1 > MAX_SIDE then
    error("area_snapshot is limited to " .. MAX_SIDE .. "x" .. MAX_SIDE .. " tiles")
  end
  return x1, y1, x2, y2
end

-- One entity as the schema's record; nil when it is not part of the picture.
local function describe(e, labelled)
  local ghost = e.type == "entity-ghost"
  local rec = {
    name = ghost and e.ghost_name or e.name,
    type = ghost and e.ghost_type or e.type,
    x = r2(e.position.x),
    y = r2(e.position.y),
    dir = try(function() return e.direction end) or 0,
    box = box_of(e),
    force = e.force and e.force.name or "neutral",
  }
  if ghost then rec.ghost = true end
  local st = status_name(try(function() return e.status end))
  if st then rec.status = st end

  if CRAFTERS[rec.type] then
    local recipe = recipe_name(try(function() return e.get_recipe() end))
    if not recipe and rec.type == "furnace" and not ghost then
      recipe = recipe_name(try(function() return e.previous_recipe end))
    end
    if recipe then rec.recipe = recipe end
  end

  if rec.type == "underground-belt" then
    local ug = try(function() return e.belt_to_ground_type end)
    if ug == "input" or ug == "output" then rec.ug = ug end
  elseif rec.type == "inserter" and not ghost then
    rec.pickup = point_of(try(function() return e.pickup_position end))
    rec.drop = point_of(try(function() return e.drop_position end))
  elseif rec.type == "mining-drill" and not ghost then
    rec.out = point_of(try(function() return e.drop_position end))
  elseif rec.type == "character" then
    local label = labelled(e)
    if label then rec.label = label end
  end
  return rec
end

function M.area_snapshot(params)
  local x1, y1, x2, y2 = parse_area(params)
  local surface = game.surfaces.nauvis or game.surfaces[1]
  local force = game.forces.player
  local area = { { x1, y1 }, { x2, y2 } }

  -- Explored chunks, memoized by chunk; the unexplored ones are reported.
  local known_memo = {}
  local function known_chunk(cx, cy)
    local k = cx .. "," .. cy
    local v = known_memo[k]
    if v == nil then
      v = vision.is_known(surface, force, { x = cx * 32 + 16, y = cy * 32 + 16 })
      known_memo[k] = v
    end
    return v
  end
  local function known(x, y)
    return known_chunk(math.floor(x / 32), math.floor(y / 32))
  end

  local unexplored = {}
  local cx1, cy1 = math.floor(x1 / 32), math.floor(y1 / 32)
  local cx2 = math.max(cx1, math.floor((x2 - 1e-6) / 32))
  local cy2 = math.max(cy1, math.floor((y2 - 1e-6) / 32))
  for cy = cy1, cy2 do
    for cx = cx1, cx2 do
      if not known_chunk(cx, cy) then unexplored[#unexplored + 1] = { cx, cy } end
    end
  end

  local entities, obstacles = {}, {}
  local resources, resource_lists = {}, {}
  local function labelled(e) return companion.name_of(e) end
  for _, e in ipairs(surface.find_entities_filtered({ area = area })) do
    if e.valid and known(e.position.x, e.position.y) then
      local t = e.type
      if t == "resource" then
        local tx, ty = math.floor(e.position.x), math.floor(e.position.y)
        if e.position.x >= x1 and e.position.x < x2 and e.position.y >= y1 and e.position.y < y2 then
          local list = resource_lists[e.name]
          if not list then
            list = {}
            resource_lists[e.name] = list
            resources[e.name] = list
          end
          list[#list + 1] = { tx, ty, e.amount }
        end
      elseif t == "tree" or t == "simple-entity" or t == "cliff" then
        obstacles[#obstacles + 1] = { box_of(e), t == "tree" and "tree" or (t == "cliff" and "cliff" or "rock") }
      elseif not SKIP[t] then
        entities[#entities + 1] = describe(e, labelled)
      end
    end
  end

  local function by_position(a, b)
    if a.y ~= b.y then return a.y < b.y end
    if a.x ~= b.x then return a.x < b.x end
    return a.name < b.name
  end
  table.sort(entities, by_position)
  for _, list in pairs(resources) do
    table.sort(list, function(a, b)
      if a[2] ~= b[2] then return a[2] < b[2] end
      return a[1] < b[1]
    end)
  end
  local flat_obstacles = {}
  table.sort(obstacles, function(a, b)
    if a[1][2] ~= b[1][2] then return a[1][2] < b[1][2] end
    if a[1][1] ~= b[1][1] then return a[1][1] < b[1][1] end
    return a[2] < b[2]
  end)
  for i, o in ipairs(obstacles) do
    local b = o[1]
    flat_obstacles[i] = { b[1], b[2], b[3], b[4], o[2] }
  end

  -- Water: every tile of the area that collides with water, on explored ground.
  local water = {}
  local tiles = try(function()
    return surface.find_tiles_filtered({ area = area, collision_mask = "water_tile" })
  end)
  if tiles then
    for _, tile in ipairs(tiles) do
      local p = tile.position
      if known(p.x, p.y) then water[#water + 1] = { p.x, p.y } end
    end
  else
    for ty = math.floor(y1), math.ceil(y2) - 1 do
      for tx = math.floor(x1), math.ceil(x2) - 1 do
        if known(tx, ty) and spatial.is_water_at(surface, tx, ty) then water[#water + 1] = { tx, ty } end
      end
    end
  end
  table.sort(water, function(a, b)
    if a[2] ~= b[2] then return a[2] < b[2] end
    return a[1] < b[1]
  end)

  return {
    tick = game.tick,
    area = { x1, y1, x2, y2 },
    unexplored_chunks = unexplored,
    entities = entities,
    resources = resources,
    water = water,
    obstacles = flat_obstacles,
  }
end

return M
