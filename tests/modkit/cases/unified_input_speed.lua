package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Game = require("src.core.Game")
local Game2 = require("src.core.Game2")
local Game3 = require("src.core.Game3")
local Input = require("src.core.Input")
local TouchControls = require("src.core.TouchControls")
local Viewport = require("src.render.GameViewport")
local Runtime = require("src.mods.Runtime")
local Boot = require("src.ui.game3.boot")

local OWNERS = { Game, Game2, Game3 }
local FIXTURES = {
  ["mods/fix_unified_input_speed/manifest.json"] = [[{
    "id":"fix_unified_input_speed", "name":"Fixture Unified Input Speed",
    "version":"1.0.0", "api":3, "games":["all"], "entry":"main.lua"
  }]],
  ["mods/fix_unified_input_speed/main.lua"] = [[
    local mod = ...
    local seen, speed, viewport = {}, { calls = 0, mode = "next" }, {}
    mod.exports.seen, mod.exports.speed, mod.exports.viewport = seen, speed, viewport
    mod.exports.input = mod.input
    mod.exports.stopPointer = mod.hooks:wrap("input.pointer", function(nextFn, game, ev)
      seen[#seen + 1] = { game = game, phase = ev.phase, source = ev.source,
        id = ev.id, x = ev.x, y = ev.y, dx = ev.dx, dy = ev.dy,
        gameX = ev.gameX, gameY = ev.gameY, insideGame = ev.insideGame,
        pressure = ev.pressure, button = ev.button }
      return nextFn(game, ev)
    end)
    mod.exports.stopSpeed = mod.hooks:wrap("core.logic_speed", function(nextFn, game, ...)
      speed.calls = speed.calls + 1
      speed.game, speed.extra = game, select("#", ...)
      if speed.mode == "next" then
        speed.vanilla = nextFn(speed.nextGame or game)
        return speed.vanilla
      end
      return speed.value
    end)
    mod.hooks:wrap("render.viewport", function(nextFn, ctx)
      if viewport.enabled then return { x = 20, y = 30, width = 120, height = 80 } end
      return nextFn(ctx)
    end)
  ]],
}

local function owner(generation, run)
  return setmetatable({
    generation = generation, input = Input, touchControls = TouchControls,
    mods = run.loader, data = run.data, phase = "field",
    save = { options = { speedOverworld = 4, speedBattle = 10, speedMenu = 2 } },
    options = { speed = 4, speedOverworld = 4, speedBattle = 10, speedMenu = 2 },
    stack = { states = { { isOverworld = true } } },
  }, { __index = OWNERS[generation] })
end

local function options(generation)
  return { generation = generation,
    data = generation == 3 and T.sdk.gen3Data() or T.fixtures.fresh(),
    fs = T.sdk.memfs(FIXTURES) }
end

local function wipe(seen)
  for i = #seen, 1, -1 do seen[i] = nil end
end

for generation = 1, 3 do
  local label = "gen" .. generation .. ": "
  Input:init()
  TouchControls:init()
  TouchControls.active = false
  Viewport.reset()

  local bareOptions = options(generation)
  bareOptions.fs = T.sdk.memfs({})
  local bare = T.sdk.loadNone(bareOptions)
  local g = owner(generation, bare)
  T.eq(Runtime.wantsHook("input.pointer"), false, label .. "no pointer subscriber")
  g:touchpressed(1, 50, 60, 0, 0, 1)
  g:touchmoved(1, 55, 66, 5, 6, 1)
  g:touchreleased(1, 55, 66, 0, 0, 1)
  g:mousepressed(30, 40, 1, false)
  g:mousemoved(34, 42, 4, 2, false)
  g:mousereleased(34, 42, 1, false)
  T.eq(g.modPointers, nil, label .. "unsubscribed handlers allocate no pointer state")
  g:cancelPointers()
  T.eq(g:logicSpeed(), 4, label .. "unsubscribed native speed resolution")
  bare.release()

  local run = T.sdk.loadMods({ "mods/fix_unified_input_speed" }, options(generation))
  T.eq(#run.errors, 0, label .. "API 3 fixture loads: " .. tostring(run.errors[1]))
  local fx = run.loader.exports.fix_unified_input_speed
  local seen, speed = fx.seen, fx.speed
  g = owner(generation, run)

  fx.viewport.enabled = true
  local rect = Viewport.begin(generation)
  T.eq(rect.x, 20, label .. "real viewport hook sets the origin")
  g:touchpressed(7, 50, 60, 0, 0, 0.5)
  g:touchmoved(7, 55, 66, 5, 6, 0.75)
  g:touchreleased(7, 55, 66, 0, 0, 0.75)
  T.eq(#seen, 3, label .. "uncaptured touch has exactly three events")
  T.same(seen[1], { game = g, phase = "pressed", source = "touch", id = 7,
    x = 50, y = 60, dx = 0, dy = 0, pressure = 0.5,
    gameX = 30, gameY = 30, insideGame = true }, label .. "portable pointer payload")
  T.eq(seen[2].phase, "moved", label .. "touch moved follows press")
  T.eq(seen[2].dx, 5, label .. "touch delta x")
  T.eq(seen[2].dy, 6, label .. "touch delta y")
  T.eq(seen[2].pressure, 0.75, label .. "touch pressure updates")
  T.eq(seen[3].phase, "released", label .. "touch release closes sequence")
  T.eq(g.modPointers[7], nil, label .. "released touch is no longer tracked")

  wipe(seen)
  g:touchpressed("outside", 19, 29)
  g:touchreleased("outside", 140, 110)
  T.eq(seen[1].gameX, -1, label .. "outside x remains relative to viewport")
  T.eq(seen[1].gameY, -1, label .. "outside y remains relative to viewport")
  T.eq(seen[1].insideGame, false, label .. "outside press is marked outside")
  T.eq(seen[2].insideGame, false, label .. "right and bottom viewport edges are outside")
  Viewport.reset()

  wipe(seen)
  g:mousepressed(30, 40, 1, true)
  g:mousemoved(34, 42, 4, 2, true)
  g:mousereleased(34, 42, 1, true)
  T.eq(#seen, 0, label .. "synthetic touch mouse twins are ignored")
  g:mousepressed(30, 40, 1, false)
  g:mousemoved(34, 42, 4, 2, false)
  g:mousereleased(34, 42, 1, false)
  T.eq(#seen, 3, label .. "real mouse has exactly three events")
  T.eq(seen[1].phase, "pressed", label .. "mouse begins pressed")
  T.eq(seen[1].source, "mouse", label .. "mouse source")
  T.eq(seen[1].id, "mouse", label .. "mouse identifier")
  if generation ~= 3 or os.getenv("POKEPORT_TOUCH") ~= "1" then
    T.eq(seen[1].button, 1, label .. "real mouse button")
  end
  T.eq(seen[2].phase, "moved", label .. "mouse moved follows press")
  T.eq(seen[2].dx, 4, label .. "mouse delta x")
  T.eq(seen[2].dy, 2, label .. "mouse delta y")
  T.eq(seen[3].phase, "released", label .. "mouse release closes sequence")
  T.eq(g.modPointers.mouse, nil, label .. "mouse release removes tracking")

  TouchControls.active, TouchControls.enabled = true, true
  TouchControls.img = { stub = true }
  local layout = TouchControls:layout()
  wipe(seen)
  g:touchpressed(21, layout.a.cx, layout.a.cy)
  T.eq(Input:isDown("a"), true, label .. "virtual A captures and holds real Input")
  g:touchmoved(21, 5, 5)
  g:touchreleased(21, 5, 5)
  T.eq(Input:isDown("a"), false, label .. "captured release clears Input")
  T.eq(#seen, 0, label .. "captured touch never enters the mod lifecycle")

  wipe(seen)
  g:touchpressed(22, 5, 5)
  g:touchmoved(22, layout.a.cx, layout.a.cy)
  T.eq(Input:isDown("a"), false, label .. "outside drag cannot acquire a virtual control")
  g:touchreleased(22, layout.a.cx, layout.a.cy)
  T.eq(#seen, 3, label .. "outside drag stays visible across a control")
  T.eq(seen[2].dx, layout.a.cx - 5, label .. "missing delta x derives from last position")
  T.eq(seen[2].dy, layout.a.cy - 5, label .. "missing delta y derives from last position")

  wipe(seen)
  g:touchpressed(23, layout.a.cx, layout.a.cy)
  g:touchpressed(40, 5, 5, 0, 0, 0.5)
  g:touchmoved(40, 10, 12, 5, 7, 0.75)
  g:focus(false)
  T.eq(#seen, 3, label .. "focus loss cancels only the uncaptured pointer once")
  T.eq(seen[3].phase, "cancelled", label .. "focus cancellation phase")
  T.eq(seen[3].id, 40, label .. "focus cancellation identifier")
  T.eq(seen[3].x, 10, label .. "cancellation retains last x")
  T.eq(seen[3].y, 12, label .. "cancellation retains last y")
  T.eq(seen[3].pressure, 0.75, label .. "cancellation retains pressure")
  T.eq(g.modPointers, nil, label .. "focus drops tracking through native cancellation")
  T.eq(Input:isDown("a"), false, label .. "focus clears the captured Input hold")
  g:touchreleased(40, 10, 12)
  g:touchreleased(23, layout.a.cx, layout.a.cy)
  g:focus(false)
  T.eq(#seen, 3, label .. "late release and repeated focus do not duplicate cancellation")
  TouchControls.active, TouchControls.img = false, nil
  TouchControls:reset()

  T.eq(g:logicSpeed(), 4, label .. "native logicSpeed falls through the API 3 hook")
  T.eq(speed.calls, 1, label .. "speed hook runs exactly once")
  T.eq(speed.game, g, label .. "speed hook receives the native owner")
  T.eq(speed.extra, 0, label .. "speed hook has no invented arguments")
  T.eq(speed.vanilla, 4, label .. "next returns native options resolution")
  local other = owner(generation, run)
  other.save.options.speedOverworld, other.options.speed, other.options.speedOverworld = 10, 10, 10
  speed.nextGame = other
  T.eq(g:logicSpeed(), 10, label .. "next forwards its owner argument to native resolution")
  speed.nextGame = nil
  speed.mode = "override"
  for _, case in ipairs({
    { name = "nil", expected = 1 },
    { name = "NaN", value = 0 / 0, expected = 1 },
    { name = "negative", value = -10, expected = 1 },
    { name = "zero", value = 0, expected = 1 },
    { name = "large", value = 1000000000, expected = 200 },
    { name = "valid", value = 20, expected = 20 },
  }) do
    speed.value = case.value
    local before = speed.calls
    T.eq(g:logicSpeed(), case.expected, label .. case.name .. " hook output clamps")
    T.eq(speed.calls, before + 1, label .. case.name .. " output came from real hook")
  end

  speed.value = 200
  g.speedOverride = 20
  local before = speed.calls
  T.eq(g:logicSpeed(), 20, label .. "explicit speed override wins over mod output")
  T.eq(speed.calls, before, label .. "explicit override bypasses hook")
  if generation == 3 then g.phase = "arena" else g.linkSession = true end
  T.eq(g:speedLocked(), true, label .. "native lock is active")
  T.eq(g:logicSpeed(), 1, label .. "native lock wins over explicit override")
  g.speedOverride = nil
  T.eq(g:logicSpeed(), 1, label .. "native lock wins over mod output")
  T.eq(speed.calls, before, label .. "locked speed never enters hook")
  g.linkSession, g.phase = nil, "field"
  T.eq(g:logicSpeed(), 200, label .. "unlock restores mod authority")

  if generation == 3 then
    g.phase = "boot"
    before = speed.calls
    for _, phase in ipairs({ Boot.PHASE.INTRO, Boot.PHASE.TITLE,
        Boot.PHASE.TITLE_CRY, Boot.PHASE.TITLE_RESTART }) do
      g.boot = { phase = phase }
      T.eq(g:logicSpeed(), 1, label .. phase .. " forces native speed")
      T.eq(speed.calls, before, label .. phase .. " bypasses speed hook")
    end
    g.speedOverride = 20
    T.eq(g:logicSpeed(), 20, label .. "explicit override retains boot precedence")
    g.speedOverride, g.boot.phase = nil, Boot.PHASE.MENU
    T.eq(g:logicSpeed(), 200, label .. "boot menu permits mod speed")

    g.phase = "field"
    wipe(seen)
    local token = fx.input:press(g, "b")
    T.eq(Input:isDown("b"), true, label .. "mod hold is live before release")
    g:touchpressed(50, 50, 60)
    g:mousepressed(30, 40, 1, false)
    g:_releaseModInput()
    T.eq(Input:isDown("b"), false, label .. "native release clears mod Input")
    T.eq(fx.input:release(token), false, label .. "native release retires hold token")
    local cancelled = {}
    for i = 3, #seen do
      T.eq(seen[i].phase, "cancelled", label .. "release cancels each live pointer")
      cancelled[seen[i].id] = true
    end
    T.eq(#seen, 4, label .. "release cancels touch and mouse exactly once")
    T.same(cancelled, { [50] = true, mouse = true }, label .. "release preserves pointer IDs")
    T.eq(g.modPointers, nil, label .. "release clears pointer state")
    g:_releaseModInput()
    T.eq(#seen, 4, label .. "repeated native release is idempotent")

    wipe(seen)
    g:touchpressed(60, 70, 80, 0, 0, 0.5)
    g:reset()
    T.eq(#seen, 2, label .. "real reset cancels a live pointer once")
    T.eq(seen[2].phase, "cancelled", label .. "reset emits cancellation")
    T.eq(seen[2].id, 60, label .. "reset cancellation retains pointer ID")
    T.eq(g.modPointers, nil, label .. "reset clears pointer state")
    g:touchreleased(60, 70, 80)
    T.eq(#seen, 2, label .. "late release after reset is ignored")
  end

  g = owner(generation, run)
  wipe(seen)
  g:touchpressed(70, 10, 20)
  fx.stopPointer()
  T.eq(Runtime.wantsHook("input.pointer"), false, label .. "unsubscribe removes pointer hook")
  g:cancelPointers()
  T.eq(g.modPointers, nil, label .. "cancellation after unsubscribe still clears state")
  T.eq(#seen, 1, label .. "unsubscribed cancellation has no callback")
  g:touchpressed(71, 10, 20)
  T.eq(g.modPointers, nil, label .. "unsubscribed press allocates no new state")
  fx.stopSpeed()
  T.eq(g:logicSpeed(), 4, label .. "speed unsubscribe restores native fall-through")
  T.eq(#run.errors, 0, label .. "native input and speed hooks report no mod errors")
  run.release()
  Viewport.reset()
  TouchControls:reset()
  Input:reset()
end

T.finish("unified_input_speed")
