-- A two-stage stat change: the European "sharply"/"harshly" rows carry the
-- whole change, and the carts skip the plain string after them (pret
-- pokeemerald multi-language, src/battle_message.c:4617).

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq

local RomText = require("src.core.game3.rom_text")
local Secondary = require("src.core.game3.battle.effects.secondary")

local saved = {}
local function set(key, ir)
  if saved[key] == nil then saved[key] = RomText.overrides[key] or false end
  RomText.overrides[key] = ir
end
local function text(s) return { { t = "text", s = s }, { t = "eos" } } end

-- src/battle_message.c:4617
set("STRINGID_STATSHARPLY", text("sharply "))
set("STRINGID_STATROSE", text("rose!"))
eq(Secondary.sharpChange("STRINGID_STATSHARPLY", "STRINGID_STATROSE"), "sharply rose!",
  "US: the sharply row runs on into the plain change")
set("STRINGID_STATSHARPLY", text("ぐーんと　"))
set("STRINGID_STATROSE", text("あがった！"))
eq(Secondary.sharpChange("STRINGID_STATSHARPLY", "STRINGID_STATROSE"), "ぐーんと　あがった！",
  "Japanese: the same")
set("STRINGID_STATSHARPLY", text("monte beaucoup!"))
set("STRINGID_STATROSE", text("augmente!"))
eq(Secondary.sharpChange("STRINGID_STATSHARPLY", "STRINGID_STATROSE"), "monte beaucoup!",
  "French: the sharply row is the whole change")
set("STRINGID_STATHARSHLY", text("harshly "))
set("STRINGID_STATFELL", text("fell!"))
eq(Secondary.sharpChange("STRINGID_STATHARSHLY", "STRINGID_STATFELL"), "harshly fell!",
  "US: the harshly row runs on into the plain fall")
set("STRINGID_STATHARSHLY", text("baisse beaucoup!"))
set("STRINGID_STATFELL", text("baisse!"))
eq(Secondary.sharpChange("STRINGID_STATHARSHLY", "STRINGID_STATFELL"), "baisse beaucoup!",
  "French: the harshly row is the whole fall")
set("STRINGID_STATSHARPLY", text("subió mucho"))
set("STRINGID_STATROSE", text("subió"))
eq(Secondary.sharpChange("STRINGID_STATSHARPLY", "STRINGID_STATROSE"), "subió mucho",
  "Spanish: a row without an exclamation mark is the whole change too")

for key, ir in pairs(saved) do RomText.overrides[key] = ir or nil end

T.finish("game3_european_stat_change_test")
