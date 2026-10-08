package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Flow = require("src.ui.union.Flow")

local function fakeClient(gens)
  local rs = { left = false, closed = false }
  function rs:send() return true end
  function rs:close() self.left = true end
  local C = {
    rs = rs,
    room = function() return { room = "r1", intent = "xg", xg = { gens = gens } } end,
    seat = function() return 1 end,
    roomSession = function() return rs end,
  }
  return C
end

local launches = {}
Flow.seams.launch = {
  start = function(game, gen, session, act)
    launches[#launches + 1] = { game = game, gen = gen, session = session, act = act }
    return { kind = "fake" }
  end,
}

local function activity(Activity, extra)
  local marks = { dropped = 0, left = 0, done = 0 }
  local act = setmetatable({
    game = { save = { player = { name = "RED" } } },
    room = { dropPrep = function() marks.dropped = marks.dropped + 1 end },
    prep = { go = { rev = 3, seed = 77, match = "m1", ruleset = "g3u", size = 2 },
             leave = function() marks.left = marks.left + 1 end, open = function() return true end },
    peer = { name = "GOLD" },
    battlePrep = { records = { { species = 25 }, { species = 1 } }, team = { 3, 1 }, size = 2,
                   ruleset = { id = "g3u", gens = { 2, 1 } }, seed = 77, match = "m1", rev = 3 },
    opts = { onDone = function() marks.done = marks.done + 1 end },
    state = "ready", done = false,
  }, Activity)
  for k, v in pairs(extra or {}) do act[k] = v end
  return act, marks
end

do
  Flow.seams.client = fakeClient({ 2, 1 })
  local Activity = require("src.ui.union.gen1.Activity")
  local act, marks = activity(Activity)
  act:finish("go")
  T.eq(#launches, 1, "gen 1: go starts the battle")
  local l = launches[1]
  T.eq(l and l.gen, 1, "gen 1: in the Gen 1 presenter")
  T.eq(l and l.act, act, "gen 1: with the activity")
  local s = l and l.session or {}
  T.eq(s.ruleset, "g3u", "gen 1: ruleset from the relay go")
  T.eq(s.seat, 1, "gen 1: my relay seat")
  T.eq(s.gens and s.gens[0], 2, "gen 1: seat 0 gen from the room")
  T.eq(s.gens and s.gens[1], 1, "gen 1: seat 1 gen from the room")
  T.eq(s.names and s.names[1], "RED", "gen 1: my name on my seat")
  T.eq(s.names and s.names[0], "GOLD", "gen 1: the peer on the other seat")
  T.eq(s.go and s.go.seed, 77, "gen 1: go seed")
  T.eq(s.go and s.go.size, 2, "gen 1: agreed size")
  T.eq(s.records and #s.records, 2, "gen 1: prepared records")
  T.eq(s.team and s.team[1], 3, "gen 1: prepared party order")
  T.eq(s.net, Flow.seams.client.rs, "gen 1: the room session is the battle net")
  T.check(not act.done, "gen 1: the activity stays open during the battle")
  T.eq(marks.left, 0, "gen 1: the xg room is kept for the battle")
  T.eq(marks.done, 0, "gen 1: the room presence stays busy")
  act:finish("battle_end")
  T.check(act.done, "gen 1: the battle end closes the activity")
  T.eq(marks.left, 1, "gen 1: the xg room is left after the battle")
  T.eq(marks.dropped, 1, "gen 1: the prep is dropped")
  T.eq(marks.done, 1, "gen 1: the presence is handed back")
  act:finish("battle_end")
  T.eq(marks.done, 1, "gen 1: a second finish is ignored")
end

do
  launches = {}
  Flow.seams.client = fakeClient({ 1, 2 })
  local Activity = require("src.ui.gen2.union.Activity")
  local ui = { done = 0 }
  local act, marks = activity(Activity, { session = { uiDone = function() ui.done = ui.done + 1 end } })
  act:finish("go")
  T.eq(#launches, 1, "gen 2: go starts the battle")
  T.eq(launches[1] and launches[1].gen, 2, "gen 2: in the Gen 2 presenter")
  T.eq(ui.done, 0, "gen 2: the room ui stays held during the battle")
  T.eq(marks.left, 0, "gen 2: the xg room is kept for the battle")
  act:finish("battle_end")
  T.eq(ui.done, 1, "gen 2: the room ui is released after the battle")
  T.eq(marks.left, 1, "gen 2: the xg room is left after the battle")
end

do
  launches = {}
  Flow.seams.launch = { start = function() return nil, "presenter_failed" end }
  Flow.seams.client = fakeClient({ 1, 2 })
  local Activity = require("src.ui.gen2.union.Activity")
  local ui = { done = 0 }
  local act = activity(Activity, { session = { uiDone = function() ui.done = ui.done + 1 end },
    game = { save = { player = { name = "GOLD" } }, stack = { push = function() end } } })
  act.closeUi = function() end
  local said
  package.loaded["src.ui.gen2.union.Dialog"].say = function(_, text, after) said = text if after then after() end end
  act:finish("go")
  T.check(act.done and act.why == "error", "a failed launch ends the activity with an error")
  T.check(said ~= nil, "and says so")
  T.eq(ui.done, 1, "and hands the room back")
end

do
  local Model = require("src.online.union.BattlePrepModel")
  local m = setmetatable({ owned = {
    { ref = { where = "party", index = 1 } }, { ref = { where = "party", index = 2 } },
    { ref = { where = "box", box = 1, index = 4 } }, { ref = { where = "party", index = 3 } } } }, Model)
  local list = { { base = 1 }, { base = 2 }, { base = 4 } }
  local idx = m:partyIndices({ 3, 1 }, list)
  T.eq(#idx, 2, "sit-outs leave the party list")
  T.eq(idx[1], 3, "party order follows the prepared slots")
  T.eq(idx[2], 1, "second slot")
  local swapped = m:partyIndices({ 1 }, { { base = 1, swap = { owned = 4 } } })
  T.eq(swapped[1], 3, "an owned swap uses the swapped mon's party index")
end

T.eq(Flow.gens({ 3, 1 })[1], 1, "relay gens list maps to seats")
T.eq(Flow.gens(nil), nil, "no gens list")

T.finish()
