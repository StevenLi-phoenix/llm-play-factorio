-- Input log for deterministic replay. Every RPC that reaches rpc.dispatch is
-- appended, server side only, to script-output/rpc-log/<run-id>.jsonl BEFORE
-- it executes, one JSON object per line:
--   {"tick":N,"method":"enqueue","character":"coal","params":{...}}
-- `params` is the exact JSON string the MCP server sent (not re-serialized, so
-- numbers keep their digits). The first line of a file, and a new one after
-- each mod version change, is a header with the run id, map seed, mod and game
-- versions and the mod settings. get_chunk (reply transport) is not logged.
-- What a replay runner needs is in docs/PROTOCOL.md ("Replay log").
local M = {}

local SETTING = "factorio-mcp-rpc-log"

local function setting_on()
  local s = settings and settings.global and settings.global[SETTING]
  if s == nil or s.value == nil then return true end
  return s.value ~= false
end

local function state()
  storage.rpc_log = storage.rpc_log or {}
  return storage.rpc_log
end

-- One run = one save: the id comes from the map seed. script-output is wiped
-- by scripts/new_run.sh for a new run, so a seed is not reused in one folder.
function M.run_id()
  local s = state()
  if not s.run_id then
    local seed = "unknown"
    pcall(function() seed = tostring(game.surfaces.nauvis.map_gen_settings.seed) end)
    s.run_id = "run-" .. seed
    s.seed = seed
  end
  return s.run_id
end

local function file_name()
  return "rpc-log/" .. M.run_id() .. ".jsonl"
end

local function append(line)
  helpers.write_file(file_name(), line .. "\n", true, 0)
end

-- A JSON string literal for a short string.
local function quoted(str)
  return helpers.table_to_json({ str }):sub(2, -2)
end

local function mod_settings()
  local out = {}
  pcall(function()
    for name, s in pairs(settings.global) do
      if type(name) == "string" and name:sub(1, 12) == "factorio-mcp" then out[name] = s.value end
    end
  end)
  return out
end

local function write_header()
  local s = state()
  local version = script.active_mods["factorio-mcp"]
  if s.header_for == version then return end
  s.header_for = version
  append(helpers.table_to_json({
    header = true,
    run_id = M.run_id(),
    seed = s.seed,
    tick = game.tick,
    mod_version = version,
    factorio_version = script.active_mods["base"],
    log_format = 1,
    settings = mod_settings(),
  }))
end

-- Called from rpc.dispatch after the params decoded, before the handler runs.
-- Never raises: a failing log must not break the game's RPCs.
function M.record(method, params_json, params)
  if method == "get_chunk" or not setting_on() then return end
  pcall(function()
    write_header()
    local character = type(params) == "table" and (params.companion or params.name) or nil
    local raw = (params_json ~= nil and params_json ~= "") and params_json:gsub("[\r\n]+", " ") or "{}"
    append(string.format('{"tick":%d,"method":%s,"character":%s,"params":%s}', game.tick, quoted(tostring(method)),
      type(character) == "string" and quoted(character) or "null", raw))
  end)
end

return M
