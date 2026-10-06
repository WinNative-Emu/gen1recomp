local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_shaderfx_shots"
local ONLY = os.getenv("GAME3_SHADERFX_ONLY")

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " game3_shaderfx_shots failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then print("[driver] " .. label .. " error: " .. tostring(err)) end
  return ok
end

local function settle(game)
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  for _ = 1, 600 do
    local busy = Warp.isBusy() or (Message.isOpen and Message.isOpen())
    if not busy then break end
    if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
    U.wait(1)
  end
end

local function goTo(game, const, x, y)
  local MapIds = require("src.core.game3.map_ids")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Runtime = require("src.core.game3.runtime")
  local mapId = MapIds.forConst(const)
  settle(game)
  try("Map.load " .. tostring(mapId), function()
    Map.load(nil, game, mapId, { x = x, y = y, facing = "down" })
  end)
  local s = Runtime.getSession()
  if s then s.x, s.y, s.facing = x, y, "down" end
  Player.cellX, Player.cellY = x, y
  Player.px, Player.py = x * 16, y * 16
  Player.targetX, Player.targetY = x, y
  Player.facing = "down"
  U.wait(60)
  settle(game)
  return mapId
end

local function fakeInput(key)
  return { wasPressed = function(_, k) return k == key end }
end

return function(game)
  local GameVersion = require("src.core.GameVersion")
  local Profile = require("src.core.game3.profile")
  local ShaderFX = require("src.render.ShaderFX")
  local version = GameVersion.get()
  local out = DIR .. "/" .. version

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, version .. " boot reached") then return finish() end

  if #ShaderFX.list() == 0 and love.filesystem.getInfo("shaderfx_buildbot.zip") then
    local copied, err = ShaderFX.installDownloaded(false)
    print("[driver] installDownloaded copied=" .. tostring(copied) .. " err=" .. tostring(err))
  end
  local list = ShaderFX.list()
  if not check(#list > 0, version .. " presets on disk (" .. #list .. ")") then return finish() end
  check(ShaderFX.canConvert(), version .. " librashader bridge loads")

  try("new_game", function()
    game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
  end)
  U.wait(60)
  local rse = Profile.family() == "rse"
  goTo(game, rse and "MAP_LITTLEROOT_TOWN" or "MAP_PALLET_TOWN", 10, 10)

  ShaderFX.deactivate()
  U.wait(10)
  U.shot(game, out .. "/00-none.png")

  local converted = 0
  for i, entry in ipairs(list) do
    local tag = entry.name:gsub("%.slangp$", "")
    if not ONLY or tag:find(ONLY, 1, true) then
      if not entry.converted then ShaderFX.convert(entry) end
      local ok, err = ShaderFX.activate("main", entry)
      if check(ok, version .. " activate " .. tag .. (ok and "" or (": " .. tostring(err)))) then
        converted = converted + 1
        U.wait(8)
        U.shot(game, ("%s/%02d-%s.png"):format(out, i, tag))
        check(ShaderFX.active("main"), version .. " " .. tag .. " survived a rendered frame")
        ShaderFX.deactivate("main")
      end
    end
  end
  check(converted > 0, version .. " at least one preset rendered")

  local byName = {}
  for _, e in ipairs(list) do byName[e.name] = e end
  local a, b = byName["gameboy-advance-dot-matrix.slangp"], byName["lcd1x.slangp"]
  if a and b then
    ShaderFX.activate("main", a)
    ShaderFX.activate("secondary", b)
    U.wait(8)
    U.shot(game, out .. "/90-stacked-gba-dot-matrix-over-lcd1x.png")
    check(ShaderFX.active("main") and ShaderFX.active("secondary"), version .. " stacked slots render")
    ShaderFX.deactivate("secondary")
  end

  if a then
    game.options.shaderfx = a.name
    game:applyOptions(game.options)
    check(ShaderFX.activeEntry("main") ~= nil, version .. " applyOptions restores options.shaderfx")
    local Zoom = require("src.render.Zoom")
    local Renderer = require("src.render.Renderer")
    Zoom.allowSurvey = true
    Zoom.offset = -1
    U.wait(10)
    U.shot(game, out .. "/91-survey-zoom-gba-dot-matrix.png")
    Zoom.offset = 0
    U.wait(4)
    local Tilt = require("src.render.Tilt")
    Tilt.setLevel(2)
    for _ = 1, 20000 do
      if Tilt.t >= 1 then break end
      U.wait(1)
    end
    U.wait(4)
    U.shot(game, out .. "/92-tilt-gba-dot-matrix.png")
    Tilt.setLevel(0)
    for _ = 1, 20000 do
      if Tilt.t >= 1 then break end
      U.wait(1)
    end
    check(Renderer.presentCanvas ~= nil, version .. " present canvas allocated for SHADER FX")
  end

  local Screens = require("src.ui.game3.screens")
  local Runtime = require("src.core.game3.runtime")
  local ShaderFXMenu = require("src.ui.game3.shaderfx_menu")
  local session = Runtime.getSession()
  local Option = Screens.get("option", session)
  try("open option", function() Option.show({ session = session, game = game }) end)
  U.wait(30)
  if Option == require("src.ui.game3.rs.option_menu") then
    U.shot(game, out .. "/93-option-rs.png")
    for _ = 1, 120 do
      if Option._state == "input" then break end
      U.wait(1)
    end
    local top = Option._pages[1]
    local gi
    for i, row in ipairs(top.rows) do
      if row.id == "group.graphics" then gi = i end
    end
    if check(gi ~= nil, version .. " RS OPTION has a visible GRAPHICS row") then
      top.index = gi
      U.tap(game, "a")
      U.wait(4)
      local page = Option._pages[#Option._pages]
      local si
      for i, row in ipairs(page.rows) do
        if row.id == "shaderfx" then si = i end
      end
      if check(si ~= nil, version .. " RS GRAPHICS lists SHADER FX") then
        page.index = si
        U.wait(2)
        U.shot(game, out .. "/94-option-rs-graphics.png")
        U.tap(game, "a")
      end
    end
  else
    local pages = Option._pages or (Option._st and Option._st.pages)
    local top = pages and pages[#pages]
    local gi
    for i, row in ipairs(top and top.rows or {}) do
      if row.id == "group.graphics" then gi = i end
    end
    if check(gi ~= nil, version .. " OPTION has GRAPHICS") then
      top.index = gi
      if Option.confirm then Option.confirm() else U.tap(game, "a") end
      U.wait(4)
      pages = Option._pages or (Option._st and Option._st.pages)
      local page = pages[#pages]
      local si
      for i, row in ipairs(page.rows) do
        if row.id == "shaderfx" then si = i end
      end
      if check(si ~= nil, version .. " GRAPHICS lists SHADER FX") then
        page.index = si
        U.wait(2)
        U.shot(game, out .. "/93-option-graphics.png")
        page.rows[si].activate({ game = game, session = session, options = game.options })
      end
    end
  end
  U.wait(4)
  check(ShaderFXMenu.isOpen(), version .. " SHADER FX picker open")
  U.shot(game, out .. "/95-shaderfx-picker.png")
  ShaderFXMenu.handleInput(fakeInput("select"))
  U.wait(4)
  U.shot(game, out .. "/96-shaderfx-params.png")
  for _ = 1, 4 do
    if not ShaderFXMenu.isOpen() then break end
    ShaderFXMenu.handleInput(fakeInput("b"))
    U.wait(2)
  end
  check(not ShaderFXMenu.isOpen(), version .. " B backs out of SHADER FX")
  if Option.close then Option.close() end
  ShaderFX.deactivate()
  game.options.shaderfx, game.options.shaderfxSecondary = nil, nil
  game:writeOptions()
  U.wait(10)
  finish()
end
