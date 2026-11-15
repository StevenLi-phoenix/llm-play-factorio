local companion = require("scripts.companion")

local M = {}

local MAX_MESSAGES = 200
local MAX_NAME = 32

-- "@w3 text" addresses w3 ("@all" everyone); a line without a leading @name is a broadcast.
-- Returns to (lower-case) or nil, and the text without the prefix.
function M.parse_target(text)
  local name, rest = tostring(text):match("^@([%w_%-]+)%s+(.+)$")
  if not name then return nil, text end
  return name:lower(), rest
end

local function check_to(to)
  if to == nil then return nil end
  if type(to) ~= "string" or to == "" or #to > MAX_NAME then error("to must be a short name (w1, all, ...)") end
  return to:lower()
end

local function append(msg)
  local chat = storage.chat
  msg.id = chat.next_id
  msg.tick = game.tick
  chat.messages[#chat.messages + 1] = msg
  chat.next_id = chat.next_id + 1
  if #chat.messages > MAX_MESSAGES then table.remove(chat.messages, 1) end
end

-- Whether `who` (a character name) is meant to read the message: broadcasts and lines addressed to them.
local function visible_to(m, who)
  return m.to == nil or m.to == "all" or m.to == who:lower()
end

function M.on_console_chat(event)
  if not event.player_index then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local to = M.parse_target(event.message)
  append({ player = player.name, text = event.message, to = to })
end

-- Everything since the cursor except this character's own lines (unless
-- include_self, e.g. for a full transcript). Without since_id the
-- character's stored cursor is used; every read advances it.
function M.get(params)
  local include_self = params.include_self == true
  local me = companion.context()
  storage.cursors = storage.cursors or {}
  local cur = storage.cursors[me]
  local since = tonumber(params.since_id) or (cur and cur.chat) or 0
  local out = {}
  for _, m in ipairs(storage.chat.messages) do
    if m.id > since and visible_to(m, me) and (include_self or not (m.bot and m.player == me)) then
      out[#out + 1] = m
    end
  end
  local last = storage.chat.next_id - 1
  if cur then cur.chat = math.max(cur.chat or 0, last) end
  return { messages = out, last_id = last }
end

-- Chat as the bound character: "[name] text", like a player speaking.
function M.say(params)
  if type(params.text) ~= "string" or params.text == "" then
    error("say requires text")
  end
  local name = companion.context()
  local to = check_to(params.to)
  if #params.text > 400 then params.text = params.text:sub(1, 397) .. "..." end
  game.print("[color=#4EC9B0][" .. name .. (to and (" -> " .. to) or "") .. "][/color] " .. params.text)
  M.log_bot_line(name, params.text, to)
  return {}
end

-- A line from the supervisor (the run's harness, no character): chat as `from` (default "supervisor"),
-- optionally addressed with `to`. Tooling RPC, not an MCP tool.
function M.post(params)
  if type(params.text) ~= "string" or params.text == "" then
    error("post_chat requires text")
  end
  local from = type(params.from) == "string" and params.from ~= "" and params.from:sub(1, MAX_NAME) or "supervisor"
  local to = check_to(params.to)
  local text = #params.text > 400 and (params.text:sub(1, 397) .. "...") or params.text
  game.print("[color=#CE9178][" .. from .. (to and (" -> " .. to) or "") .. "][/color] " .. text)
  append({ player = from, text = text, to = to })
  return {}
end

-- A line from the server itself (game events such as a rocket launch), in the
-- same log, so agents read it with the chat.
function M.log_server_line(text)
  append({ player = "server", text = text })
end

-- Agents hear each other: their lines go into the same chat log, tagged bot.
function M.log_bot_line(name, text, to)
  append({ player = name, text = text, bot = true, to = to })
end

return M
