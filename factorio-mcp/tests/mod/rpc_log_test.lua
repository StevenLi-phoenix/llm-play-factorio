-- Offline tests for scripts/rpc_log.lua (0.2.24): the input log for replay,
-- and its place in rpc.dispatch (written BEFORE the handler runs).
local here = (arg and arg[0] or "."):match("^(.*)/[^/]+$") or "."
package.path = here .. "/../../mod/factorio-mcp/?.lua;" .. package.path

local failures = 0
local function check(cond, what)
  if cond then print("ok   " .. what) else failures = failures + 1 print("FAIL " .. what) end
end

local files = {}
local order = {} -- "log" / "handler" in the order they happened
local write_ok = true
_G.helpers = {
  write_file = function(name, data, append, player)
    if not write_ok then error("disk full") end
    files[name] = (files[name] or "") .. data
    order[#order + 1] = "log"
    if append ~= true or player ~= 0 then failures = failures + 1 print("FAIL write_file must append for player 0") end
  end,
  table_to_json = function(t)
    if t.header then
      return string.format('{"header":true,"run_id":"%s","seed":"%s","tick":%d,"mod_version":"%s"}', t.run_id, t.seed, t.tick,
        t.mod_version)
    end
    if t[1] then return '["' .. t[1] .. '"]' end
    return "{}"
  end,
  json_to_table = function(s) return { companion = s:match('"companion":"([^"]+)"'), name = s:match('"name":"([^"]+)"') } end,
}
_G.game = { tick = 100, surfaces = { nauvis = { map_gen_settings = { seed = 424242 } } } }
_G.storage = {}
_G.settings = { global = { ["factorio-mcp-chart-radius"] = { value = 2 } } }
_G.script = { active_mods = { ["factorio-mcp"] = "0.2.24", base = "2.0.77" } }
local printed = {}
_G.rcon = { print = function(s) printed[#printed + 1] = s end }
require("scripts.state").init()

local log = require("scripts.rpc_log")
local FILE = "rpc-log/run-424242.jsonl"

check(log.run_id() == "run-424242", "run id comes from the map seed")

log.record("enqueue", '{"task":{"type":"walk_to","x":-0.91},"companion":"coal","session":"abcdefgh"}',
  { companion = "coal" })
local lines = {}
for line in files[FILE]:gmatch("[^\n]+") do lines[#lines + 1] = line end
check(#lines == 2 and lines[1]:find('"header":true', 1, true) and lines[1]:find('"seed":"424242"', 1, true)
  and lines[1]:find('"mod_version":"0.2.24"', 1, true), "the file starts with a header: run id, seed, mod version")
check(lines[2] == '{"tick":100,"method":["enqueue"],"character":["coal"],"params":{"task":{"type":"walk_to","x":-0.91},'
  .. '"companion":"coal","session":"abcdefgh"}}'
  or lines[2] == '{"tick":100,"method":"enqueue","character":"coal","params":{"task":{"type":"walk_to","x":-0.91},'
  .. '"companion":"coal","session":"abcdefgh"}}', "a call is one line: tick, method, character, the exact params text; " .. tostring(lines[2]))

-- the header is written once per mod version
_G.game.tick = 101
log.record("ping", "", {})
check(select(2, files[FILE]:gsub('"header":true', "")) == 1, "no second header for the same mod version")
check(files[FILE]:find('"tick":101', 1, true) and files[FILE]:find('"character":null,"params":{}}', 1, true),
  "empty params log as {} and no character as null")
_G.script.active_mods["factorio-mcp"] = "0.2.25"
log.record("ping", "{}", {})
check(select(2, files[FILE]:gsub('"header":true', "")) == 2, "a mod version change writes a new header")
_G.script.active_mods["factorio-mcp"] = "0.2.24"

-- bind carries the name in params.name; multi-line params stay on one line
log.record("bind", '{\n"name":"scout-1",\n"session":"x"}', { name = "scout-1" })
local last = files[FILE]:match("[^\n]+\n$")
check(last:find("scout-1", 1, true) and last:find('"params":{ "name"', 1, true), "bind logs its character from params.name")
check(select(2, last:gsub("\n", "")) == 1, "newlines inside params never split a record")

-- not logged: get_chunk (transport), and nothing at all when the setting is off
local before = #files[FILE]
log.record("get_chunk", '{"id":1,"part":2}', {})
check(#files[FILE] == before, "get_chunk is not logged")
settings.global["factorio-mcp-rpc-log"] = { value = false }
log.record("enqueue", "{}", {})
check(#files[FILE] == before, "the setting turns the log off")
settings.global["factorio-mcp-rpc-log"] = { value = true }

-- a failing log never breaks the RPC
write_ok = false
check(pcall(log.record, "ping", "{}", {}), "a write error is swallowed")
write_ok = true

-- in rpc.dispatch: logged before the handler runs, on success and on error
package.loaded["scripts.companion"] = { touch = function() end, set_context = function() end, context = function() return "agent" end }
package.loaded["scripts.alerts"] = { line = function() return nil end }
_G.storage.rpc_outbox = { next_id = 1, by_id = {} }
local rpc = require("scripts.rpc")
rpc.register("probe", function(params) order[#order + 1] = "handler" return { ok = true } end)
rpc.register("explode", function() order[#order + 1] = "handler" error("boom") end)
order = {}
rpc.dispatch("probe", '{"companion":"coal","session":"s"}')
check(order[1] == "log" and order[#order] == "handler", "dispatch: the call is logged before its handler runs")
order = {}
rpc.dispatch("explode", '{"companion":"coal","session":"s"}')
check(order[1] == "log" and order[2] == "handler", "dispatch: a call that errors is in the log too")
before = #files[FILE]
rpc.dispatch("no_such_method", "{}")
check(#files[FILE] == before, "dispatch: an unknown method has no effect and no log line")
rpc.dispatch("get_chunk", '{"id":1,"part":1}')
check(#files[FILE] == before, "dispatch: get_chunk replies are not logged")

print(failures == 0 and "\nALL TESTS PASSED" or ("\n" .. failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
