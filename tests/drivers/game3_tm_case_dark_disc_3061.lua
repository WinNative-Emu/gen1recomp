local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_tm_case_dark_disc_3061"

-- pokefirered/include/constants/items.h:436
local ITEM_TM_CASE = 364
-- pokefirered/include/constants/items.h:311
local ITEM_TM12 = 300
-- pokefirered/include/constants/items.h:337
local ITEM_TM38 = 326

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS tm_case_dark_disc_3061")
    love.event.quit(0)
  else
    print("FAIL tm_case_dark_disc_3061 failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Bag = require("src.core.game3.bag")
  local Pokemon = require("src.core.game3.pokemon")
  local TmCase = require("src.ui.game3.tm_case")
  local TmCaseChrome = require("src.ui.game3.tm_case_chrome")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_TM_CASE, 1)
  Bag.add(session.bag, ITEM_TM12, 1)
  Bag.add(session.bag, ITEM_TM38, 1)

  local taunt = Pokemon.battleMove(Pokemon.moveFromTmItem(ITEM_TM12)) or {}
  result(tonumber(taunt.type) == 17, "TM12 TAUNT is TYPE_DARK, type=" .. tostring(taunt.type))
  local fireBlast = Pokemon.battleMove(Pokemon.moveFromTmItem(ITEM_TM38)) or {}
  result(tonumber(fireBlast.type) == 10, "TM38 FIRE BLAST is TYPE_FIRE, type=" .. tostring(fireBlast.type))

  result(TmCaseChrome.ready(), "TM case chrome is in the cache")
  result(TmCaseChrome.discBank == nil, "the UI carries no type to palette bank table")
  for t = 0, 17 do
    result(TmCaseChrome.loadDisc(t, false) ~= nil and TmCaseChrome.loadDisc(t, true) ~= nil,
      "TM and HM discs load for type " .. t)
  end
  local Dataset = require("src.core.game3.dataset")
  local Extract = require("src.import.gba.extract_island1")
  local function hasColor(typeIdx, r, g, b)
    local rel = string.format("%s/items/tm_case/disc_%d.rgba", Extract.CACHE_ROOT or "data/generated/gba", typeIdx)
    local data = Dataset.cache():read(rel)
    if type(data) ~= "string" or #data < 32 * 32 * 4 then return false end
    for i = 0, 32 * 32 - 1 do
      local pr, pg, pb, pa = data:byte(i * 4 + 1, i * 4 + 4)
      if pa == 255 and pr == r and pg == g and pb == b then return true end
    end
    return false
  end
  result(hasColor(17, 82, 156, 165), "the Dark TM disc is tinted Dark teal")
  result(hasColor(10, 239, 173, 33), "the Fire TM disc is tinted Fire orange")

  TmCase.show(session, session.bag)
  U.wait(10)
  if not result(TmCase.isOpen(), "the TM CASE is open") then return finish() end
  local sel = TmCase.list()[TmCase.cursor]
  result(sel and sel.id == ITEM_TM12, "the cursor is on TM12, id=" .. tostring(sel and sel.id))
  U.still(game, DIR .. "/3061_01_dark_tm_disc.png")

  U.tap(game, "down")
  U.wait(10)
  sel = TmCase.list()[TmCase.cursor]
  result(sel and sel.id == ITEM_TM38, "the cursor is on TM38, id=" .. tostring(sel and sel.id))
  U.still(game, DIR .. "/3061_02_fire_tm_disc.png")

  TmCase.close()
  return finish()
end
