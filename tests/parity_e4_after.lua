-- Parity: Lorelei / Bruno / Agatha push AfterBattle text immediately on
-- win (pokered *EndBattleScript -> DisplayTextID -> TalkToTrainer), not
-- only on a later re-talk.  Lance is covered by parity_lance.lua.
--
-- Sources: scripts/LoreleisRoom.asm, BrunosRoom.asm, AgathasRoom.asm
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.LORELEIS_ROOM) then Data:load() end
local Font = require("src.render.Font")
if not pcall(Font.encode, "A") then Font.load(Data) end
local S = require("tests.harness").suite("parity e4 after")
local check, eq = S.check, S.eq

local mapScripts = require("data.scripts.init")

local CASES = {
  {
    map = "LORELEIS_ROOM", text = "TEXT_LORELEISROOM_LORELEI",
    after = "_LoreleisRoomLoreleiAfterBattleText",
    headerMap = "LoreleisRoom", event = "EVENT_BEAT_LORELEIS_ROOM_TRAINER_0",
    npcName = "LORELEISROOM_LORELEI", class = "OPP_LORELEI",
    closed = 0x24, open = 0x05,
  },
  {
    map = "BRUNOS_ROOM", text = "TEXT_BRUNOSROOM_BRUNO",
    after = "_BrunoAfterBattleText",
    headerMap = "BrunosRoom", event = "EVENT_BEAT_BRUNOS_ROOM_TRAINER_0",
    npcName = "BRUNOSROOM_BRUNO", class = "OPP_BRUNO",
    closed = 0x24, open = 0x05,
  },
  {
    map = "AGATHAS_ROOM", text = "TEXT_AGATHASROOM_AGATHA",
    after = "_AgathaAfterBattleText",
    headerMap = "AgathasRoom", event = "EVENT_BEAT_AGATHAS_ROOM_TRAINER_0",
    npcName = "AGATHASROOM_AGATHA", class = "OPP_AGATHA",
    closed = 0x3b, open = 0x0e,
  },
}

for _, c in ipairs(CASES) do
  local after = Data.text[c.after]
  check(after ~= nil, c.after .. " extracted")
  local header = Data:trainerHeader(c.headerMap, 1)
  check(header and header.after == c.after,
        c.headerMap .. " header wires after-battle label")

  local talk = mapScripts.talkScript(c.map, c.text)
  check(type(talk) == "function", c.map .. " talk wraps engageTrainer")

  local pushed = {}
  local game = {
    data = Data,
    save = {
      flags = {},
      defeatedTrainers = {},
      player = { name = "RED", rival = "BLUE" },
    },
    stack = {
      push = function(_, state) pushed[#pushed + 1] = state end,
    },
  }
  local npc = {
    def = { name = c.npcName, index = 1, trainerClass = c.class,
            trainerParty = 1, text = c.text },
    id = c.map .. ":1",
    facePlayer = function() end,
  }
  local engaged = false
  local blocks = {}
  local blocksAtPush
  game.stack.push = function(_, state)
    pushed[#pushed + 1] = state
    blocksAtPush = blocksAtPush or #blocks
  end
  local ow = {
    player = { cellY = 5 },
    trainerDefeated = function(_, n)
      return game.save.defeatedTrainers[n.id] == true
    end,
    replaceBlock = function(_, bx, by, id)
      blocks[#blocks + 1] = { bx, by, id }
    end,
    engageTrainer = function(self, n, onDone)
      engaged = n == npc
      game.save.defeatedTrainers[n.id] = true
      game.save.flags[c.event] = true
      local hooks = mapScripts.get(c.map)
      if hooks and hooks.onVictory then hooks.onVictory(game, self) end
      if onDone then onDone() end
    end,
  }

  local finished = false
  talk(game, ow, npc, function() finished = true end)
  check(engaged, c.map .. " engages on first talk")
  check(#pushed == 1 and pushed[1].pages ~= nil,
        c.map .. " win pushes after-battle TextBox")
  check(#pushed[1].pages > 0, c.map .. " after-battle TextBox has pages")
  eq(blocksAtPush, 0, c.map .. " exit stays shut while after-battle text is up")
  check(not finished, c.map .. " talk not done before after-battle text closes")
  pushed[1].onDone()
  eq(#blocks, 1, c.map .. " exit block swapped once after the text")
  local b = blocks[1] or {}
  check(b[1] == 2 and b[2] == 0 and b[3] == c.open,
        c.map .. " exit opens at block (2,0) after the text")
  check(finished, c.map .. " talk done after after-battle text closes")
  game.stack.push = function(_, state) pushed[#pushed + 1] = state end

  -- loss: no after text
  pushed, engaged = {}, false
  game.save.defeatedTrainers = {}
  game.save.flags = {}
  ow.engageTrainer = function(_, n, onDone)
    engaged = true
    if onDone then onDone() end
  end
  talk(game, ow, npc, function() end)
  check(engaged, c.map .. " still engages on loss path")
  eq(#pushed, 0, c.map .. " loss does not push after-battle text")

  -- re-talk after win still shows after text (TalkToTrainer after branch)
  pushed = {}
  game.save.defeatedTrainers[npc.id] = true
  game.save.flags[c.event] = true
  ow.engageTrainer = function()
    error(c.map .. " re-talk must not re-engage")
  end
  talk(game, ow, npc, function() end)
  check(#pushed == 1 and pushed[1].pages ~= nil,
        c.map .. " defeated re-talk shows after text")

  local hooks = mapScripts.get(c.map)
  check(hooks.onVictory == nil, c.map .. " has no onVictory door swap")
  blocks = {}
  game.save.flags = { [c.event] = true }
  hooks.onEnter(game, ow)
  check(blocks[1] and blocks[1][3] == c.open, c.map .. " reload after win opens exit")
  blocks = {}
  game.save.flags = {}
  hooks.onEnter(game, ow)
  check(blocks[1] and blocks[1][3] == c.closed, c.map .. " reload before win keeps exit shut")
end

S.finish()
