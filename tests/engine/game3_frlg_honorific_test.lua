-- FireRed's {KUN} placeholder: the honorific after the player's name is the
-- cart's gExpandedPlaceholder_Kun or _Chan string (pokefirered/src/string_util.c:386).

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq

local GameVersion = require("src.core.GameVersion")
local Space = require("src.core.game3.scripting.space")
local TextIR = require("src.core.game3.scripting.text_ir")

local prevBundle = Space.bundle
local prevProvider = TextIR._provider
TextIR.setContextProvider(nil)

-- pokefirered/charmap.txt: FD 01 is {PLAYER}, FD 05 is {KUN}
local ir = TextIR.decode({ 0xFD, 0x01, 0xFD, 0x05, 0xFF }, { dialect = "frlg" })
local boy = { dialect = "frlg", playerName = "RED", playerGender = 0 }
local girl = { dialect = "frlg", playerName = "LEAF", playerGender = 1 }

Space.bundle = nil
eq(TextIR.toPlain(ir, boy), "RED", "no script cache loaded: no honorific")

Space.bundle = { text = {
  gExpandedPlaceholder_Kun = TextIR.fromAscii(""),
  gExpandedPlaceholder_Chan = TextIR.fromAscii(""),
} }
eq(TextIR.toPlain(ir, boy), "RED", "the US cart's empty strings: no honorific")

local asked = 0
TextIR.setContextProvider(function(kind)
  if kind == "gender" then asked = asked + 1 end
end)
eq(TextIR.toPlain(ir, { dialect = "frlg", playerName = "RED" }), "RED", "empty strings never ask for the gender")
eq(asked, 0, "no gender lookup for the US cart")
TextIR.setContextProvider(nil)

Space.bundle = { text = {
  gExpandedPlaceholder_Kun = TextIR.fromAscii("くん"),
  gExpandedPlaceholder_Chan = TextIR.fromAscii("ちゃん"),
} }
eq(TextIR.toPlain(ir, boy), "REDくん", "a boy gets the cache's _Kun string")
eq(TextIR.toPlain(ir, girl), "LEAFちゃん", "a girl gets the cache's _Chan string")
eq(TextIR.toPlain({ { t = "ph", name = "KUN" }, { t = "eos" } }, girl), "ちゃん",
  "a placeholder segment named KUN reads the same strings")

TextIR.setContextProvider(function(kind)
  if kind == "gender" then return "female" end
end)
eq(TextIR.toPlain(ir, { dialect = "frlg", playerName = "LEAF" }), "LEAFちゃん",
  "the provider supplies the gender when the context does not")
TextIR.setContextProvider(nil)

local prevVersion = GameVersion.get()
GameVersion.set("leafgreen")
eq(TextIR.toPlain(ir, { playerName = "LEAF", playerGender = 1 }), "LEAFちゃん",
  "a context without a dialect takes LeafGreen's from the game version")
GameVersion.set(prevVersion)

Space.bundle.text.gExpandedPlaceholder_Kun = TextIR.fromAscii("{KUN}くん")
eq(TextIR.toPlain(ir, boy), "REDくん", "a label holding the placeholder itself does not recurse")

-- pokeemerald/src/string_util.c:456: Emerald keeps reading {KUN} from its placeholders.
local ph = { byGender = { KUN = { male = "", female = "" } } }
local rse = TextIR.decode({ 0xFD, 0x01, 0xFD, 0x05, 0xFF }, { dialect = "rse" })
eq(TextIR.toPlain(rse, { dialect = "rse", playerName = "MAY", playerGender = 1, placeholders = ph }), "MAY",
  "rse ignores FireRed's labels")

Space.bundle = prevBundle
TextIR.setContextProvider(prevProvider)

T.finish("game3_frlg_honorific_test")
