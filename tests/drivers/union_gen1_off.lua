local U = require("tests.drivers.util")
local SaveData = require("src.core.SaveData")
local TextBox = require("src.render.TextBox")
local UnionCenters = require("src.world.gen1.UnionCenters")
local Origin = require("src.online.union.Origin")
local Setting = require("src.online.union.Setting")
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
  ok(not Setting.patchesOn(1), "options.lua has the Union Room setting off")
  ok(game.data.maps[UnionCenters.FLOOR_2F] == nil and game.data.maps[UnionCenters.UNION_ROOM] == nil,
     "no added maps with the setting off")
  ok(UnionCenters.forData(game.data) == nil, "no union center registry with the setting off")
  local raw = SaveData.load()
  ok(raw and raw.player.map == UnionCenters.FLOOR_2F, "the save on disk stands on the 2F: " .. tostring(raw and raw.player.map))
  ok(raw and (Origin.get(raw) or {}).map == "MT_MOON_POKECENTER", "the save on disk carries the Mt Moon origin")
  game:restoreSave(raw, nil, { freshBoot = true, continued = true })
  U.wait(20)
  local o = game.overworld
  local p = o.player
  ok(o.map.id == "MT_MOON_POKECENTER", "relocated to the origin center: " .. o.map.id)
  ok(p.cellX == 3 and p.cellY == 3, ("standing in front of the nurse (%d,%d)"):format(p.cellX, p.cellY))
  ok(Origin.get(game.save) == nil, "origin cleared after relocation")
  local def = game.data.maps.MT_MOON_POKECENTER
  ok(def.blocks[6] == 13 and def.blocks[7] == 13 and def.blocks[13] == 34 and def.blocks[14] == 35,
     "1F keeps the vanilla desk blocks")
  local rec
  for _, obj in ipairs(def.objects) do
    if obj.sprite == "SPRITE_LINK_RECEPTIONIST" then rec = obj end
  end
  ok(rec and rec.x == 11 and rec.y == 2, "receptionist back at the 1F desk")
  U.still(game, ("%s/%s_off_01_relocated.png"):format(SHOT_DIR, v))
  game.save.flags.EVENT_GOT_POKEDEX = true
  U.teleport(game, "MT_MOON_POKECENTER", 11, 3, "up")
  U.wait(30)
  U.tap(game, "a")
  local greeted = false
  for _ = 1, 300 do
    local top = game.stack:top()
    if getmetatable(top) == TextBox then
      for _, page in ipairs(top.pages or {}) do
        for _, line in ipairs(page) do
          if tostring(type(line) == "table" and table.concat(line) or line):find("Cable Club", 1, true) then greeted = true end
        end
      end
    end
    if greeted then break end
    U.wait(1)
  end
  ok(greeted, "vanilla 1F cable club receptionist answers")
  for _ = 1, 240 do
    local top = game.stack:top()
    if not (top and top.pages and not top.done) then break end
    U.wait(1)
  end
  U.still(game, ("%s/%s_off_02_desk_text.png"):format(SHOT_DIR, v))
  print(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  love.event.quit(fails == 0 and 0 or 1)
end
