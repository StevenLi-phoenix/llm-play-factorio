-- Blueprint ghosts on the character's own surface (mod 0.3.14).
--
-- A ghost is the blue see-through preview a human gets from a blueprint: it costs nothing, builds nothing and
-- can be deleted at will. ghost_build lets an agent show a design to the human before (or instead of) building
-- it; ghost_clear takes ghosts back. Space platforms have their own pair in scripts/space.lua.
local companion = require("scripts.companion")

local M = {}

local MAX_STEPS = 1500

-- What an item or entity name places: the entity name, or nil when it places nothing (tiles are not handled).
local function entity_of(name)
  local it = prototypes.item[name]
  if it and it.place_result then return it.place_result.name end
  if prototypes.entity[name] then return name end
  return nil
end

-- rpc "ghost_build": steps = [{name, x, y, direction?, recipe?}]; name is an item or an entity.
-- Each step is checked with can_place_entity; rejects are listed with the reason and the rest still goes through.
function M.ghost_build(params)
  local c = companion.require_companion()
  local s = c.surface
  local steps = params.steps
  if type(steps) ~= "table" or #steps == 0 then
    error('give steps = [{"name":"electric-mining-drill","x":1.5,"y":1.5,"direction":4}, {"name":"transport-belt","x":3.5,"y":0.5}]')
  end
  if #steps > MAX_STEPS then error("at most " .. MAX_STEPS .. " steps per call") end
  local placed, rejected, by_name = 0, {}, {}
  for i, st in ipairs(steps) do
    local why
    local target = entity_of(st.name)
    local x, y = tonumber(st.x), tonumber(st.y)
    if not target then
      why = "unknown item/entity '" .. tostring(st.name) .. "'"
    elseif not x or not y then
      why = "needs x and y"
    else
      local dir = tonumber(st.direction) or 0
      local spec = { name = target, position = { x, y }, direction = dir, force = c.force,
        build_check_type = defines.build_check_type.manual_ghost }
      if not s.can_place_entity(spec) then
        why = "blocked (overlaps a building, water or a cliff, or invalid here)"
      else
        local g = s.create_entity({ name = "entity-ghost", inner_name = target, position = { x, y },
          direction = dir, force = c.force })
        if not (g and g.valid) then
          why = "the game refused the ghost"
        elseif st.recipe then
          local ok, err = pcall(function() g.set_recipe(st.recipe) end)
          if not ok then why = "ghost placed, but recipe '" .. tostring(st.recipe) .. "' was refused: " .. tostring(err) end
        end
      end
    end
    if why then
      if #rejected < 30 then rejected[#rejected + 1] = { i = i, name = st.name, x = x, y = y, why = why } end
    else
      placed = placed + 1
      by_name[st.name] = (by_name[st.name] or 0) + 1
    end
  end
  return { surface = s.name, placed = placed, placed_by_name = by_name, rejected = rejected,
    rejected_total = #steps - placed }
end

-- rpc "ghost_clear": delete every ghost of this force in the rectangle.
function M.ghost_clear(params)
  local c = companion.require_companion()
  local x1, y1, x2, y2 = tonumber(params.x1), tonumber(params.y1), tonumber(params.x2), tonumber(params.y2)
  if not (x1 and y1 and x2 and y2) then error("give x1, y1, x2, y2") end
  local area = { { math.min(x1, x2), math.min(y1, y2) }, { math.max(x1, x2), math.max(y1, y2) } }
  local n = 0
  for _, e in ipairs(c.surface.find_entities_filtered({ area = area, force = c.force, name = { "entity-ghost", "tile-ghost" } })) do
    if e.valid then e.destroy(); n = n + 1 end
  end
  return { removed = n }
end

return M
