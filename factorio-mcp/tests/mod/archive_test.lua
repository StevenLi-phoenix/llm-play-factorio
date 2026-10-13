-- Offline tests for scripts/archive.lua (0.2.24): the save archive.
local here = (arg and arg[0] or "."):match("^(.*)/[^/]+$") or "."
package.path = here .. "/../../mod/factorio-mcp/?.lua;" .. package.path

local failures = 0
local function check(cond, what)
  if cond then print("ok   " .. what) else failures = failures + 1 print("FAIL " .. what) end
end

local saved, logged = {}, {}
_G.game = { tick = 0, server_save = function(name) saved[#saved + 1] = name end }
_G.log = function(s) logged[#logged + 1] = s end
_G.storage = {}
_G.settings = { global = {} }
require("scripts.state").init()

local archive = require("scripts.archive")

check(archive.minutes() == 10, "default interval is 10 minutes")
check(archive.save_name(36000) == "archive-000036000", "name is archive-<tick padded to 9 digits>")

game.tick = 600
archive.check()
check(#saved == 0, "nothing before the first interval")
game.tick = 36000
archive.check()
check(saved[1] == "archive-000036000" and #saved == 1, "first archive at 10 minutes")
game.tick = 36600
archive.check()
check(#saved == 2 and saved[2] == "archive-000036000",
  "requested again one check later under the same name (an autosave in the same tick drops a save)")
game.tick = 37200
archive.check()
check(#saved == 2, "and not a third time")
game.tick = 72000
archive.check()
check(saved[3] == "archive-000072000" and storage.archive.count == 2, "next archive 10 minutes after the first, counted once each")
game.tick = 72600
archive.check()
check(#saved == 4, "with its retry")

settings.global["factorio-mcp-archive-minutes"] = { value = 1 }
game.tick = 72000 + 3600
archive.check()
check(saved[5] == "archive-000075600", "a shorter setting applies at once")
game.tick = 72000 + 3600 + 600
archive.check()

settings.global["factorio-mcp-archive-minutes"] = { value = 0 }
game.tick = 1000000
archive.check()
check(#saved == 6, "0 turns it off")

settings.global["factorio-mcp-archive-minutes"] = { value = 5 }
game.server_save = function() error("disk full") end
game.tick = 2000000
check(pcall(archive.check), "a failing save does not raise")
check(#logged == 1 and logged[1]:find("archive-002000000", 1, true) and storage.archive.count == 3 and storage.archive.retry == nil,
  "and is logged, not counted, and not retried")

print(failures == 0 and "\nALL TESTS PASSED" or ("\n" .. failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
