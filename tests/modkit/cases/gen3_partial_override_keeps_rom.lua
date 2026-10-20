package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Version = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Profile = require("src.core.game3.profile")
local Schemas = require("src.mods.Schemas")

local BODY = [[
local mod = ...
mod.content.pokemon:override("CHARMANDER", {
  id = "CHARMANDER", name = "CHARMANDER", types = { "FIRE" },
  baseStats = { hp = 99, attack = 52, defense = 43, speed = 65,
    specialAttack = 60, specialDefense = 50 },
  catchRate = 45, baseExp = 65, growthRate = "MEDIUM_SLOW",
  spriteFront = "front.png", spriteBack = "back.png",
  learnset = {}, evolutions = {} })
mod.content.moves:override("SCRATCH", {
  id = "SCRATCH", name = "SCRATCH", type = "NORMAL",
  power = 41, accuracy = 100, pp = 35 })
]]

Version.set("firered")
Versions.select("firered")
Profile.reset()
T.sdk.captureRuntime()
local files = {
  ["mods/partial/manifest.json"] = '{"id":"partial","name":"partial","version":"1.0.0","api":2,"games":["all"],"entry":"main.lua"}',
  ["mods/partial/main.lua"] = BODY,
}
local data = T.sdk.gen3Data()
local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 3, version = "firered", dev = true })
local ok, err = pcall(loader.load, loader, data)
T.check(ok, "partial overrides load: " .. tostring(err))
local mons = data.gen3Pokemon
T.eq(mons._stats[4].hp, 99, "the field the mod set is written")
T.eq(mons._speciesMeta[4].genderRatio, 31, "ROM gender ratio survives a partial override")
T.eq(mons._speciesMeta[4].friendship, 70, "ROM friendship survives a partial override")
T.eq(mons._speciesMeta[4].eggCycles, 20, "ROM egg cycles survive a partial override")
T.eq(mons._speciesMeta[4].eggGroup1, 1, "ROM egg group survives a partial override")
T.check(mons._abilities[4] ~= nil and mons._abilities[4][1] == 66, "ROM abilities survive a partial override")
T.check(mons._eggMoves[4] ~= nil and mons._eggMoves[4][1] == 57, "ROM egg moves survive a partial override")
T.check(mons._dex[4] ~= nil and mons._dex[4].category == "LIZARD", "ROM dex entry survives a partial override")
local row = data.gen3Moves._rom[10]
T.eq(row.power, 41, "the move field the mod set is written")
T.eq(row.accuracy, 100, "ROM move accuracy survives a partial override")
T.eq(row.priority, 0, "ROM move priority survives a partial override")
T.eq(row.flags, 0, "ROM move flags survive a partial override")
T.eq(row.secondaryChance, 0, "ROM secondary chance survives a partial override")

local leaked = {}
for name, spec in pairs(Schemas.REGISTRIES) do
  for _, shape in ipairs({ spec.fields or {}, spec.gen3Fields or {} }) do
    for field in pairs(shape) do
      if type(field) == "string" and field:sub(1, 1) == "_" then leaked[#leaked + 1] = name .. "." .. field end
    end
  end
end
local doc = io.open("docs/modding/reference/registries.md", "r")
local text = doc and doc:read("*a") or ""
if doc then doc:close() end
for _, key in ipairs(leaked) do
  local field = key:match("%.(.+)$")
  T.check(not text:find("| `" .. field .. "` |", 1, true), "internal field " .. key .. " stays out of the generated docs")
end
T.sdk.restoreRuntime()
T.finish("gen3 partial override keeps ROM fields")
