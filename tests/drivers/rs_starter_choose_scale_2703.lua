local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/drv2703"

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
    local Message = require("src.ui.game3.message")
    local Warp = require("src.core.game3.warp")
    pcall(function() game:_handleBootAction({ action = "new_game", name = "TAI", gender = 0 }) end)
    U.wait(60)
    until_(600, function()
      if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
      return not (Warp.isBusy() or (Message.isOpen and Message.isOpen()))
    end)
    local Starter = require("src.ui.game3.rse.starter_choose")
    local screen = Starter.open({})
    check(screen.policy ~= nil, "rs policy active")
    until_(120, function() return screen.state == "input" end)
    U.wait(30)
    U.tap(game, "a")
    until_(60, function() return screen.circle and screen.circle.affine.begun end)
    U.wait(6)
    local mid = screen.policy.affineScale(screen.circle.affine.scale)
    check(mid > 0 and mid < 1.25, "circle grows in from small (" .. mid .. ")")
    U.still(game, DIR .. "/2703_01_circle_growing.png")
    until_(240, function() return screen.state == "confirm" end)
    U.wait(2)
    local cs = screen.policy.affineScale(screen.circle.affine.scale)
    local ms = screen.policy.affineScale(screen.mon.affine.scale)
    check(cs == 1.25, "circle final scale 1.25 (" .. cs .. ")")
    check(ms == 1, "mon final scale 1.0 (" .. ms .. ")")
    U.still(game, DIR .. "/2703_02_circle_fits_mon.png")
  end, debug.traceback)
  if not ok then print("FAIL driver error: " .. tostring(err)); pass = false end
  love.event.quit(pass and 0 or 1)
  U.wait(10)
end
