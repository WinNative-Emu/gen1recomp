local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/drv2707"

local function until_(n, fn)
  for _ = 1, n do
    if fn() then return true end
    U.wait(1)
  end
  return fn()
end

return function(game)
  local pass = true
  local function check(cond, label)
    print((cond and "PASS " or "FAIL ") .. label)
    if not cond then pass = false end
  end
  until_(900, function() return game.phase == "boot" and game.boot end)
  local ok, err = xpcall(function()
    local MapIds = require("src.core.game3.map_ids")
    local Map = require("src.core.game3.map")
    local Runtime = require("src.core.game3.runtime")
    local Warp = require("src.core.game3.warp")
    local Message = require("src.ui.game3.message")
    pcall(function() game:_handleBootAction({ action = "new_game", name = "TAI", gender = 0 }) end)
    U.wait(60)
    until_(600, function()
      if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
      return not (Warp.isBusy() or (Message.isOpen and Message.isOpen()))
    end)
    Map.load(nil, game, MapIds.forConst("MAP_ROUTE101"), { x = 10, y = 10, facing = "down" })
    U.wait(30)
    local s = Runtime.getSession()
    s.party = {}
    local Party = require("src.core.game3.party")
    local _, _, mon = Party.giveMon(s, 277, 5, "RAZOR")
    check(mon and tonumber(mon.metLocation) == 16, "treecko met on route 101 (" .. tostring(mon and mon.metLocation) .. ")")
    local Summary = require("src.ui.game3.rs.summary_menu")
    Summary.openMenu(s.party, 1, { playerState = s })
    U.wait(60)
    local name = Summary.locationName(tonumber(mon.metLocation) or 0)
    check(name == "ROUTE 101", "memo location ROUTE 101 (" .. tostring(name) .. ")")
    local runs = Summary.policy.memo(mon, s, name)
    local t = {}
    for _, r in ipairs(runs) do t[#t + 1] = r.text end
    local memo = table.concat(t)
    print("memo " .. memo:gsub("\n", "/"))
    check(memo:find("ROUTE 101", 1, true) and memo:find("(met)", 1, true), "memo names route 101 and (met)")
    local okD, errD = pcall(Summary.draw)
    check(okD, "info page draws without error " .. (okD and "" or tostring(errD)))
    print("nationalDex " .. tostring(require("src.core.game3.dex").nationalEnabled(s)))
    U.still(game, DIR .. "/2707_01_trainer_memo.png")
  end, debug.traceback)
  if not ok then print("FAIL driver error: " .. tostring(err)); pass = false end
  love.event.quit(pass and 0 or 1)
  U.wait(10)
end
