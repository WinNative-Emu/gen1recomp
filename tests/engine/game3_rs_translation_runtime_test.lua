
package.path = "./?.lua;./?/init.lua;" .. package.path

local function ir(s) return { { t = "text", s = s }, { t = "eos" } } end

local BUNDLE = { text = {} }
package.loaded["src.core.game3.scripting.space"] = { ensureBundle = function() return BUNDLE end }

local TextIR = require("src.core.game3.scripting.text_ir")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

-- pokeruby/src/string_util.c:476
local Extract = require("src.import.gba.text_placeholders_extract")
local ruby, sapphire = Extract.rsSymbols("ruby"), Extract.rsSymbols("sapphire")
check(ruby.EVIL_TEAM == "gExpandedPlaceholder_Magma" and sapphire.EVIL_TEAM == "gExpandedPlaceholder_Aqua",
  "the evil team is Magma in Ruby and Aqua in Sapphire")
check(ruby.GOOD_LEADER == "gExpandedPlaceholder_Archie" and sapphire.GOOD_LEADER == "gExpandedPlaceholder_Maxie",
  "the good team's leader follows the edition")
check(ruby.VERSION == "gExpandedPlaceholder_Ruby" and sapphire.VERSION == "gExpandedPlaceholder_Sapphire",
  "the version names the edition")
check(Extract.symbolsFor("emerald") == Extract.SYMBOLS, "Emerald keeps its own labels")

local Message = require("src.ui.game3.message")
BUNDLE.text = {
  gExpandedPlaceholder_Maxie = ir("MAX"), gExpandedPlaceholder_Archie = ir("ARTHUR"),
  gExpandedPlaceholder_Ruby = ir("RUBIS"), gExpandedPlaceholder_May = ir("FLORA"),
  gExpandedPlaceholder_Kun = ir("くん"),
}
local placeholders = Message.cartPlaceholders({
  EVIL_TEAM = "MAGMA", EVIL_LEADER = "MAXIE", GOOD_LEADER = "ARCHIE", VERSION = "RUBY",
  RIVAL_MALE = "MAY", RIVAL_FEMALE = "BRENDAN", KUN_MALE = "", KUN_FEMALE = "",
  byGender = { RIVAL = { male = "MAY", female = "BRENDAN" }, KUN = { male = "", female = "" } },
}, "ruby")
check(placeholders.EVIL_LEADER == "MAX" and placeholders.GOOD_LEADER == "ARTHUR",
  "the leaders' names read the cache by the edition's labels")
check(placeholders.VERSION == "RUBIS", "the version's name reads the cache")
check(placeholders.EVIL_TEAM == "MAGMA", "a placeholder missing from the cache keeps the copy")
check(placeholders.byGender.RIVAL.male == "FLORA", "the rival's name reads the cache")
local line = { { t = "player" }, { t = "ph", code = 5, name = "KUN" }, { t = "text", s = ": " },
  { t = "ph", code = 10, name = "EVIL_LEADER" }, { t = "text", s = " / " },
  { t = "ph", code = 6, name = "RIVAL" }, { t = "eos" } }
check(TextIR.toPlain(line, { dialect = "rs", playerName = "RED", playerGender = 0, placeholders = placeholders })
  == "REDくん: MAX / FLORA", "a Ruby line expands the honorific, the leader and the rival from the cache")
BUNDLE.text = { gExpandedPlaceholder_Archie = ir("ARTHUR"), gExpandedPlaceholder_Maxie = ir("MAX") }
local sapphireLine = Message.cartPlaceholders({ EVIL_LEADER = "ARCHIE", byGender = {} }, "sapphire")
check(sapphireLine.EVIL_LEADER == "ARTHUR", "Sapphire's evil leader is Archie's row")

local MANIFEST = {
  assetLayout = "rs",
  strings = { UnknownPoke = "            ????? POKéMON", CryOf = "\252\019\002CRY OF", RegisterComplete = "REGISTERED",
    UnknownHeight = "\252\019\012??'??\"", UnknownWeight = "????.? lbs.", SizeComparedTo = "SIZE COMPARED TO ",
    Searching = "Searching...", SearchComplete = "Search completed.", NoMatching = "No matching POKéMON.",
    RightPointingTriangle = ">" },
  search = {
    topBar = { { description = "Search for POKéMON.", descriptionKey = "DexText_SearchForPoke" } },
    items = { { description = "List by the first letter.", descriptionKey = "DexText_ListByABC" } },
    names = { { title = "ABC", titleKey = "DexText_ABC", description = "" } },
    colors = {}, types = {}, orders = {}, modes = {},
  },
}
package.loaded["src.ui.game3.rse.pokedex_gfx"] = setmetatable({ manifest = function() return MANIFEST end },
  { __index = function() return function() end end })
package.loaded["src.ui.game3.rse.mapsec"] = setmetatable({ readLua = function(path)
  if path:find("entries", 1, true) then
    return { [277] = { category = "WOOD GECKO", height = 5, weight = 50, description = "Ruby page one.",
      description2 = "Ruby page two.", descriptionLabel = "DexDescription_Treecko_1",
      descriptionLabel2 = "DexDescription_Treecko_2" } }
  end
  return { nationalToRegional = {} }
end }, { __index = function() return function() end end })
package.loaded["src.core.game3.pokemon"] = { speciesFromNational = function() return 277 end,
  name = function() return "ARCKO" end }
local Pokedex = require("src.ui.game3.rse.pokedex")
BUNDLE.text = {
  DexDescription_Treecko_2 = ir("Page deux."), gDexText_UnknownPoke = ir("            ????? POKéMON"),
  gDexText_CryOf = ir("CRI DE"), DexText_SearchForPoke = ir("Chercher des POKéMON."), DexText_ABC = ir("ABC FR"),
}
local function texts(rows)
  local out = {}
  for _, row in ipairs(rows) do out[#out + 1] = row.text end
  return table.concat(out, "|")
end
local page1 = texts(Pokedex.monInfo({ descriptionPage = 0 }, 252, true, true, false))
local page2 = texts(Pokedex.monInfo({ descriptionPage = 1 }, 252, true, true, false))
check(page1:find("Ruby page one.", 1, true) ~= nil, "a page missing from the cache keeps the pack's copy")
check(page2:find("Page deux.", 1, true) ~= nil, "the second page reads the cache by its own label")
check(page1:find("WOOD GECKO POKéMON", 1, true) ~= nil, "the category keeps the cart's POKéMON after it")
check(Pokedex.topBarDescription(0) == "Chercher des POKéMON.", "the search top bar reads its own label")
check(Pokedex.itemDescription(0) == "List by the first letter.", "a search line missing from the cache keeps the copy")
check(Pokedex.searchOptionTexts(Pokedex.SEARCH.NAME)[1].title == "ABC FR", "a search option reads its own label")
-- pokeruby/src/pokedex.c:4228
local function infoRow(owned, y)
  for _, row in ipairs(Pokedex.monInfo({ descriptionPage = 0 }, 252, true, owned, false)) do
    if row.y == y then return row.text end
  end
end
local function category(unknown)
  BUNDLE.text.gDexText_UnknownPoke = ir(unknown)
  return infoRow(true, 40)
end
check(category("            ????? POKéMON") == "WOOD GECKO POKéMON", "the English cart follows the category with POKéMON")
check(category("?????") == "WOOD GECKO", "the French and German carts print the category alone")
check(category("POKéMON ?????") == "WOOD GECKO", "so does the Italian cart, whose word comes first")
check(category("？？？？？ポケモン") == "WOOD GECKOポケモン", "the Japanese word follows the category without a space")
BUNDLE.text.gDexText_UnknownHeight = ir("???,?  m")
check(infoRow(false, 56) == "\252\019\012???,?  m", "a label keeps its copy's CLEAR_TO in front of the cache's text")
local Registry = require("src.import.gba.layouts.registry")
local active = Registry.active
Registry.active = function() return { id = "rs" } end
local Entries = require("src.import.gba.pokedex_entries_extract")
local function entriesCache(body) return { exists = function() return true end, read = function() return body end } end
check(not Entries.ready(entriesCache("return { [277] = { description = \"x\" } }")),
  "an R/S cache without the description labels extracts its entries again")
check(Entries.ready(entriesCache("return { [277] = { descriptionLabel = \"DexDescription_Treecko_1\" } }")),
  "an R/S cache with the labels keeps its entries")
Registry.active = active

local COPY = { 0xBD, 0xC9, 0xCA, 0xD3, 0xFF }
local Kit = require("src.ui.game3.rse.scene_kit")
local MANIFESTS = {
  ["items/shop"] = { assetLayout = "rs", shopVersion = 2, textAliases = { gText_HowMayIServeYou = "gOtherText_HowMayIServe" },
    textBytes = { gOtherText_HowMayIServe = COPY, gOtherText_Unnamed = COPY } },
}
Kit.manifest = function(sub)
  if MANIFESTS[sub] then return MANIFESTS[sub] end
  return { assetLayout = "rs", textBytes = { gOtherText_TeachWhichMove = COPY, gOtherText_Unnamed = COPY } }
end
local Shop = require("src.ui.game3.rs.shop_menu")
BUNDLE.text = { gOtherText_HowMayIServe = ir("Que puis-je faire pour vous ?"),
  gOtherText_TeachWhichMove = ir("Quelle capacité apprendre ?") }
check(Shop.plain("gText_HowMayIServeYou") == "Que puis-je faire pour vous ?", "the shop reads the cache by its label")
check(Shop.plain("gOtherText_Unnamed") == "COPY", "a shop line missing from the cache keeps the pack's copy")

package.loaded["src.ui.game3.rse.move_relearner"] = { SUB = "tutor", show = function(_, opts) return opts end }
local tutorText = require("src.ui.game3.rs.move_relearner").show({}, {}).text
check(tutorText("gText_TeachWhichMoveToPkmn") == "Quelle capacité apprendre ?", "the move relearner reads the cache by its label")
check(tutorText("gOtherText_Unnamed") == "COPY", "a move relearner line missing from the cache keeps the pack's copy")
BUNDLE.text.gOtherText_TeachWhichMove = ir("Autre texte")
check(tutorText("gText_TeachWhichMoveToPkmn") == "Quelle capacité apprendre ?", "a screen resolves its text once while it is open")
tutorText = require("src.ui.game3.rs.move_relearner").show({}, {}).text
check(tutorText("gText_TeachWhichMoveToPkmn") == "Autre texte", "and again when it opens")

package.loaded["src.ui.game3.rse.decoration"] = { open = function(opts) return opts end }
package.loaded["src.core.game3.rse.decoration"] = { manifest = function()
  return { textBytes = { gSecretBaseText_DecorReturned = COPY, gSecretBaseText_NoDecor = COPY }, strings = {} }
end }
package.loaded["src.core.game3.rse.decoration_inventory"] = { categoryName = function() return "" end }
local decorText = require("src.ui.game3.rs.decoration").open().text
BUNDLE.text = { gSecretBaseText_DecorReturned = ir("La décoration est retournée au PC.") }
check(decorText("gText_DecorationReturnedToPC") == "La décoration est retournée au PC.", "the decoration menus read the cache by their labels")
check(decorText("gText_NoDecorationHere") == "COPY", "a decoration line missing from the cache keeps the pack's copy")

package.loaded["src.ui.game3.rse.contest_painting"] = { ID = "contest_painting", SUB = "contest_painting" }
local Painting = require("src.ui.game3.rs.contest_painting")
local PAINT = { captionLayout = { museumStart = 5, nicknameBytes = 10 },
  captionParts = { [0] = { prefix = "gContestPaintingCool1", suffix = "gContestPaintingCool2" } },
  textBytes = { gContestPaintingCool1 = COPY, gContestPaintingCool2 = COPY } }
BUNDLE.text = { gContestPaintingCool1 = ir("Le POKéMON ") }
check(Painting.caption(5, { nickname = "ZIGZATON", contestCategory = 0 }, nil, PAINT) == "Le POKéMON ZIGZATONCOPY",
  "a painting's caption reads the cache by its labels, the pack's copy where the cache has none")
-- pokeruby/src/contest_painting.c:234
PAINT.rankNames = { [0] = "gContestRankNormal" }
PAINT.hallCaption, PAINT.hallPossessive = "gContestText_ContestWinner", "gOtherText_Unknown1"
PAINT.captionLayout.hallLatinControl = {}
PAINT.textBytes.gContestRankNormal, PAINT.textBytes.gContestText_ContestWinner, PAINT.textBytes.gOtherText_Unknown1 = COPY, COPY, COPY
local winner = { nickname = "ZIGZATON", trainerName = "MAY", contestCategory = 0 }
BUNDLE.text = { gContestRankNormal = ir("NORMAL "), gContestText_ContestWinner = ir("WINNER "), gOtherText_Unknown1 = ir("'s ") }
check(Painting.caption(0, winner, nil, PAINT) == "NORMAL WINNER MAY's ZIGZATON", "the US hall caption names the trainer first")
BUNDLE.text.gOtherText_Unknown1 = ir(" von ")
check(Painting.caption(0, winner, nil, PAINT) == "NORMAL WINNER ZIGZATON von MAY", "a European hall caption names the POKéMON first")

package.loaded["src.core.game3.easy_chat_text"] = {
  rawWord = function(id) return "RAW" .. id % 1000 end, word = function(id) return "MOT" .. id end,
  group = function() return { words = { { id = 513, text = "RAW513" } } } end,
}
package.loaded["src.core.game3.rs.dewford_trend"] = { editorValid = function() return true end,
  trySetTrendyPhrase = function() return true end }
local Contracts = require("src.core.game3.rs.easy_chat_contracts")
local trend = Contracts.commit({ type = 9, wordCount = 2, before = { 0xFFFF, 0xFFFF }, session = {} }, { 513, 514 })
check(trend.stringVar2 == "MOT513 MOT514", "the trendy phrase the script prints is translated")
check(trend.result == 1, "a new trend counts as a change")
local same = Contracts.commit({ type = 9, wordCount = 2, before = { 1513, 514 }, session = {} }, { 513, 514 })
check(same.result == 0, "the change is measured on the cart's words, not their translation")
check(require("src.core.game3.rs.tv_playback").word(513) == "MOT513", "the TV prints a word translated")
local Routes = require("src.core.game3.scripting.natives_rs_tv_routes")
local Rse, Tv = require("src.core.game3.rse.init"), require("src.core.game3.rse.tv")
local session, gabbyData = { version = "ruby" }, { quote = {} }
local rseSession, tvState = Rse.session, Tv.state
Rse.session = function() return session end
Tv.state = function() return { gabbyAndTyData = gabbyData } end
local function lastQuote()
  gabbyData.quote[0] = 513
  local ctx = {}
  Routes.BY_NAME.GabbyAndTyGetLastQuote(ctx, nil)
  return ctx.stringVars[1]
end
check(lastQuote() == "MOT513", "Gabby and Ty quote a word translated")
local EASY = package.loaded["src.core.game3.easy_chat_text"]
local word = EASY.word
EASY.word = function() return "ともだち" end
check(lastQuote() == "RAW513", "a word the cart cannot print keeps the cart's word")
EASY.word, Rse.session, Tv.state = word, rseSession, tvState

-- pokeruby/src/pokemon_menu.c:126
MANIFESTS["rse/menus"] = { party = { cursorOptions = { "SUMMARY", "SWITCH", "ITEM", "CANCEL", "GIVE", "TAKE",
  "TAKE", "MAIL", "READ", "CANCEL", "CUT" } } }
package.loaded["src.core.game3.pokemon"].moveName = function(move) return move == 15 and "COUPE" or nil end
local PartyData = require("src.ui.game3.rs.party_menu_data")
BUNDLE.text = { OtherText_Summary = ir("RESUME"), OtherText_Take = ir("PRENDRE") }
check(PartyData.actionText("SUMMARY") == "RESUME", "a party action reads the cache by its label")
check(PartyData.actionText("TAKE_MAIL") == "PRENDRE", "the mail's TAKE reads its own label")
check(PartyData.actionText("SWITCH") == "SWITCH", "an action missing from the cache keeps the pack's copy")
check(PartyData.actionText("CUT", { index = { CUT = 0 }, moves = { 15 } }) == "COUPE", "a field move prints its move's name")
MANIFESTS["rse/party"] = { prompts = setmetatable({}, { __index = function() return "PROMPT" end }) }
local drawn, resolved = {}, 0
local font, chrome, cursor, partyChrome = package.loaded["src.ui.game3.frlg_font"], package.loaded["src.ui.game3.chrome"],
  package.loaded["src.ui.game3.rs.menu_cursor"], package.loaded["src.ui.game3.rs.party_chrome"]
package.loaded["src.ui.game3.frlg_font"] = { draw = function(text) drawn[#drawn + 1] = text end }
package.loaded["src.ui.game3.chrome"] = { stdFrame = function() end }
package.loaded["src.ui.game3.rs.menu_cursor"] = { draw = function() end }
package.loaded["src.ui.game3.rs.party_chrome"] = { textOptions = function() return {} end }
local menu = { ACTIONS = { "SUMMARY", "CANCEL" }, actionCursor = 1,
  _actionTextsFor = function(list) resolved = resolved + 1 return { "RESUME", "RETOUR" } end }
PartyData.drawActions(menu, false)
check(drawn[2] == "RESUME" and drawn[3] == "RETOUR" and resolved == 1, "the action menu draws the texts resolved for its list")
local displayName = package.loaded["src.core.game3.pokemon"].displayName
package.loaded["src.core.game3.pokemon"].displayName = function(mon) return mon.nickname end
BUNDLE.text = { ["PartyMenuPromptTexts[5]"] = { { t = "text", s = "Que faire avec " }, { t = "strvar", n = 1 },
  { t = "text", s = "?" }, { t = "eos" } } }
drawn, menu.ACTIONS, menu._party, menu.cursor = {}, { "SUMMARY", "CANCEL" }, { { nickname = "POUSSIFEU" } }, 1
PartyData.drawActions(menu, false)
check(drawn[1] == "Que faire avec POUSSIFEU?", "the action prompt reads the cache and names the POKeMON")
BUNDLE.text = {}
drawn = {}
PartyData.drawActions(menu, false)
check(drawn[1] == "Que faire avec POUSSIFEU?", "the prompt resolved for this menu is drawn again without a lookup")
BUNDLE.text = { ["PartyMenuPromptTexts[5]"] = { { t = "text", s = "Que faire avec " }, { t = "strvar", n = 1 },
  { t = "text", s = "?" }, { t = "eos" } } }
drawn, menu.ACTIONS, menu._party = {}, { "SUMMARY", "CANCEL" }, { { nickname = "GOBOU" } }
PartyData.drawActions(menu, false)
check(drawn[1] == "Que faire avec GOBOU?", "a new action menu names its own POKeMON")
package.loaded["src.core.game3.pokemon"].displayName = displayName
package.loaded["src.ui.game3.frlg_font"], package.loaded["src.ui.game3.chrome"] = font, chrome
package.loaded["src.ui.game3.rs.menu_cursor"], package.loaded["src.ui.game3.rs.party_chrome"] = cursor, partyChrome
if failed > 0 then
  print(failed .. " check(s) failed")
  os.exit(1)
end
print("all checks passed")
