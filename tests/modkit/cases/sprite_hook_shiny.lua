package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local GameVersion = require("src.core.GameVersion")
local Sprites = require("src.pokemon.Sprites")

local BODY = [[
local mod = ...
local Stats = require("src.pokemon.Stats")
mod.hooks:wrap("pokemon.sprite", function(next, path, ctx)
  mod.exports.seen = { shiny = ctx.shiny, monShiny = ctx.mon and ctx.mon.shiny,
    isShiny = ctx.mon and Stats.isShiny(ctx.mon.dvs) }
  return next(path, ctx)
end)
]]

local originalVersion = GameVersion.get()
local DVS = { attack = 10, defense = 10, speed = 10, special = 10 }
local PLAIN = { attack = 1, defense = 1, speed = 1, special = 1 }

for _, case in ipairs({ { 1, "red" }, { 2, "gold" } }) do
  local generation, version = case[1], case[2]
  for _, api in ipairs({ 1, 3 }) do
    local label = ("%s api %d"):format(version, api)
    GameVersion.set(version)
    T.sdk.captureRuntime()
    local files = {
      ["mods/m/manifest.json"] = ('{"id":"m","name":"m","version":"1.0.0","api":%d,'
        .. '"games":["all"],"entry":"main.lua"}'):format(api),
      ["mods/m/main.lua"] = BODY,
    }
    local loader = Loader.new({ fs = T.sdk.memfs(files), generation = generation,
      version = version, dev = true })
    local data = { pokemon = { PIDGEY = { id = "PIDGEY", spriteFront = "f.png",
      spriteBack = "b.png", types = { "NORMAL" },
      baseStats = { hp = 1, attack = 1, defense = 1, speed = 1, special = 1 } } },
      moves = {}, items = {}, maps = {}, text = {}, trainers = {}, encounters = {},
      type_chart = { types = {}, matchups = {} } }
    loader.game = { data = data, generation = generation, phase = "field" }
    T.check(pcall(loader.load, loader, data), label .. " loads")
    local out = loader.exports.m
    for _, shiny in ipairs({ true, false }) do
      local mon = { species = "PIDGEY", level = 5, hp = 10, maxHp = 10,
        dvs = shiny and DVS or PLAIN, stats = { hp = 10, attack = 1, defense = 1,
        speed = 1, special = 1 }, moves = {} }
      if generation == 2 then mon.shiny = shiny end
      out.seen = nil
      if generation == 1 then
        Sprites.path(data, "PIDGEY", "front", { mon = mon, kind = "battle" })
      else
        Sprites.pic("f.png", { species = "PIDGEY", side = "front", kind = "battle",
          mon = mon, shiny = shiny, data = data })
      end
      local tag = label .. (shiny and " shiny" or " plain")
      T.check(out.seen ~= nil, tag .. " hook fires")
      if out.seen then
        T.eq(out.seen.shiny, shiny, tag .. " ctx.shiny")
        if api == 3 then T.eq(out.seen.monShiny, shiny, tag .. " ctx.mon.shiny") end
        T.eq(out.seen.isShiny, shiny, tag .. " Stats.isShiny(ctx.mon.dvs)")
      end
    end
    T.sdk.restoreRuntime()
  end
end

GameVersion.set(originalVersion)
T.finish("sprite_hook_shiny")
