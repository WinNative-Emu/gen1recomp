package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._g3u_fixture")
local L = require("tests.support.g3u_loopback")
local Table = require("src.battle.g3u.Table")
local BS = require("src.online.union.BattleSession")

local data = F.gen1()
local t = assert(Table.build(data, 1))

local function stack()
  local s = { states = {} }
  function s:push(st) self.states[#self.states + 1] = st if st.enter then st:enter() end end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end

local started = {}
package.loaded["src.ui.g3u.Gen1Screen"] = {
  start = function(game, bs, opts)
    started[#started + 1] = { game = game, bs = bs, opts = opts }
    return { screen = true }
  end,
}

local Launch = require("src.ui.g3u.Launch")

T.eq(select(2, Launch.start({}, 4, { net = {} })), "bad_gen", "unknown gen is refused")
T.eq(select(2, Launch.start({}, 1, {})), "no_session", "missing net is refused")
T.eq(select(2, Launch.start({}, 1, { net = {}, ruleset = "x" })), "bad_ruleset", "unknown ruleset is refused")

do
  local na, nb = L.pair()
  local results = {}
  local h, why = Launch.start({ stack = stack() }, 1, {
    ruleset = "g3u", net = na, seat = 0, go = { seed = 5, size = 6 }, gens = { [0] = 1, [1] = 3 },
    data = data, records = F.randomParty(t, L.lcg(2), 2), names = { [0] = "RED", [1] = "MAY" },
    onDone = function(r) results[#results + 1] = r end,
  })
  T.check(h ~= nil, "g3u launch returns a handle (" .. tostring(why) .. ")")
  T.eq(h and h.kind, "g3u", "handle kind g3u")
  local call = started[1]
  T.check(call and getmetatable(call.bs) == BS, "the gen 1 presenter receives a BattleSession")
  T.eq(call and call.opts.names.me, "RED", "presenter gets my name")
  T.eq(call and call.opts.names.foe, "MAY", "presenter gets the foe name")
  T.eq(nb.inbox[1] and require("src.link.Json").decode(nb.inbox[1]).type, "g3u_table",
    "the lower seat's session sent the table")
  call.opts.onDone({ outcome = "win" })
  call.opts.onDone({ outcome = "lose" })
  T.eq(#results, 1, "onDone fires once")
end

do
  local na = L.pair()
  local h, why = Launch.start({ stack = stack(), save = { version = "red" } }, 1, {
    ruleset = "g3u", net = na, seat = 1, go = { seed = 5 }, gens = { [0] = 1, [1] = 3 },
    records = F.randomParty(t, L.lcg(2), 1),
  })
  T.check(h ~= nil, "higher seat needs no dataset (" .. tostring(why) .. ")")
end

do
  local na = L.pair()
  local finished = {}
  local act = { finish = function(self, kind, text) finished[#finished + 1] = { self = self, kind = kind, text = text } end }
  local results = {}
  Launch.start({ stack = stack() }, 1, {
    ruleset = "g3u", net = na, seat = 0, go = { seed = 5 }, gens = { [0] = 1, [1] = 2 }, data = data,
    records = F.randomParty(t, L.lcg(3), 1), onDone = function(r) results[#results + 1] = r end,
  }, act)
  local call = started[#started]
  call.opts.onDone({ outcome = "win", why = "faint" })
  T.eq(#results, 1, "session onDone still fires with an act")
  T.eq(finished[1] and finished[1].kind, "battle_end", "the act is finished with battle_end")
  T.check(finished[1] and finished[1].self == act, "act:finish is a method call")
  T.eq(finished[1] and finished[1].text, Launch.resultText(1, { outcome = "win" }), "act gets the result line")
  T.eq(Launch.resultText(3, { outcome = "draw", why = "desync" }), Launch.RESULT_TEXT[3].desync, "desync line")
  T.eq(Launch.resultText(2, "lose"), Launch.RESULT_TEXT.gb.lose, "native word result line")
end

do
  local client = { room = function() return nil end, state = function() return "online" end }
  T.eq(Launch.linkState(client, "r1")(), "gone", "no room means gone")
  client.room = function() return { room = "r2" } end
  T.eq(Launch.linkState(client, "r1")(), "gone", "another room means gone")
  client.room = function() return { room = "r1" } end
  T.eq(Launch.linkState(client, "r1")(), "ok", "same room online is ok")
  client.state = function() return "reconnecting" end
  T.eq(Launch.linkState(client, "r1")(), "resuming", "reconnecting is resuming")
end

local linkCalls = {}
local function fakeLinkBattle(name)
  local function make(role)
    return function(game, net, opts)
      local battle = { role = role, opts = opts, net = net }
      linkCalls[#linkCalls + 1] = { mod = name, role = role, opts = opts }
      return battle
    end
  end
  package.loaded[name] = { newHost = make("host"), newGuest = make("guest") }
end
fakeLinkBattle("src.link.LinkBattle")
fakeLinkBattle("src.link.LinkBattle2")
package.loaded["src.link.Protocol"] = {
  packParty = function(party, idx)
    local out = {}
    for i, j in ipairs(idx) do out[i] = { species = party[j].species } end
    return out
  end,
  packParty2 = function(party, idx)
    local out = {}
    for i, j in ipairs(idx) do out[i] = { species = party[j].species, gen = 2 } end
    return out
  end,
}

for _, gen in ipairs({ 1, 2 }) do
  local na, nb = L.pair()
  local st = stack()
  local reports, results = {}, {}
  local save = { party = { { species = "PIKACHU" }, { species = "ONIX" }, { species = "MEW" } } }
  local game = { stack = st, save = save }
  local h = Launch.start(game, gen, {
    ruleset = "native", net = na, seat = 1, go = { seed = 777, size = 2 }, team = { 3, 1, 2 },
    names = { [0] = "BLUE", [1] = "RED" }, client = { report = function(w) reports[#reports + 1] = w end },
    onDone = function(r) results[#results + 1] = r end,
  })
  T.eq(h and h.kind, "native", "gen " .. gen .. " native launch pushes the party exchange")
  local sent = require("src.link.Json").decode(nb.inbox[1])
  T.eq(sent.type, "party", "gen " .. gen .. " native sends its party")
  T.eq(#sent.mons, 2, "gen " .. gen .. " native trims the team to go.size")
  T.eq(sent.mons[1].species, "MEW", "gen " .. gen .. " native keeps the prep team order")
  local state = st:top()
  state:update(0.1)
  T.eq(#linkCalls, (gen - 1) * 1, "gen " .. gen .. " waits for the peer party")
  nb:send({ type = "party", mons = { { species = "GENGAR" } } })
  state:update(0.1)
  local call = linkCalls[#linkCalls]
  T.eq(call.mod, gen == 2 and "src.link.LinkBattle2" or "src.link.LinkBattle", "gen " .. gen .. " uses its link battle")
  T.eq(call.role, "guest", "seat 1 plays the guest role")
  T.eq(call.opts.seed, 777, "seed comes from xg_go")
  T.eq(call.opts.verdict, "full", "fingerprint already agreed by the relay")
  T.check(call.opts.keepNetOpen, "the room session stays open for the room")
  T.eq(call.opts.theirName, "BLUE", "peer name from the room")
  T.eq(#st.states, 2, "link battle pushed over the party exchange")
  local battle = st:pop()
  battle.result = "win"
  state:update(0.1)
  T.eq(#st.states, 0, "the exchange state pops itself after the battle")
  T.eq(reports[1], "win", "native result is reported")
  T.eq(results[1], "win", "onDone gets the native result")
  T.eq(save.party[1].species, "PIKACHU", "the real party is untouched")
end

T.finish("union_battle_launch")
