-- Category lists from the game API. Factorio 2.0 returned {name = true} dictionaries, 2.1 returns plain arrays of
-- names (LuaRecipe.categories, LuaItemPrototype.fuel_categories, ...). These helpers accept either shape.
local M = {}

-- Sorted array of the names in `t` (dictionary or array); {} for anything else.
function M.sorted(t)
  local out = {}
  if type(t) ~= "table" then return out end
  for k, v in pairs(t) do
    out[#out + 1] = (type(k) == "number" and type(v) == "string") and v or k
  end
  table.sort(out)
  return out
end

-- True when `name` is in `t` (dictionary or array).
function M.has(t, name)
  if type(t) ~= "table" then return false end
  if t[name] then return true end
  for _, v in pairs(t) do
    if v == name then return true end
  end
  return false
end

-- True when any name in `wanted` (dictionary or array) is in `t`.
function M.intersects(t, wanted)
  for _, n in ipairs(M.sorted(wanted)) do
    if M.has(t, n) then return true end
  end
  return false
end

return M
