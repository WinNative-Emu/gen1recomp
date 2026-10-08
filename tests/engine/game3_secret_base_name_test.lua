#!/usr/bin/env luajit
-- pokeemerald/src/secret_base.c:728, pokeruby/src/secret_base.c:629

package.path = "./?.lua;./?/init.lua;" .. package.path

local BUNDLE = { text = {} }
package.loaded["src.core.game3.scripting.space"] = { ensureBundle = function() return BUNDLE end }
local ALIASES = {}
package.loaded["src.core.game3.profile"] = { forSession = function() return { ui = { textAliases = ALIASES } } end }

local T = require("tests.harness")
local eq = T.eq

local SB = require("src.core.game3.rse.secret_base")

T.suite("secret base name")

local function ir(...)
  local out = { ... }
  out[#out + 1] = { t = "eos" }
  return out
end
local function text(s) return { t = "text", s = s } end

BUNDLE.text = { gText_ApostropheSBase = ir(text("'s BASE")) }
eq(SB.nameWith("MAY"), "MAY's BASE", "Emerald's row follows the owner's name")
ALIASES.gText_ApostropheSBase = "gOtherText_PlayersBase"
BUNDLE.text = { gOtherText_PlayersBase = ir(text("'s BASE")) }
eq(SB.nameWith("MAY"), "MAY's BASE", "Ruby and Sapphire's row follows the owner's name")
BUNDLE.text = { gOtherText_PlayersBase = ir(text("BASIS v. "), { t = "player" }) }
eq(SB.nameWith("MAIKE"), "BASIS v. MAIKE", "a row with the player placeholder names the owner there")
BUNDLE.text = { gOtherText_PlayersBase = ir(text("BASE DE "), { t = "ph", code = 1, name = "PLAYER" }) }
eq(SB.nameWith("FLORA"), "BASE DE FLORA", "a named player placeholder is filled with the owner too")
ALIASES.gText_ApostropheSBase = nil
BUNDLE.text = { gText_ApostropheSBase = ir(text("BASE DE "), { t = "strvar", n = 1 }) }
eq(SB.nameWith("SACHA"), "BASE DE SACHA", "Emerald's European row gets the owner in its STR_VAR_1")
local RomText = require("src.core.game3.rom_text")
local plain, renders = RomText.plain, 0
RomText.plain = function(...) renders = renders + 1 return plain(...) end
eq(SB.nameWith("SACHA"), "BASE DE SACHA", "the rendered row names the owner")
eq(SB.nameWith("FLORA"), "BASE DE FLORA", "the rendered row names another owner")
RomText.plain = plain
eq(renders, 0, "a row already rendered is not rendered again for another owner")
BUNDLE.text = {}
eq(SB.nameWith("MAY"), "MAY's BASE", "a cart without the row keeps the English")
local Space = package.loaded["src.core.game3.scripting.space"]
local ensureBundle = Space.ensureBundle
Space.ensureBundle = function() error("no script bundle") end
eq(SB.nameWith("MAY"), "MAY's BASE", "without the script cache, the English row")
Space.ensureBundle = ensureBundle

T.finish("secret base name")
