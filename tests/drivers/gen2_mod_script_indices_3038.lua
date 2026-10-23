local U = require("tests.drivers.util")
local Loader = require("src.mods.Loader")
local Sdk = require("tests.modkit.sdk")

return function(game)
  U.wait(45)
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local files = {
    ["mods/probe/manifest.json"] = '{"id":"probe","name":"probe","version":"1.0.0",'
      .. '"api":3,"games":["all"],"entry":"main.lua"}',
    ["mods/probe/main.lua"] = [[local mod = ...
local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}; for k, row in pairs(v) do out[k] = copy(row) end; return out
end
local move = copy(mod.content.moves:get("TACKLE"))
move.id, move.name, move.index, move.native = "BSA_INDEX_MOVE", "INDEX HIT", 512, nil
mod.content.moves:register(move.id, move)
local mon = copy(mod.content.pokemon:get("CYNDAQUIL"))
mon.id, mon.name, mon.index, mon.native = "BSA_INDEX_MON", "INDEX MON", 512, nil
mon.level1Moves = { "BSA_INDEX_MOVE" }
mon.learnset = {}
mod.content.pokemon:register(mon.id, mon)
mod.content.items:register("BSA_INDEX_ITEM", { name = "INDEX ITEM", price = 1, index = 512 })]],
  }
  local loader = Loader.new({ fs = Sdk.memfs(files), generation = 2,
    version = game.save.version, dev = true })
  loader.game = game
  local data = {}
  for key, value in pairs(game.data) do data[key] = value end
  for key in pairs(require("src.mods.Builtins").namespaceRoots(2)) do data[key] = nil end
  loader:load(data)
  if not check(not loader.mods.probe.failed, "3038_fixture_registered") then
    love.event.quit(1)
    return
  end
  local world, vm = game.world, game.world.vm
  world:warpToMapId("ELMS_LAB", 4, 4, "down")
  U.wait(15)
  vm = world.vm
  check(vm.getMonNameFn(512) == "INDEX MON", "3038_getmonname")
  game.save.party = {}
  local mon = vm.givePokeFn(512, 5, 0, { nickname = "INDEX" })
  check(mon and mon.species == "BSA_INDEX_MON", "3038_givepoke")
  check(mon and mon.moves[1] and mon.moves[1].id == "BSA_INDEX_MOVE", "3038_mod_move")
  game.save.inventory.BSA_INDEX_ITEM = nil
  vm.giveItemFn(512, 2)
  check(game.save.inventory.BSA_INDEX_ITEM == 2, "3038_giveitem")
  world:showPokePic(512)
  check(world.pokePic ~= nil and world.pokePicName == "BSA_INDEX_MON", "3038_pokepic")
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2_mod_script_indices_3038"
  check(U.still(game, dir .. "/3038_mod_species_pokepic.png"), "3038_pokepic_shot")
  world.pokePic = nil
  local Save = require("src.save_convert.Gen2Save")
  check(not pcall(Save.util.indexOf, { BSA_INDEX_MON = 512 }, "BSA_INDEX_MON", "species"),
    "3038_cartridge_export_refused")
  love.event.quit(failures == 0 and 0 or 1)
end
