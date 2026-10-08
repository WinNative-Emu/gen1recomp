local BattleSession = require("src.online.union.BattleSession")

local Launch = {}

Launch.PRESENTERS = {
  [1] = "src.ui.g3u.Gen1Screen",
  [2] = "src.ui.g3u.Gen2Facade",
  [3] = "src.ui.g3u.Gen3Presenter",
}

Launch.NATIVE_WAIT = 60

local function version(game)
  local GameVersion = require("src.core.GameVersion")
  return (game and game.save and game.save.version) or GameVersion.get()
end

local function once(fn)
  local done = false
  return function(...)
    if done then return end
    done = true
    if fn then return fn(...) end
  end
end

function Launch.linkState(client, roomId)
  if type(client) ~= "table" then return nil end
  return function()
    local room = type(client.room) == "function" and client.room() or nil
    if not room or (roomId ~= nil and room.room ~= roomId) then return "gone" end
    if type(client.state) == "function" and client.state() ~= "online" then return "resuming" end
    return "ok"
  end
end

function Launch.names(session, seat)
  local n = session.names or {}
  return { me = n[seat], foe = n[1 - seat] }
end

function Launch.session(game, session)
  local seat = tonumber(session.seat)
  if seat ~= 0 and seat ~= 1 then return nil, "no_seat" end
  local gens = session.gens or {}
  local lower = BattleSession.lowerSeat(gens)
  local data = session.data
  if not data and lower == seat and not session.table then
    local Datasets = require("src.online.xgen.Datasets")
    local why
    data, why = Datasets.get(version(game))
    if not data then return nil, why or "missing_import" end
  end
  local client = session.client
  return BattleSession.new({
    net = session.net,
    seat = seat,
    go = session.go,
    gens = gens,
    data = data,
    table = session.table,
    records = session.records,
    names = session.names,
    client = client,
    linkState = session.linkState or Launch.linkState(client, session.roomId),
    timeouts = session.timeouts,
  })
end

local function startG3u(game, gen, session)
  local bs, why = Launch.session(game, session)
  if not bs then return nil, why end
  local mod = require(Launch.PRESENTERS[gen])
  local done = once(session.onDone)
  local handle, err = mod.start(game, bs, {
    names = Launch.names(session, bs.seat),
    foeClass = session.foeClass,
    onDone = function(result) done(result) end,
  })
  if not handle then
    bs:quit()
    return nil, err or "presenter_failed"
  end
  return { kind = "g3u", gen = gen, bs = bs, screen = handle }
end

local Native = {}
Native.__index = Native

function Native.new(game, gen, session)
  local Protocol = require("src.link.Protocol")
  local party = game.save and game.save.party or {}
  local size = tonumber(session.go and session.go.size) or 6
  local indices = {}
  for _, i in ipairs(session.team or {}) do
    if party[i] and #indices < size then indices[#indices + 1] = i end
  end
  if #indices == 0 then
    for i = 1, math.min(#party, size) do indices[i] = i end
  end
  if #indices == 0 then return nil, "no_party" end
  local packed = gen == 2 and Protocol.packParty2(party, indices) or Protocol.packParty(party, indices)
  local self = setmetatable({
    game = game, gen = gen, session = session, net = session.net,
    seat = tonumber(session.seat) or 0, packed = packed, stage = "party",
    waited = 0, done = once(session.onDone), isOpaque = false,
  }, Native)
  return self
end

function Native:enter()
  self.net:send({ type = "party", mons = self.packed })
end

function Native:takeParty()
  local net = self.net
  if type(net.take) == "function" then return net:take("party") end
  if type(net.takeWhere) == "function" then
    return net:takeWhere(function(m) return m.type == "party" end)
  end
  return nil
end

function Native:finish(result)
  if self.stage == "over" then return end
  self.stage = "over"
  local game = self.game
  if game.linkNet == self.net then game.linkNet = nil end
  game.linkSession = nil
  if game.stack:top() == self then game.stack:pop() end
  local client = self.session.client
  if client and (result == "win" or result == "lose" or result == "draw") and type(client.report) == "function" then
    pcall(client.report, result)
  end
  self.done(result)
end

function Native:start(theirs)
  local session, game = self.session, self.game
  local names = Launch.names(session, self.seat)
  local opts = {
    myParty = self.packed,
    theirParty = theirs.mons,
    theirName = names.foe or "FOE",
    seed = tonumber(session.go and session.go.seed) or 1,
    verdict = "full",
    strict = true,
    keepNetOpen = true,
  }
  local LB = require(self.gen == 2 and "src.link.LinkBattle2" or "src.link.LinkBattle")
  local battle, why
  if self.seat == 0 then
    battle, why = LB.newHost(game, self.net, opts)
  else
    battle, why = LB.newGuest(game, self.net, opts)
  end
  if not battle then
    self.net:send({ type = "bye" })
    return self:finish("error", why)
  end
  self.battle = battle
  self.stage = "battle"
  game.linkSession = true
  game.stack:push(battle)
end

function Native:update(dt)
  if self.stage == "party" then
    if type(self.net.update) == "function" then self.net:update() end
    local theirs = self:takeParty()
    if theirs and type(theirs.mons) == "table" then return self:start(theirs) end
    self.waited = self.waited + (dt or 0)
    if self.net.closed or self.waited > Launch.NATIVE_WAIT then return self:finish("error") end
    return
  end
  if self.stage == "battle" and self.game.stack:top() == self then
    local battle = self.battle
    self.battle = nil
    self:finish((battle and battle.result) or "draw")
  end
end

function Native:draw() end

local function startNative(game, gen, session)
  if gen == 3 then
    local Gen3 = require(Launch.PRESENTERS[3])
    return Gen3.startNative(game, session, { onDone = once(session.onDone) })
  end
  local state, why = Native.new(game, gen, session)
  if not state then return nil, why end
  game.stack:push(state)
  return { kind = "native", gen = gen, state = state }
end

Launch.RESULT_TEXT = {
  [3] = { win = "You won the battle!", lose = "You lost the battle.", draw = "The battle ended in a draw.",
    desync = "The battle stopped: the two games disagreed.", disconnect = "The link was lost.",
    error = "The battle could not continue." },
  gb = { win = "You won the\nbattle!", lose = "You lost the\nbattle.", draw = "The battle was\na draw.",
    desync = "The games fell\nout of step.", disconnect = "The link was\nlost.",
    error = "The battle could\nnot go on." },
}

function Launch.resultText(gen, result)
  local set = Launch.RESULT_TEXT[gen == 3 and 3 or "gb"]
  if type(result) == "string" then return set[result] or set.error end
  if type(result) ~= "table" then return set.error end
  local why = result.why
  if why == "desync" or why == "disconnect" then return set[why] end
  if why == "illegal" or why == "error" or why == "bad_table" or why == "bad_party" then return set.error end
  return set[result.outcome] or set.error
end

function Launch.start(game, gen, session, act)
  gen = tonumber(gen)
  if not Launch.PRESENTERS[gen] then return nil, "bad_gen" end
  if type(session) ~= "table" or type(session.net) ~= "table" then return nil, "no_session" end
  if act ~= nil then
    local inner = session.onDone
    local wrapped = {}
    for k, v in pairs(session) do wrapped[k] = v end
    wrapped.onDone = function(result)
      if inner then inner(result) end
      if type(act) == "table" and type(act.finish) == "function" then
        act:finish("battle_end", Launch.resultText(gen, result))
      end
    end
    session = wrapped
  end
  local ruleset = session.ruleset or (session.go and session.go.ruleset)
  if ruleset == "native" then return startNative(game, gen, session) end
  if ruleset ~= "g3u" then return nil, "bad_ruleset" end
  return startG3u(game, gen, session)
end

Launch.Native = Native

return Launch
