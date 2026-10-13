-- Save archive. Vanilla autosaves cycle through a few slots, so a run keeps
-- only its last half hour. Every N minutes (mod setting
-- factorio-mcp-archive-minutes, 0 = off) the server writes
-- saves/archive-<tick, 9 digits>.zip, which nothing overwrites: the run's
-- whole history stays on disk (mind the space: a save is some MB).
--
-- Measured on the headless 2.0.77 server: a game.server_save requested in the
-- same tick as an autosave is dropped without an error (the autosave runs,
-- the archive file never appears), and the two grids line up whenever the
-- interval is a multiple of the autosave interval. So every archive is
-- requested twice, one check (10 s) apart, under the same name; the second
-- request rewrites the file with the state 10 s later when the first one
-- succeeded too.
local M = {}

local SETTING = "factorio-mcp-archive-minutes"
local TICKS_PER_MINUTE = 3600

function M.minutes()
  local s = settings and settings.global and settings.global[SETTING]
  if s == nil or tonumber(s.value) == nil then return 10 end
  return math.floor(tonumber(s.value))
end

function M.save_name(tick)
  return string.format("archive-%09d", tick)
end

local function request(name)
  local ok, err = pcall(function() game.server_save(name) end)
  if not ok then
    log("factorio-mcp: archive save " .. name .. " failed: " .. tostring(err))
  end
  return ok
end

-- Called on_nth_tick (control.lua). Never raises.
function M.check()
  storage.archive = storage.archive or { last_tick = 0, count = 0 }
  local a = storage.archive
  if a.retry then
    local name = a.retry
    a.retry = nil
    request(name)
    return
  end
  local minutes = M.minutes()
  if minutes <= 0 then return end
  if game.tick - a.last_tick < minutes * TICKS_PER_MINUTE then return end
  a.last_tick = game.tick
  local name = M.save_name(game.tick)
  if request(name) then
    a.count = a.count + 1
    a.last_name = name
    a.retry = name
  end
end

return M
