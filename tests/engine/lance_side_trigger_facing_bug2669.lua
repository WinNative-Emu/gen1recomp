-- scripts/LancesRoom.asm:54
-- home/overworld.asm:1212

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local story4 = require("data.scripts.story4")
local hooks = story4.LANCES_ROOM

local function facingToward(npc, player)
  local dx, dy = player.cellX - npc.cellX, player.cellY - npc.cellY
  if math.abs(dx) > math.abs(dy) then
    return dx < 0 and "left" or "right"
  end
  return dy < 0 and "up" or "down"
end

local function trigger(x, y, playerFacing)
  local lance = {
    def = { name = "LANCESROOM_LANCE", index = 1,
            trainerClass = "OPP_LANCE", trainerParty = 1, text = 1 },
    id = "LANCES_ROOM:1",
    cellX = 6, cellY = 1,
    facing = "down",
  }
  function lance:facePlayer(player) self.facing = facingToward(self, player) end
  local engaged = false
  local facingAtEngage
  local game = { data = {}, save = { flags = {}, defeatedTrainers = {} } }
  local ow = {
    npcs = { lance },
    player = { cellX = x, cellY = y, facing = playerFacing },
  }
  function ow:trainerDefeated(npc) return game.save.defeatedTrainers[npc.id] == true end
  function ow:engageTrainer(npc)
    engaged = npc == lance
    facingAtEngage = npc.facing
  end
  local handled = hooks.onStep(game, ow, x, y)
  return handled, engaged, facingAtEngage, lance
end

do
  local handled, engaged, atEngage, lance = trigger(5, 1, "right")
  check(handled == true, "(5,1) trigger handled")
  check(engaged, "(5,1) trigger engages Lance")
  eq(atEngage, "down", "(5,1) Lance still faces down when his text starts")
  eq(lance.facing, "down", "(5,1) Lance keeps his object_event DOWN facing")
end

do
  local handled, engaged, atEngage, lance = trigger(6, 2, "up")
  check(handled == true, "(6,2) trigger handled")
  check(engaged, "(6,2) trigger engages Lance")
  eq(atEngage, "down", "(6,2) Lance faces down when his text starts")
  eq(lance.facing, "down", "(6,2) Lance keeps facing down")
end

T.finish("lance_side_trigger_facing_bug2669")
