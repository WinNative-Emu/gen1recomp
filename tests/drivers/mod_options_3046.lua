local U = require("tests.drivers.util")
local Loader = require("src.mods.Loader")
local Sdk = require("tests.modkit.sdk")
local Manager = require("src.mods.ManagerState")
local Version = require("src.core.GameVersion")

return function(game)
  U.wait(45)
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local generation = Version.generation()
  if generation == 3 then
    for _ = 1, 900 do
      if game.phase == "boot" and game.boot then break end
      U.wait(1)
    end
    if not check(game.boot ~= nil, "3046_boot_reached") then
      love.event.quit(1)
      return
    end
    game:_handleBootAction({action="new_game",name="RED"})
    for _ = 1, 600 do
      if game.phase == "field" then break end
      U.wait(1)
    end
    if not check(game.phase == "field", "3046_field_reached") then
      love.event.quit(1)
      return
    end
  end
  local files = {
    ["mods/settings/manifest.json"] = '{"id":"settings","name":"Deferred settings",'
      .. '"version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}',
    ["mods/settings/main.lua"] = [[local mod = ...
mod.events:on("mods.loaded", function(event)
  local choices = {{"NONE", "NONE"}}
  for id in pairs(event.loader.exports) do
    local pack = mod.find(id)
    if pack.exports.isSpritePack then
      choices[#choices + 1] = {pack.exports.packLabel, id}
    end
  end
  mod.options:define({{key="pack",label="SPRITE PACK",type="choice",
    default="NONE",choices=choices}})
end)
mod.exports.value = function() return mod.options:get("pack") end]],
    ["mods/pack/manifest.json"] = '{"id":"pack","name":"Pack",'
      .. '"version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}',
    ["mods/pack/main.lua"] = [[local mod = ...
mod.exports.isSpritePack, mod.exports.packLabel = true, "CUSTOM"]],
  }
  local loader = Loader.new({fs=Sdk.memfs(files),generation=generation,version=Version.get()})
  loader.game = game
  local data = {}
  for key, value in pairs(game.data) do data[key] = value end
  for key in pairs(require("src.mods.Builtins").namespaceRoots(generation)) do data[key] = nil end
  loader:load(data)
  game.mods = loader
  local manager
  if generation == 3 then
    local Menu = require("src.ui.game3.mod_manager")
    Menu.show({game=game,session=game.session})
    manager = Menu._mgr
  else
    manager = Manager.new(game)
    game.stack:push(manager)
  end
  manager.currentMod = manager.byId.settings
  manager:goTo("detail")
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/mod_options_3046"
  local options
  for _, row in ipairs(manager:detailRows(manager.currentMod)) do
    if row.label == "OPTIONS.." then options = row end
  end
  check(U.still(game, dir .. "/3046_detail_options.png"), "3046_detail_shot")
  if check(options ~= nil, "3046_deferred_options_visible") then
    options.action()
    check(manager.screen == "options", "3046_options_open")
    manager.optionRows[1].step(manager.game, 1)
    check(loader.exports.settings.value() == "pack", "3046_mod_reads_selection")
    check(U.still(game, dir .. "/3046_custom_pack_selected.png"), "3046_options_shot")
    manager:goBack()
    manager:openOptions(manager.currentMod)
    check(manager.optionRows[1].value() == "CUSTOM", "3046_selection_reopens")
  end
  love.event.quit(failures == 0 and 0 or 1)
end
