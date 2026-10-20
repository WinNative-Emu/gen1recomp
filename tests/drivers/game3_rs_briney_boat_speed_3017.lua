local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local d = X.new("rs_briney_boat_speed_3017", "/tmp/rs_briney_boat_speed_3017")

-- pokeruby/src/event_object_movement.c:8100
local PRET_FRAMES = {}
for b = 0x10, 0x13 do PRET_FRAMES[b] = 16 end
for b = 0x1D, 0x20 do PRET_FRAMES[b] = 8 end
for b = 0x35, 0x38 do PRET_FRAMES[b] = 4 end

return function(game)
  local session = X.newGame(d, game, 0)
  if not session then return d.finish() end
  local version = session.version
  local Objects = require("src.core.game3.objects")
  local Player = require("src.core.game3.player")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Movement = require("src.core.game3.scripting.movement")
  local Fade = require("src.ui.game3.fade")
  require("src.core.game3.encounters").onStep = function() return nil end
  require("src.core.game3.trainer_sight").check = function() return false end
  local F = Flags.forVersion(version)
  local function setFlag(name, on) Flags.setFlag(Space.store, nil, assert(F.IDS[name], name), on ~= false) end
  local function setVar(name, v) Flags.setVar(Space.store, nil, assert(F.VAR_IDS[name], name), v) end
  local prefix = X.session().map:match("^(%u+_)") or "SA_"
  local function map(name) return prefix .. name end

  local origDecode = Movement.decodeAction
  Movement.decodeAction = function(b)
    local act = origDecode(b)
    if type(act) == "table" then act._raw = tonumber(b) end
    return act
  end

  local frame = 0
  local ride
  local origStep = Player.scriptStep
  Player.scriptStep = function(...)
    local ok = origStep(...)
    local tr = Objects._tracks[Objects.PLAYER_LOCAL_ID]
    if ride and ok and tr and #tr.actions > 20 then
      local act = tr.actions[tr.i - 1]
      ride.steps[#ride.steps + 1] = { frame = frame, raw = type(act) == "table" and act._raw or nil, track = tr }
      if Player.visible == false and not ride.shot and #ride.steps == ride.shotAt then ride.wantShot = true end
    end
    return ok
  end

  local function tick()
    if ride and ride.wantShot then
      ride.wantShot = nil
      ride.shot = d.still(game, ride.prefix .. "_mid_ride.png")
    end
    frame = frame + 1
    U.wait(1)
  end

  local function waitFor(pred, frames)
    for i = 1, frames do
      if pred() then return true end
      if i % 6 == 0 and not (ride and Player.visible == false) then table.insert(game.input.pressQueue, "a") end
      tick()
      game.input.state.a = false
    end
    return pred()
  end

  local function report(r)
    local byFrames, mismatches, total, pretTotal = {}, 0, 0, 0
    for i = 1, #r.steps - 1 do
      local s, n = r.steps[i], r.steps[i + 1]
      local want = s.raw and PRET_FRAMES[s.raw]
      if want and n.track == s.track then
        local got = n.frame - s.frame
        local row = byFrames[want] or { count = 0, sum = 0, min = math.huge, max = 0 }
        byFrames[want] = row
        row.count, row.sum = row.count + 1, row.sum + got
        row.min, row.max = math.min(row.min, got), math.max(row.max, got)
        total, pretTotal = total + got, pretTotal + want
        if got ~= want then
          mismatches = mismatches + 1
          if mismatches <= 5 then
            d.note(string.format("%s step %d raw 0x%02X took %d frames, pret %d", r.name, i, s.raw, got, want))
          end
        end
      end
    end
    for _, want in ipairs({ 16, 8, 4 }) do
      local row = byFrames[want]
      if row then
        d.note(string.format("%s pret %2d f/tile: %d steps, measured min %d max %d avg %.2f", r.name, want,
          row.count, row.min, row.max, row.sum / row.count))
      end
    end
    d.check(#r.steps > 20, r.name .. " sail track measured (" .. #r.steps .. " steps)")
    d.check(byFrames[4] ~= nil, r.name .. " ride uses the fastest step")
    d.check(mismatches == 0, string.format("%s every step matches pret frames/tile (%d mismatches, %d frames vs pret %d)",
      r.name, mismatches, total, pretTotal))
    d.check(r.shot == true, r.name .. " mid-ride screenshot")
  end

  local function sail(name, shotPrefix, landing, startFn)
    ride = { name = name, prefix = shotPrefix, steps = {}, shotAt = 60 }
    if not startFn() then ride = nil return end
    d.check(waitFor(function() return Player.visible == false end, 1200), name .. " player boards the boat")
    d.check(waitFor(function()
      return not X.scriptRunning() and X.session().map == landing and Player.visible ~= false
        and not Fade.isActive() and not Fade.lockInput and (Fade.t or 0) <= 0
    end, 20000), name .. " lands on " .. landing .. " (VM " .. X.vmWhere() .. ")")
    report(ride)
    ride = nil
  end

  local function start(label, localId, facing)
    local key = Space.bundle.labels[label]
    return d.check(key and Space.startScript(key, localId, facing), "cached " .. label .. " starts")
  end

  sail("Route104 to Dewford", "3017_route104_dewford", map("DEWFORD_TOWN"), function()
    setFlag("FLAG_HIDE_MR_BRINEY_BOAT_ROUTE104", false)
    setFlag("FLAG_HIDE_MR_BRINEY_ROUTE104", false)
    setVar("VAR_BOARD_BRINEY_BOAT_ROUTE104_STATE", 1)
    if not d.check(X.goTo(d, game, map("ROUTE104"), 13, 52, "left"), "Route104 boat dock loads") then return false end
    if X.scriptRunning() then return true end
    return start("Route104_EventScript_14EEA1", 0, 0)
  end)
  for _, trip in ipairs({
    { name = "Dewford to Petalburg", label = "DewfordTown_EventScript_SailToPetalburg",
      landing = "ROUTE104_MR_BRINEYS_HOUSE", prefix = "3017_dewford_petalburg" },
    { name = "Dewford to Slateport", label = "DewfordTown_EventScript_SailToSlateport",
      landing = "ROUTE109", prefix = "3017_dewford_slateport" },
  }) do
    sail(trip.name, trip.prefix, map(trip.landing), function()
      setFlag("FLAG_HIDE_MR_BRINEY_DEWFORD_TOWN", false)
      setFlag("FLAG_HIDE_MR_BRINEY_BOAT_DEWFORD", false)
      X.settle(game)
      if not d.check(X.goTo(d, game, map("DEWFORD_TOWN"), 11, 9, "right"), trip.name .. " departure loads") then return false end
      return start(trip.label, 2, 4)
    end)
  end
  sail("Route109 to Dewford", "3017_route109_dewford", map("DEWFORD_TOWN"), function()
    setFlag("FLAG_HIDE_MR_BRINEY_ROUTE109", false)
    setFlag("FLAG_HIDE_MR_BRINEY_BOAT_ROUTE109", false)
    X.settle(game)
    if not d.check(X.goTo(d, game, map("ROUTE109"), 21, 23, "down"), "Route109 departure loads") then return false end
    return start("Route109_EventScript_14F4D3", 2, 1)
  end)
  Movement.decodeAction = origDecode
  Player.scriptStep = origStep
  d.finish()
end
