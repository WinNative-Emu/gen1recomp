package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")
local Merge = require("src.mods.Merge")
local Schemas = require("src.mods.Schemas")
local Pipelines = require("src.render.Pipelines")
local Ids = require("src.mods.UnifiedIds")

local MANIFEST = [[{"id":"progress","name":"Progress","version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}]]
local MAIN = [[
local mod = ...
mod.content.growth_rates:register("TURBO", { expForLevel = function(n) return n * n end })
mod.content.type_chart:register("SPARK", { name = "SPARK", category = "special" })
mod.content.type_chart:register("SPARK>NORMAL", { multiplier = 20 })
mod.content.type_chart:patch("FIRE>WATER", { multiplier = 20 })
if mod.generation == 2 then
  mod.content.evolution_methods:register("LUCKY", { check = function(_, mon)
    return (mon.level or 1) >= 3
  end })
else
  mod.content.evolution_methods:register("LUCKY", { check = function(_, mon, _, trigger)
    return trigger.kind == "levelup" and mon.level >= 3
  end })
end
if mod.generation == 3 then
  mod.content.pokemon:patch("CHARMANDER", { growthRate = "TURBO",
    evolutions = { { method = "LUCKY", species = "CHARMELEON" } } })
  mod.content.pokemon:patch("MEW", { types = { "SPARK" } })
end
mod.content.render_pipelines:register("tint", { label = "TINT", present = function(canvas) return canvas end })
mod.content.render_pipelines:register("solo", { label = "SOLO", drawWorld = function() return nil end })
]]

local function files()
  return { ["mods/progress/manifest.json"] = MANIFEST, ["mods/progress/main.lua"] = MAIN }
end

local function load3(version, mods)
  GameVersion.set(version)
  local data = T.sdk.gen3Data()
  Schemas.bindGen3(data, version)
  local run = T.sdk.loadMods(mods and { "mods/progress" } or {},
    { fs = T.sdk.memfs(mods and files() or {}), data = data, generation = 3 })
  return run, data
end

local function restoreTypes()
  require("src.core.game3.progression").reset()
end

local savedVersion = GameVersion.get()
local Types = require("src.core.game3.battle.types")
local Progression = require("src.core.game3.progression")
local SummaryData = require("src.core.game3.summary_data")
local Experience = require("src.core.game3.battle.experience")

do
  local run, data = load3("firered", false)
  T.eq(#run.errors, 0, "mod-free Gen 3 load is clean")
  T.check(Types.TABLE == Types.NATIVE_TABLE, "mod-free type table is the cart table")
  T.check(Types.PHYSICAL == Types.NATIVE_PHYSICAL, "mod-free physical set is the cart set")
  for g = 0, 5 do
    T.eq(SummaryData.expForLevel(g, 50), SummaryData.nativeExpForLevel(g, 50), "native growth " .. g)
  end
  T.eq(Progression.growthKey(7), 1, "unregistered growth index wraps like pret")
  T.check(data.type_chart and data.type_chart.matchups, "engine seeds the Gen 3 type chart")
  T.eq(#data.type_chart.matchups, 110, "all cart matchups are registered")
  run.release()
end

do
  local run, data = load3("firered", true)
  T.eq(#run.errors, 0, "progression mod loads on Gen 3 (" .. tostring(run.errors[1]) .. ")")
  local turbo = Progression.growthIndexFor("TURBO")
  T.eq(turbo, 6, "custom curve takes the first index after pret's six")
  T.eq(SummaryData.expForLevel(turbo, 20), 400, "custom curve drives expForLevel")
  T.eq(Experience.levelForExp(turbo, 400), 20, "custom curve drives levelForExp")
  T.eq(SummaryData.expForLevel(3, 10), SummaryData.nativeExpForLevel(3, 10), "native curves untouched")

  local _, _, product = Types.typeCalc(10, 11, 11)
  T.eq(product, 2, "patched FIRE>WATER reads 2x")
  local spark = Progression.typeIndexFor("SPARK")
  T.eq(spark, 18, "custom type gets the first free type index")
  local _, _, sparkProduct = Types.typeCalc(spark, 0, 0)
  T.eq(sparkProduct, 2, "custom matchup applies")
  T.eq(Types.name(spark), "SPARK", "custom type name")
  T.eq(Types.isPhysical(spark), false, "custom type category")
  T.eq(Progression.typeIndexFor("PSYCHIC"), 14, "native spelling resolves")
  T.eq(Progression.typeIndexFor("PSYCHIC_TYPE"), 14, "canonical spelling resolves")
  T.eq(Ids.type and Ids.type("PSYCHIC", 3) or "PSYCHIC_TYPE", "PSYCHIC_TYPE", "type id canonicalises")

  T.check(Pipelines.list ~= nil, "pipelines load")
  Pipelines.install(data)
  T.eq(Pipelines.get("tint") ~= nil, true, "render pipeline registers on Gen 3")
  Pipelines.applyOptions({ pipelines = { tint = 1, solo = 1 } })
  T.eq(Pipelines.level("tint"), 1, "present pipeline keeps its level on Gen 3")
  T.eq(Pipelines.level("solo"), 0, "drawWorld-only pipeline is retired where no world pass exists")
  T.eq(Pipelines.wantsPresent(), true, "present half is composited")
  T.eq(Pipelines.worldPipeline(), nil, "no world pipeline on Gen 3")
  Pipelines.install(nil)
  restoreTypes()
  run.release()
end

do
  local run, data = load3("firered", true)
  local Pokemon = require("src.core.game3.pokemon")
  local Evolution = require("src.core.game3.evolution")
  local P = data.gen3Pokemon
  T.eq(P._speciesMeta[4].growthRate, 6, "species growthRate writes the custom index")
  T.same(P._types[151], { 18, 18 }, "species types write the custom type index")
  T.eq(P._evolutions[4][1].method, "LUCKY", "custom evolution method rides the row")
  local restore = {}
  for key, value in pairs(P) do
    restore[key] = Pokemon[key]
    Pokemon[key] = value
  end
  local target = Evolution.targetSpecies({ species = 4, level = 3, hp = 10, maxHp = 10 }, Evolution.EVO_MODE_NORMAL)
  T.eq(target, 5, "custom method decides level-up evolution")
  target = Evolution.targetSpecies({ species = 4, level = 2, hp = 10, maxHp = 10 }, Evolution.EVO_MODE_NORMAL)
  T.eq(target, 0, "custom method can decline")
  T.eq(Pokemon.growthRate(4), 6, "Pokemon.growthRate reads the custom index")
  T.eq(Experience.expForLevel({ species = 4 }, 10), 100, "species-keyed exp lookup uses the custom curve")
  restoreTypes()
  for key, value in pairs(restore) do Pokemon[key] = value end
  for key in pairs(P) do if restore[key] == nil then Pokemon[key] = nil end end
  run.release()
end

do
  GameVersion.set("gold")
  local data = T.fixtures.fresh()
  local run = T.sdk.loadMods({ "mods/progress" },
    { fs = T.sdk.memfs(files()), data = data, generation = 2 })
  T.eq(#run.errors, 0, "progression mod loads on Gen 2 (" .. tostring(run.errors[1]) .. ")")
  local Mon = require("src.battle.gen2.Mon")
  local Damage = require("src.battle.gen2.Damage")
  local Evolution2 = require("src.core.gen2.Evolution")
  T.eq(Mon.experienceForLevel(Mon.growthFor(data, "TURBO"), 10), 100, "Gen 2 reads the custom curve")
  T.eq(Damage.typeMultiplier("FIRE", { "WATER" }, data.type_chart.matchups), 20, "Gen 2 reads the patched chart")
  local entry = { method = "LUCKY", into = "CHARMELEON" }
  T.eq(Evolution2.rowMatches(entry, { level = 3 }, {}, data), true,
    "Gen 2 dispatches the custom evolution method")
  run.release()
end

do
  local Effects = require("src.mods.UnifiedEffects")
  local known = function(id) return id == "MYFX" end
  T.eq(Effects.write("MYFX", 2, nil, known), "MYFX", "Gen 2 accepts a registered custom move effect")
  T.eq(Effects.write("MYFX", 2, nil), nil, "Gen 2 refuses an unregistered effect id")
  T.eq(Effects.write("MYFX", 3, nil, known), 0, "Gen 3 stores a registered custom effect on native effect byte 0")
  T.eq(Effects.write("MYFX", 3, nil), nil, "Gen 3 refuses an unregistered effect id")
  T.eq(Effects.read(0, 3, { effect = 0, _modEffectId = "MYFX" }), "MYFX",
    "Gen 3 reads a custom move effect back as authored")
  T.eq(Effects.read("MYFX", 2, { effect = "MYFX", _modEffectId = "MYFX" }), "MYFX",
    "Gen 2 reads a custom move effect back as authored")
end

GameVersion.set(savedVersion)
T.finish("unified_progression")
