local U = require("tests.drivers.util")
local Loader = require("src.mods.Loader")
local Sdk = require("tests.modkit.sdk")
local Mon = require("src.battle.gen2.Mon")

local hostVisible = love.visible
love.visible = function(v) if hostVisible then pcall(hostVisible, v) end end

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
local ok, reason = mod.content.pokemon:patch("CYNDAQUIL", { battleScaleBack = 1.5 })
mod.exports.patched, mod.exports.reason = ok ~= nil, reason
mod.exports.back = (mod.content.pokemon:get("CYNDAQUIL") or {}).battleScaleBack]],
  }
  local loader = Loader.new({ fs = Sdk.memfs(files), generation = 2,
    version = game.save.version, dev = true })
  loader.game = game
  local data = {}
  for key, value in pairs(game.data) do data[key] = value end
  for key in pairs(require("src.mods.Builtins").namespaceRoots(2)) do data[key] = nil end
  loader:load(data)
  local probe = loader.mods.probe
  local out = loader.exports.probe or {}
  if not check(probe and not probe.failed and out.patched == true,
      "3049_api3_patch_accepted " .. tostring(out.reason)) then
    love.event.quit(1)
    return
  end
  check(out.back == 1.5, "3049_get_returns_back_scale")
  game.data.pokemon = data.pokemon
  check(game.data.pokemon.CYNDAQUIL.battleScaleBack == 1.5, "3049_merged_back_scale")

  game.save.party = { Mon.new(game.data, "CYNDAQUIL", 30) }
  if not check(game.world:startBattle({ wild = Mon.new(game.data, "PIDGEY", 5) }),
      "3049_battle_started") then
    love.event.quit(1)
    return
  end
  local battle
  for _ = 1, 900 do
    local top = game.stack:top()
    if top and top.battle then battle = top break end
    U.wait(1)
  end
  if not check(battle ~= nil, "3049_battle_screen") then
    love.event.quit(1)
    return
  end
  for _ = 1, 400 do
    if battle.phase == "menu" or battle.battle.over then break end
    U.tap(game, "a")
    U.wait(2)
  end
  check(battle.phase == "menu", "3049_reached_menu")
  local player = battle.battle.player
  check(player and player.species == "CYNDAQUIL"
    and battle:picScale("player_back", player, true) == 1.5, "3049_back_pic_scale_1_5")
  check(battle:picScale("enemy_front", { species = "PIDGEY" }, false) == 1, "3049_front_pic_default")
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2_mod_battle_scale_3049"
  check(U.still(game, dir .. "/3049_01_scaled_back_pic.png"), "3049_scaled_back_shot")
  love.event.quit(failures == 0 and 0 or 1)
end
