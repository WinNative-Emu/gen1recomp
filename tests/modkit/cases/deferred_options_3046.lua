package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Sdk = require("tests.modkit.sdk")
local Loader = require("src.mods.Loader")
local Manager = require("src.mods.ManagerState")
local Version = require("src.core.GameVersion")
local originalVersion = Version.get()

for _, version in ipairs({"red", "gold", "firered"}) do
  Version.set(version)
  local generation = Version.generation()
  local files = {
    ["mods/settings/manifest.json"] = '{"id":"settings","name":"Settings",'
      .. '"version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}',
    ["mods/settings/main.lua"] = [[local mod = ...
mod.events:on("mods.loaded", function(event)
  local choices = {{"NONE", "NONE"}}
  for id in pairs(event.loader.exports) do
    local other = mod.find(id)
    if other.exports.isSpritePack then
      choices[#choices + 1] = {other.exports.packLabel, id}
    end
  end
  mod.exports.narrow = event.loader._loadMod == nil and event.loader.fs == nil
  event.loader.exports.pack = nil
  mod.options:define({{key="pack", label="SPRITE PACK", type="choice",
    default="NONE", choices=choices}})
end)
mod.exports.value = function() return mod.options:get("pack") end]],
    ["mods/pack/manifest.json"] = '{"id":"pack","name":"Pack",'
      .. '"version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}',
    ["mods/pack/main.lua"] = [[local mod = ...
mod.exports.isSpritePack, mod.exports.packLabel = true, "CUSTOM"]],
  }
  local data = generation == 3 and Sdk.gen3Data()
    or require("tests.modkit.fixtures").fresh()
  local loader = Loader.new({fs=Sdk.memfs(files), generation=generation, version=version})
  local game = {data=data, mods=loader, save={version=version, options={}}}
  loader.game = game
  loader:load(data)
  local manager = Manager.new(game)
  manager:refresh()
  local mod = manager.byId.settings
  local options
  for _, row in ipairs(manager:detailRows(mod)) do
    if row.label == "OPTIONS.." then options = row end
  end
  T.check(options ~= nil, version .. " deferred OPTIONS row")
  T.check(loader.exports.pack ~= nil, version .. " export map is isolated")
  T.eq(loader.exports.settings.narrow, true, version .. " no native loader internals")
  T.eq(loader.exports.settings.value(), "NONE", version .. " deferred option default")
  if options then
    manager.currentMod = mod
    options.action()
    T.eq(manager.screen, "options", version .. " opens deferred settings")
    T.eq(manager.optionRows[1].value(), "NONE", version .. " renders default")
    manager.optionRows[1].step(game, 1)
    T.eq(loader.exports.settings.value(), "pack", version .. " selected pack reaches mod")
    T.eq(game.save.options.modOptions.settings.pack, "pack", version .. " selected pack persists")
    manager:openOptions(mod)
    T.eq(manager.optionRows[1].value(), "CUSTOM", version .. " reopened selected pack")
  end
end

Version.set(originalVersion)
T.finish()
