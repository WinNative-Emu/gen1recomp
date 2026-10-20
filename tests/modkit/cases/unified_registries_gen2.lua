package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local BattleTransition = require("src.ui.gen2.BattleTransition")

local BODY = [[
local mod = ...
mod.content.transitions:register("MOD_WIPE", { frames = 5, flash = false, draw = function(state, prog)
  mod.exports.drawn = (mod.exports.drawn or 0) + 1
  mod.exports.lastProg = prog
end })
mod.hooks:wrap("transition.style", function(nextLink, ctx)
  if ctx.trainer then return "MOD_WIPE" end
  return nextLink(ctx)
end)
]]

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local data = {}
  T.sdk.captureRuntime()
  local files = {
    ["mods/reg/manifest.json"] = '{"id":"reg","name":"reg","version":"1.0.0","api":2,"games":["all"],"entry":"main.lua"}',
    ["mods/reg/main.lua"] = BODY,
  }
  local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 2, version = version, dev = true })
  T.check(loader:load(data), version .. " loads with the transitions registry")
  T.same(loader.errors, {}, version .. " transitions is not reported unavailable")
  T.eq(type(data.transitions.MOD_WIPE), "table", version .. " mod transition merged")

  local game = { data = data, stack = { pop = function() end } }
  local done = false
  local trans = BattleTransition.new(game, { trainer = true, onDone = function() done = true end })
  T.eq(trans.style, "MOD_WIPE", version .. " the hook picks the mod style")
  T.check(trans.modDef ~= nil, version .. " the Gen 2 transition resolved the mod record")
  trans.phase = "flash"
  trans.frame = 0
  trans:update(0)
  T.eq(trans.phase, "outro", version .. " flash = false skips the flash")
  trans:update(0)
  trans:drawWidescreen(160, 144)
  T.check((loader.exports.reg.drawn or 0) >= 1, version .. " the mod style's draw runs in the outro")
  for _ = 1, 4 do trans:update(0) end
  T.check(trans.phase ~= "outro", version .. " the outro lasts the record's frames")
  local plain = BattleTransition.new(game, { trainer = false, enemyLevel = 1, playerLevel = 1 })
  T.eq(plain.style, "spin", version .. " other battles keep the cart outro")
  T.sdk.restoreRuntime()
end

T.finish("unified registries gen2")
