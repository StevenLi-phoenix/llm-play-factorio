-- Humans spectate. Agents are the only ones allowed to change the map; a human
-- who joins the server to watch is put in the spectator controller, which
-- cannot build, mine, craft or fight. Their character (freeplay hands every new
-- player a body with the start kit) would otherwise stand in the world as a
-- free item source, so it is DESTROYED, items included: spectators need none.
-- Characters of agents (scripts/companion.lua) are never touched.
--
-- Applied when a player joins, when the setting is turned on, when the mod
-- starts, and by a 5-second sweep that catches a player who got a character
-- back (respawn, an admin command). Remote view (/follow, the map) is left
-- alone: it is a viewing controller.
local companion = require("scripts.companion")

local M = {}

local SETTING = "factorio-mcp-humans-spectate"

function M.enabled()
  local s = settings and settings.global and settings.global[SETTING]
  if s == nil or s.value == nil then return true end
  return s.value ~= false
end

function M.apply(player)
  if not M.enabled() then return false end
  if not (player and player.valid) then return false end
  local ctype = player.controller_type
  if ctype == defines.controllers.spectator or ctype == defines.controllers.remote then return false end
  local body = player.character
  player.set_controller({ type = defines.controllers.spectator })
  if body and body.valid and not companion.name_of(body) then
    pcall(function() body.destroy() end)
  end
  return true
end

-- Every player, connected or not: an offline player's body is as good a free
-- item source as an online one's.
function M.sweep()
  if not M.enabled() then return end
  for _, player in pairs(game.players) do
    pcall(M.apply, player)
  end
end

function M.on_player_joined_game(event)
  local player = game.get_player(event.player_index)
  if player then pcall(M.apply, player) end
end

return M
