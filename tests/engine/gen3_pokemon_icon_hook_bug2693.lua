package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")
local Assets = require("src.render.Assets")

local MOD_ICON = "mods/skin/pikachu_icon.png"
local loadedPaths = {}
local assetsImageData = Assets.imageData
Assets.imageData = function(path)
  if path == MOD_ICON then
    loadedPaths[#loadedPaths + 1] = path
    return love.image.newImageData(32, 64)
  end
  return assetsImageData(path)
end

package.loaded["src.core.game3.runtime"] = { getSession = function() return nil end }

local vanillaIcon = { image = "vanilla-icon", w = 32, h = 32, sheetH = 64, frames = 2,
                      quads = { [0] = "q0", [1] = "q1" } }
local Pokemon = { _names = { [25] = "PIKACHU", [4] = "CHARMANDER" }, _front = {}, _back = {} }
function Pokemon.name(sp) return Pokemon._names[sp] or "?????" end
function Pokemon.speciesFromName() return nil end
function Pokemon.frontPic() return nil end
function Pokemon.backPic() return nil end
function Pokemon.monPicSpecies(mon) return mon and mon.species end
local iconCalls = 0
function Pokemon.icon(species)
  iconCalls = iconCalls + 1
  if tonumber(species) == 999 then return nil end
  return vanillaIcon
end
function Pokemon.monIcon(mon) return Pokemon.icon(Pokemon.monPicSpecies(mon)) end
function Pokemon.onReload() end
package.loaded["src.core.game3.pokemon"] = Pokemon

local Gen3Compat = require("src.mods.Gen3Compat")
local game = { phase = "field", data = {}, mods = { content = {} } }
Gen3Compat.bind(function() return game end)

Runtime.hooks = Hooks.new()
Gen3Compat.applyMerged(game)

T.eq(Pokemon.monIcon({ species = 25 }), vanillaIcon, "unhooked monIcon is the vanilla entry")
T.eq(Pokemon.icon(25), vanillaIcon, "unhooked icon is the vanilla entry")

local calls = {}
local mode = "swap"
Runtime.hooks:wrap("pokemon.icon", function(next, path, ctx)
  calls[#calls + 1] = { path = path, kind = ctx.kind, species = ctx.species, mon = ctx.mon,
                        gen3Species = ctx.gen3Species }
  if mode == "swap" then return MOD_ICON end
  if mode == "hide" then return nil end
  if mode == "false" then return false end
  return next(path, ctx)
end)

local mon = { species = 25 }
local before = iconCalls
local entry = Pokemon.monIcon(mon)
T.eq(#calls, 1, "monIcon raises pokemon.icon once")
T.eq(iconCalls - before, 1, "monIcon builds the vanilla entry once")
T.eq(calls[1].kind, "icon", "ctx.kind is icon")
T.eq(calls[1].species, "PIKACHU", "ctx.species is the Gen 1 style name")
T.eq(calls[1].gen3Species, 25, "ctx.gen3Species is the Gen 3 index")
T.eq(calls[1].mon, mon, "ctx.mon is the drawn mon")
T.eq(calls[1].path, "data/generated/gba/pokemon/icons/25.rgba", "vanilla path is the cache icon")
T.check(entry and entry ~= vanillaIcon, "a string return swaps the icon")
T.eq(entry and entry.path, MOD_ICON, "the entry is the mod's image")
T.check(entry and entry.quads[0] and entry.quads[1], "the swapped icon has both frames")
T.eq(entry and entry.w, 32, "a 32x64 sheet is 32 wide")
T.eq(entry and entry.h, 32, "and 32 tall per frame")
T.eq(Pokemon.monIcon(mon), entry, "the loaded image is cached")
T.eq(#loadedPaths, 1, "the mod image is read once")

local dexEntry = Pokemon.icon(25)
T.eq(calls[#calls].mon, nil, "Pokemon.icon raises the hook with no mon")
T.eq(dexEntry and dexEntry.path, MOD_ICON, "Pokemon.icon is swapped too")

mode = "hide"
local hidden = Pokemon.monIcon(mon)
T.check(hidden ~= nil, "a nil return never hands nil to the draw site")
T.check(hidden and hidden.blank, "a nil return yields a blank icon")
T.check(hidden and hidden.image and hidden.quads[0] and hidden.quads[1],
  "the blank icon is drawable on both frames")
T.eq(hidden and hidden.w, 32, "the blank icon keeps the vanilla width")

mode = "false"
local hiddenF = Pokemon.monIcon(mon)
T.check(hiddenF and hiddenF.blank, "a false return yields a blank icon")
local missing = Pokemon.icon(999)
T.check(missing and missing.blank and missing.quads[0],
  "a hidden icon with no vanilla entry is still a blank icon")

mode = "pass"
T.eq(Pokemon.monIcon(mon), vanillaIcon, "passing through keeps the vanilla entry")

local wrapped = Pokemon.monIcon
Gen3Compat.applyMerged(game)
T.eq(Pokemon.monIcon, wrapped, "applyMerged does not wrap twice")

T.finish("gen3 pokemon.icon hook bug 2693")
