package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Schemas = require("src.mods.Schemas")
local GameVersion = require("src.core.GameVersion")
local CacheFs = require("src.import.CacheFs")
local BattleState = require("src.ui.gen2.BattleState")
local World = require("src.world.gen2.World")

local function gen2Data()
  local data = T.fixtures.fresh()
  for _, mon in pairs(data.pokemon) do
    mon.baseStats.specialAttack, mon.baseStats.specialDefense = mon.baseStats.special, mon.baseStats.special
    mon.baseStats.special = nil
    mon.levelMoves, mon.learnset, mon.level1Moves = mon.learnset, nil, nil
    mon.picSize, mon.frontSize, mon.evolutions = mon.frontSize, nil, {}
    local dex = mon.dexEntry
    mon.dexEntry = dex and { kind = dex.kind, text = dex.text, text2 = dex.text2 }
  end
  data.pokemon.growthRates = { MEDIUM_SLOW = {
    numerator = 1, denominator = 1, squared = 0, linear = 0, constant = 0 } }
  return data
end

local GEN2_BODY = [[
local mod = ...
local p = mod.content.pokemon
mod.exports.theme = mod.content.music:register("FX_THEME", { file = "theme.ogg" }) ~= nil
local patched, reason = p:patch("FIXMON_A", { battleScaleBack = 1.5, battleScaleFront = 0.5,
  battleTheme = "FX_THEME" })
mod.exports.patched, mod.exports.reason = patched ~= nil, reason
local mon = p:get("FIXMON_A") or {}
mod.exports.back, mod.exports.front, mod.exports.bgm = mon.battleScaleBack, mon.battleScaleFront, mon.battleTheme
mod.exports.native = mon.native and mon.native.battleScaleBack
mon.battleScaleBack = 2
mod.exports.roundtrip = p:override("FIXMON_A", mon) ~= nil
mod.exports.after = (p:get("FIXMON_A") or {}).battleScaleBack
mod.exports.rangeOk = pcall(p.patch, p, "FIXMON_B", { battleScaleBack = 5 })
mod.exports.lowOk = pcall(p.patch, p, "FIXMON_B", { battleScaleFront = 0.1 })
mod.exports.done = true
]]

local GEN3_BODY = [[
local mod = ...
local p = mod.content.pokemon
for _, key in ipairs({ "battleScaleBack", "battleScaleFront", "battleTheme" }) do
  local ok, result, reason = pcall(p.patch, p, "BULBASAUR",
    { [key] = key == "battleTheme" and "MUS_NONE" or 1.5 })
  mod.exports[key] = { ok = ok, result = result, reason = reason }
end
mod.exports.done = true
]]

local function load(files, data, version)
  T.sdk.captureRuntime()
  Loader._resetShimWarned()
  local loader = Loader.new({ fs = T.sdk.memfs(files), dev = true,
    generation = GameVersion.generation(version), version = version })
  local ok, result = pcall(loader.load, loader, data)
  T.sdk.restoreRuntime()
  T.check(ok, version .. " loader completes: " .. tostring(result))
  return loader
end

local function manifest(files, body)
  files["mods/s/manifest.json"] =
    '{"id":"s","name":"s","version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}'
  files["mods/s/main.lua"] = body
  files["mods/s/theme.ogg"] = "OggS"
end

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  GameVersion.set(version)
  CacheFs.prefix = GameVersion.cachePrefix(version)
  local files, data = {}, gen2Data()
  manifest(files, GEN2_BODY)
  local loader = load(files, data, version)
  local e = loader.exports.s or {}
  T.eq(e.done, true, version .. " mod body ran to the end")
  T.eq(e.theme, true, version .. " music registered")
  T.eq(e.patched, true, version .. " api 3 patch of battleScale/battleTheme accepted: " .. tostring(e.reason))
  T.eq(e.back, 1.5, version .. " get returns battleScaleBack at the top level")
  T.eq(e.front, 0.5, version .. " get returns battleScaleFront at the top level")
  T.eq(e.bgm, "FX_THEME", version .. " get returns battleTheme at the top level")
  T.eq(e.native, nil, version .. " battleScaleBack is not parked under native")
  T.eq(e.roundtrip, true, version .. " get then override round-trips")
  T.eq(e.after, 2, version .. " override changes battleScaleBack")
  T.eq(e.rangeOk, false, version .. " battleScaleBack 5 is rejected")
  T.eq(e.lowOk, false, version .. " battleScaleFront 0.1 is rejected")
  local mon = data.pokemon.FIXMON_A
  T.eq(mon.battleScaleBack, 2, version .. " merged back scale")
  T.eq(mon.battleScaleFront, 0.5, version .. " merged front scale")
  T.eq(mon.battleTheme, "FX_THEME", version .. " merged battleTheme")
  T.eq(data.pokemon.FIXMON_B.battleScaleBack, nil, version .. " rejected write left FIXMON_B alone")
  local state = setmetatable({ pokemon = data.pokemon, spriteScales = {} }, { __index = BattleState })
  state.imageScale = function() return nil end
  local live = { species = "FIXMON_A" }
  T.eq(state:picScale("back.png", live, true), 2, version .. " battle back pic uses the mod scale")
  T.eq(state:picScale("front.png", live, false), 0.5, version .. " battle front pic uses the mod scale")
  T.eq(state:picScale("front.png", { species = "FIXMON_B" }, false), 1, version .. " unpatched species stays 1x")
  T.eq(World.modBattleTheme({ game = { data = data } }, { wild = { species = "FIXMON_A" } }),
    "FX_THEME", version .. " wild battle music uses the mod theme")
end

GameVersion.set("firered")
CacheFs.prefix = GameVersion.cachePrefix("firered")
local g3 = T.sdk.gen3Data()
Schemas.bindGen3(g3, GameVersion.get())
local files = {}
manifest(files, GEN3_BODY)
local loader = load(files, g3, "firered")
local e = loader.exports.s or {}
T.eq(e.done, true, "firered mod body ran to the end")
for _, key in ipairs({ "battleScaleBack", "battleScaleFront", "battleTheme" }) do
  local row = e[key] or {}
  T.eq(row.ok, true, "firered " .. key .. " does not raise")
  T.eq(row.result, nil, "firered " .. key .. " is refused")
  T.eq(row.reason, "unsupported: " .. key .. " has no Gen 3 representation",
    "firered " .. key .. " refuse reason")
end

T.finish("unified gen2 battle scale")
