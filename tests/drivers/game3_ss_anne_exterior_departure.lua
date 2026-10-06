local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_ss_anne_exterior_departure"

-- pokefirered/include/constants/vars.h:178
local VAR_MAP_SCENE_VERMILION_CITY = 0x407E
-- pokefirered/include/constants/event_objects.h:157
local OBJ_EVENT_GFX_SS_ANNE = 151
local EXTERIOR = "FR_SSANNE_EXTERIOR"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print(failures == 0 and "PASS ss_anne_exterior_departure"
    or ("FAIL ss_anne_exterior_departure failures=" .. failures))
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
  local Objects = require("src.core.game3.objects")
  local OwSprites = require("src.core.game3.ow_sprites")
  local Cutscene = require("src.core.game3.ss_anne_cutscene")
  local GfxIds = require("src.core.game3.scripting.gfx_ids")

  if not result(Runtime.getSession() ~= nil, "new game reached the game3 field") then return finish() end
  local function ctx() return Space.vm and Space.vm.ctx end

  local function goTo(x, y)
    Map.load(nil, game, EXTERIOR, { x = x, y = y, facing = "down" })
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = "down"
  end

  goTo(32, 14)
  U.wait(30)
  -- pokefirered/data/maps/SSAnne_Exterior/scripts.inc:11
  Flags.setVar(Space.store, ctx(), VAR_MAP_SCENE_VERMILION_CITY, 1)
  goTo(32, 14)

  result(GfxIds.TO_SPRITE[OBJ_EVENT_GFX_SS_ANNE] == nil, "no host sprite fallback for the SS Anne")
  local ship = Objects.find(1)
  local gid = ship and (ship.graphicsId or (ship.def and ship.def.graphicsId))
  local spr = OwSprites.getDraw(gid)
  print(("[driver] ship gid=%s cell=(%s,%s) spr=%sx%s slot=%s"):format(tostring(gid),
    tostring(ship and ship.cellX), tostring(ship and ship.cellY), tostring(spr and spr.width),
    tostring(spr and spr.height), tostring(spr and spr.paletteSlot)))
  result(gid == OBJ_EVENT_GFX_SS_ANNE, "SS Anne object uses OBJ_EVENT_GFX_SS_ANNE")
  result(spr and spr.width == 128 and spr.height == 64, "SS Anne draws the 128x64 ROM sheet")

  local started = false
  for _ = 1, 600 do
    if Cutscene.isActive() then started = true break end
    U.wait(1)
  end
  result(started, "the departure cutscene started")
  U.shot(game, DIR .. "/ssanne_00_start.png")
  local shots = 0
  for _ = 1, 1800 do
    if not Cutscene.isActive() then break end
    local off = Cutscene._boatOffset or 0
    if off >= (shots + 1) * 40 and shots < 5 then
      shots = shots + 1
      U.shot(game, ("%s/ssanne_%02d_off%d.png"):format(DIR, shots, off))
    else
      U.wait(1)
    end
  end
  result(not Cutscene.isActive(), "the departure cutscene finished")
  finish()
end
