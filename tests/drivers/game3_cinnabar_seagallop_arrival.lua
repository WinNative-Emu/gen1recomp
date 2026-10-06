local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_cinnabar_seagallop_arrival"

-- pokefirered/include/constants/vars.h:165
local VAR_MAP_SCENE_CINNABAR_ISLAND = 0x4071
-- pokefirered/include/constants/flags.h:114
local FLAG_HIDE_CINNABAR_BILL = 0x062
-- pokefirered/include/constants/event_objects.h:114
local OBJ_EVENT_GFX_SEAGALLOP = 108
local CINNABAR = "FR_CINNABAR_ISLAND"
local SEAGALLOP_LOCALID = 4

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print(failures == 0 and "PASS cinnabar_seagallop_arrival"
    or ("FAIL cinnabar_seagallop_arrival failures=" .. failures))
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Objects = require("src.core.game3.objects")
  local OwSprites = require("src.core.game3.ow_sprites")
  local GfxIds = require("src.core.game3.scripting.gfx_ids")

  if not result(Runtime.getSession() ~= nil, "new game reached the game3 field") then return finish() end
  local function ctx() return Space.vm and Space.vm.ctx end

  local function goTo(x, y)
    Map.load(nil, game, CINNABAR, { x = x, y = y, facing = "down" })
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = "down"
    U.wait(90)
  end

  goTo(20, 5)
  -- pokefirered/data/maps/CinnabarIsland_Gym/scripts.inc:61
  Flags.setVar(Space.store, ctx(), VAR_MAP_SCENE_CINNABAR_ISLAND, 1)
  Flags.setFlag(Space.store, ctx(), FLAG_HIDE_CINNABAR_BILL, false)
  goTo(20, 5)

  result(OwSprites.ready(), "FRLG OW sprites are ready")
  result(GfxIds.TO_SPRITE[OBJ_EVENT_GFX_SEAGALLOP] == nil, "no host sprite fallback for the Seagallop")

  local shots, boatSeen, arrived, arrivedMsg = 0, false, false, false
  local lastX
  for _ = 1, 2400 do
    local boat = Objects.find(SEAGALLOP_LOCALID)
    local visible = boat and boat.visible and not boat.hidden and not boat.invisible
    if visible and not boatSeen then
      boatSeen = true
      local spr = OwSprites.getDraw(boat.graphicsId or (boat.def and boat.def.graphicsId))
      print(("[driver] boat added gid=%s cell=(%s,%s) spr=%sx%s frames=%s slot=%s"):format(
        tostring(boat.graphicsId or (boat.def and boat.def.graphicsId)), tostring(boat.cellX), tostring(boat.cellY),
        tostring(spr and spr.width), tostring(spr and spr.height), tostring(spr and spr.frameCount),
        tostring(spr and spr.paletteSlot)))
      result(spr and spr.width == 64 and spr.height == 64, "Seagallop draws the 64x64 ROM sheet")
    end
    if boatSeen and not arrived and boat and boat.px ~= lastX then
      lastX = boat.px
      if shots < 12 and (boat.px % 8 == 0) then
        shots = shots + 1
        U.shot(game, ("%s/arrive_%02d_px%d.png"):format(DIR, shots, boat.px))
      end
    end
    if boatSeen and not arrived and boat and boat.cellX == 25 and not boat.moving then
      arrived = true
      U.wait(2)
      U.shot(game, DIR .. "/arrive_docked.png")
      print(("[driver] boat docked cell=(%d,%d) px=(%s,%s)"):format(boat.cellX, boat.cellY,
        tostring(boat.px), tostring(boat.py)))
    end
    if arrived and Message.isOpen and Message.isOpen() and not arrivedMsg then
      arrivedMsg = true
      U.wait(30)
      U.shot(game, DIR .. "/arrive_message.png")
      break
    end
    if not boatSeen and Message.isOpen and Message.isOpen() then
      U.tap(game, "a")
      U.wait(8)
    else
      U.wait(1)
    end
  end
  result(boatSeen, "the Seagallop was added by the Bill scene")
  result(arrived, "the Seagallop docked at x=25")
  result(arrivedMsg, "Bill's boat-arrived message opened")
  finish()
end
