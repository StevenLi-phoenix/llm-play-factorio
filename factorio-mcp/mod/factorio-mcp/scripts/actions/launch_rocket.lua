-- launch_rocket: walk into reach of a rocket silo and launch its rocket, like
-- a player pressing the launch button in the silo's window. A silo with no
-- rocket (fewer than all its rocket parts built) fails at once with the parts
-- count; a rocket still going through the opening/rising phases is waited
-- for. The cargo is whatever insert_items put into the silo. The result of
-- the launch is recorded by scripts/rocket.lua (on_rocket_launched).
local companion = require("scripts.companion")
local approach = require("scripts.actions.approach")
local rocket = require("scripts.rocket")

local M = {}

local SEARCH_RADIUS = 6 -- a silo is 9x9: any point on it is within this of its centre
local READY_TIMEOUT_TICKS = 60 * 120 -- a rocket takes ~40 s to rise with power
local LAUNCH_TIMEOUT_TICKS = 60 * 90 -- from the launch call to the launch event

local function dist_sq(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return dx * dx + dy * dy
end

function M.start(task)
  companion.require_companion()
  local t = task.target
  if type(t) ~= "table" or type(t.x) ~= "number" or type(t.y) ~= "number" then
    error("launch_rocket requires target = {x, y} — a point on the rocket silo")
  end
  task._deadline = nil
end

local function find_silo(c, target)
  local best, bestd
  for _, e in ipairs(c.surface.find_entities_filtered({ type = "rocket-silo", position = target, radius = SEARCH_RADIUS })) do
    local d = dist_sq(e.position, target)
    if not best or d < bestd then best, bestd = e, d end
  end
  return best
end

function M.tick(task)
  local c = companion.get()
  if not c then return { status = "failed", detail = "the companion character is gone" } end

  -- after the launch call: wait for the launch event
  if task._launched_tick then
    local launches = storage.rocket and storage.rocket.launches or {}
    local last = launches[#launches]
    if last and last.tick >= task._launched_tick then
      return { status = "done", detail = string.format("rocket launched at tick %d (%s)%s — payload: %s", last.tick,
        rocket.clock(last.tick), last.character and (" by " .. last.character) or "", rocket.payload_text(last.payload)) }
    end
    if game.tick - task._launched_tick > LAUNCH_TIMEOUT_TICKS then
      return { status = "done", detail = string.format(
        "launch started at tick %d, but no launch event has arrived yet — watch the news for ROCKET LAUNCHED",
        task._launched_tick) }
    end
    return nil
  end

  local reached = approach.ensure(task, c, task.target, c.reach_distance)
  if type(reached) == "table" then return reached end
  if reached ~= "ok" then return nil end

  local silo = find_silo(c, task.target)
  if not silo then
    return { status = "failed", detail = string.format(
      "no rocket silo at (%.1f, %.1f) — check the position with inspect", task.target.x, task.target.y) }
  end
  local info = rocket.silo_info(silo)

  if info.launching then
    return { status = "failed", detail = "the silo " .. rocket.describe(info) }
  end
  if not info.ready then
    if not info.has_rocket then
      return { status = "failed", detail = string.format(
        "can't launch: %s (the silo at (%.1f, %.1f) builds a rocket once it has %d parts)",
        rocket.describe(info), silo.position.x, silo.position.y, info.parts_required) }
    end
    -- a rocket exists and is on its way up: wait for it
    task._deadline = task._deadline or (game.tick + READY_TIMEOUT_TICKS)
    if game.tick > task._deadline then
      return { status = "failed", detail = string.format(
        "the rocket never became ready: %s (silo status: %s) — a silo without power stops at its opening phases",
        rocket.describe(info), tostring(info.status)) }
    end
    return nil
  end

  rocket.note_launch(silo, info.cargo)
  local ok, res = pcall(function() return silo.launch_rocket() end)
  if not ok then
    return { status = "failed", detail = "the silo refused to launch: " .. (tostring(res):gsub("^.-:%d+:%s*", "")) }
  end
  if res == false then
    return { status = "failed", detail = "the silo refused to launch (" .. rocket.describe(rocket.silo_info(silo)) .. ")" }
  end
  task._launched_tick = game.tick
  return nil
end

return M
