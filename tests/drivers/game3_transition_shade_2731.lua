local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or ".bazinga/BSA/10-07-26-00-userreported/shots/game3_transition_shade_2731"
local VERSION = os.getenv("POKEPORT_VERSION") or "emerald"

local function loadPng(path)
  local f = path and io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return love.image.newImageData(love.filesystem.newFileData(s, "x.png"))
end

local function diffCount(a, b)
  if not (a and b) then return -1 end
  local w, h = math.min(a:getWidth(), b:getWidth()), math.min(a:getHeight(), b:getHeight())
  local n = 0
  for y = 0, h - 1, 4 do
    for x = 0, w - 1, 4 do
      local r1, g1, b1 = a:getPixel(x, y)
      local r2, g2, b2 = b:getPixel(x, y)
      if math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2) > 0.06 then n = n + 1 end
    end
  end
  return n
end

local function grayShare(img)
  if not img then return 0 end
  local w, h = img:getWidth(), img:getHeight()
  local n, g = 0, 0
  for y = math.floor(h * 0.3), math.floor(h * 0.7), 4 do
    for x = math.floor(w * 0.3), math.floor(w * 0.7), 4 do
      local r, gg, b = img:getPixel(x, y)
      n = n + 1
      if math.max(r, gg, b) - math.min(r, gg, b) < 0.08 and r > 0.2 and r < 0.55 then g = g + 1 end
    end
  end
  return n > 0 and g / n or 0
end

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "NICK", gender = 0 })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local BT = require("src.core.game3.battle_transition")
  local Map = require("src.core.game3.map")
  local MapIds = require("src.core.game3.map_ids")
  local C = require("src.core.game3.constants").of(VERSION)
  local session = Runtime.getSession()
  local Ids = BT.ids()
  local rse = VERSION ~= "firered" and VERSION ~= "leafgreen"
  local W = rse and require("src.core.game3.field_weather_rse") or nil

  local cases
  if rse then
    cases = {
      { map = "MAP_ROUTE104", x = 20, y = 40, tid = "POKEBALLS_TRAIL", shade = false },
      { map = "MAP_PETALBURG_WOODS", x = 14, y = 32, tid = "POKEBALLS_TRAIL", shade = true },
      { map = "MAP_PETALBURG_WOODS", x = 14, y = 32, tid = "ANGLED_WIPES", shade = true },
      { map = "MAP_PETALBURG_WOODS", x = 14, y = 32, tid = "SLICE", shade = true },
      { map = "MAP_PETALBURG_WOODS", x = 14, y = 32, tid = "WHITE_BARS_FADE", shade = true },
      { map = "MAP_PETALBURG_WOODS", x = 14, y = 32, pick = "WHITE_BARS_FADE", lead = 5, foe = 6, shade = true },
      { map = "MAP_ROUTE120", x = 22, y = 61, tid = "POKEBALLS_TRAIL", rain = true },
      { map = "MAP_ROUTE120", x = 22, y = 61, tid = "WHITE_BARS_FADE", rain = true },
    }
  else
    cases = {
      { map = "MAP_ROUTE1", x = 10, y = 20, tid = "POKEBALLS_TRAIL" },
    }
  end

  for i, c in ipairs(cases) do
    local mapId = MapIds.forConst(c.map, VERSION)
    local tag = string.format("%s %s", c.map, c.tid or ("pick " .. c.pick))
    local stem = string.format("%s/2731_%02d_%s_%s_%s", DIR, i, VERSION, c.map:lower():gsub("^map_", ""),
      (c.tid or c.pick):lower())
    local ok, err = pcall(function() Map.load(nil, game, mapId, { x = c.x, y = c.y, facing = "down" }) end)
    result(ok and mapId ~= nil, "load " .. tag .. " " .. tostring(err or ""))
    U.wait(120)
    if c.rain then
      W.setNextWeather(W.WEATHER.RAIN)
    end
    U.wait(240)
    session.party = {}
    Party.giveMon(session, C.species.byName.SPECIES_MUDKIP, c.lead or 20, "MUDKIP")
    if W then
      local snap = W.snapshot()
      print(string.format("[driver] %s weather %s colorMapIndex %s", tag, tostring(snap.curr), tostring(snap.colorMapIndex)))
      if c.shade or c.rain then
        result(snap.colorMapIndex ~= 0, tag .. " weather color map active")
      end
    end
    local base = stem .. "_base.png"
    U.still(game, base)
    local opts = {}
    if c.tid then opts.transitionId = Ids.ID[c.tid] end
    BattleBridge.startWild(Runtime._mod, game, { species = C.species.byName.SPECIES_WURMPLE, level = c.foe or 5 }, opts)
    if c.pick then
      result(BT._transitionId == Ids.ID[c.pick], tag .. " level compare picked " .. c.pick
        .. " (got " .. tostring(BT._transitionId) .. ")")
    end
    local peakShot
    local mainShots = {}
    local frames, mainAt = 0, nil
    while frames < 900 do
      U.wait(1)
      frames = frames + 1
      if BT._phase == "intro" and BT._intro and BT._intro.blend >= 14 and not peakShot then
        peakShot = stem .. "_gray_flash.png"
        U.still(game, peakShot)
      end
      if BT._phase == "main" and not mainAt then mainAt = frames end
      if mainAt and (frames - mainAt == 8 or frames - mainAt == 20 or frames - mainAt == 32) then
        local p = string.format("%s_main_%02d.png", stem, frames - mainAt)
        U.still(game, p)
        mainShots[#mainShots + 1] = p
      end
      if Battle.isActive() then break end
    end
    local b = loadPng(base)
    local peakImg = loadPng(peakShot)
    local dPeak = diffCount(b, peakImg)
    local dMain, best = -1, nil
    for _, p in ipairs(mainShots) do
      local d = diffCount(b, loadPng(p))
      if d > dMain then dMain, best = d, p end
    end
    for _, p in ipairs(mainShots) do
      if p ~= best then os.remove(p) end
    end
    local gray = grayShare(peakImg)
    print(string.format("[driver] %s introDiff %d mainDiff %d grayShare %.2f", tag, dPeak, dMain, gray))
    result(dPeak > 2000, tag .. " intro flash visible (diff " .. dPeak .. ")")
    result(gray > 0.8, string.format("%s intro flash is gray (%.2f)", tag, gray))
    result(dMain > 2000, tag .. " main transition visible (diff " .. dMain .. ")")
    Battle.abort("run")
    for _ = 1, 600 do
      if not Battle.isActive() then break end
      U.wait(1)
    end
    U.wait(60)
  end
  love.event.quit(fails == 0 and 0 or 1)
end
