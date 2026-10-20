package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Version = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Profile = require("src.core.game3.profile")
local Schemas = require("src.mods.Schemas")
local PaletteMods = require("src.core.game3.palette_mods")

local BODY = [[
local mod = ...
mod.content.sprites:register("ART_NPC", { image = "mods/art/npc.png", frames = 6, walker = true })
mod.content.palettes:register("CHARMANDERMON", { {255,255,255}, {255,0,0}, {0,0,255}, {0,0,0} })
mod.content.palettes:register("CHARMANDERMON_SHINY", { {255,255,0}, {0,255,0}, {0,0,255}, {0,0,0} })
mod.content.palettes:register("OBJ_EVENT_GFX_RED_NORMAL", { colors = {
  { r = 255, g = 255, b = 255 }, { r = 0, g = 255, b = 0 }, { r = 0, g = 0, b = 255 }, { r = 0, g = 0, b = 0 } } })
mod.content.font:register("artpage", { image = "mods/art/font.png", base = 768, glyphsPerRow = 2, advance = 9 })
mod.content.font:register("charmap:hash", { seq = "#", code = 768 })
mod.content.font:register("ttf", {})
]]

local versions = { "firered", "leafgreen", "ruby", "sapphire", "emerald" }
for _, version in ipairs(versions) do
  Version.set(version)
  Versions.select(version)
  Profile.reset()
  local data = T.sdk.gen3Data()
  T.sdk.captureRuntime()
  local files = {
    ["mods/art/manifest.json"] = '{"id":"art","name":"art","version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}',
    ["mods/art/main.lua"] = BODY,
  }
  local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 3, version = version, dev = true })
  T.check(loader:load(data), version .. " loads with graphics registries")
  T.same(loader.errors, {}, version .. " no unavailable reports")

  T.eq(Schemas.targetFor("palettes", Schemas.REGISTRIES.palettes, 3, version), "gen3Palettes",
    version .. " palettes route to gen3Palettes")
  T.eq(Schemas.targetFor("font", Schemas.REGISTRIES.font, 3, version), "gen3Font",
    version .. " font routes to gen3Font")
  T.eq(Schemas.targetFor("palettes", Schemas.REGISTRIES.palettes, 1), Schemas.REGISTRIES.palettes.target,
    version .. " Gen 1 palettes target untouched")
  T.eq(#data.gen3Palettes.CHARMANDERMON, 4, version .. " palette record merged")
  T.eq(data.gen3Palettes.OBJ_EVENT_GFX_RED_NORMAL.colors[2].g, 255, version .. " named-colour form merged")
  T.eq(data.gen3Font.pages.artpage.base, 768, version .. " font page merged")
  T.eq(data.gen3Font.charmap[1].seq, "#", version .. " charmap row merged")
  T.check(type(data.gen3Font.ttf) == "table", version .. " ttf entry merged")
  T.eq(data.sprites.ART_NPC.frames, 6, version .. " sprite record merged")

  local okShort, errShort = pcall(function()
    local bad = Loader.new({ fs = T.sdk.memfs({
      ["mods/bad/manifest.json"] = '{"id":"bad","name":"bad","version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}',
      ["mods/bad/main.lua"] = 'local mod = ...\nmod.content.palettes:register("BADMON", { {0,0,0}, {1,1,1} })',
    }), generation = 3, version = version, dev = true })
    bad:load(T.sdk.gen3Data())
    return bad
  end)
  T.check(okShort and #errShort.errors > 0, version .. " a short palette is judged, not crashed")
end

local function rgba(pixels)
  local out = {}
  for i, p in ipairs(pixels) do out[i] = string.char(p[1], p[2], p[3], p[4]) end
  return table.concat(out)
end

local function pixel(str, i) return str:byte(i * 4 + 1), str:byte(i * 4 + 2), str:byte(i * 4 + 3), str:byte(i * 4 + 4) end

local ramp = PaletteMods.rampOf({ { 255, 255, 0 }, { 0, 255, 0 }, { 0, 0, 255 }, { 0, 0, 0 } })
T.check(ramp ~= nil, "a four colour record is a ramp")
T.eq(PaletteMods.rampOf({ { 1, 2, 3 } }), nil, "three colours is not a ramp")

local source = rgba({ { 250, 250, 250, 255 }, { 10, 10, 10, 255 }, { 128, 128, 128, 255 }, { 0, 0, 0, 0 } })
local out = PaletteMods.recolourRgba(source, ramp)
T.eq(#out, #source, "recolouring keeps the byte length")
local r, g, b, a = pixel(out, 0)
T.same({ r, g, b, a }, { 255, 255, 0, 255 }, "the lightest pixel takes colour 1")
r, g, b, a = pixel(out, 1)
T.same({ r, g, b, a }, { 0, 0, 0, 255 }, "the darkest pixel takes colour 4")
r, g, b, a = pixel(out, 3)
T.same({ r, g, b, a }, { 0, 0, 0, 0 }, "transparent pixels are left alone")
for i = 0, 2 do
  local pr, pg, pb = pixel(out, i)
  local function onGrid(v) return math.floor(math.floor(v / 255 * 31 + 0.5) * 255 / 31 + 0.5) == v end
  T.check(onGrid(pr) and onGrid(pg) and onGrid(pb), "pixel " .. i .. " is a 15-bit GBA colour")
end
T.eq(PaletteMods.recolourRgba(source, nil), source, "no ramp returns the very same bytes")

PaletteMods.install(nil)
T.check(not PaletteMods.active(), "nothing installed is inactive")
T.eq(PaletteMods.recolourPic(source, 4, false), source, "native pictures pass through untouched")
T.eq(PaletteMods.recolourIcon(source, 4), source, "native icons pass through untouched")
T.eq(PaletteMods.monRamp(4, false), nil, "no ramp without records")
T.eq(PaletteMods.objectRamp(1), nil, "no object ramp without records")

local savedPokemon = package.loaded["src.core.game3.pokemon"]
package.loaded["src.core.game3.pokemon"] = { speciesFromName = function(name) return ({ CHARMANDER = 4 })[name] end }
PaletteMods.install({ gen3Palettes = {
  CHARMANDERMON = { { 255, 255, 255 }, { 255, 0, 0 }, { 0, 0, 255 }, { 0, 0, 0 } },
  CHARMANDERMON_SHINY = { { 255, 255, 0 }, { 0, 255, 0 }, { 0, 0, 255 }, { 0, 0, 0 } },
  NOT_A_PALETTE = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } },
} })
T.check(PaletteMods.active(), "records make it active")
T.eq(PaletteMods.monRamp(4, false)[2][1], 255, "normal ramp is the species' own")
T.eq(PaletteMods.monRamp(4, true)[2][2], 255, "shiny ramp is separate")
T.eq(PaletteMods.monRamp(5, false), nil, "another species keeps native art")
T.check(PaletteMods.recolourPic(source, 4, false) ~= source, "a recoloured species changes")
T.eq(PaletteMods.recolourPic(source, 5, false), source, "an unlisted species is the same bytes")
package.loaded["src.core.game3.pokemon"] = savedPokemon
PaletteMods.install(nil)

T.eq(select(1, PaletteMods.idKind("MEWMON")), "mon", "MEWMON names a normal palette")
T.eq(select(1, PaletteMods.idKind("MEWMON_SHINY")), "monShiny", "MEWMON_SHINY names a shiny palette")
T.eq(select(1, PaletteMods.idKind("OBJ_EVENT_GFX_BOY")), "object", "OBJ_EVENT_GFX_ names an overworld graphic")
T.eq(PaletteMods.idKind("WHATEVER"), nil, "other ids are not palettes")

local FontMods = require("src.ui.game3.font_mods")
T.eq(FontMods.install(nil), false, "no font records installs nothing")
T.check(not FontMods.active(), "font mods inactive without records")
T.eq(FontMods.glyph(768), nil, "no page glyph without records")
T.eq(FontMods.ttfEligible("A"), false, "no ttf without records")

T.sdk.restoreRuntime()
T.finish("unified gen3 art")
