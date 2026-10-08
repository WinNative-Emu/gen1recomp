package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
love = require("tests.love_stub")
local T = require("tests.harness")
local clock = 300
love.timer.getTime = function() return clock end
local App = require("tools.save-editor.App")
local Ops, Gen, Kit = require("Ops"), require("Gen"), require("Kit")
local MapBrowser = require("MapBrowser")
local SD = require("src.core.SaveData")

T.check(type(MapBrowser.pointActions) == "function", "the map browser builds its own point buttons")
if type(MapBrowser.pointActions) == "function" then
  local function labels(actions)
    local out = {}
    for _, action in ipairs(actions) do out[#out + 1] = action.label end
    return table.concat(out, ",")
  end
  local g2 = { save = { generation = 2, spawn = "SPAWN_HOME", position = { map = "NEW_BARK_TOWN", x = 5, y = 5 } },
    mapId = "NEW_BARK_TOWN" }
  local a2 = MapBrowser.pointActions(g2, nil)
  T.eq(labels(a2), "Player,Spawn", "Gen 2 shows Player and Spawn")
  T.eq(a2[2].run, Ops.setLastHeal, "Gen 2 Spawn writes through Ops.setLastHeal")
  T.eq(a2[1].run, Ops.setPlayerHere, "Player writes through Ops.setPlayerHere")
  local g3 = { save = { generation = 3, healMap = "FR_PALLET_TOWN", healX = 1, healY = 2 }, mapId = "FR_PALLET_TOWN" }
  local a3 = MapBrowser.pointActions(g3, nil)
  T.eq(labels(a3), "Player,Heal", "Gen 3 shows Player and Heal")
  T.eq(a3[2].run, Ops.setLastHeal, "Gen 3 Heal writes through Ops.setLastHeal")
  T.check(not a3[2].enabled and a3[2].reason:find("FR_PALLET_TOWN (1,2)", 1, true),
    "with no cell the Gen 3 Heal button is off and says the current heal spot")
end

local path = os.tmpname() .. "-s8.lua"
local f = assert(io.open(path, "wb"))
f:write(SD.encode(Gen.newGame("red")))
f:close()
local loaded = pcall(App.load, path, { version = "red", embedded = true })
local S = App.getState()
if not loaded or not S or not S.save or S.missingCache or not (S.data.maps and S.data.maps.PALLET_TOWN) then
  os.remove(path)
  print("[skip] save_editor_map_point_buttons_s8: no red data")
  T.finish("save_editor_map_point_buttons_s8")
  return
end

local oldOS = love.system.getOS
local function frame(w, h, os, audit)
  love.graphics.getDimensions = function() return w, h end
  love.window.getSafeArea = function() return 0, 0, w, h end
  love.system.getOS = function() return os end
  clock = clock + .3
  Kit.audit = audit and {} or nil
  App.draw()
  local got = Kit.audit
  Kit.audit = nil
  return got
end
local function controls(audit, label)
  local out = {}
  for _, c in ipairs(audit or {}) do
    if c.class == "control" and c.label == label then out[#out + 1] = c end
  end
  return out
end
local function tap(x, y, shape)
  App.mousepressed(x, y, 1)
  frame(shape[1], shape[2], shape[3])
end

for _, shape in ipairs({ { 390, 844, "Android" }, { 1360, 860, "OS X" } }) do
  local name = shape[3]
  S.tab, S.mapFocused, S.navPopup, S.editPopup = "map", false, nil, nil
  S.mapSection = "spawn"
  S.save.lastHeal, S.save.lastOutdoor = nil, nil
  MapBrowser.select(S, "PALLET_TOWN")
  frame(shape[1], shape[2], shape[3])
  if S._mapStacked then
    T.eq(S.mapSection, "view", "a stale Spawn page falls back to the map view at " .. name)
  end
  local audit = frame(shape[1], shape[2], shape[3], true)
  T.eq(#controls(audit, "Set here"), 0, "no separate Set here card at " .. name)
  local r = S._mapViewRect
  local buttons = {}
  for _, label in ipairs({ "Player", "Heal", "Outdoor" }) do
    local c = controls(audit, label)[1]
    buttons[label] = c
    T.check(c ~= nil, label .. " button is on the map at " .. name)
    if c then
      T.check(r and c.x >= r.x and c.y >= r.y and c.x + c.w <= r.x + r.w and c.y + c.h <= r.y + r.h,
        label .. " sits inside the map viewport at " .. name)
      T.check(c.h >= Kit.tapMin() and c.w >= Kit.tapMin(), label .. " meets the tap minimum at " .. name)
    end
  end
  if buttons.Heal and r then
    local before = SD.encode(S.save)
    clock = clock + 10
    S.mapClickCell = nil
    tap(buttons.Heal.x + buttons.Heal.w / 2, buttons.Heal.y + buttons.Heal.h / 2, shape)
    T.eq(S.toast and S.toast.kind, "info", "Heal with no cell explains itself at " .. name)
    T.check(S.toast and S.toast.text:find("Tap a cell first", 1, true), "the reason names the missing cell at " .. name)
    T.eq(S.mapClickCell, nil, "a tap on a disabled button does not select the cell under it at " .. name)
    T.eq(SD.encode(S.save), before, "a disabled button writes nothing at " .. name)

    local map = require("src.world.MapLoader").load(S.data, "PALLET_TOWN")
    local pick
    for cy = map.heightCells - 2, 1, -1 do
      for cx = 1, map.widthCells - 2 do
        local sx = r.x + ((cx + 0.5) * 16 - S.mapCamX) * S.mapZoom
        local sy = r.y + ((cy + 0.5) * 16 - S.mapCamY) * S.mapZoom
        if not pick and not map:warpAtCell(cx, cy) and sx > r.x + 2 and sx < r.x + r.w - 2
          and sy > r.y + 2 and sy < r.y + r.h - 2 and not MapBrowser.insideOverlay(S, sx, sy) then
          pick = { cx = cx, cy = cy, x = sx, y = sy }
        end
      end
    end
    T.check(pick ~= nil, "a free cell is visible at " .. name)
    tap(pick.x, pick.y, shape)
    T.check(S.mapClickCell and S.mapClickCell.cx == pick.cx and S.mapClickCell.cy == pick.cy,
      "tapping the map selects a cell at " .. name)

    local function press(label)
      audit = frame(shape[1], shape[2], shape[3], true)
      local c = controls(audit, label)[1]
      clock = clock + 10
      tap(c.x + c.w / 2, c.y + c.h / 2, shape)
      T.check(S.mapClickCell and S.mapClickCell.cx == pick.cx and S.mapClickCell.cy == pick.cy,
        label .. " tap does not reselect the cell under the button at " .. name)
      T.eq(S.toast and S.toast.kind, "ok", label .. " raises a green toast at " .. name)
    end
    press("Heal")
    local heal = S.save.lastHeal
    T.check(heal and heal.map == "PALLET_TOWN" and heal.x == pick.cx and heal.y == pick.cy,
      "Heal writes lastHeal for the selected cell at " .. name)
    press("Player")
    local pm, px, py = Gen.playerMap(S.save)
    T.check(pm == "PALLET_TOWN" and px == pick.cx and py == pick.cy, "Player moves the player at " .. name)
    press("Outdoor")
    local out = S.save.lastOutdoor
    T.check(out and out.id == "PALLET_TOWN" and out.x == pick.cx and out.y == pick.cy,
      "Outdoor writes lastOutdoor for the selected cell at " .. name)
  end
end

do
  local shape = { 320, 568, "Android" }
  S.tab, S.mapFocused, S.mapSection = "map", false, "view"
  MapBrowser.select(S, "PALLET_TOWN")
  frame(shape[1], shape[2], shape[3])
  local audit = frame(shape[1], shape[2], shape[3], true)
  T.eq(S._mapActionsCompact, true, "a viewport too narrow for the labels falls back to icon-only buttons")
  local r = S._mapViewRect
  for _, label in ipairs({ "Player", "Heal", "Outdoor" }) do
    local c = controls(audit, label)[1]
    T.check(c ~= nil, label .. " stays reachable as a compact button")
    if c then
      T.check(r and c.x >= r.x and c.y >= r.y and c.x + c.w <= r.x + r.w and c.y + c.h <= r.y + r.h,
        label .. " compact button sits inside the map viewport")
      T.check(c.h >= Kit.tapMin() and c.w >= Kit.tapMin() and c.w == c.h, label .. " compact button is a tap-size square")
    end
  end
  local heal = controls(audit, "Heal")[1]
  if heal and r then
    S.mapClickCell = { cx = 3, cy = 3 }
    clock = clock + 10
    tap(heal.x + heal.w / 2, heal.y + heal.h / 2, shape)
    T.eq(S.toast and S.toast.kind, "ok", "the compact Heal button writes the heal spot")
    T.check(S.save.lastHeal and S.save.lastHeal.x == 3 and S.save.lastHeal.y == 3, "compact Heal writes the selected cell")
    T.check(S.mapClickCell and S.mapClickCell.cx == 3, "the compact tap does not fall through to the map")
  end
end

if S.data.maps.REDS_HOUSE_1F then
  local shape = { 390, 844, "Android" }
  MapBrowser.select(S, "REDS_HOUSE_1F")
  S.save.visited = {}
  S.mapClickCell = { cx = 2, cy = 2 }
  local audit = frame(shape[1], shape[2], shape[3], true)
  local c = controls(audit, "Outdoor")[1]
  T.check(c ~= nil, "Outdoor is shown on an indoor map")
  if c then
    local before = SD.encode(S.save)
    clock = clock + 10
    tap(c.x + c.w / 2, c.y + c.h / 2, shape)
    T.eq(S.toast and S.toast.kind, "error", "Outdoor on an indoor map is refused with a toast")
    T.eq(SD.encode(S.save), before, "the refused Outdoor writes nothing")
  end
end

love.system.getOS = oldOS
App.unload()
os.remove(path)
T.finish("save_editor_map_point_buttons_s8")
