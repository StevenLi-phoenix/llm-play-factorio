-- ride_rocket: walk into reach of a rocket silo and ride its rocket up to a
-- space platform parked above this planet, like a player pressing "ride" in
-- the silo window. The silo's cargo goes up with you into the hub. The job
-- ends when you are on the platform (inside its hub; from there the platform
-- tools work and drop_to_planet takes you down again).
local companion = require("scripts.companion")
local approach = require("scripts.actions.approach")
local rocket = require("scripts.rocket")
local space = require("scripts.space")

local M = {}

local SEARCH_RADIUS = 6
local READY_TIMEOUT_TICKS = 60 * 120
local ARRIVE_TIMEOUT_TICKS = 60 * 120

function M.start(task)
  local c = companion.require_companion()
  local t = task.target
  if type(t) ~= "table" or type(t.x) ~= "number" or type(t.y) ~= "number" then
    error("ride_rocket requires target = {x, y} — a point on the rocket silo")
  end
  if not script.active_mods["space-age"] then error("Space Age is not active on this server") end
  local p = space.find_platform(c.force, task.platform)
  local planet = c.surface.planet
  if not (planet and p.space_location and p.space_location.name == planet.name) then
    error("platform '" .. p.name .. "' is not parked above " .. (planet and planet.name or "this surface")
      .. " — check platforms")
  end
  if not (p.hub and p.hub.valid) then error("platform '" .. p.name .. "' has no hub yet") end
  task.platform = p.name
end

local function find_silo(c, target)
  local best, bestd
  for _, e in ipairs(c.surface.find_entities_filtered({ type = "rocket-silo", position = target, radius = SEARCH_RADIUS })) do
    local dx, dy = e.position.x - target.x, e.position.y - target.y
    local d = dx * dx + dy * dy
    if not best or d < bestd then best, bestd = e, d end
  end
  return best
end

function M.tick(task)
  local c = companion.get()
  if not c then return { status = "failed", detail = "the companion character is gone" } end

  if task._launched_tick then
    local here = space.platform_of_surface(c.surface)
    if here and here.name == task.platform and not c.cargo_pod then
      return { status = "done", detail = "arrived on platform '" .. here.name .. "' (inside its hub)" }
    end
    if game.tick - task._launched_tick > ARRIVE_TIMEOUT_TICKS then
      return { status = "failed", detail = "launched, but you have not arrived on the platform after 2 minutes" }
    end
    return nil
  end

  local reached = approach.ensure(task, c, task.target, c.reach_distance)
  if type(reached) == "table" then return reached end
  if reached ~= "ok" then return nil end

  local silo = find_silo(c, task.target)
  if not silo then
    return { status = "failed", detail = string.format("no rocket silo at (%.1f, %.1f)", task.target.x, task.target.y) }
  end
  local p = space.find_platform(c.force, task.platform)
  if not (p.space_location and c.surface.planet and p.space_location.name == c.surface.planet.name) then
    return { status = "failed", detail = "platform '" .. p.name .. "' left this planet's orbit" }
  end
  local info = rocket.silo_info(silo)
  if info.launching then return nil end -- a rocket is going up; wait for the next
  if not info.ready then
    if not info.has_rocket then
      return { status = "failed", detail = "can't ride: " .. rocket.describe(info) }
    end
    task._deadline = task._deadline or (game.tick + READY_TIMEOUT_TICKS)
    if game.tick > task._deadline then
      return { status = "failed", detail = "the rocket never became ready: " .. rocket.describe(info) }
    end
    return nil
  end
  rocket.note_launch(silo, info.cargo)
  local ok, res = pcall(function()
    return silo.launch_rocket({ type = defines.cargo_destination.station, station = p.hub }, c)
  end)
  if not ok or res == false then
    return { status = "failed", detail = "the silo refused the launch: " .. tostring(res) }
  end
  task._launched_tick = game.tick
  return nil
end

return M
