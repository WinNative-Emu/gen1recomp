-- scripts/Route23.asm:195
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local played = {}
package.loaded["src.core.Sound"] = {
  play = function(_, id) played[#played + 1] = id; return nil end,
}

local OW = require("src.world.OverworldController")
local RealTextBox = require("src.render.TextBox")

local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end

local OH = "You can pass here\nonly if you have\vthe {RAM:wNameBuffer}!\fOh! That is the\n{RAM:wNameBuffer}!{DONE}"
local GO = "\fOK then! Please,\ngo right ahead!{DONE}"
local NO = "You can pass here\nonly if you have\vthe {RAM:wNameBuffer}!\fYou don't have the\n{RAM:wNameBuffer} yet!{DONE}"
local NO22 = "Only truly skilled\ntrainers are\vallowed through.\fYou don't have the\nBOULDERBADGE yet!{DONE}"
local RULES = "\fThe rules are\nrules. I can't\vlet you pass.{DONE}"

local pushed
local textBoxStub = setmetatable({
  new = function(_, text, onDone, opts)
    return { text = text, onDone = onDone, opts = opts }
  end,
}, { __index = RealTextBox })
local fakeGame = {
  data = {
    text = {
      _Route23OhThatIsTheBadgeText = OH,
      _Route23GoRightAheadText = GO,
      _Route23YouDontHaveTheBadgeYetText = NO,
      _Route22GateGuardNoBoulderbadgeText = NO22,
      _Route22GateGuardICantLetYouPassText = RULES,
    },
    items = { CASCADEBADGE = { name = "CASCADEBADGE" } },
    field = { badgeGates = {
      ROUTE_23 = {
        passText = "Route23OhThatIsTheBadgeText",
        failText = "Route23YouDontHaveTheBadgeYetText",
        guards = { { y = 96, badge = "CASCADEBADGE", event = "EVENT_PASSED_CASCADEBADGE_CHECK" } },
      },
      ROUTE_22_GATE = {
        badge = "BOULDERBADGE",
        passText = "Route22GateGuardGoRightAheadText",
        failText = "Route22GateGuardNoBoulderbadgeText",
        coords = { { x = 4, y = 2 } },
      },
    } },
  },
  save = { inventory = { CASCADEBADGE = 1 }, flags = {} },
  stack = { push = function(_, box) pushed = box end },
}
T.check(setUpvalue(OW.checkBadgeGate, "TextBox", textBoxStub),
  "TextBox upvalue on checkBadgeGate")
T.check(setUpvalue(OW.checkBadgeGate, "Game", fakeGame),
  "Game upvalue on checkBadgeGate")
T.check(type(OW.route23BadgeCheck) == "function", "route23BadgeCheck shared helper exists")
if OW.route23BadgeCheck then
  setUpvalue(OW.route23BadgeCheck, "TextBox", textBoxStub)
  setUpvalue(OW.route23BadgeCheck, "Game", fakeGame)
end

local moves = {}
local function newOw(x, y, mapId)
  return setmetatable({
    player = { cellX = x, cellY = y },
    map = { id = mapId or "ROUTE_23" },
    scriptMove = function(_, entity, dir, tiles, onDone, opts)
      moves[#moves + 1] = { entity = entity, dir = dir, tiles = tiles,
                            onDone = onDone, collide = opts and opts.collide }
    end,
  }, { __index = OW })
end

local function checkPassBox(label)
  local text = pushed and pushed.text or ""
  local ohAt = text:find("Oh! That is the\nCASCADEBADGE!", 1, true)
  local pauseAt = text:find(RealTextBox.PAUSE, 1, true)
  local goAt = text:find("OK then! Please,\ngo right ahead!", 1, true)
  T.check(ohAt ~= nil, label .. ": badge line present")
  T.check(goAt ~= nil, label .. ": go right ahead text follows the badge text")
  T.check(ohAt and pauseAt and goAt and ohAt < pauseAt and pauseAt < goAt,
    label .. ": fanfare mark sits between the badge line and the go-ahead page")
  T.check(not text:sub(1, (goAt or 1) - 1):find("{DONE}", 1, true),
    label .. ": badge text DONE stripped before the go-ahead page")
  local opts = pushed and pushed.opts or {}
  T.eq(opts.pauseSounds and opts.pauseSounds[1], "Get_Item1",
    label .. ": Get_Item1 rides the mid-string mark")
  T.eq(opts.pauseSoundWait, true, label .. ": fanfare waits like TextCommand_SOUND")
  local pages = RealTextBox.paginate((text:gsub(RealTextBox.PAUSE, "")))
  T.eq(#pages, 3, label .. ": pass text is three pages")
end

local function checkFailBox(label)
  local text = pushed and pushed.text or ""
  T.check(text:find("You don't have the\nCASCADEBADGE yet!", 1, true) ~= nil,
    label .. ": fail text shown")
  T.eq(#played, 0, label .. ": no SFX_DENIED before the text")
  local opts = pushed and pushed.opts or {}
  T.check(opts.auto and type(opts.auto.sound) == "function",
    label .. ": SFX_DENIED armed as the trailing text_asm sound")
  T.eq(opts.auto and opts.auto.wait, true, label .. ": button wait after the sound")
  if opts.auto and opts.auto.sound then opts.auto.sound() end
  T.eq(played[1], "Denied", label .. ": the trailing sound is SFX_DENIED")
  T.check(pushed and type(pushed.onDone) == "function",
    label .. ": the box closes into Route23MovePlayerDownScript")
end

pushed, played, moves = nil, {}, {}
local self_ = newOw(10, 96)
T.eq(self_:checkBadgeGate(), false, "badge holder walks on")
T.check(pushed ~= nil, "pass text box pushed")
checkPassBox("step")
T.eq(fakeGame.save.flags.EVENT_PASSED_CASCADEBADGE_CHECK ~= nil, true, "pass flag set")

pushed, played, moves = nil, {}, {}
fakeGame.save = { inventory = {}, flags = {} }
self_ = newOw(10, 96)
T.eq(self_:checkBadgeGate(), true, "no badge: the step is blocked")
T.check(pushed ~= nil, "fail text box pushed")
checkFailBox("step")
if pushed and pushed.onDone then pushed.onDone() end
T.eq(#moves, 1, "step fail: one scripted move after the box")
T.eq(moves[1] and moves[1].dir, "down", "step fail: the move is down")
T.eq(moves[1] and moves[1].tiles, 1, "step fail: one tile")
T.eq(moves[1] and moves[1].collide, true, "step fail: simulated d-pad collides")
T.eq(moves[1] and moves[1].entity, self_.player, "step fail: the player walks")
T.eq(fakeGame.save.flags.EVENT_PASSED_CASCADEBADGE_CHECK, nil, "no pass flag without the badge")

local R23 = require("data.scripts.flavor.route_23")
local talk = R23.ROUTE_23.talk
local expect = {
  TEXT_ROUTE23_GUARD1 = { "EARTHBADGE", "EVENT_PASSED_EARTHBADGE_CHECK" },
  TEXT_ROUTE23_GUARD2 = { "VOLCANOBADGE", "EVENT_PASSED_VOLCANOBADGE_CHECK" },
  TEXT_ROUTE23_GUARD3 = { "RAINBOWBADGE", "EVENT_PASSED_RAINBOWBADGE_CHECK" },
  TEXT_ROUTE23_GUARD4 = { "THUNDERBADGE", "EVENT_PASSED_THUNDERBADGE_CHECK" },
  TEXT_ROUTE23_GUARD5 = { "CASCADEBADGE", "EVENT_PASSED_CASCADEBADGE_CHECK" },
  TEXT_ROUTE23_SWIMMER1 = { "MARSHBADGE", "EVENT_PASSED_MARSHBADGE_CHECK" },
  TEXT_ROUTE23_SWIMMER2 = { "SOULBADGE", "EVENT_PASSED_SOULBADGE_CHECK" },
}
for id, want in pairs(expect) do
  local badge, flag = want[1], want[2]
  T.eq(type(talk[id]), "function", id .. " is a Lua talk handler")
  if type(talk[id]) == "function" then
    fakeGame.data.items[badge] = { name = badge }
    pushed, played, moves = nil, {}, {}
    fakeGame.save = { inventory = { [badge] = 1 }, flags = {} }
    local doneCalls = 0
    local ow = newOw(7, 136)
    talk[id](fakeGame, ow, {}, function() doneCalls = doneCalls + 1 end)
    T.check(pushed ~= nil, id .. " pass: one box pushed")
    local text = pushed and pushed.text or ""
    T.check(text:find("Oh! That is the\n" .. badge .. "!", 1, true) ~= nil,
      id .. " pass: badge line names " .. badge)
    local pauseAt = text:find(RealTextBox.PAUSE, 1, true)
    local goAt = text:find("OK then! Please,\ngo right ahead!", 1, true)
    T.check(pauseAt and goAt and pauseAt < goAt, id .. " prints go-ahead after the badge text")
    local opts = pushed and pushed.opts or {}
    T.eq(opts.pauseSounds and opts.pauseSounds[1], "Get_Item1", id .. " pass: Get_Item1 on the mark")
    T.eq(opts.pauseSoundWait, true, id .. " pass: fanfare waits")
    T.eq(fakeGame.save.flags[flag] ~= nil, true, id .. " sets " .. flag)
    T.eq(#played, 0, id .. " pass: nothing played before the box")
    if pushed and pushed.onDone then pushed.onDone() end
    T.eq(doneCalls, 1, id .. " pass: done fires when the box closes")
    T.eq(#moves, 0, id .. " pass: no scripted move")

    pushed, played, moves = nil, {}, {}
    fakeGame.save = { inventory = {}, flags = {} }
    doneCalls = 0
    ow = newOw(7, 136)
    talk[id](fakeGame, ow, {}, function() doneCalls = doneCalls + 1 end)
    T.check(pushed ~= nil, id .. " fail: box pushed")
    text = pushed and pushed.text or ""
    T.check(text:find("You don't have the\n" .. badge .. " yet!", 1, true) ~= nil,
      id .. " fail: text names " .. badge)
    T.eq(#played, 0, id .. " fail: no SFX_DENIED before the text")
    opts = pushed and pushed.opts or {}
    T.check(opts.auto and type(opts.auto.sound) == "function",
      id .. " fail: SFX_DENIED armed after the text")
    if opts.auto and opts.auto.sound then opts.auto.sound() end
    T.eq(played[1], "Denied", id .. " fail: trailing sound is SFX_DENIED")
    T.eq(doneCalls, 0, id .. " fail: done waits for the walk")
    if pushed and pushed.onDone then pushed.onDone() end
    T.eq(#moves, 1, id .. " fail: Route23MovePlayerDownScript queued")
    T.eq(moves[1] and moves[1].dir, "down", id .. " fail: walks down")
    T.eq(moves[1] and moves[1].collide, true, id .. " fail: simulated d-pad collides")
    T.check(moves[1] and type(moves[1].onDone) == "function",
      id .. " fail: move carries an onDone")
    if moves[1] and moves[1].onDone then moves[1].onDone() end
    T.eq(doneCalls, 1, id .. " fail: done fires after the walk")
    T.eq(fakeGame.save.flags[flag], nil, id .. " fail: no pass flag")
  end
end

pushed, played, moves = nil, {}, {}
fakeGame.save = { inventory = {}, flags = {} }
self_ = newOw(4, 2, "ROUTE_22_GATE")
T.eq(self_:checkBadgeGate(), true, "Route 22 gate: no badge blocks the step")
T.check(pushed ~= nil, "Route 22 gate: fail box pushed")
local text22 = pushed and pushed.text or ""
local noAt = text22:find("BOULDERBADGE yet!", 1, true)
local pause22 = text22:find(RealTextBox.PAUSE, 1, true)
local rulesAt = text22:find("The rules are", 1, true)
T.check(noAt and pause22 and rulesAt and noAt < pause22 and pause22 < rulesAt,
  "Route 22 gate: Denied mark sits between the two texts")
T.eq(#played, 0, "Route 22 gate: no SFX_DENIED before the text")
local opts22 = pushed and pushed.opts or {}
T.eq(opts22.pauseSounds and opts22.pauseSounds[1], "Denied", "Route 22 gate: mark plays SFX_DENIED")
T.eq(opts22.pauseSoundWait, true, "Route 22 gate: sound waits")
T.check(not text22:sub(1, (rulesAt or 1) - 1):find("{DONE}", 1, true),
  "Route 22 gate: first text DONE stripped")

T.finish("route23_go_right_ahead_bug2649")
