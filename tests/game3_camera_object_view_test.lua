#!/usr/bin/env luajit
-- pokeemerald/src/field_specials.c:1251
-- pokeemerald/data/maps/SootopolisCity/scripts.inc:179

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")

local CameraObject = require("src.core.game3.camera_object")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Movement = require("src.core.game3.scripting.movement")
local FieldView = require("src.core.game3.field_view")

FieldView.draw = function() end

local MAP = "EM_SOOTOPOLIS_CITY"
local CELL = 16
local L, D, R, U = Movement.CMD.WALK_LEFT, Movement.CMD.WALK_DOWN, Movement.CMD.WALK_RIGHT, Movement.CMD.WALK_UP
local STEP_END = Movement.STEP_END

local function settle()
  for _ = 1, 600 do
    Objects.update(nil)
    if Objects.pollMovement(CameraObject.LOCALID) then return true end
  end
  return false
end

CameraObject.reset()
Objects.loadMap(nil, MAP, { objects = {} })
Player.reset(43, 32, "down")

print("[test] 1. pan to the fight, then RemoveCameraObject")
CameraObject.spawn(nil)
Objects.applyMovement(CameraObject.LOCALID, { L, L, D, D, STEP_END })
check(settle(), "the pan to the fight finished")
CameraObject.remove(nil)
eq(CameraObject.isActive(), false, "the camera object is gone")
local ox, oy = CameraObject.offset()
eq(ox, -2 * CELL, "the view stays on the fight, x")
eq(oy, 2 * CELL, "the view stays on the fight, y")

print("[test] 2. SpawnCameraObject after the scene starts at the view, not the player")
local eo = CameraObject.spawn(nil)
eq(eo.cellX, 41, "camera spawns at the view cell x")
eq(eo.cellY, 34, "camera spawns at the view cell y")
local sx, sy = CameraObject.offset()
eq(sx, -2 * CELL, "spawning does not jump the view, x")
eq(sy, 2 * CELL, "spawning does not jump the view, y")
Objects.applyMovement(CameraObject.LOCALID, { R, R, U, U, STEP_END })
check(settle(), "the pan back finished")
local px, py = CameraObject.offset()
eq(px, 0, "the pan back ends on the player, x")
eq(py, 0, "the pan back ends on the player, y")
CameraObject.remove(nil)
local zx, zy = CameraObject.offset()
eq(zx, 0, "no offset left after a full pan back, x")
eq(zy, 0, "no offset left after a full pan back, y")

print("[test] 3. a warp into the same map drops a live camera object")
CameraObject.spawn(nil)
Objects.applyMovement(CameraObject.LOCALID, { U, U, STEP_END })
check(settle(), "the pan up finished")
eq(CameraObject.isActive(), true, "the camera object is live before the warp")
local Map = require("src.core.game3.map")
pcall(Map.load, nil, nil, MAP, { x = 43, y = 32, facing = "down" })
Objects.loadMap(nil, MAP, { objects = {} })
Player.reset(43, 32, "down")
eq(CameraObject.isActive(), false, "the warp dropped the camera object")
local wx, wy = CameraObject.offset()
eq(wx, 0, "the view is back on the player after the warp, x")
eq(wy, 0, "the view is back on the player after the warp, y")

print("[test] 4. reset clears a left-over view offset")
CameraObject.spawn(nil)
Objects.applyMovement(CameraObject.LOCALID, { L, STEP_END })
check(settle(), "the pan left finished")
CameraObject.remove(nil)
local lx = CameraObject.offset()
eq(lx, -CELL, "the view is left one cell over")
CameraObject.reset()
local rx, ry = CameraObject.offset()
eq(rx, 0, "reset clears the offset, x")
eq(ry, 0, "reset clears the offset, y")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
