package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")
local Records = require("src.mods.UnifiedRecords")

package.loaded["src.core.game3.runtime"] = { getSession = function() return nil end }

local Pokemon = require("src.core.game3.pokemon")
local vanilla = { image = "vanilla", w = 64, h = 64 }
Pokemon.frontPic = function() return vanilla end
Pokemon.frontSprite = Pokemon.frontPic
Pokemon.backPic = function() return vanilla end
Pokemon.icon = function() return nil end
Pokemon.name = function() return "PIKACHU" end
Pokemon.speciesFromName = function() return nil end

local Gen3Compat = require("src.mods.Gen3Compat")
local game = { phase = "field", data = {}, mods = { content = {} } }
Gen3Compat.bind(function() return game end)

Runtime.hooks = Hooks.new()
Gen3Compat.applyMerged(game)

local seen
Runtime.hooks:wrap("pokemon.sprite", function(next, path, ctx)
  seen = ctx
  return next(path, ctx)
end)

local shinyMon = { species = 25, personality = 0, otId = 0, otSecretId = 0, level = 5 }
local plainMon = { species = 25, personality = 0x12345678, otId = 0x9abcdef0, otSecretId = 0, level = 5 }

for _, case in ipairs({ { "front", Pokemon.monFrontPic }, { "back", Pokemon.monBackPic } }) do
  for _, row in ipairs({ { shinyMon, true }, { plainMon, false } }) do
    local mon, shiny = row[1], row[2]
    seen = nil
    case[2](mon, nil, "summary")
    local tag = case[1] .. (shiny and " shiny" or " plain")
    T.check(seen ~= nil, tag .. " hook fires")
    T.eq(seen and seen.shiny, shiny, tag .. " ctx.shiny")
    T.check(seen and seen.mon == mon, tag .. " ctx.mon is the mon")
    local view = seen and seen.mon and Records.mon(seen.mon, 3, {}, "firered")
    T.eq(view and view.shiny, shiny, tag .. " api 3 ctx.mon.shiny")
  end
end

seen = nil
Pokemon.frontPic(25, nil, nil, nil, "credits")
T.eq(seen and seen.mon, nil, "a species-only pic has no mon")
T.eq(seen and seen.shiny, false, "a species-only pic is not shiny")

T.finish("gen3 pokemon.sprite ctx.mon and ctx.shiny")
