-- fight: anchored area combat. Walks into gun range, re-sets shooting_state
-- every tick (one-shot writes, like walking_state), moves to the next enemy
-- until the radius is clear, retreats toward a player at low health.
-- With a long gun (rocket launcher) it kites: backs away from any enemy unit
-- inside keep_away while it keeps shooting, so short-range units never close in.
local companion = require("scripts.companion")
local vision = require("scripts.vision")
local equipment = require("scripts.equipment")
local walk = require("scripts.actions.walk")

local M = {}

local ENEMY_TYPES = { "unit", "unit-spawner", "turret" }
local DEFAULT_RADIUS = 20
local MAX_RADIUS = 40
local DEFAULT_FLEE_BELOW = 0.3

local function stop_shooting(c)
  pcall(function()
    c.shooting_state = { state = defines.shooting.not_shooting }
  end)
end

local function gun_range(c)
  local range = 15
  local name = equipment.current_gun(c)
  if name then
    pcall(function()
      local ap = prototypes.item[name].attack_parameters
      if ap and type(ap.range) == "number" then range = ap.range end
    end)
  end
  return range
end

local function total_ammo(c)
  local n = 0
  pcall(function()
    local inv = c.get_inventory(defines.inventory.character_ammo)
    if inv then
      for i = 1, #inv do
        if inv[i].valid_for_read then n = n + inv[i].count end
      end
    end
  end)
  return n
end

local function kills_phrase(n)
  return string.format("%d kill%s", n, n == 1 and "" or "s")
end

function M.start(task)
  local c = companion.require_companion()
  local gun = equipment.current_gun(c)
  if not gun then
    error("equip a gun first — I have none. Give me e.g. a pistol and use equip")
  end
  if total_ammo(c) == 0 then
    error("no ammo for my " .. gun .. " — hand me some and equip it")
  end
  task.radius = math.min(tonumber(task.radius) or DEFAULT_RADIUS, MAX_RADIUS)
  task.flee_below = tonumber(task.flee_below) or DEFAULT_FLEE_BELOW
  local anchor = (task.target and type(task.target.x) == "number") and task.target or c.position
  local range = gun_range(c)
  local keep_away = tonumber(task.keep_away)
  if not keep_away then keep_away = range > 20 and range - 8 or 0 end
  task._fight = {
    anchor = { x = anchor.x, y = anchor.y },
    kills = 0,
    range = range,
    keep_away = math.min(keep_away, range - 2),
    engaged = false,
  }
end

local function nearest_unit(c, within)
  local best, best_d
  for _, e in ipairs(c.surface.find_entities_filtered({
    type = "unit", force = game.forces.enemy, position = c.position, radius = within,
  })) do
    if e.valid then
      local dx, dy = e.position.x - c.position.x, e.position.y - c.position.y
      local d = dx * dx + dy * dy
      if not best or d < best_d then best, best_d = e, d end
    end
  end
  return best
end

-- A point `dist` tiles from the character, straight away from `threat`.
local function away_point(c, threat, dist)
  local dx, dy = c.position.x - threat.position.x, c.position.y - threat.position.y
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 0.01 then dx, dy, len = 0, 1, 1 end
  return { x = c.position.x + dx / len * dist, y = c.position.y + dy / len * dist }
end

-- Step away from units inside keep_away. True while kiting this tick.
local function kite(c, f)
  if f.keep_away <= 0 or (f.kite_blocked_until or 0) > game.tick then return false end
  local threat = nearest_unit(c, f.keep_away)
  if not threat then
    f.kite_last = nil
    return false
  end
  local last = f.kite_last
  if last and math.abs(last.x - c.position.x) + math.abs(last.y - c.position.y) < 0.02 then
    f.kite_stuck = (f.kite_stuck or 0) + 1
    if f.kite_stuck > 30 then
      -- Backed against a cliff or water: stand and shoot for a while.
      f.kite_stuck, f.kite_last = 0, nil
      f.kite_blocked_until = game.tick + 180
      return false
    end
  else
    f.kite_stuck = 0
  end
  f.kite_last = { x = c.position.x, y = c.position.y }
  c.walking_state = { walking = true, direction = walk.direction_toward(c.position, away_point(c, threat, 10)) }
  f.walk = nil
  return true
end

local function pick_target(c, f, radius)
  local best, best_d
  for _, e in ipairs(vision.filter_visible(c.surface.find_entities_filtered({
    type = ENEMY_TYPES,
    force = game.forces.enemy,
    position = f.anchor,
    radius = radius,
  }), c.surface, c.force)) do
    if e.valid then
      local dx, dy = e.position.x - c.position.x, e.position.y - c.position.y
      local d = dx * dx + dy * dy
      if not best or d < best_d then
        best, best_d = e, d
      end
    end
  end
  return best
end

function M.tick(task)
  local c = companion.get()
  if not c then
    return { status = "failed", detail = "the companion character is gone" }
  end
  local f = task._fight

  -- Low health → break off and retreat toward a player (or the spawn point).
  local max_health = 250
  pcall(function() max_health = c.max_health end)
  if (c.health or 0) / max_health < task.flee_below then
    stop_shooting(c)
    if not f.retreat then
      -- Run straight away from the nearest enemy first; fall back to a player or the spawn point.
      local threat = nearest_unit(c, 40)
      local dest
      if threat then
        dest = away_point(c, threat, 40)
        f.retreat_away = true
      else
        local p = game.connected_players[1]
        if p and p.character and p.surface == c.surface then
          dest = { x = p.position.x, y = p.position.y }
        else
          local sp = c.force.get_spawn_position(c.surface)
          dest = { x = sp.x, y = sp.y }
        end
      end
      f.retreat = {}
      walk.begin(f.retreat, c, dest, 3)
    end
    local r = walk.step(f.retreat, c, task.id)
    if type(r) == "table" and f.retreat_away then
      -- No path straight away (water, cliffs): head for the spawn point instead.
      f.retreat_away = false
      local sp = c.force.get_spawn_position(c.surface)
      f.retreat = {}
      walk.begin(f.retreat, c, { x = sp.x, y = sp.y }, 3)
      return nil
    end
    if r == "arrived" or type(r) == "table" then
      return {
        status = "done",
        detail = string.format("retreated at low health after %s — patch me up before the next fight",
          kills_phrase(f.kills)),
      }
    end
    return nil
  end

  -- Current target (re-acquire when dead/invalid; count the kill if we were on it).
  local target = f.target
  if not (target and target.valid) then
    if f.engaged then
      f.kills = f.kills + 1
      f.engaged = false
    end
    target = pick_target(c, f, task.radius)
    f.target = target
    f.walk = nil
    if not target then
      stop_shooting(c)
      return { status = "done", detail = string.format("area cleared — %s", kills_phrase(f.kills)) }
    end
  end

  if total_ammo(c) == 0 then
    stop_shooting(c)
    return {
      status = "failed",
      detail = string.format("out of ammo after %s — enemies remain, bring me more ammo", kills_phrase(f.kills)),
    }
  end

  local dx, dy = target.position.x - c.position.x, target.position.y - c.position.y
  local dist = math.sqrt(dx * dx + dy * dy)
  if kite(c, f) then
    -- Shoot while backing off when the target is still in range.
    if dist <= f.range - 1 then
      f.engaged = true
      c.shooting_state = {
        state = defines.shooting.shooting_enemies,
        position = { x = target.position.x, y = target.position.y },
      }
    else
      stop_shooting(c)
    end
    return nil
  end
  if dist > f.range - 1 then
    stop_shooting(c)
    -- Walk toward the target; re-plan when it has drifted from the walk goal.
    if not f.walk or not f.walk_goal
      or math.abs(f.walk_goal.x - target.position.x) + math.abs(f.walk_goal.y - target.position.y) > 3 then
      f.walk = {}
      f.walk_goal = { x = target.position.x, y = target.position.y }
      walk.begin(f.walk, c, f.walk_goal, math.max(f.range - 2, 2))
    end
    local r = walk.step(f.walk, c, task.id)
    if type(r) == "table" then
      -- Unreachable (water in between?) — drop this target and look for another.
      f.target = nil
      f.walk = nil
    elseif r == "arrived" then
      f.walk = nil
    end
    return nil
  end

  c.walking_state = { walking = false }
  f.engaged = true
  c.shooting_state = {
    state = defines.shooting.shooting_enemies,
    position = { x = target.position.x, y = target.position.y },
  }
  return nil
end

return M
