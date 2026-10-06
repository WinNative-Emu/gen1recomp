local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_shaderfx_showcase"

local PRESETS = {
  "gameboy-advance-dot-matrix", "lcd3x", "zfast-lcd", "sameboy-lcd", "retro-v3",
  "dot", "bevel", "simpletex_lcd", "pixel_transparency", "sunlight_shimmer",
  "lcd1x_psp", "gameboy-color-dot-matrix",
}

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_shaderfx_showcase failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  pcall(love.window.setMode, 1440, 960, { resizable = true })
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end

  local ShaderFX = require("src.render.ShaderFX")
  if #ShaderFX.list() == 0 and love.filesystem.getInfo("shaderfx_buildbot.zip") then
    ShaderFX.installDownloaded(false)
  end
  local byName = {}
  for _, e in ipairs(ShaderFX.list()) do byName[e.name] = e end
  local ready = {}
  for _, tag in ipairs(PRESETS) do
    local e = byName[tag .. ".slangp"]
    if e then
      if not e.converted then ShaderFX.convert(e) end
      ready[#ready + 1] = { tag = tag, entry = e }
    end
  end
  if not check(#ready >= 8, "at least 8 presets ready (" .. #ready .. ")") then return finish() end

  game:_handleBootAction({ action = "new_game", name = "MAY", gender = 1 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Party = require("src.core.game3.party")
  local Weather = require("src.core.game3.weather")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Message = require("src.ui.game3.message")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field session") then return finish() end
  local function sp(name) return C.species.byName["SPECIES_" .. name] end

  session.party = {}
  Party.giveMon(session, sp("TORCHIC"), 20, "TORCHIC")
  local m = session.party[1]
  m.hp = m.maxHp or m.hp

  local function load(id, x, y)
    local ok, err = pcall(function() Map.load(nil, game, id, { x = x, y = y, facing = "down" }) end)
    check(ok, "load " .. id .. " " .. tostring(err or ""))
    U.wait(90)
    for _ = 1, 300 do
      if not (Message.isOpen and Message.isOpen()) then break end
      U.tap(game, "b")
    end
  end

  local function sweep(scene)
    ShaderFX.deactivate()
    U.wait(4)
    U.shot(game, ("%s/none_%s.png"):format(DIR, scene))
    for _, r in ipairs(ready) do
      local ok = ShaderFX.activate("main", r.entry)
      if check(ok, r.tag .. " on " .. scene) then
        U.wait(6)
        U.shot(game, ("%s/%s_%s.png"):format(DIR, r.tag, scene))
      end
    end
    ShaderFX.deactivate()
  end

  load("EM_LITTLEROOT_TOWN", 10, 10)
  sweep("town")

  load("EM_ROUTE117", 32, 15)
  sweep("route_grass")

  Weather.set(Weather.RAIN)
  Weather.doWeather()
  U.wait(240)
  sweep("route_rain")
  Weather.set(Weather.NONE)
  Weather.doWeather()
  U.wait(60)

  load("EM_ROUTE113", 30, 8)
  U.wait(120)
  sweep("route_ash")

  load("EM_ROUTE117", 32, 15)
  local ok = BattleBridge.startWild(Runtime._mod, game, { species = sp("ODDISH"), level = 14 }, {})
  if check(ok == true, "wild battle started") then
    local lastTap = 0
    for f = 1, 8000 do
      if Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu" then break end
      if Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14 then
        lastTap = f
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    U.wait(30)
    check(Battle.isActive(), "battle on screen")
    sweep("battle")
    Battle.abort("run")
    for _ = 1, 600 do
      if not Battle.isActive() then break end
      U.wait(1)
    end
    U.wait(90)
  end

  load("EM_LITTLEROOT_TOWN", 10, 10)
  U.tap(game, "start")
  U.wait(30)
  sweep("start_menu")
  U.tap(game, "b")
  U.wait(20)

  local Option = require("src.ui.game3.screens").get("option", session)
  Option.show({ session = session, game = game })
  U.wait(40)
  sweep("option_menu")
  if Option.close then Option.close() end
  U.wait(10)
  finish()
end
