local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local d = X.new("em_sootopolis_camera_2746", "/tmp/em_sootopolis_camera_2746")

local CameraObject = require("src.core.game3.camera_object")
local Scenes = require("src.core.game3.scripting.natives_scenes_rse")
local Player = require("src.core.game3.player")
local Fade = require("src.ui.game3.fade")

local PAN = 12 * 16

local function off()
  local dx, dy = CameraObject.offset()
  return dx, dy
end

local function fmt(dx, dy) return string.format("(%d,%d)", dx, dy) end

local function fightScene(game)
  Scenes.last = nil
  X.setFlag("FLAG_LEGENDARIES_IN_SOOTOPOLIS", false)
  X.setVar("VAR_SKY_PILLAR_STATE", 0)
  X.setVar("VAR_SOOTOPOLIS_CITY_STATE", 1)
  X.goTo(d, game, "EM_SOOTOPOLIS_CITY", 43, 32, "down")

  local wasActive, removedAt = false, nil
  local opened = X.waitFor(function()
    local active = CameraObject.isActive()
    if wasActive and not active and not removedAt then removedAt = { off() } end
    wasActive = active
    return Scenes.last ~= nil
  end, 8000)
  d.check(opened, "fight: Sootopolis ON_FRAME reaches Script_DoRayquazaScene")
  if not opened then return end
  removedAt = removedAt or { 0, 0 }
  d.check(removedAt[1] == -PAN and removedAt[2] == PAN,
    "fight: RemoveCameraObject leaves the view on the fight " .. fmt(removedAt[1], removedAt[2]))
  X.waitFor(function() return Scenes.last.done end, 60000)
  d.check(Scenes.last.done == true, "fight: the scene returns to the field")
  U.wait(2)
  local ax, ay = off()
  d.check(ax == -PAN and ay == PAN, "fight: view is on the fight after the scene " .. fmt(ax, ay))
  X.waitFor(function() return not Fade.isActive() end, 300)
  d.still(game, "2746_01_camera_on_fight.png")

  local spawnAt, maxX, maxY, wentNE = nil, 0, 0, false
  local midShot = false
  local cont = X.waitFor(function()
    if CameraObject.isActive() then
      local o = CameraObject.object()
      if o and not spawnAt then spawnAt = { o.cellX, o.cellY } end
      local dx, dy = off()
      maxX, maxY = math.max(maxX, math.abs(dx)), math.max(maxY, math.abs(dy))
      if dx > 0 or dy < 0 then wentNE = true end
      if not midShot and math.abs(dx) <= PAN / 2 and math.abs(dx) > 0 then
        midShot = true
        d.still(game, "2746_02_camera_pan_back_mid.png")
      end
    end
    return X.var("VAR_SOOTOPOLIS_CITY_STATE") == 2
  end, 30000)
  d.check(cont, "fight: script reaches VAR_SOOTOPOLIS_CITY_STATE=2")
  d.check(spawnAt ~= nil and spawnAt[1] == 31 and spawnAt[2] == 44,
    "fight: SpawnCameraObject after the scene starts at the fight (31,44) got " ..
    (spawnAt and fmt(spawnAt[1], spawnAt[2]) or "none"))
  d.check(maxX <= PAN and maxY <= PAN and not wentNE,
    "fight: pan back stays between the fight and the player " .. fmt(maxX, maxY))
  U.wait(4)
  local ex, ey = off()
  d.check(ex == 0 and ey == 0, "fight: view ends on the player " .. fmt(ex, ey))
  d.still(game, "2746_03_camera_back_on_player.png")
end

local function rayquazaScene(game)
  Scenes.last = nil
  X.setFlag("FLAG_LEGENDARIES_IN_SOOTOPOLIS", false)
  X.setVar("VAR_SOOTOPOLIS_CITY_STATE", 5)
  X.setVar("VAR_SKY_PILLAR_STATE", 1)
  X.goTo(d, game, "EM_SOOTOPOLIS_CITY", 43, 32, "down")
  local opened = X.waitFor(function() return Scenes.last ~= nil end, 8000)
  d.check(opened, "rayquaza: Sootopolis ON_FRAME reaches Script_DoRayquazaScene")
  if not opened then return end
  X.waitFor(function() return Scenes.last.done end, 120000)
  U.wait(2)
  local ax, ay = off()
  d.check(ax == -PAN and ay > 0, "rayquaza: view is on the fight after the scene " .. fmt(ax, ay))
  X.waitFor(function() return not Fade.isActive() end, 300)
  d.still(game, "2746_04_rayquaza_camera_on_fight.png")
  local cont = X.waitFor(function() return X.var("VAR_SKY_PILLAR_STATE") == 3 end, 30000)
  d.check(cont, "rayquaza: script reaches VAR_SKY_PILLAR_STATE=3")
  X.waitFor(function() return not X.scriptRunning() end, 6000)
  X.settle(game, 1200)
  U.wait(30)
  local ex, ey = off()
  d.check(ex == 0 and ey == 0, "rayquaza: view is on the player after the warp " .. fmt(ex, ey))
  d.check(CameraObject.isActive() == false, "rayquaza: the warp dropped the camera object")
  d.note(string.format("rayquaza: player at %s,%s", tostring(Player.cellX), tostring(Player.cellY)))
  d.still(game, "2746_05_rayquaza_after_warp_on_player.png")
end

return function(game)
  local sess = X.newGame(d, game, 0)
  if not sess then return d.finish() end
  d.try("fight", function() fightScene(game) end)
  d.try("rayquaza", function() rayquazaScene(game) end)
  d.finish()
end
