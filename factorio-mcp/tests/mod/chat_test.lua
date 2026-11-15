-- Offline tests for scripts/chat.lua: directed messages (0.3.13).
local here = (arg and arg[0] or "."):match("^(.*)/[^/]+$") or "."
package.path = here .. "/../../mod/factorio-mcp/?.lua;" .. package.path

local failures = 0
local function check(cond, what)
  if cond then print("ok   " .. what) else failures = failures + 1 print("FAIL " .. what) end
end

local me = "w1"
package.loaded["scripts.companion"] = { context = function() return me end }
local printed = {}
_G.game = {
  tick = 100,
  print = function(s) printed[#printed + 1] = s end,
  get_player = function(i) return i == 1 and { name = "stevenli" } or nil end,
}
_G.storage = { chat = { messages = {}, next_id = 1 }, cursors = {} }

local chat = require("scripts.chat")

local function texts_for(who)
  me = who
  local out = {}
  for _, m in ipairs(chat.get({ since_id = 0 }).messages) do out[#out + 1] = m.text end
  return table.concat(out, "|")
end

-- parse_target: "@w3 text" addresses w3; anything else is for everyone
local to, body = chat.parse_target("@w3 build a furnace")
check(to == "w3" and body == "build a furnace", "parse_target: @w3 prefix")
to, body = chat.parse_target("hello everyone")
check(to == nil and body == "hello everyone", "parse_target: no prefix is a broadcast")
to = chat.parse_target("@ALL stop")
check(to == "all", "parse_target: names are lower-cased")
to = chat.parse_target("email me @w3 later")
check(to == nil, "parse_target: only a leading @name addresses someone")

-- a human line addressed to w2 reaches w2 only (and stays visible in the game chat itself)
chat.on_console_chat({ player_index = 1, tick = 1, message = "@w2 fuel the boilers" })
chat.on_console_chat({ player_index = 1, tick = 2, message = "good job team" })
check(texts_for("w2"):find("fuel the boilers", 1, true) ~= nil, "w2 sees the line addressed to w2")
check(texts_for("w1"):find("fuel the boilers", 1, true) == nil, "w1 does not see a line addressed to w2")
check(texts_for("w1"):find("good job team", 1, true) ~= nil, "a broadcast reaches everyone")

-- say with `to`: agent to agent, printed with an arrow, logged with `to`
me = "w3"
chat.say({ text = "gears are ready", to = "w4" })
check(printed[#printed]:find("w3", 1, true) and printed[#printed]:find("w4", 1, true) and printed[#printed]:find("gears are ready", 1, true),
  "say: the game chat line names sender and receiver")
check(texts_for("w4"):find("gears are ready", 1, true) ~= nil, "say to w4: w4 reads it")
check(texts_for("w5"):find("gears are ready", 1, true) == nil, "say to w4: w5 does not")
check(texts_for("w3"):find("gears are ready", 1, true) == nil, "an agent does not read its own line")

-- say without `to` stays a broadcast (old behaviour)
me = "w3"
chat.say({ text = "status: ok" })
check(texts_for("w5"):find("status: ok", 1, true) ~= nil, "say without to is heard by all")

-- post_chat: the supervisor speaks without a character
local r = chat.post({ from = "supervisor", to = "w2", text = "game restarts in 5 minutes" })
check(type(r) == "table" and printed[#printed]:find("supervisor", 1, true) ~= nil, "post: printed in the game chat")
check(texts_for("w2"):find("restarts in 5 minutes", 1, true) ~= nil, "post to w2: w2 reads it")
check(texts_for("w1"):find("restarts in 5 minutes", 1, true) == nil, "post to w2: w1 does not")
check(not pcall(chat.post, { text = "" }), "post: empty text is refused")
check(not pcall(chat.say, { text = "x", to = string.rep("a", 40) }), "say: an absurd recipient is refused")

os.exit(failures == 0 and 0 or 1)
