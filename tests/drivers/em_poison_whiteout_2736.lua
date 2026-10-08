local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_poison_whiteout_2736"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_poison_whiteout_2736 failures=" .. failures)
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
  local Flags = require("src.core.game3.scripting.flags")
  local Warp = require("src.core.game3.warp")
  local StepEvents = require("src.core.game3.step_events")
  local Sem = require("src.core.game3.field_semantics")
  local HealLocations = require("src.core.game3.heal_locations")
  local RomText = require("src.core.game3.rom_text")

  local session = Runtime.getSession()
  if not check(session ~= nil, "field session exists") then return finish() end
  local C = require("src.core.game3.constants").active(session)
  local id = require("src.core.game3.profile").forSession(session).id
  local isEm = id == "emerald"
  local tag = id .. ": "
  local whiteKey = isEm and "gText_PlayerWhitedOut" or "UnknownString_81A1141"
  local route = MapIds.forConst("MAP_ROUTE103", id)

  for _ = 1, 600 do
    if not (Space.vm and Space.vm:isRunning()) and not Message.isOpen() and not Warp.isBusy() then break end
    if Message.isOpen() then U.tap(game, "a") end
    U.wait(2)
  end

  local romWhite = RomText.box(whiteKey, { playerName = "BRENDAN" })
  check(type(romWhite) == "string" and romWhite:find("whited out", 1, true) ~= nil,
    tag .. whiteKey .. " resolves from the ROM cache")

  local function setup(mons, money)
    Map.load(nil, game, route, { x = 10, y = 10, facing = "down" })
    session.x, session.y, session.facing = 10, 10, "down"
    Field.unlock()
    U.wait(20)
    session.party = {}
    for i, row in ipairs(mons) do
      Party.giveMon(session, C:require("species", row.species), 5)
      local mon = session.party[i]
      if row.psn then
        mon.hp = 1
        mon.status = "PSN"
      end
    end
    session.money = money
    session.vars[Sem.var(session, "poisonSteps")] = 3
    session.poisonSteps = 3
  end

  local function step()
    local sx, sy = Player.cellX, Player.cellY
    for _, dir in ipairs({ "down", "left", "right", "up" }) do
      U.hold(game, dir, 20)
      U.wait(10)
      if Player.cellX ~= sx or Player.cellY ~= sy then return true end
    end
    return false
  end

  local function pump(name, shotName, expectWhiteout)
    local seen = { faint = 0, white = false, rom = false }
    local lastFaint
    for _ = 1, 1500 do
      local p = Message.isOpen() and Message.currentPage and Message.currentPage() or ""
      if p:find("fainted", 1, true) and p ~= lastFaint then
        seen.faint = seen.faint + 1
        lastFaint = p
      end
      if p:find("whited out", 1, true) and not seen.white then
        seen.white = true
        seen.rom = romWhite:find(p, 1, true) ~= nil
        Message.skipReveal()
        U.wait(4)
        if shotName then U.shot(game, DIR .. "/" .. shotName) end
      end
      local settled = not Message.isOpen() and not Warp.isBusy() and not StepEvents.busy()
        and not (Space.vm and Space.vm:isRunning())
      if settled and (not expectWhiteout or Map.current ~= route) then break end
      if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
      if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
      U.wait(2)
    end
    print("INFO " .. name .. " map=" .. tostring(Map.current) .. " money=" .. tostring(session.money))
    return seen
  end

  local Fade = require("src.ui.game3.fade")
  local function fadedIn()
    for _ = 1, 300 do
      if not Fade.active and (Fade.t or 0) <= 0 then return true end
      U.wait(2)
    end
    return false
  end

  local function healed()
    for _, mon in ipairs(session.party) do
      if (mon.hp or 0) <= 0 or (mon.hp or 0) ~= (mon.maxHp or mon.hp) or mon.status then return false end
    end
    return true
  end

  local okRun, err = pcall(function()
    setup({ { species = "SPECIES_TORCHIC", psn = true }, { species = "SPECIES_MUDKIP" } }, 3000)
    check(Map.current == route, tag .. "survive case on " .. tostring(route))
    check(step(), tag .. "survive case took a poisoned step")
    local s = pump("survive", nil, false)
    check(s.faint == 1, tag .. "survive case shows one fainted message (" .. s.faint .. ")")
    check(not s.white, tag .. "survive case shows no whited out text")
    check(Map.current == route, tag .. "survive case stays on " .. tostring(route))
    check(session.money == 3000, tag .. "survive case money unchanged (" .. tostring(session.money) .. ")")
    local m1 = session.party[1]
    check(m1 and (m1.hp or 0) == 0 and not m1.status, tag .. "fainted mon has 0 HP and poison cleared")
    check(not Field.isLocked or not Field.isLocked(), tag .. "survive case releases the field")

    setup({ { species = "SPECIES_TORCHIC", psn = true } }, 3000)
    local oldale = C:require("heal_locations", "HEAL_LOCATION_OLDALE_TOWN")
    Field.setRespawn(oldale)
    local oldaleMap = HealLocations.get(oldale).map
    check(step(), tag .. "whiteout case took a poisoned step")
    local w = pump("whiteout", "2736_01_" .. id .. "_whited_out_text.png", true)
    check(w.faint == 1, tag .. "fainted message shown before whiteout")
    check(w.white, tag .. "whited out message shown")
    check(w.rom, tag .. "whited out page comes from ROM " .. whiteKey)
    check(Map.current == oldaleMap, tag .. "respawned at last heal location " .. tostring(oldaleMap)
      .. " (" .. tostring(Map.current) .. ")")
    check(session.money == 1500, tag .. "money halved 3000 -> 1500 (" .. tostring(session.money) .. ")")
    check(healed(), tag .. "party healed")
    check(fadedIn(), tag .. "screen fades in from black after respawn (fade t=" .. tostring(Fade.t) .. ")")
    U.wait(30)
    U.shot(game, DIR .. "/2736_02_" .. id .. "_after_respawn.png")

    setup({ { species = "SPECIES_TORCHIC", psn = true } }, 0)
    Field.setRespawn(oldale)
    local target = oldaleMap
    if isEm then
      local lavaridge = C:require("heal_locations", "HEAL_LOCATION_LAVARIDGE_TOWN")
      target = HealLocations.get(lavaridge).map
      Flags.setFlag(Space.store, nil, C:require("flags", "FLAG_WHITEOUT_TO_LAVARIDGE"), true)
    end
    check(step(), tag .. "zero money case took a poisoned step")
    local z = pump("zero_money", isEm and "2736_03_emerald_lavaridge_whited_out.png" or nil, true)
    check(z.white and z.rom, tag .. "zero money whited out text from ROM")
    check(Map.current == target, tag .. (isEm and "FLAG_WHITEOUT_TO_LAVARIDGE respawns at " or "respawns at ")
      .. tostring(target) .. " (" .. tostring(Map.current) .. ")")
    check(session.money == 0, tag .. "zero money stays 0 (" .. tostring(session.money) .. ")")
    check(healed(), tag .. "party healed after zero money whiteout")
    check(fadedIn(), tag .. "screen fades in after zero money respawn")
  end)
  check(okRun, tag .. "no crash " .. tostring(okRun and "" or err))
  return finish()
end
