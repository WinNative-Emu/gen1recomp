package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Version = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Profile = require("src.core.game3.profile")
local UnifiedContent = require("src.mods.UnifiedContent")

local function load(version, generation, body)
  Version.set(version)
  if generation == 3 then
    Versions.select(version)
    Profile.reset()
  end
  T.sdk.captureRuntime()
  local files = {
    ["mods/d/manifest.json"] = '{"id":"d","name":"d","version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}',
    ["mods/d/main.lua"] = "local mod = ...\n" .. body,
  }
  local data = generation == 3 and T.sdk.gen3Data() or {}
  local loader = Loader.new({ fs = T.sdk.memfs(files), generation = generation, version = version, dev = true })
  local ok = loader:load(data)
  local errors = table.concat(loader.errors, " | ")
  T.sdk.restoreRuntime()
  return ok, errors, data
end

for _, case in ipairs({
  { "gold", 2, { "sprites", "palettes", "battle_anims", "icons", "balls" } },
  { "crystal", 2, { "sprites", "palettes", "battle_anims", "icons", "balls" } },
  { "firered", 3, { "balls", "battle_anims" } },
  { "emerald", 3, { "balls", "battle_anims" } },
}) do
  for _, name in ipairs(case[3]) do
    local ok, reason = UnifiedContent.supports(name, case[2], case[1])
    T.check(ok == true, case[1] .. " API 3 supports " .. name .. " " .. tostring(reason))
  end
end

local ok, errors, data = load("gold", 2, [[
mod.content.sprites:register("API3_NPC", { image = "n.png", frames = 6, walker = true })
mod.content.palettes:patch("trainers", { MODTRAINER = {
  { 255, 255, 255 }, { 200, 200, 200 }, { 100, 100, 100 }, { 0, 0, 0 } } })
mod.content.battle_anims:patch("objects", { MODOBJ = {
  gfx = "G", palette = "P", frameset = "F", func = "U" } })
mod.content.icons:register("ICON_MODSHEET", { image = "i.png", width = 16, height = 32, frames = 2 })
]])
T.check(ok, "an API 3 mod writes Gold registries: " .. errors)
T.check(data.gen2Sprites and data.gen2Sprites.API3_NPC ~= nil, "Gold sprites record merged")
T.check(data.gen2Palettes and data.gen2Palettes.trainers and data.gen2Palettes.trainers.MODTRAINER ~= nil,
  "Gold palette row merged")
T.check(data.gen2BattleAnims and data.gen2BattleAnims.objects and data.gen2BattleAnims.objects.MODOBJ ~= nil,
  "Gold battle animation object merged")
T.check(data.gen2Icons ~= nil, "Gold icon sheet merged")

for _, version in ipairs({ "firered", "emerald" }) do
  local okF, errF, dataF = load(version, 3, [[
mod.content.balls:register("MOD_BALL", { multiplier = 25 })
mod.content.battle_anims:register("SHADOW_BALL", { seq = { 1, 2 } })
]])
  T.check(okF, "an API 3 mod writes " .. version .. " balls and battle_anims: " .. errF)
  T.check(dataF.balls and dataF.balls.MOD_BALL ~= nil, version .. " ball record merged")
  T.check(dataF.gen3BattleAnims ~= nil, version .. " battle animation merged")
end
T.finish("unified registry writes")
