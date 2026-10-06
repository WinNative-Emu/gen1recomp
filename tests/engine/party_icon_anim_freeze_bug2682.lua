package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local PartyMenu = require("src.ui.PartyMenu")

local function newGame(moveId, ow)
  local function mk(species)
    return { species = species, hp = 50, stats = { hp = 50 },
             level = 30, moves = { { id = moveId, pp = 15 } } }
  end
  local party = { mk("MACHOP"), mk("MACHOP") }
  ow.map = ow.map or { def = { tileset = "OVERWORLD" }, id = "PALLET_TOWN" }
  ow.dark = ow.dark or false
  ow.partyKnows = function() return party[1] end
  local game = {
    data = { pokemon = { MACHOP = { name = "MACHOP" } } },
    save = { party = party, inventory = {}, options = {}, flags = {} },
    overworld = ow,
  }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  game.input = {
    queue = {},
    wasPressed = function(self, btn) return self.queue[btn] or false end,
    isDown = function() return false end,
  }
  return game
end

local function press(pm, btn)
  pm.game.input.queue = { [btn] = true }
  pm:update(1 / 60)
  pm.game.input.queue = {}
end

local function idle(pm, n)
  for _ = 1, n do pm:update(1 / 60) end
end

local function rowOf(pm, action)
  for i, item in ipairs(pm.subItems or {}) do
    if item.action == action then return i end
  end
end

do
  local game = newGame("STRENGTH", {})
  local pm = PartyMenu.new(game, {})
  game.stack:push(pm)
  idle(pm, 7)
  check(pm.blink > 0, "the cursor mon animates while the list takes input")
  press(pm, "a")
  check(pm.submenu, "A opens the submenu")
  local frozen = pm.blink
  idle(pm, 40)
  eq(pm.blink, frozen, "the icon counter holds while the submenu is open")
  press(pm, "b")
  eq(pm.blink, 0, "closing the submenu restarts the icon on its rest frame")
  idle(pm, 7)
  press(pm, "down")
  eq(pm.index, 2, "down moves the cursor")
  eq(pm.blink, 0, "a cursor move restarts the icon on its rest frame")
  idle(pm, 3)
  press(pm, "up")
  eq(pm.blink, 0, "up restarts the icon too")
end

do
  local game = newGame("STRENGTH", {})
  local pm = PartyMenu.new(game, {})
  game.stack:push(pm)
  idle(pm, 5)
  local before = pm.blink
  pm:animateTo(game.save.party[1], 10)
  pm:update(1 / 60)
  eq(pm.blink, before, "the icon counter holds during the HP bar fill")
end

local function fieldMove(label, moveId, action, ow, captured)
  local game = newGame(moveId, ow)
  local pm = PartyMenu.new(game, {})
  game.stack:push(pm)
  press(pm, "a")
  pm.subIndex = rowOf(pm, action) or 1
  press(pm, "a")
  check(captured.onClose ~= nil, label .. " reaches the overworld handler")
  check(not pm.submenu, label .. ": the options box is gone under the text")
  check(pm.chosenHollow, label .. ": the party cursor stays hollow under the text")
end

do
  local captured = {}
  fieldMove("STRENGTH", "STRENGTH", "strength", {
    useStrengthFieldMove = function(_, _, onClose) captured.onClose = onClose end,
  }, captured)
end

do
  local captured = {}
  fieldMove("SURF", "SURF", "surf", {
    player = { facingCell = function() return 4, 14 end },
    useSurfFieldMove = function() return "ok" end,
    trySurf = function(_, _, _, onClose) captured.onClose = onClose end,
  }, captured)
end

do
  local captured = {}
  fieldMove("FLASH", "FLASH", "flash", {
    dark = true,
    useFlashFieldMove = function(_, onClose) captured.onClose = onClose end,
  }, captured)
end

T.finish()
