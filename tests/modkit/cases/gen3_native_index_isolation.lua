package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Version = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Profile = require("src.core.game3.profile")

local function body(id, index)
  return ([[
local mod = ...
mod.content.pokemon:register("%s", {
  id = "%s", name = "%s", dex = 200, types = { "NORMAL" }, index = %d,
  spriteFront = "front.png", spriteBack = "back.png",
  baseStats = { hp = 60, attack = 70, defense = 65, speed = 75,
    specialAttack = 80, specialDefense = 80 },
  catchRate = 45, baseExp = 64, growthRate = "MEDIUM_FAST",
  level1Moves = {}, learnset = {}, evolutions = {}, tmhm = {} })
]]):format(id, id, id, index)
end

local function manifest(id)
  return ('{"id":"%s","name":"%s","version":"1.0.0","api":2,"games":["all"],"entry":"main.lua"}'):format(id, id)
end

Version.set("firered")
Versions.select("firered")
Profile.reset()
T.sdk.captureRuntime()
local files = {
  ["mods/a_good/manifest.json"] = manifest("a_good"),
  ["mods/a_good/main.lua"] = body("AAA_MON", 500),
  ["mods/b_clash/manifest.json"] = manifest("b_clash"),
  ["mods/b_clash/main.lua"] = body("CLASH_MON", 500),
  ["mods/c_reserved/manifest.json"] = manifest("c_reserved"),
  ["mods/c_reserved/main.lua"] = body("EGG_MON", 412),
  ["mods/d_after/manifest.json"] = manifest("d_after"),
  ["mods/d_after/main.lua"] = body("AFTER_MON", 501),
}
local data = T.sdk.gen3Data()
local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 3, version = "firered", dev = true })
local ok, loaded = pcall(loader.load, loader, data)
T.check(ok, "a bad native index does not abort the whole load: " .. tostring(loaded))
if ok then
  T.eq(loader.mods.a_good.failed, nil, "the first claimant of an index stays loaded")
  T.eq(loader.mods.b_clash.failed, true, "the colliding mod is the one that fails")
  T.eq(loader.mods.c_reserved.failed, true, "the reserved-index mod is the one that fails")
  T.eq(loader.mods.d_after.failed, nil, "an unrelated mod after the failures stays loaded")
  local named = {}
  for _, message in ipairs(loader.errors) do named[message:match("^[%w_]+")] = true end
  T.check(named.b_clash and named.c_reserved, "failures are reported through loader.errors by mod id")
  T.check(data.gen3Pokemon._names[500] ~= nil, "surviving mod's species reached the native tables")
  T.check(data.gen3Pokemon._names[501] ~= nil, "later surviving mod's species reached the native tables")
end
T.sdk.restoreRuntime()
T.finish("gen3 native index isolation")
