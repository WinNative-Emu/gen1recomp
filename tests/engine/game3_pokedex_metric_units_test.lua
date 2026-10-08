#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
_G.love = _G.love or require("tests.love_stub")

local T = require("tests.harness")
local check = T.check

T.suite("game3 pokedex metric units")

local Schemas = require("src.mods.Schemas")
local target = { _names = { [1] = "BULBASAUR" }, _dex = { [1] = { category = "SEED", height = 7, weight = 69 } } }
local patched = { dexEntry = { kind = "SEED", height = 7, weight = 69, heightM = 0.7, weightKg = 6.9 } }
Schemas.gen3View.monWrite(target, { ops = { BULBASAUR = true }, get = function() return patched end })
local row = target._dex[1]
check(row.heightM == 0.7 and row.weightKg == 6.9 and row.height == 7 and row.category == "SEED",
  "a patch's metric values reach the dex table beside the cart's")

local DEX = { [252] = { category = "WOOD GECKO", height = 5, weight = 50, heightM = 0.5, weightKg = 5 },
  [253] = { category = "WOOD GECKO", height = 9, weight = 216 } }
package.loaded["src.core.game3.pokemon"] = { _dex = DEX,
  dexEntry = function(species) return DEX[species] end,
  name = function() return "TREECKO" end,
  speciesFromNational = function(nat) return nat end,
}

local Units = require("src.core.game3.pokedex_units")
check(Units.metric(252) == DEX[252] and Units.metric(253) == nil, "only a species with metric values is metric")
check(Units.height(DEX[252]) == "  0,5 m" and Units.weight(DEX[252]) == "  5,0 kg",
  "a metric height and weight print with one decimal and a comma")
check(Units.weight({ weightKg = 950 }) == "950,0 kg", "a three-digit weight fills the field")
check(Units.unknownHeight() == "???,? m" and Units.unknownWeight() == "???,? kg", "the unknown masks")

local MANIFEST = { assetLayout = "emerald", tenDashes = "----------",
  strings = { UnknownPoke = "?????POKéMON", UnknownHeight = "??'??\"", UnknownWeight = "????.? lbs." } }
package.loaded["src.ui.game3.rse.pokedex_gfx"] = setmetatable({ manifest = function() return MANIFEST end },
  { __index = function() return function() end end })
package.loaded["src.ui.game3.rse.mapsec"] = setmetatable({ readLua = function(path)
  if path:find("entries", 1, true) then return DEX end
  return { nationalToRegional = {} }
end }, { __index = function() return function() end end })
local BUNDLE = { text = {} }
package.loaded["src.core.game3.scripting.space"] = { ensureBundle = function() return BUNDLE end }
local Pokedex = require("src.ui.game3.rse.pokedex")
local function rows(nat, owned)
  local out = {}
  for _, r in ipairs(Pokedex.monInfo({ descriptionPage = 0 }, nat, true, owned, false)) do out[#out + 1] = r.text end
  return table.concat(out, "|")
end
MANIFEST.assetLayout = "rs"
check(rows(252, true):find("|    0,5 m|    5,0 kg|", 1, true) ~= nil,
  "a caught Ruby/Sapphire entry prints its metric values, two spaces per missing digit")
check(rows(253, true):find("lbs.", 1, true) ~= nil, "a Ruby/Sapphire entry without metric values keeps the US ones")
check(rows(252, false):find("????.? lbs.", 1, true) ~= nil, "a seen Ruby/Sapphire entry keeps the cart's unknown rows")

local function ir(text) return { { t = "text", s = text }, { t = "eos" } } end
BUNDLE.text = { gText_Pokemon = ir("POKéMON"), gText_5MarksPokemon = ir("?????POKéMON"), gText_NumberClear01 = ir("No. "),
  gText_HTHeight = ir("HT"), gText_WTWeight = ir("WT"),
  gText_UnkHeight = ir("???,? m"), gText_UnkWeight = ir("???,? kg") }
MANIFEST.assetLayout = "emerald"
check(rows(252, true):find("{UNK_SPACER}{UNK_SPACER}0,5 m|{UNK_SPACER}{UNK_SPACER}5,0 kg", 1, true) ~= nil,
  "a caught Emerald entry prints its metric values aligned with the digit spacer")
check(rows(253, true):find("lbs.", 1, true) ~= nil, "an Emerald entry without metric values keeps the US ones")
check(rows(252, false):find("???,? m|???,? kg", 1, true) ~= nil, "a seen Emerald entry prints the cart's unknown rows")

T.finish("game3 pokedex metric units")
