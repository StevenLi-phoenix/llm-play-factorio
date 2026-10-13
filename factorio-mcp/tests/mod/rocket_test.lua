-- Offline tests for the rocket launch (0.2.24): scripts/rocket.lua (silo
-- progress, the on_rocket_launched result record) and actions/launch_rocket.lua
-- (the job). Silos, the character and the game API are stubs.
local here = (arg and arg[0] or "."):match("^(.*)/[^/]+$") or "."
package.path = here .. "/../../mod/factorio-mcp/?.lua;" .. package.path

local failures = 0
local function check(cond, what)
  if cond then print("ok   " .. what) else failures = failures + 1 print("FAIL " .. what) end
end

local ST = { building_rocket = 0, create_rocket = 1, doors_opening = 3, rocket_ready = 7, launch_starting = 8,
  doors_closing = 13, launch_started = 14 }
_G.defines = {
  rocket_silo_status = ST,
  entity_status = { working = 1, no_power = 2, waiting_to_launch_rocket = 3 },
  inventory = { rocket_silo_rocket = 9, cargo_unit = 1 },
}
_G.game = { tick = 1000, printed = {} }
function game.print(text) game.printed[#game.printed + 1] = text end
function game.get_player(i) return i == 5 and { name = "alice" } or nil end
_G.storage = {}
local written = {}
_G.helpers = {
  write_file = function(name, data, append, player) written[#written + 1] = { name = name, data = data, append = append, player = player } end,
  table_to_json = function(t) return "JSON:" .. tostring(t.tick) .. ":" .. tostring(t.character) end,
}
_G.script = { active_mods = { ["factorio-mcp"] = "test" } }
require("scripts.state").init()

local context = "coal"
package.loaded["scripts.companion"] = {
  context = function() return context end,
  get = function() return nil end,
  require_companion = function() return {} end,
}

local rocket = require("scripts.rocket")

-- a stub silo: parts, phase, cargo inventory
local function inventory(contents)
  return { get_contents = function()
    local out = {}
    for name, count in pairs(contents) do out[#out + 1] = { name = name, count = count } end
    return out
  end }
end
local function silo(opts)
  local s = {
    valid = true, unit_number = opts.unit or 1, position = { x = 60.5, y = -60.5 },
    surface = { name = "nauvis" },
    prototype = { rocket_parts_required = 100 },
    rocket_parts = opts.parts or 0,
    rocket_silo_status = opts.phase or ST.building_rocket,
    rocket = opts.has_rocket and { valid = true } or nil,
    status = opts.status or 1,
    launched = 0,
  }
  function s.get_inventory() return inventory(opts.cargo or {}) end
  function s.launch_rocket()
    s.launched = s.launched + 1
    if opts.refuse then return false end
    return true
  end
  return s
end

-- ---------------------------------------------------- silo progress

local building = rocket.silo_info(silo({ parts = 37 }))
check(building.parts == 37 and building.parts_required == 100 and not building.has_rocket and not building.ready
  and not building.launching, "silo_info: 37/100 parts, no rocket")
check(rocket.describe(building) == "no rocket yet: 37/100 rocket parts", "describe: " .. rocket.describe(building))

local rising = rocket.silo_info(silo({ has_rocket = true, phase = ST.doors_opening, status = 2 }))
check(rising.has_rocket and not rising.ready and rising.phase == "doors_opening" and rising.status == "no_power",
  "silo_info: a rocket in its opening phase, status name from defines")
check(rocket.describe(rising) == "the rocket is being prepared (doors opening)", "describe: preparing")

local ready = rocket.silo_info(silo({ has_rocket = true, phase = ST.rocket_ready, cargo = { ["raw-fish"] = 3 } }))
check(ready.ready and ready.cargo["raw-fish"] == 3 and rocket.describe(ready) == "the rocket is ready", "silo_info: ready with cargo")

local flying = rocket.silo_info(silo({ phase = ST.doors_closing }))
check(flying.launching and rocket.describe(flying):find("already launching", 1, true), "silo_info: past launch_starting is launching")

-- ------------------------------------------------- the launch result

local silo_a = silo({ unit = 11, has_rocket = true, phase = ST.rocket_ready })
rocket.note_launch(silo_a, { ["raw-fish"] = 3 })
local pod_inv = inventory({ ["raw-fish"] = 3 })
rocket.on_rocket_launched({
  rocket_silo = silo_a,
  rocket = { valid = true, cargo_pod = { get_inventory = function() return pod_inv end } },
})
local r = storage.run_result
check(r and r.tick == 1000 and r.character == "coal" and r.payload["raw-fish"] == 3 and r.launch_number == 1
  and r.silo.x == 60.5, "launch: the first launch is the run result (tick, character, payload, silo)")
check(#storage.rocket.launches == 1 and storage.rocket.pending[11] == nil, "launch: recorded, pending note consumed")
check(#written == 1 and written[1].name == "run-result.json" and written[1].player == 0 and written[1].append == false,
  "launch: run-result.json written for the server only (player 0), not appended")
check(#game.printed == 1 and game.printed[1]:find("ROCKET LAUNCHED", 1, true) and game.printed[1]:find("coal", 1, true)
  and game.printed[1]:find("3 raw-fish", 1, true), "launch: broadcast with the character and payload")
local chat_line = storage.chat.messages[#storage.chat.messages]
check(chat_line and chat_line.player == "server" and chat_line.text:find("ROCKET LAUNCHED", 1, true) and not chat_line.bot,
  "launch: a server chat line agents read")
local ev = storage.events.list[#storage.events.list]
check(ev and ev.kind == "rocket_launched" and ev.companion == nil, "launch: a force-wide rocket_launched event for the news footer")

-- cargo falls back to what the job saw when the pod can't be read; a human launch names the player
_G.game.tick = 5000
local silo_b = silo({ unit = 12 })
rocket.note_launch(silo_b, { satellite = 1 })
rocket.on_rocket_launched({ rocket_silo = silo_b, rocket = { valid = true } })
check(storage.rocket.launches[2].payload.satellite == 1 and storage.run_result.tick == 1000,
  "launch: cargo from the job's snapshot when the pod is unreadable; the run result stays the first launch")
rocket.on_rocket_launched({ rocket_silo = silo({ unit = 13 }), player_index = 5, rocket = { valid = true } })
check(storage.rocket.launches[3].player == "alice" and storage.rocket.launches[3].character == nil,
  "launch: a launch with no job names the player")
-- a stale pending note (older than 3 minutes) is ignored
rocket.note_launch(silo({ unit = 14 }), { x = 1 })
_G.game.tick = 5000 + 60 * 200
rocket.on_rocket_launched({ rocket_silo = silo({ unit = 14 }), rocket = { valid = true } })
check(storage.rocket.launches[4].character == nil, "launch: a stale job note is not blamed")

-- ------------------------------------------------------- the job

_G.game.tick = 9000
package.loaded["scripts.actions.approach"] = { ensure = function() return "ok" end }
local current_silo
local c = {
  reach_distance = 10, position = { x = 55, y = -55 },
  surface = { find_entities_filtered = function() return current_silo and { current_silo } or {} end },
}
package.loaded["scripts.companion"].get = function() return c end
local job = require("scripts.actions.launch_rocket")

local function task() return { target = { x = 60.5, y = -60.5 }, id = 1 } end
local function run(t, ticks)
  job.start(t)
  local res
  for _ = 1, ticks or 1 do
    res = job.tick(t)
    if res then return res end
    _G.game.tick = _G.game.tick + 1
  end
  return nil
end

check(not pcall(job.start, { target = { x = "a" } }), "job: needs a target")

current_silo = nil
local res = run(task())
check(res and res.status == "failed" and res.detail:find("no rocket silo at", 1, true), "job: no silo at the point")

current_silo = silo({ parts = 37 })
res = run(task())
check(res and res.status == "failed" and res.detail:find("no rocket yet: 37/100 rocket parts", 1, true)
  and current_silo.launched == 0, "job: no rocket yet fails at once with the parts count, nothing launched")

current_silo = silo({ has_rocket = true, phase = ST.doors_opening })
local t = task()
check(run(t, 5) == nil and current_silo.launched == 0, "job: a rising rocket is waited for")
current_silo.rocket_silo_status = ST.rocket_ready
res = job.tick(t)
check(res == nil and current_silo.launched == 1, "job: it launches once the rocket is ready")
check(storage.rocket.pending[current_silo.unit_number or 1] ~= nil, "job: notes the character and cargo for the launch event")

-- the launch event ends the job
rocket.on_rocket_launched({ rocket_silo = current_silo, rocket = { valid = true } })
res = job.tick(t)
check(res and res.status == "done" and res.detail:find("rocket launched at tick", 1, true)
  and res.detail:find("by coal", 1, true), "job: done once the launch event is recorded: " .. tostring(res and res.detail))

-- never ready (no power): fails after the timeout, naming the phase and status
current_silo = silo({ has_rocket = true, phase = ST.doors_opening, status = 2 })
t = task()
job.start(t)
job.tick(t)
_G.game.tick = _G.game.tick + 60 * 121
res = job.tick(t)
check(res and res.status == "failed" and res.detail:find("never became ready", 1, true) and res.detail:find("no_power", 1, true),
  "job: a rocket that never gets ready fails with the phase and status")

-- the silo refuses
current_silo = silo({ has_rocket = true, phase = ST.rocket_ready, refuse = true })
res = run(task())
check(res and res.status == "failed" and res.detail:find("refused to launch", 1, true), "job: a refusal is reported")

-- already launching
current_silo = silo({ phase = ST.launch_started })
res = run(task())
check(res and res.status == "failed" and res.detail:find("already launching", 1, true), "job: a silo already launching")

-- no launch event ever arrives
current_silo = silo({ has_rocket = true, phase = ST.rocket_ready })
t = task()
job.start(t)
job.tick(t)
_G.game.tick = _G.game.tick + 60 * 91
res = job.tick(t)
check(res and res.status == "done" and res.detail:find("no launch event", 1, true), "job: ends with a note when the event never comes")

print(failures == 0 and "\nALL TESTS PASSED" or ("\n" .. failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
