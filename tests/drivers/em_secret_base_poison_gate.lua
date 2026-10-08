local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_secret_base_poison_gate"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_secret_base_poison_gate failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(60)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local MapIds = require("src.core.game3.map_ids")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Party = require("src.core.game3.party")
  local Field = require("src.core.game3.field")
  local Space = require("src.core.game3.scripting.space")
  local Warp = require("src.core.game3.warp")
  local StepEvents = require("src.core.game3.step_events")
  local Sem = require("src.core.game3.field_semantics")

  local session = Runtime.getSession()
  if not check(session ~= nil, "field session exists") then return finish() end
  local C = require("src.core.game3.constants").active(session)
  local id = require("src.core.game3.profile").forSession(session).id
  local tag = id .. ": "

  for _ = 1, 600 do
    if not (Space.vm and Space.vm:isRunning()) and not Message.isOpen() and not Warp.isBusy() then break end
    if Message.isOpen() then U.tap(game, "a") end
    U.wait(2)
  end

  local function settle()
    for _ = 1, 300 do
      if not (Space.vm and Space.vm:isRunning()) and not Message.isOpen() and not Warp.isBusy()
        and not StepEvents.busy() then return end
      if Message.isOpen() then U.tap(game, "a") end
      U.wait(2)
    end
  end

  local function poisonParty()
    session.party = {}
    Party.giveMon(session, C:require("species", "SPECIES_TORCHIC"), 30)
    local mon = session.party[1]
    mon.status = "PSN"
    mon.hp = mon.maxHp or mon.hp
    return mon
  end

  local function setSteps(n)
    session.vars[Sem.var(session, "poisonSteps")] = n
    session.poisonSteps = n
  end

  local function stepDir(dir)
    local sx, sy = Player.cellX, Player.cellY
    U.hold(game, dir, 20)
    U.wait(10)
    settle()
    return Player.cellX ~= sx or Player.cellY ~= sy
  end

  local okRun, err = pcall(function()
    local base = MapIds.forConst("MAP_SECRET_BASE_BLUE_CAVE1", id)
    local def = game.data.maps[base]
    local w = def and def.warps and def.warps[1]
    check(w ~= nil, tag .. "secret base map " .. tostring(base) .. " has an exit warp")
    Map.load(nil, game, base, { x = w.x, y = w.y, facing = "up" })
    session.x, session.y, session.facing = w.x, w.y, "up"
    Field.unlock()
    U.wait(30)
    settle()
    local cur = Map.currentDef()
    check(Map.current == base, tag .. "inside " .. tostring(base))
    check(cur and tonumber(cur.mapType) == 9, tag .. "map header mapType is MAP_TYPE_SECRET_BASE ("
      .. tostring(cur and cur.mapType) .. ")")

    local mon = poisonParty()
    local hp0 = mon.hp
    setSteps(3)
    local moved = 0
    if stepDir("up") then moved = moved + 1 end
    for i = 1, 7 do
      if stepDir(i % 2 == 1 and "up" or "down") then moved = moved + 1 end
    end
    print("INFO inside steps=" .. moved .. " hp=" .. tostring(mon.hp) .. "/" .. tostring(hp0))
    check(moved >= 6, tag .. "walked " .. moved .. " steps inside the base")
    check(Map.current == base, tag .. "still inside the base")
    check(mon.hp == hp0, tag .. "HP unchanged inside the secret base (" .. tostring(mon.hp) .. ")")
    check(tonumber(session.vars[Sem.var(session, "poisonSteps")]) == 3, tag .. "poison counter held at 3")
    U.still(game, DIR .. "/s1_01_" .. id .. "_secret_base_poisoned_full_hp.png")

    local route = MapIds.forConst("MAP_ROUTE103", id)
    Map.load(nil, game, route, { x = 10, y = 10, facing = "down" })
    session.x, session.y, session.facing = 10, 10, "down"
    Field.unlock()
    U.wait(30)
    settle()
    mon.hp = hp0
    mon.status = "PSN"
    setSteps(0)
    local out = 0
    local dirs = { "down", "up", "left", "right" }
    for i = 1, 16 do
      if out >= 8 then break end
      if stepDir(dirs[(i - 1) % 4 + 1]) then out = out + 1 end
    end
    print("INFO outside steps=" .. out .. " hp=" .. tostring(mon.hp) .. "/" .. tostring(hp0))
    check(out >= 8, tag .. "walked " .. out .. " steps on route 103")
    check(mon.hp == hp0 - 2, tag .. "HP drops 2 after 8 steps outside (" .. tostring(mon.hp) .. ")")
    U.still(game, DIR .. "/s1_02_" .. id .. "_route103_poison_hp_drop.png")
  end)
  check(okRun, tag .. "no crash " .. tostring(okRun and "" or err))
  return finish()
end
