-- A name joined to a cart string the US code appends after it: the European
-- carts put it in the string's STR_VAR_1 (pret pokeemerald multi-language,
-- src/naming_screen.c:1746, src/secret_base.c:732).

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq

local RomText = require("src.core.game3.rom_text")
local Naming = require("src.ui.game3.naming")
local SB = require("src.core.game3.rse.secret_base")

local saved = {}
local function set(key, ir)
  if saved[key] == nil then saved[key] = RomText.overrides[key] or false end
  RomText.overrides[key] = ir
end
local function text(s) return { { t = "text", s = s }, { t = "eos" } } end

-- src/naming_screen.c:1746
set("gText_PkmnsNickname", text("'s nickname?"))
eq(Naming.monTitle("BULBASAUR"), "BULBASAUR's nickname?", "FireRed's US row has no placeholder: the name goes first")
set("gText_PkmnsNickname", { { t = "strvar", n = 1 }, { t = "text", s = "'s nickname?" }, { t = "eos" } })
eq(Naming.monTitle("MUDKIP"), "MUDKIP's nickname?", "Emerald's US row prints the same")
set("gText_PkmnsNickname", { { t = "text", s = "Surnom de " }, { t = "strvar", n = 1 }, { t = "text", s = "?" }, { t = "eos" } })
eq(Naming.monTitle("POUSSIFEU"), "Surnom de POUSSIFEU?", "French: the species fills the row's STR_VAR_1")
eq(Naming.monTitle(nil), "Surnom de ?", "a missing name leaves the placeholder empty")
set("gText_PkmnsNickname", text("　の　ニックネームは？"))
eq(Naming.monTitle("フシギダネ"), "フシギダネ　の　ニックネームは？", "FireRed's Japanese row has no placeholder either")

-- a mod's catalog entry for the English source: the name still lands in it
local Strings = require("src.core.Strings")
set("gText_PkmnsNickname", { { t = "strvar", n = 1 }, { t = "text", s = "'s nickname?" }, { t = "eos" } })
Strings.load({ strings = { ["%s's nickname?"] = "Surnom de %s?" } })
eq(Naming.monTitle("MUDKIP"), "Surnom de MUDKIP?", "a catalog translation takes the name in its %s")
Strings.load(nil)

-- src/secret_base.c:732
local sess = { secretBases = { { trainerName = "SACHA" } } }
set("gText_ApostropheSBase", text("'s BASE"))
eq(SB.name(0, sess), "SACHA's BASE", "US: the row follows the owner")
set("gText_ApostropheSBase", text("　きち"))
eq(SB.name(0, sess), "SACHA　きち", "Japanese: the same")
set("gText_ApostropheSBase", { { t = "text", s = "BASE DE " }, { t = "strvar", n = 1 }, { t = "eos" } })
eq(SB.name(0, sess), "BASE DE SACHA", "French: the owner fills the row's STR_VAR_1")

for key, ir in pairs(saved) do RomText.overrides[key] = ir or nil end

T.finish("game3_european_name_placeholder_test")
