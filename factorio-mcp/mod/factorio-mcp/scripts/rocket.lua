-- The end of the run: launching a rocket. A silo builds a rocket from 100
-- rocket parts; the rocket then goes through the opening, rising and arms
-- phases until rocket_silo_status is rocket_ready. Items inserted into the
-- silo (insert_items) land in the rocket's cargo slot once a rocket exists.
-- The launch itself is the launch_rocket job (actions/launch_rocket.lua);
-- this module reads silo state and records the result.
--
-- on_rocket_launched writes the run's result:
--   * storage.rocket.launches (every launch) and storage.run_result (the first,
--     the run's finish: tick, launching character, payload);
--   * script-output/run-result.json, server side only (write_file for_player 0);
--   * a server chat line, and a force-wide "rocket_launched" event, which
--     rides the news footer of every tool result.
local companion = require("scripts.companion")
local events = require("scripts.events")
local chat = require("scripts.chat")
local items = require("scripts.items")

local M = {}

local PENDING_TICKS = 60 * 180 -- a launch call counts as the cause of a launch event this soon after
local RESULT_FILE = "run-result.json"

local function store()
  storage.rocket = storage.rocket or { launches = {}, pending = {} }
  return storage.rocket
end

local function try(fn)
  local ok, v = pcall(fn)
  if ok then return v end
  return nil
end

local phase_names -- value -> key of defines.rocket_silo_status
function M.phase_name(value)
  if value == nil then return nil end
  if not phase_names then
    phase_names = {}
    for key, v in pairs(defines.rocket_silo_status) do phase_names[v] = key end
  end
  return phase_names[value]
end

-- Items in the rocket's cargo slot: {["raw-fish"] = 3}.
function M.cargo(silo)
  local inv = try(function() return silo.get_inventory(defines.inventory.rocket_silo_rocket) end)
  return inv and items.inventory_map(inv) or {}
end

-- Rocket progress of one silo: parts built, the phase, whether the rocket is
-- ready to launch, and what it carries.
function M.silo_info(silo)
  local required = try(function() return silo.prototype.rocket_parts_required end) or 100
  local code = try(function() return silo.rocket_silo_status end)
  local phase = M.phase_name(code)
  local has_rocket = try(function() return silo.rocket end) ~= nil
  local status
  local st = try(function() return silo.status end)
  if st ~= nil then
    for name, value in pairs(defines.entity_status) do
      if value == st then status = name break end
    end
  end
  return {
    parts = try(function() return silo.rocket_parts end) or 0,
    parts_required = required,
    phase = phase,
    has_rocket = has_rocket,
    ready = phase == "rocket_ready",
    launching = code ~= nil and code >= defines.rocket_silo_status.launch_starting,
    status = status,
    cargo = M.cargo(silo),
  }
end

-- One line for errors and the job's result: where the silo is in its cycle.
function M.describe(info)
  if info.launching then
    return "a rocket is already launching (" .. tostring(info.phase):gsub("_", " ") .. ")"
  end
  if info.ready then return "the rocket is ready" end
  if info.has_rocket then
    return "the rocket is being prepared (" .. tostring(info.phase):gsub("_", " ") .. ")"
  end
  return string.format("no rocket yet: %d/%d rocket parts", info.parts, info.parts_required)
end

-- Silos of the force on known ground, for get_state ("status").
function M.silos(surface, force, vision)
  local out = {}
  for _, e in ipairs(vision.filter_known(
      surface.find_entities_filtered({ type = "rocket-silo", force = force }), surface, force)) do
    local info = M.silo_info(e)
    info.x, info.y = e.position.x, e.position.y
    out[#out + 1] = info
  end
  table.sort(out, function(a, b)
    if a.y ~= b.y then return a.y < b.y end
    return a.x < b.x
  end)
  return out
end

-- Called by the launch job just before it asks the silo to launch, so the
-- event that follows can name the character and the cargo that went up.
function M.note_launch(silo, cargo)
  local s = store()
  s.pending[silo.unit_number or 0] = {
    character = companion.context(),
    tick = game.tick,
    cargo = cargo,
  }
end

-- The run's result so far: nil until a rocket has launched.
function M.result()
  return storage.run_result
end

local function payload_of(event, pending)
  local cargo
  local rocket = event.rocket
  if rocket and rocket.valid then
    cargo = try(function()
      local pod = rocket.cargo_pod
      local inv = pod and pod.get_inventory(defines.inventory.cargo_unit)
      return inv and items.inventory_map(inv) or nil
    end)
  end
  if (cargo == nil or next(cargo) == nil) and pending and pending.cargo then cargo = pending.cargo end
  return cargo or {}
end

function M.payload_text(payload)
  local names = {}
  for name in pairs(payload) do names[#names + 1] = name end
  table.sort(names)
  local bits = {}
  for _, name in ipairs(names) do bits[#bits + 1] = string.format("%d %s", payload[name], name) end
  return #bits > 0 and table.concat(bits, ", ") or "nothing"
end

function M.on_rocket_launched(event)
  local s = store()
  local silo = event.rocket_silo
  local pos, surface_name, unit
  if silo and silo.valid then
    pos, surface_name, unit = silo.position, silo.surface.name, silo.unit_number
  elseif event.rocket and event.rocket.valid then
    pos, surface_name = event.rocket.position, event.rocket.surface.name
  end
  local pending = unit and s.pending[unit]
  if pending and game.tick - pending.tick > PENDING_TICKS then pending = nil end
  if unit then s.pending[unit] = nil end

  local character = pending and pending.character or nil
  local player
  if not character and event.player_index then
    local p = game.get_player(event.player_index)
    player = p and p.name or nil
  end
  local payload = payload_of(event, pending)

  local rec = {
    tick = game.tick,
    seconds = math.floor(game.tick / 60),
    character = character,
    player = player,
    payload = payload,
    silo = pos and { x = pos.x, y = pos.y, surface = surface_name } or nil,
    launch_number = #s.launches + 1,
  }
  s.launches[#s.launches + 1] = rec
  if #s.launches == 1 then storage.run_result = rec end

  local who = character or player or "someone"
  local text = string.format("ROCKET LAUNCHED at tick %d (%s) by %s, payload: %s.",
    rec.tick, M.clock(rec.tick), who, M.payload_text(payload))
  pcall(function() game.print(text) end)
  pcall(function() chat.log_server_line(text) end)
  pcall(function() events.push("rocket_launched", text) end)

  pcall(function()
    local result = storage.run_result
    helpers.write_file(RESULT_FILE, helpers.table_to_json({
      finished = true,
      tick = result.tick,
      seconds = result.seconds,
      character = result.character,
      player = result.player,
      payload = result.payload,
      silo = result.silo,
      launches = s.launches,
      mod_version = script.active_mods["factorio-mcp"],
    }), false, 0)
  end)
end

-- h:mm:ss of a tick count, for human-readable lines.
function M.clock(tick)
  local sec = math.floor(tick / 60)
  return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60)
end

return M
