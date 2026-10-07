-- engine/items/item_effects.asm:1223-1237
--   luajit tests/engine/status_cure_party_message_s2.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.core.Sound"] = {
  play = function() end,
  playCry = function() end,
  stopLoop = function() end,
}
package.loaded["src.render.TextBox"] = {
  new = function(_, text, done) return { textBox = true, text = text, done = done } end,
  strip = function(text)
    if type(text) ~= "string" then return text end
    return (text:gsub("{DONE}", ""):gsub("{PROMPT}", ""))
  end,
  soundOpts = function(_, _, opts) return opts or {} end,
}
package.loaded["src.ui.BagMenu"] = nil
package.loaded["src.ui.PartyMenu"] = nil
local BagMenu = require("src.ui.BagMenu")
local PartyMenu = require("src.ui.PartyMenu")
require("src.ui.Screens").invalidate()

local Fixtures = require("tests.modkit.fixtures")
local Bag = require("src.inventory.Bag")
local Pokemon = require("src.pokemon.Pokemon")
local ItemEffects = require("src.inventory.ItemEffects")

local Data = Fixtures.fresh()
local function addItem(id, index, name)
  Data.items[id] = { id = id, index = index, name = name, price = 100, tossable = true }
end
addItem("ANTIDOTE", 11, "ANTIDOTE")
addItem("PARLYZ_HEAL", 15, "PARLYZ HEAL")
addItem("AWAKENING", 14, "AWAKENING")
addItem("BURN_HEAL", 12, "BURN HEAL")
addItem("ICE_HEAL", 13, "ICE HEAL")
addItem("FULL_HEAL", 52, "FULL HEAL")
addItem("FULL_RESTORE", 16, "FULL RESTORE")

for _, id in ipairs({ "ANTIDOTE", "PARLYZ_HEAL", "AWAKENING", "BURN_HEAL",
                      "ICE_HEAL", "FULL_HEAL", "FULL_RESTORE" }) do
  eq(ItemEffects.keepsPartyMenuOpen(id), true, id .. " keeps the party menu up")
end

local function freshGame(id, status)
  local mon = Pokemon.new(Data, "FIXMON_C", 5)
  mon.status = status
  local game = {
    data = Data,
    save = {
      party = { mon },
      player = { name = "RED", id = 1 },
      inventory = {},
      options = {},
      flags = {},
      money = 0,
    },
  }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  game.input = { pressed = nil }
  function game.input:wasPressed(b) return self.pressed == b end
  Bag.add(game.save, id, 3)
  return game, mon
end

local function isPicker(s) return getmetatable(s) == PartyMenu end
local function isBox(s) return type(s) == "table" and s.textBox == true end
local function inStack(stack, pred)
  for _, s in ipairs(stack.states) do
    if pred(s) then return true end
  end
  return false
end

local function useFromBag(game, battle, id)
  local list = BagMenu.new(game, { battle = battle })
  game.stack:push(list)
  local row
  for i, r in ipairs(list.items) do
    if r.value == id then row = i break end
  end
  if not row then return nil, nil, "no " .. id .. " row" end
  list.index = row
  list.onChoose(list.items[row], list)
  local sub = game.stack:top()
  if not battle and sub and sub.items and sub.items[1]
     and sub.items[1].onSelect then
    game.stack:pop()
    sub.items[1].onSelect()
  end
  local picker = game.stack:top()
  if not isPicker(picker) then return nil, nil, "party picker never opened" end
  game.input.pressed = "a"
  picker:update(1 / 60)
  game.input.pressed = nil
  return list, picker
end

local cases = {
  { "ANTIDOTE", "PSN" }, { "PARLYZ_HEAL", "PAR" }, { "AWAKENING", "SLP" },
  { "BURN_HEAL", "BRN" }, { "ICE_HEAL", "FRZ" }, { "FULL_HEAL", "PSN" },
}

for _, c in ipairs(cases) do
  local id, status = c[1], c[2]
  local game, mon = freshGame(id, status)
  local list, picker, why = useFromBag(game, nil, id)
  if check(list ~= nil, id .. " reached the picker: " .. tostring(why)) then
    eq(mon.status, nil, id .. " cured " .. status)
    eq(picker.keepOpen, true, id .. " opened the picker with keepOpen")
    local box = game.stack:top()
    check(isBox(box), id .. " prints its cure line")
    check(inStack(game.stack, isPicker),
          id .. " prints over the still-drawn party menu")
    eq(picker.cursorsErased, true, id .. " erases the party cursor first")
    eq(game.save.inventory[id], 2, id .. " was consumed")
    if isBox(box) then
      game.stack:pop()
      box.done()
      check(not inStack(game.stack, isPicker),
            id .. " closes the picker once the line is dismissed")
      local flash = game.stack:top()
      check(type(flash) == "table" and flash.frames ~= nil and flash.t ~= nil,
            id .. " whites out on the way back to the bag")
      check(inStack(game.stack, function(s) return s == list end),
            id .. " returns to the ITEM list")
    end
  end
end

do
  local game, mon = freshGame("FULL_RESTORE", "PSN")
  mon.hp = mon.stats.hp
  local list, picker = useFromBag(game, nil, "FULL_RESTORE")
  if check(list ~= nil, "FULL RESTORE at full HP reached the picker") then
    eq(mon.status, nil, "FULL RESTORE at full HP cures PSN")
    check(isBox(game.stack:top()), "and prints its cure line")
    check(inStack(game.stack, isPicker), "over the still-drawn party menu")
    eq(picker.cursorsErased, true, "with the cursor erased")
  end
end

do
  local game, mon = freshGame("ANTIDOTE", nil)
  local list = useFromBag(game, nil, "ANTIDOTE")
  if check(list ~= nil, "a refused ANTIDOTE reached the picker") then
    eq(mon.status, nil, "nothing to cure")
    eq(game.save.inventory.ANTIDOTE, 3, "the refused ANTIDOTE is kept")
    local box = game.stack:top()
    check(isBox(box), "the no-effect line prints")
    check(inStack(game.stack, isPicker), "over the still-drawn party menu")
  end
end

do
  local spent
  local battle = { itemUsed = function(_, msgs, o) spent = { msgs = msgs, o = o } end }
  local game, mon = freshGame("ANTIDOTE", "PSN")
  local list, picker = useFromBag(game, battle, "ANTIDOTE")
  if check(list ~= nil, "the battle bag reached the picker") then
    eq(mon.status, nil, "ANTIDOTE in battle cures PSN")
    eq(picker.keepOpen, true, "the battle picker stays up for a cure")
    local box = game.stack:top()
    check(isBox(box), "the cure line prints in battle")
    check(inStack(game.stack, isPicker), "over the battle party menu")
    eq(spent, nil, "the turn is not spent until the line is dismissed")
    if isBox(box) then
      game.stack:pop()
      box.done()
      check(not inStack(game.stack, isPicker), "the picker closes after the line")
      check(not inStack(game.stack, function(s) return s == list end),
            "and the battle bag comes down with it")
      check(spent ~= nil, "then the item spends the turn")
    end
  end
end

T.finish()
