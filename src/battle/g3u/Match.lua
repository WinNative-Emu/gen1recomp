local Table = require("src.battle.g3u.Table")
local Scope = require("src.battle.g3u.Scope")
local Rng = require("src.battle.g3u.Rng")
local Hash = require("src.battle.g3u.Hash")
local Events = require("src.battle.g3u.Events")

local Match = {}
Match.__index = Match

local STAGES = { "attack", "defense", "speed", "spAtk", "spDef", "accuracy", "evasion" }
local GENDER = { [0] = "M", [1] = "F", [2] = "U" }
local MOVE_STRUGGLE = 165
local SIDE = { [0] = "player", [1] = "enemy" }

local function mods() return Scope.modules() end

local function engineMon(rec)
  local moves, pp, ups = {}, {}, {}
  for i, m in ipairs(rec.moves or {}) do
    moves[i] = m.id
    pp[i] = m.pp
    ups[i] = m.ppUps or 0
  end
  local iv = rec.ivs or {}
  return {
    species = rec.species, level = rec.level, hp = rec.hp, maxHp = rec.maxHp,
    attack = rec.atk, defense = rec.def, spAtk = rec.spAtk, spDef = rec.spDef, speed = rec.speed,
    moves = moves, pp = pp, ppUps = ups, nickname = rec.nickname,
    ivs = { hp = iv.hp or 0, atk = iv.atk or 0, def = iv.def or 0, spe = iv.spe or 0, spa = iv.spa or 0,
      spd = iv.spd or 0 },
    evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
    personality = 0, ability = 0, abilityId = 0, item = 0, heldItem = 0,
    gender = GENDER[rec.gender] or "U", friendship = rec.friendship or 0,
  }
end

function Match.new(opts)
  local t = opts.table
  local ok, why = Table.validate(t)
  if not ok then error("g3u table rejected: " .. tostring(why), 2) end
  local m = setmetatable({
    t = t, seed = math.floor(tonumber(opts.seed) or 0) % 4294967296, draws = { n = 0 },
    turn = 0, phase = "init", illegal = Table.illegalSet(t), hashes = {}, out = {},
    names = opts.names or {}, stageOwner = {}, stageSnap = {},
  }, Match)
  m.parties = { [0] = {}, [1] = {} }
  for seat = 0, 1 do
    for i, rec in ipairs(opts.parties[seat]) do m.parties[seat][i] = engineMon(rec) end
  end
  m.stack = Scope.newStack()
  m.co = coroutine.create(function() return m:_main() end)
  return m
end

function Match:_resume(arg)
  self.legalCache = nil
  self.out = {}
  local co = self.co
  Scope.run(self.t, function()
    local ok, err = coroutine.resume(co, arg)
    if not ok then error(debug.traceback(co, err), 0) end
  end, self.stack)
  local out = self.out
  self.out = {}
  return out
end

function Match:start()
  if self.phase ~= "init" then error("g3u match already started", 2) end
  return self:_resume()
end

function Match:_setup()
  local M = mods()
  local State = M["src.core.game3.battle.state"]
  local Adapter = M["src.core.game3.battle.adapter"]
  self.rng = Rng.make(self.seed, self.draws)
  local st = State.new({ playerParty = self.parties[0], foeParty = self.parties[1], rng = self.rng })
  st.link = true
  st.linkMaster = true
  st.terrain = 8
  st.g3u = true
  st.moveMax = self.t.moveMax
  st.moveExcluded = self.illegal
  st.playerName = self.names[0]
  st.peerName = self.names[1]
  self.st = st
  self.ad = Adapter.new(st, function() end)
  self.lastWeather = st.weather
end

function Match:_emit(ev)
  self.out[#self.out + 1] = ev
end

function Match:_drain()
  local ad, st = self.ad, self.st
  local raw = ad._events
  ad._events = {}
  local first = #self.out + 1
  Events.normalize(raw, self.out)
  local reported = { [0] = {}, [1] = {} }
  for i = first, #self.out do
    local ev = self.out[i]
    if ev.kind == "stage" and ev.side ~= nil then
      local r = reported[ev.side]
      r[ev.stat] = (r[ev.stat] or 0) + (ev.delta or 0)
    end
  end
  local State = mods()["src.core.game3.battle.state"]
  for seat = 0, 1 do
    local b = State.battler(st, seat)
    if b and b.stages then
      local snap = self.stageSnap[seat]
      if self.stageOwner[seat] == b and snap then
        for _, k in ipairs(STAGES) do
          local want = (snap[k] or 0) + (reported[seat][k] or 0)
          local cur = b.stages[k] or 0
          if cur ~= want then
            self:_emit({ kind = "stage", side = seat, stat = k, delta = cur - want, sync = true })
          end
        end
      end
      local copy = {}
      for _, k in ipairs(STAGES) do copy[k] = b.stages[k] or 0 end
      self.stageOwner[seat], self.stageSnap[seat] = b, copy
    end
  end
  if st.weather ~= self.lastWeather then
    self.lastWeather = st.weather
    self:_emit({ kind = "weather", weather = st.weather or "NONE", turns = st.weatherTurns })
  end
end

function Match:_hashNow()
  return Hash.value((Hash.parts(self.st, self.draws)))
end

function Match:hash(turn)
  if turn == nil then turn = self.turn end
  return self.hashes[turn]
end

function Match:_ask(need)
  self.phase = "replace"
  self.need = need
  for seat = 0, 1 do
    if need[seat] then self:_emit({ kind = "need_replacement", side = seat, reason = need[seat].kind }) end
  end
  local picks = coroutine.yield("replace")
  self.need = nil
  self.phase = "running"
  return picks
end

function Match:_finish(winner, why)
  local st = self.st
  st.over = true
  local result
  if winner == "draw" then
    result = { draw = true, why = why }
    st.result = "draw"
  else
    result = { winner = winner, why = why }
    st.result = (winner == 0) and "win" or "lose"
  end
  self.result = result
  self.phase = "over"
  self:_emit({ kind = "end", result = result })
end

local function anyFainted(st, State)
  return State.isFainted(st.player) or State.isFainted(st.enemy)
end

-- pokefirered/src/battle_util.c:1144
function Match:_handleFaints()
  local M = mods()
  local State, Engine = M["src.core.game3.battle.state"], M["src.core.game3.battle.engine"]
  local st, ad = self.st, self.ad
  while true do
    if st.over then return true end
    local pF, eF = State.isFainted(st.player), State.isFainted(st.enemy)
    if not pF and not eF then
      local r = Engine.checkEnd(st, ad)
      if r == "win" then self:_finish(0, "faint") return true end
      if r == "lose" then self:_finish(1, "faint") return true end
      if r == "draw" then self:_finish("draw", "faint") return true end
      return false
    end
    State.syncBattlerToParty(st.player, st.playerParty)
    State.syncBattlerToParty(st.enemy, st.foeParty)
    local pL, eL = Engine.hasLivingMons(st.playerParty), Engine.hasLivingMons(st.foeParty)
    -- pokefirered/src/battle_script_commands.c:3413
    if not pL and not eL then self:_finish("draw", "faint") return true end
    if not pL then self:_finish(1, "faint") return true end
    if not eL then self:_finish(0, "faint") return true end
    local need = {}
    if pF then need[0] = { kind = "faint", candidates = Engine.replacementCandidates(st, 0) } end
    if eF then need[1] = { kind = "faint", candidates = Engine.replacementCandidates(st, 1) } end
    local picks = self:_ask(need)
    for seat = 0, 1 do
      if need[seat] then
        Engine.performSwitch(st, ad, seat, picks[seat], { reason = "switch", nativeSwitchKind = "replace" })
        Engine.switchInEffects(st, ad, State.battler(st, seat), { spikes = true })
        self:_drain()
      end
    end
  end
end

-- pokefirered/src/battle_script_commands.c:8337
function Match:_pursuitRow(pid, targetId)
  local M = mods()
  local State, Engine = M["src.core.game3.battle.state"], M["src.core.game3.battle.engine"]
  local st, ad = self.st, self.ad
  local user, target = State.battler(st, pid), State.battler(st, targetId)
  if not user or State.isFainted(user) or not target or State.isFainted(target) then return nil end
  for _, row in ipairs(st.turnActions or {}) do
    if row.battler == pid and row.kind == "move" and not row.done and not row.finished
        and Engine.isPursuit(row.move) and not ad:hasStatus(user, "SLP") and not ad:hasStatus(user, "FRZ")
        and (tonumber(user.expTruantCounter) or 0) == 0 then
      return row
    end
  end
  return nil
end

function Match:_switchAction(id, slot)
  local M = mods()
  local State, Engine = M["src.core.game3.battle.state"], M["src.core.game3.battle.engine"]
  local st, ad = self.st, self.ad
  local prow = self:_pursuitRow(1 - id, id)
  if prow then
    prow.done = true
    st.interactiveChoices = true
    Engine.resolveMove(State.battler(st, 1 - id), State.battler(st, id), prow.move, prow.slot, ad, st, {},
      { pursuitSwitch = true })
    st.interactiveChoices = nil
    self:_drain()
  end
  if State.isFainted(State.battler(st, id)) then
    if st.monToSwitchInto then st.monToSwitchInto[id] = nil end
    return true
  end
  Engine.performSwitch(st, ad, id, slot, { reason = "switch", nativeSwitchKind = "switch" })
  Engine.switchInEffects(st, ad, State.battler(st, id), { spikes = true })
  self:_drain()
  return anyFainted(st, State)
end

function Match:_moveAction(act)
  local M = mods()
  local State, Engine = M["src.core.game3.battle.state"], M["src.core.game3.battle.engine"]
  local st, ad = self.st, self.ad
  local u, tg = State.occupant(st, act.user), State.occupant(st, act.target)
  if State.isFainted(u) or State.isFainted(tg) then return false end
  act.done = true
  st.interactiveChoices = true
  local out = Engine.resolveMove(act.user, act.target, act.move, act.slot, ad, st, {})
  self:_drain()
  while out and out.pendingChoice do
    local req = out.pendingChoice
    local seat = Events.seatOf(req.side)
    local picks = self:_ask({ [seat] = { kind = "baton_pass", candidates = req.candidates } })
    st.interactiveChoices = true
    out = Engine.resumeChoice(st, ad, picks[seat])
    self:_drain()
  end
  st.interactiveChoices = nil
  return anyFainted(st, State)
end

function Match:_engineAction(seat, act)
  local State = mods()["src.core.game3.battle.state"]
  local b = State.battler(self.st, seat)
  local side = SIDE[seat]
  if act.kind == "switch" then return { kind = "switch", slot = act.index, user = side } end
  local mon = b.mon or {}
  if b.expLockedMove or b.expMustRecharge then
    -- pokefirered/src/battle_main.c:3125
    local slot = b.expLockedSlot
    return { kind = "move", user = side, locked = true, slot = slot,
      move = b.expLockedMove or b.lastMoveId or b.lastMove or (mon.moves and mon.moves[slot or 1]) }
  end
  if act.slot == 0 then return { kind = "move", move = MOVE_STRUGGLE, slot = nil, user = side } end
  return { kind = "move", move = mon.moves[act.slot], slot = act.slot, user = side }
end

function Match:_turn(acts)
  local Engine = mods()["src.core.game3.battle.engine"]
  local st, ad = self.st, self.ad
  st.turn = st.turn + 1
  self.turn = st.turn
  local f0, f1 = acts[0].kind == "forfeit", acts[1].kind == "forfeit"
  if f0 or f1 then
    -- pokeemerald/src/battle_main.c:5061
    self:_finish((f0 and f1) and "draw" or (f0 and 1 or 0), "forfeit")
    return
  end
  local pAct, eAct = self:_engineAction(0, acts[0]), self:_engineAction(1, acts[1])
  st.monToSwitchInto = {}
  if pAct.kind == "switch" then st.monToSwitchInto[0] = pAct.slot end
  if eAct.kind == "switch" then st.monToSwitchInto[1] = eAct.slot end
  local actions, meta = Engine.planTurnFromActions(st, ad, pAct, eAct)
  self:_drain()
  local midFaint = false
  if meta and meta.kind == "switch" then midFaint = self:_switchAction(0, meta.slot) end
  if not midFaint then
    for _, act in ipairs(actions or {}) do
      if st.over then break end
      if Engine.actionRunnable(st, act) then
        if act.kind == "switch" then
          midFaint = self:_switchAction(act.battler, act.slot)
        elseif act.kind == "move" then
          midFaint = self:_moveAction(act)
        end
        if midFaint then break end
      end
    end
  end
  if midFaint and self:_handleFaints() then return end
  -- pokefirered/src/battle_main.c:2953
  Engine.collectResidualEvents(st, ad)
  self:_drain()
  self:_handleFaints()
end

function Match:_main()
  local M = mods()
  local Engine = M["src.core.game3.battle.engine"]
  local State = M["src.core.game3.battle.state"]
  self:_setup()
  for seat = 0, 1 do
    local b = State.battler(self.st, seat)
    self:_emit({ kind = "sendout", side = seat, index = b.partyIndex, reason = "start" })
  end
  -- pokefirered/src/battle_main.c:2856
  Engine.battleStartEffects(self.st, self.ad)
  self:_drain()
  while true do
    self.hashes[self.turn] = self:_hashNow()
    if self.phase == "over" then return end
    self.phase = "choose"
    local acts = coroutine.yield("choose")
    self.phase = "running"
    self:_turn(acts)
  end
end

local function canSwitch(b)
  -- pokefirered/src/battle_main.c:3196
  return not (b.expTrapped or b.escapePrevention or (b.expTrapTurns or 0) > 0 or b.expIngrain)
end

function Match:_legal(seat)
  local M = mods()
  local State, Engine = M["src.core.game3.battle.state"], M["src.core.game3.battle.engine"]
  local st, ad = self.st, self.ad
  local b = State.battler(st, seat)
  local out = {}
  if b.expLockedMove or b.expMustRecharge then
    out[1] = { kind = "move", slot = b.expLockedSlot or 0, locked = true }
    out[2] = { kind = "forfeit" }
    return out
  end
  local bad = Engine.moveLimitations(b, ad)
  local moves = b.mon and b.mon.moves or {}
  for i = 1, 4 do
    local mv = tonumber(moves[i])
    if mv and not bad[i] and not self.illegal[mv] then out[#out + 1] = { kind = "move", slot = i } end
  end
  if #out == 0 then out[1] = { kind = "move", slot = 0 } end
  if canSwitch(b) then
    for _, i in ipairs(Engine.switchCandidates(st, seat)) do out[#out + 1] = { kind = "switch", index = i } end
  end
  out[#out + 1] = { kind = "forfeit" }
  return out
end

function Match:legalActions(seat)
  if self.phase == "replace" then
    local need = self.need and self.need[seat]
    local out = {}
    for _, i in ipairs(need and need.candidates or {}) do out[#out + 1] = { kind = "switch", index = i } end
    return out
  end
  if self.phase ~= "choose" then return {} end
  self.legalCache = self.legalCache or {}
  local cached = self.legalCache[seat]
  if not cached then
    cached = Scope.run(self.t, function() return self:_legal(seat) end, self.stack)
    self.legalCache[seat] = cached
  end
  local out = {}
  for i, a in ipairs(cached) do out[i] = { kind = a.kind, slot = a.slot, index = a.index, locked = a.locked } end
  return out
end

local function same(a, b)
  if a.kind ~= b.kind then return false end
  if a.kind == "move" then return a.slot == b.slot end
  if a.kind == "switch" then return a.index == b.index end
  return true
end

function Match:isLegal(seat, act)
  if type(act) ~= "table" then return false end
  for _, l in ipairs(self:legalActions(seat)) do
    if same(l, act) then return true end
  end
  return false
end

function Match:submit(acts)
  if self.phase ~= "choose" then error("g3u match is not choosing actions", 2) end
  for seat = 0, 1 do
    if not self:isLegal(seat, acts[seat]) then error("g3u illegal action from seat " .. seat, 2) end
  end
  return self:_resume({ [0] = acts[0], [1] = acts[1] })
end

function Match:replace(picks)
  if self.phase ~= "replace" then error("g3u match is not waiting for a replacement", 2) end
  local clean = {}
  for seat = 0, 1 do
    if self.need[seat] then
      local i = picks and picks[seat]
      if not self:isLegal(seat, { kind = "switch", index = i }) then
        error("g3u illegal replacement from seat " .. seat, 2)
      end
      clean[seat] = i
    end
  end
  return self:_resume(clean)
end

function Match:needs(seat)
  return self.phase == "replace" and self.need and self.need[seat] ~= nil
end

function Match:active(seat)
  local State = mods()["src.core.game3.battle.state"]
  local b = self.st and State.battler(self.st, seat)
  return b and b.partyIndex or nil
end

function Match:party(seat)
  return self.st and ((seat == 0) and self.st.playerParty or self.st.foeParty) or nil
end

return Match
