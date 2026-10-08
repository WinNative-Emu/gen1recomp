local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("em_mr_stone_head_2737", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_mr_stone_head_2737")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Objects = require("src.core.game3.objects")
  local FieldView = require("src.core.game3.field_view")
  local session = Runtime.getSession()
  if not S.check(session.version == "emerald", "driver runs Emerald") then return S.finish() end
  F.setVar("VAR_DEVON_CORP_3F_STATE", 3)
  S.check(F.goTo(game, "EM_RUSTBORO_CITY_DEVON_CORP_3F", 13, 5, "right"), "Devon Corp 3F loads")
  U.wait(20)
  local stone
  for _, lid in ipairs(Objects._order or {}) do
    local eo = Objects._byId[lid]
    if eo and eo.cellX == 17 and eo.cellY == 5 then stone = eo end
  end
  if not S.check(stone ~= nil, "Mr. Stone spawned at 17,5") then return S.finish() end
  S.note("stone elevation=" .. tostring(stone.elevation) .. " current=" .. tostring(stone.currentElevation))
  S.check(stone.elevation == 4, "Mr. Stone elevation follows chair metatile")
  local _, over = FieldView.applyDrawOrder({
    { kind = "npc", eventObject = stone, elevation = stone.elevation, y = stone.py },
  }, {}, {}, 0)
  S.check(#over == 1, "Mr. Stone draws over the chair back layer")
  S.check(S.still(game, "2737_01_mr_stone_head_over_chair.png"), "Mr. Stone office screenshot")
  S.finish()
end
