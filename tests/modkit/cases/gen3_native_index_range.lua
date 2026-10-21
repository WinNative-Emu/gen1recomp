package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Version = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Profile = require("src.core.game3.profile")

local function body(index)
  return ([[
local mod = ...
mod.content.pokemon:register("BIGMON", {
  id = "BIGMON", name = "BIGMON", dex = 200, types = { "NORMAL" }, index = %d,
  spriteFront = "front.png", spriteBack = "back.png",
  baseStats = { hp = 60, attack = 70, defense = 65, speed = 75,
    specialAttack = 80, specialDefense = 80 },
  catchRate = 45, baseExp = 64, growthRate = "MEDIUM_FAST",
  level1Moves = {}, learnset = {}, evolutions = {}, tmhm = {} })
]]):format(index)
end

for _, api in ipairs({ 2, 3 }) do
  for _, case in ipairs({ { 1023, true }, { 1024, true }, { 1500, true }, { 65535, true }, { 65536, false } }) do
    local index, accepted = case[1], case[2]
    local label = ("api %d index %d"):format(api, index)
    Version.set("firered")
    Versions.select("firered")
    Profile.reset()
    T.sdk.captureRuntime()
    local files = {
      ["mods/m/manifest.json"] = ('{"id":"m","name":"m","version":"1.0.0","api":%d,'
        .. '"games":["all"],"entry":"main.lua"}'):format(api),
      ["mods/m/main.lua"] = body(index),
    }
    local data = T.sdk.gen3Data()
    local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 3,
      version = "firered", dev = true })
    local ok = pcall(loader.load, loader, data)
    T.check(ok, label .. " load completes")
    T.eq(loader.mods.m.failed == nil, accepted, label .. (accepted and " is accepted" or " is rejected"))
    T.eq(data.gen3Pokemon._names[index] ~= nil, accepted, label .. " reaches the native tables only when accepted")
    T.sdk.restoreRuntime()
  end
end

T.finish("gen3 native index range")
