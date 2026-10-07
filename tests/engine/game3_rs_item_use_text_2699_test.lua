package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

local function ir(s)
  return { { t = "text", s = s .. ":" }, { t = "strvar", n = 1 }, { t = "text", s = ":" },
    { t = "strvar", n = 2 }, { t = "eos" } }
end

local RS_TEXT = {}
for _, name in ipairs(require("src.import.gba.versions_text_rs").NAMED_TEXTS) do RS_TEXT[name] = ir(name) end
local BUNDLE = { text = RS_TEXT }
package.loaded["src.core.game3.scripting.space"] = { ensureBundle = function() return BUNDLE end }

local TextIR = require("src.core.game3.scripting.text_ir")
TextIR.toTextBox = function(x, ctx) return TextIR.toPlain(x, ctx or {}) end
local GameVersion = require("src.core.GameVersion")
local RomText = require("src.core.game3.rom_text")
local Pokemon = require("src.core.game3.pokemon")
local ItemUse = require("src.core.game3.item_use")

local LEARNABLE = { [1] = true }
Pokemon.moveFromTmItem = function(id) return ({ [289] = 1, [290] = 2, [291] = 3 })[id] end
Pokemon.canLearnTmItem = function(_, id) return LEARNABLE[Pokemon.moveFromTmItem(id)] == true end
Pokemon.moveName = function(m) return "MOVE" .. tostring(m) end
Pokemon.displayMonName = function() return "ZIGZAGOON" end
Pokemon.adjustFriendship = function() end
Pokemon.itemFriendship = function() end
Pokemon.currentMapSec = function() return 0 end
Pokemon.applyStats = function() end
Pokemon.raiseEvFromItem = function() return 10 end
Pokemon.teachMove = function(mon, m)
  for i = 1, 4 do
    if not mon.moves[i] or mon.moves[i] == 0 then mon.moves[i] = m return true end
  end
  return false
end
Pokemon.knowsMove = function(mon, m)
  for i = 1, 4 do if mon.moves[i] == m then return true end end
  return false
end
Pokemon.moveSlotCount = function(mon)
  local n = 0
  for i = 1, 4 do if mon.moves[i] and mon.moves[i] ~= 0 then n = n + 1 end end
  return n
end
package.loaded["src.core.game3.quest_log_recorder"] = { event = function() end }

local function has(text, key) return type(text) == "string" and text:find(key, 1, true) ~= nil end

local KEYS = {
  "gText_PkmnAlreadyKnows", "gText_PkmnCantLearnMove", "gText_PkmnNeedsToReplaceMove",
  "gText_PkmnLearnedMove3", "gText_WhichMoveToForget", "gText_12PoofForgotMove",
  "gText_StopLearningMove2", "gText_MoveNotLearned", "gText_RestoreWhichMove", "gText_BoostPp",
  "gText_PkmnBaseVar2StatIncreased", "gText_MovesPPIncreased", "gText_PPWasRestored",
  "gText_WontHaveEffect", "gText_PkmnElevatedToLvVar2", "gText_PkmnNotHolding",
  "gText_ReceivedItemFromPkmn", "gText_ThereIsNoPokemon", "gText_CantDismountBike",
  "gText_CoinCase", "gText_PlayerUsedVar2", "gText_RepelEffectsLingered",
  "gText_UsedVar2WildLured", "gText_UsedVar2WildRepelled",
}

for _, version in ipairs({ "ruby", "sapphire" }) do
  GameVersion.set(version)
  require("src.core.game3.profile").reset()
  local session = { version = version, party = {} }

  for _, key in ipairs(KEYS) do
    T.check(RomText.has(key), version .. " resolves " .. key .. " from the RS cache")
  end

  local four = { species = 288, level = 18, hp = 50, maxHp = 50, moves = { 10, 11, 12, 13 } }
  local status, msg = ItemUse.checkTmPreflight(four, 289)
  T.eq(status, "ok", version .. " four-move mon passes TM preflight")
  T.check(has(msg, "gOtherText_WantsToLearn"), version .. " four-move preflight reads gOtherText_WantsToLearn")

  status, msg = ItemUse.checkTmPreflight(four, 290)
  T.eq(status, "incompatible", version .. " incompatible TM")
  T.check(has(msg, "gOtherText_NotCompatible"), version .. " incompatible reads gOtherText_NotCompatible")

  local knower = { species = 288, level = 18, hp = 50, maxHp = 50, moves = { 2, 11 } }
  status, msg = ItemUse.checkTmPreflight(knower, 290)
  T.eq(status, "knows", version .. " already-knows is checked before compatibility")
  T.check(has(msg, "gOtherText_AlreadyKnows"), version .. " already-knows reads gOtherText_AlreadyKnows")

  status, msg = ItemUse.checkTmPreflight(four, 999)
  T.eq(status, "invalid", version .. " non-TM item")
  T.check(has(msg, "gOtherText_WontHaveAnyEffect"), version .. " no effect reads gOtherText_WontHaveAnyEffect")

  local two = { species = 288, level = 18, hp = 50, maxHp = 50, moves = { 10, 11 } }
  session.party = { two }
  local bag = {}
  package.loaded["src.core.game3.bag"].remove = function() return true end
  local ok, kind, text = ItemUse.useTm(session, bag, 289, 1)
  T.check(ok and kind == "tm", version .. " free-slot TM teach succeeds")
  T.check(has(text, "gOtherText_LearnedMove"), version .. " learned reads gOtherText_LearnedMove")

  local candy = { species = 288, level = 18, hp = 50, maxHp = 50, moves = { 10 } }
  ok, kind, text = ItemUse.useRareCandy(session, candy)
  T.check(ok, version .. " rare candy levels up")
  T.check(has(text, "gOtherText_ElevatedTo"), version .. " rare candy reads gOtherText_ElevatedTo")

  ok, kind, text = ItemUse.useVitamin(session, candy, 64)
  T.check(ok, version .. " protein raises attack")
  T.check(has(text, "gOtherText_WasRaised") and has(text, "gOtherText_Attack"),
    version .. " vitamin reads gOtherText_WasRaised with gOtherText_Attack")
  ok, kind, text = ItemUse.useVitamin(session, candy, 63)
  T.check(has(text, "gOtherText_Hp2"), version .. " HP up names gOtherText_Hp2")

  local boosts = ItemUse.ppItemBoosts
  ItemUse.ppItemBoosts = function() return true end
  T.check(has(ItemUse.ppItemText(candy, 69, 1), "gOtherText_PPIncreased"), version .. " PP up reads gOtherText_PPIncreased")
  ItemUse.ppItemBoosts = function() return false end
  T.check(has(ItemUse.ppItemText(candy, 34, 1), "gOtherText_PPRestored"), version .. " ether reads gOtherText_PPRestored")
  ItemUse.ppItemBoosts = boosts

  ok, kind, text = ItemUse.takeFromMon(session, bag, 1)
  T.check(not ok and has(text, "gOtherText_NotHoldingAnything"), version .. " take from empty-handed mon")
end

GameVersion.set("firered")
require("src.core.game3.profile").reset()
BUNDLE.text = { gText_PkmnCantLearnMove = ir("gText_PkmnCantLearnMove") }
local status, msg = ItemUse.checkTmPreflight({ species = 1, moves = { 2, 11 } }, 290)
T.eq(status, "incompatible", "firered keeps compatibility before already-knows")
T.check(has(msg, "gText_PkmnCantLearnMove"), "firered keeps its own text")

T.finish("game3_rs_item_use_text_2699_test")
