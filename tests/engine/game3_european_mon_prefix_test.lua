-- The wild/foe word joined to a foe's name: the US and Japanese rows go before
-- it, the European carts write theirs to follow it and append it (pret
-- pokeemerald multi-language, src/battle_message.c:4042, :4649).

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq

local RomText = require("src.core.game3.rom_text")
local BattleText = require("src.core.game3.battle.battle_text")
local State = require("src.core.game3.battle.state")

local saved = {}
local function set(key, ir)
  if saved[key] == nil then saved[key] = RomText.overrides[key] or false end
  RomText.overrides[key] = ir
end
local function text(s) return { { t = "text", s = s }, { t = "eos" } } end

-- pokeemerald multi-language src/battle_message.c:4042
eq(BattleText.withMonPrefix("Wild ", "ZIGZAGOON"), "Wild ZIGZAGOON", "US: the wild word comes first")
eq(BattleText.withMonPrefix("やせいの　", "ジグザグマ"), "やせいの　ジグザグマ", "Japanese: the wild word comes first")
eq(BattleText.withMonPrefix(" sauvage", "ZIGZATON"), "ZIGZATON sauvage", "French: the wild word follows the name")
eq(BattleText.withMonPrefix(" (Wild)", "ZIGZACHS"), "ZIGZACHS (Wild)", "German: the wild word follows the name")

set("sText_WildPkmnPrefix", text(" sauvage"))
set("sText_FoePkmnPrefix", text(" ennemi"))
set("sText_TestAttackerUses", { { t = "bph", code = 0x0F }, { t = "text", s = " utilise" }, { t = "eos" } })
eq(BattleText.get("sText_TestAttackerUses", { atk = { name = "ZIGZATON", side = "opponent" } }),
  "ZIGZATON sauvage utilise", "B_ATK_NAME_WITH_PREFIX puts the French wild word after the name")
eq(BattleText.get("sText_TestAttackerUses", { atk = { name = "ZIGZATON", side = "opponent" }, trainer = true }),
  "ZIGZATON ennemi utilise", "and the foe word against a trainer")
eq(BattleText.get("sText_TestAttackerUses", { atk = { name = "POUSSIFEU", side = "player" } }),
  "POUSSIFEU utilise", "the player's own POKéMON has no prefix")
-- src/battle_message.c:4649 B_BUFF_MON_NICK_WITH_PREFIX
eq(State.prefixedName({ wild = true }, { side = "opponent" }, "ZIGZATON"), "ZIGZATON sauvage",
  "a buffered name takes the same order")
eq(State.prefixedName({ wild = false }, { side = "opponent" }, "ZIGZATON"), "ZIGZATON ennemi",
  "a buffered foe name too")
set("sText_WildPkmnPrefix", text("Wild "))
eq(State.prefixedName({ wild = true }, { side = "opponent" }, "ZIGZAGOON"), "Wild ZIGZAGOON",
  "the US row still goes first")

for key, ir in pairs(saved) do RomText.overrides[key] = ir or nil end

T.finish("game3_european_mon_prefix_test")
