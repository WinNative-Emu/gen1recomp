package.path = "./?.lua;./?/init.lua;" .. package.path

local Strings = require("src.core.Strings")
local Mapsec = require("src.ui.game3.rse.mapsec")
local RomText = require("src.core.game3.rom_text")
local FrlgFont = require("src.ui.game3.frlg_font")
local Pokemon = require("src.core.game3.pokemon")
local BattleText = require("src.core.game3.battle.battle_text")
local SummaryData = require("src.core.game3.summary_data")

Pokemon._abilityNames = { [9] = "STATIC" }
Pokemon._romAbilityNames = { [9] = "STATIC" }

Mapsec.readLua = function(rel)
  assert(rel == "pokemon/pokedex/entries.lua")
  return {
    [252] = {
      category = "Wood Gecko",
      description = "A small gecko.",
      height = 5,
      weight = 50,
    },
  }
end
RomText.plain = function(key) return key end
FrlgFont.measure = function(text) return #text end
Pokemon.name = function() return "TREECKO" end

local Pokedex = require("src.ui.game3.rse.pokedex")
Pokedex.speciesOf = function() return 252 end
Pokedex.hoennNumber = function() return 1 end

local function info()
  return Pokedex.monInfo({}, 252, false, true, false)
end

-- pokeemerald/src/starter_choose.c:579 and battle_factory_screen.c:2007 print
-- the same CopyMonCategoryText string as the Pokédex.
local Kit = require("src.ui.game3.rse.scene_kit")
Kit.loadLua = function(rel)
  if rel == "data/generated/gba/region_map/map_sections.lua" then
    return { sections = { [0] = { name = "LITTLEROOT TOWN" } } }
  end
  -- the Pokédex reads its layout from the graphics manifest (Emerald's, not
  -- Ruby/Sapphire's native one)
  if rel == "data/generated/gba/rse/pokedex/manifest.lua" then return {} end
  assert(rel == "data/generated/gba/pokemon/dex.lua", rel)
  return { [252] = { category = "Wood Gecko" } }
end
Pokemon.national = function(species) return species end
Pokemon._names = { [252] = "TREECKO" } -- keeps the starter label from reinstalling the packs
local StarterChoose = require("src.ui.game3.rse.starter_choose")
StarterChoose.species = function() return 252 end
local function starterCategory()
  local view = setmetatable({ man = {}, selection = 1 }, StarterChoose)
  view:_createLabel()
  return view.label.category
end

local PokeblockGfx = require("src.ui.game3.rse.pokeblock_gfx")
PokeblockGfx.loadLua = function(rel)
  assert(rel == "data/generated/gba/pokemon/pokedex/entries.lua", rel)
  return { [252] = { category = "Wood Gecko" } }
end
local FactoryCommon = require("src.ui.game3.rse.factory_select").Common

-- pokeemerald/src/contest.c:3237
local ContestUI = require("src.ui.game3.rse.contest")
ContestUI.has = function(key) return key == "gContestEffectDescriptionPointers[1]" end
ContestUI.plain = function(key)
  if key == "gContestEffectDescriptionPointers[1]" then return "Startles the audience." end
  return key
end
local function contestMoveDescription()
  local view = setmetatable({
    c = { data = { moves = { [33] = { category = 0, effect = 1 } }, effects = { [1] = { appeal = 20, jam = 0 } } } },
    win = {},
    fillBox = function() end,
    fillBoxInc = function() end,
  }, { __index = ContestUI })
  view:printContestMoveDescription(33)
  return view.win[10].text
end

-- pokeemerald/src/region_map.c:1568
Mapsec.pack = function()
  return { count = 1, sections = { [0] = { name = "LITTLEROOT TOWN" } } }
end

-- pokeemerald/src/pokemon_summary_screen.c:3116: the trainer memo's met
-- location is a map section name.
local RseSummary = require("src.ui.game3.rse.summary_menu")
local PalText = require("src.ui.game3.rse.pal_text")
local drawInfo
for i = 1, 60 do
  local name, value = debug.getupvalue(RseSummary.draw, i)
  if not name then break end
  if name == "drawInfo" then drawInfo = value; break end
end
assert(drawInfo, "RSE summary info page drawer")
RomText.ir = function() return {} end
RomText.at = function() return {} end
PalText.width = function() return 0 end
Pokemon.types = function() return {} end
Pokemon.speciesOf = function() return 252 end
SummaryData.nature = function() return 0 end
local function metLocation()
  local shown
  local draw = PalText.draw
  PalText.draw = function(_, _, _, ctx)
    if ctx and ctx.dynamic then shown = ctx.dynamic[4] end
  end
  local w = { left = 0, top = 0, paletteNum = 0 }
  local m = { palette = {}, textColors = {}, windows = {}, pageWindows = { info = { w, w, w, w } } }
  local describe = SummaryData.abilityDescription
  SummaryData.abilityDescription = function() return "" end
  drawInfo(m, { _playerState = { name = "MAY", trainerId = 1 } },
    { species = 252, ability = 9, otName = "MAY", otId = 1, metLevel = 5, metLocation = 0 }, false)
  PalText.draw, SummaryData.abilityDescription = draw, describe
  return shown
end

-- A modded ability past the built-in id table resolves to a key from its name.
local Adapter = require("src.core.game3.battle.adapter")
Pokemon._abilityNames[200] = "NEW SKILL"
Pokemon._romAbilityNames[200] = "NEW SKILL"
local function adapterAbilityKey()
  return Adapter.new({}):abilityOf({ ability = 200 })
end

Strings.load({})
assert(Pokemon.abilityName(9) == "STATIC",
  "an ability name keeps its English ROM value without translations")
assert(SummaryData.contestCategoryName("Cool") == "Cool",
  "a contest category keeps its English source without translations")
assert(SummaryData.contestEffectDescription({ description = "Startles the audience." })
    == "Startles the audience.",
  "a contest effect description keeps its English source without translations")
local english = info()
assert(english[3].text == "Wood Gecko gText_Pokemon",
  "the category keeps its English source when no translation is loaded")
assert(english[#english].text == "A small gecko.",
  "the description keeps its English source when no translation is loaded")
assert(starterCategory() == "Wood Gecko gText_Pokemon",
  "the starter label keeps its English category without translations")
assert(FactoryCommon.categoryText(252) == "Wood Gecko gText_Pokemon",
  "the Battle Factory keeps its English category without translations")
assert(contestMoveDescription() == "Startles the audience.",
  "the contest move window keeps its English effect text without translations")
assert(Mapsec.name(0) == "LITTLEROOT TOWN",
  "a map section keeps its English name without translations")
assert(Mapsec.name(99) == "", "an unknown map section has no name")
assert(metLocation() == "LITTLEROOT TOWN",
  "the RSE summary keeps the English met location without translations")
assert(adapterAbilityKey() == "NEW_SKILL", "the battle adapter keys an unlisted ability by its ROM name")

Strings.load({ strings = {
  STATIC = "STATIQUE",
  Cool = "Sang-froid",
  ["Startles the audience."] = "Surprend le public.",
  ["Wood Gecko"] = "Gecko des bois",
  ["A small gecko."] = "Un petit gecko.",
  ["LITTLEROOT TOWN"] = "BOURG-EN-VOL",
  ["NEW SKILL"] = "NOUVEAU TALENT",
} })
assert(Pokemon.abilityName(9) == "STATIQUE",
  "the shared ability-name getter translates the displayed name")
assert(Pokemon.romAbilityName(9) == "STATIC",
  "the original ROM name stays available for stable ID lookups")
assert(BattleText.RESOLVE_RSE[0x17]({ lastAbility = 9 }) == "STATIQUE",
  "the RSE battle ability placeholder uses the translated shared getter")
assert(SummaryData.contestCategoryName("Cool") == "Sang-froid",
  "the move relearner translates the contest category source")
assert(SummaryData.contestEffectDescription({ description = "Startles the audience." })
    == "Surprend le public.",
  "the RSE summary and move relearner translate the contest effect source")
local french = info()
assert(french[3].text == "Gecko des bois gText_Pokemon",
  "the RSE Pokédex translates the source category at presentation time")
assert(french[#french].text == "Un petit gecko.",
  "the RSE Pokédex translates the source description at presentation time")
assert(starterCategory() == "Gecko des bois gText_Pokemon",
  "the starter label translates the category like the Pokédex")
assert(FactoryCommon.categoryText(252) == "Gecko des bois gText_Pokemon",
  "the Battle Factory translates the category like the Pokédex")
assert(contestMoveDescription() == "Surprend le public.",
  "the contest move window translates the effect text like the summary")
assert(Mapsec.name(0) == "BOURG-EN-VOL",
  "the Emerald map section name goes through the registry")
assert(metLocation() == "BOURG-EN-VOL",
  "the RSE summary translates the met location like the region map")
assert(Pokemon.abilityName(200) == "NOUVEAU TALENT", "the display name is translated")
assert(adapterAbilityKey() == "NEW_SKILL",
  "the battle adapter keeps keying on the ROM name when the display name is translated")

Strings.load({})
local reloaded = info()
assert(reloaded[#reloaded].text == "A small gecko.",
  "reloading without a catalog restores the English description")

print("game3_emerald_translation_runtime_test: PASS")
