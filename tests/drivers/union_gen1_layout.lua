local U = require("tests.drivers.util")
local UnionCenters = require("src.world.gen1.UnionCenters")
local PaletteFX = require("src.render.PaletteFX")
local Zoom = require("src.render.Zoom")
local GameVersion = require("src.core.GameVersion")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. line)
  end
  local v = GameVersion.get()
  U.wait(10)
  local r = UnionCenters.forData(game.data)
  ok(r ~= nil and #r.order == 12, "12 centers patched")
  Zoom.offset = -3
  local modes = { "gbc", "redpp", "ogred" }
  local spots = {
    { "VIRIDIAN_POKECENTER", 11, 3, "1f_viridian", "VIRIDIAN_CITY" },
    { UnionCenters.FLOOR_2F, 11, 3, "2f", "VIRIDIAN_CITY" },
    { "INDIGO_PLATEAU_LOBBY", 13, 7, "1f_indigo", "INDIGO_PLATEAU" },
    { UnionCenters.FLOOR_2F, 11, 3, "2f_indigo", "INDIGO_PLATEAU" },
    { UnionCenters.UNION_ROOM, 12, 12, "room_top", "VIRIDIAN_CITY" },
    { UnionCenters.UNION_ROOM, 12, 20, "room_bottom", "VIRIDIAN_CITY" },
  }
  for _, mode in ipairs(modes) do
    PaletteFX.setMode(mode)
    for _, s in ipairs(spots) do
      game.save.lastOutdoor = { id = s[5], x = 10, y = 10 }
      U.teleport(game, s[1], s[2], s[3], "up")
      game.overworld.lastOutdoor = game.save.lastOutdoor
      U.wait(4)
      ok(game.overworld.map.id == s[1], ("%s %s loaded"):format(mode, s[1]))
      U.still(game, ("%s/%s_%s_%s.png"):format(SHOT_DIR, v, s[4], mode))
    end
  end
  Zoom.offset = 0
  PaletteFX.setMode("gbc")
  print(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  love.event.quit(fails == 0 and 0 or 1)
end
