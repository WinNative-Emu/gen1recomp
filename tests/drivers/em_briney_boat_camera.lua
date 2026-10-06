local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local d = X.new("em_briney_boat_camera", "/tmp/em_briney_boat_camera")

return function(game)
  if not X.newGame(d, game, 0) then return d.finish() end
  local Objects = require("src.core.game3.objects")
  local Player = require("src.core.game3.player")
  local Space = require("src.core.game3.scripting.space")
  local Fade = require("src.ui.game3.fade")
  local FieldView = require("src.core.game3.field_view")
  local state
  local function boatOf()
    for _, eo in pairs(Objects._byId) do
      if eo.originMapId == state.origin and eo.originLocalId == state.localId then return eo end
    end
  end
  local function monitor()
    if not state then return end
    state.frame = state.frame + 1
    if Player.visible ~= false then return end
    local boat = boatOf()
    if not boat then return end
    local tr
    for lid, eo in pairs(Objects._byId) do
      if eo == boat then tr = Objects._tracks[lid] end
    end
    if not tr or tr.done then return end
    local dx = boat.px - Player.px - (FieldView.cameraPanX or 0)
    local dy = boat.py - Player.py - (FieldView.cameraPanY or 0)
    if state.dx == nil then state.dx, state.dy = dx, dy end
    state.samples = state.samples + 1
    local dev = math.max(math.abs(dx - state.dx), math.abs(dy - state.dy))
    if dev > state.maxDev then
      state.maxDev = dev
      if dev > 0 and not state.noted then
        state.noted = true
        d.note(string.format("%s boat leaves center on %s frame %d: %d,%d -> %d,%d (player cell %d,%d stepFrames %s)",
          state.name, X.session().map, state.frame, state.dx, state.dy, dx, dy,
          Player.cellX, Player.cellY, tostring(Player.stepFrames)))
      end
    end
    if state.samples % state.every == 1 and state.shots < 12 then
      state.shots = state.shots + 1
      d.shot(game, string.format("%s_%02d.png", state.prefix, state.shots))
    end
  end
  local function waitFor(pred, frames)
    for i = 1, frames do
      if pred() then return true end
      if i % 6 == 0 then table.insert(game.input.pressQueue, "a") end
      U.wait(1)
      game.input.state.a = false
      monitor()
    end
    return pred()
  end
  local function begin(name, prefix, origin, localId)
    state = { name = name, prefix = prefix, origin = origin, localId = localId,
      samples = 0, maxDev = 0, frame = 0, shots = 0, every = 200 }
  end
  local function finishTrip(mapId)
    local ok = waitFor(function()
      return not X.scriptRunning() and X.session().map == mapId and Player.visible ~= false
        and not Fade.isActive() and not Fade.lockInput and (Fade.t or 0) <= 0
    end, 18000)
    d.check(ok, state.name .. " lands on " .. mapId .. " (VM " .. X.vmWhere() .. ")")
    d.check(state.samples > 0, state.name .. " sampled " .. state.samples .. " sailing frames")
    d.check(state.maxDev == 0, state.name .. " boat stays centered (max drift " .. state.maxDev .. "px)")
    state = nil
  end
  local function start(label, localId, facing)
    local key = Space.bundle.labels[label]
    return d.check(key and Space.startScript(key, localId, facing), "cached " .. label .. " starts")
  end
  local function mount(bike)
    Player.biking = bike and true or false
    Player.bikeType = bike and "mach" or nil
  end

  X.setFlag("FLAG_MR_BRINEY_SAILING_INTRO", true)
  X.setFlag("FLAG_HIDE_BRINEYS_HOUSE_MR_BRINEY", false)
  X.setFlag("FLAG_HIDE_BRINEYS_HOUSE_PEEKO", false)
  X.setFlag("FLAG_ENABLE_NORMAN_MATCH_CALL", false)
  X.setVar("VAR_BRINEY_HOUSE_STATE", 0)
  d.check(X.goTo(d, game, "EM_ROUTE104_MR_BRINEYS_HOUSE", 5, 6, "up"), "Route104 house loads")
  local briney = Objects.find(1)
  local bx, by = briney and briney.cellX or 5, briney and briney.cellY or 3
  X.goTo(d, game, "EM_ROUTE104_MR_BRINEYS_HOUSE", bx, by + 1, "up")
  begin("Route104 dad call", "r104_call", "EM_ROUTE104", 7)
  table.insert(game.input.pressQueue, "a")
  finishTrip("EM_DEWFORD_TOWN")
  X.setFlag("FLAG_HIDE_ROUTE_104_MR_BRINEY", false)
  X.setFlag("FLAG_HIDE_ROUTE_104_MR_BRINEY_BOAT", false)
  X.setVar("VAR_BOARD_BRINEY_BOAT_STATE", 1)
  begin("Route104 no call", "r104_nocall", "EM_ROUTE104", 7)
  d.check(X.goTo(d, game, "EM_ROUTE104", 17, 50, "down"), "Route104 doorstep loads")
  finishTrip("EM_DEWFORD_TOWN")
  for _, bike in ipairs({ false, true }) do
    local tag = bike and " on bike" or ""
    local ptag = bike and "_bike" or ""
    for _, trip in ipairs({
      { name = "Dewford Petalburg", label = "DewfordTown_EventScript_SailToPetalburg",
        landing = "EM_ROUTE104_MR_BRINEYS_HOUSE", prefix = "dewford_r104" },
      { name = "Dewford Slateport", label = "DewfordTown_EventScript_SailToSlateport",
        landing = "EM_ROUTE109", prefix = "dewford_r109" },
    }) do
      X.setFlag("FLAG_HIDE_MR_BRINEY_DEWFORD_TOWN", false)
      X.setFlag("FLAG_HIDE_MR_BRINEY_BOAT_DEWFORD_TOWN", false)
      d.check(X.goTo(d, game, "EM_DEWFORD_TOWN", 11, 9, "right"), trip.name .. tag .. " departure loads")
      mount(bike)
      begin(trip.name .. tag, trip.prefix .. ptag, "EM_DEWFORD_TOWN", 4)
      if start(trip.label, 2, 4) then finishTrip(trip.landing) end
      mount(false)
    end
    X.setFlag("FLAG_HIDE_ROUTE_109_MR_BRINEY", false)
    X.setFlag("FLAG_HIDE_ROUTE_109_MR_BRINEY_BOAT", false)
    d.check(X.goTo(d, game, "EM_ROUTE109", 21, 23, "down"), "Route109" .. tag .. " departure loads")
    mount(bike)
    begin("Route109 Dewford" .. tag, "r109_dewford" .. ptag, "EM_ROUTE109", 1)
    if start("Route109_EventScript_StartDepartForDewford", 2, 1) then finishTrip("EM_DEWFORD_TOWN") end
    mount(false)
  end
  d.finish()
end
