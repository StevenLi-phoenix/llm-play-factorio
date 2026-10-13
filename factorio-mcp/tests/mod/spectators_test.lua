-- Offline tests for scripts/spectators.lua (0.2.24): humans only spectate.
local here = (arg and arg[0] or "."):match("^(.*)/[^/]+$") or "."
package.path = here .. "/../../mod/factorio-mcp/?.lua;" .. package.path

local failures = 0
local function check(cond, what)
  if cond then print("ok   " .. what) else failures = failures + 1 print("FAIL " .. what) end
end

_G.defines = { controllers = { character = 1, spectator = 5, remote = 7 } }
_G.settings = { global = {} }
local agent_bodies = {}
package.loaded["scripts.companion"] = { name_of = function(e) return agent_bodies[e] end }

local players = {}
_G.game = { players = players, get_player = function(i) return players[i] end }

local function player(index, ctype, with_body)
  local p = { valid = true, index = index, controller_type = ctype }
  if with_body then
    p.character = { valid = true, destroyed = false }
    p.character.destroy = function() p.character.destroyed = true p.character.valid = false end
  end
  p.set_controller = function(spec) p.controller_type = spec.type p.last_spec = spec end
  players[index] = p
  return p
end

local spectators = require("scripts.spectators")

-- a new player joins with their freeplay body: spectator, body destroyed
local p1 = player(1, defines.controllers.character, true)
local body_ref = p1.character
spectators.on_player_joined_game({ player_index = 1 })
check(p1.controller_type == defines.controllers.spectator and body_ref.destroyed, "join: spectator controller and the body is destroyed")

-- already a spectator or in remote view: untouched
local p2 = player(2, defines.controllers.spectator, false)
local p3 = player(3, defines.controllers.remote, true)
check(spectators.apply(p2) == false and spectators.apply(p3) == false and not p3.character.destroyed
  and p3.controller_type == defines.controllers.remote, "spectators and remote viewers are left alone")

-- an agent's body is never destroyed, even if it is attached to a player
local p4 = player(4, defines.controllers.character, true)
agent_bodies[p4.character] = "scout-1"
local agent_body = p4.character
spectators.apply(p4)
check(p4.controller_type == defines.controllers.spectator and not agent_body.destroyed, "an agent's character is not destroyed")

-- a player without a body
local p5 = player(5, defines.controllers.character, false)
check(spectators.apply(p5) == true and p5.controller_type == defines.controllers.spectator, "a player with no body just becomes a spectator")

-- the sweep reaches everyone, including offline players, and survives errors
local p6 = player(6, defines.controllers.character, true)
local p7 = player(7, defines.controllers.character, true)
p6.set_controller = function() error("offline player") end
spectators.sweep()
check(p7.controller_type == defines.controllers.spectator, "sweep: one failing player does not stop the rest")

-- the setting off: nothing happens
settings.global["factorio-mcp-humans-spectate"] = { value = false }
local p8 = player(8, defines.controllers.character, true)
spectators.on_player_joined_game({ player_index = 8 })
spectators.sweep()
check(p8.controller_type == defines.controllers.character and not p8.character.destroyed, "with the setting off players keep their characters")
-- ...and turning it on applies to players already connected
settings.global["factorio-mcp-humans-spectate"] = { value = true }
spectators.sweep()
check(p8.controller_type == defines.controllers.spectator, "turning it on spectates everyone already there")

check(spectators.on_player_joined_game({ player_index = 99 }) == nil, "an unknown player index is ignored")

print(failures == 0 and "\nALL TESTS PASSED" or ("\n" .. failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
