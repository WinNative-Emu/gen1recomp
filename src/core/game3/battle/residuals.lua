-- End-of-turn residual scheduler (owned game3).

local Rules = require("src.core.game3.battle.rules")
local EffectCtx = require("src.core.game3.battle.effect_ctx")
local BattleProfile = require("src.core.game3.battle.profile")
local ModRuntime = require("src.mods.Runtime")

local Residuals = {}

local handlers = {}

function Residuals.register(phase, fn)
  handlers[phase] = handlers[phase] or {}
  handlers[phase][#handlers[phase] + 1] = fn
end

function Residuals.clear()
  handlers = {}
end

local function battlerSpeed(battler, adapter)
  if not battler then return 0 end
  local Engine = package.loaded["src.core.game3.battle.engine"]
  if Engine and Engine.speedOf then
    return Engine.speedOf(battler, adapter and adapter._st, adapter)
  end
  local mon = battler.mon
  return tonumber(mon and (mon.speed or mon.spe)) or 50
end

-- pokefirered/src/battle_util.c:494
local function sortedBattlers(adapter)
  local st = adapter and adapter._st
  if st and st.double then
    local State = require("src.core.game3.battle.state")
    local ids = st._endTurnOrder
    if not ids then
      local pri
      if st.turnActions then
        local Moves = require("src.core.game3.battle.moves")
        pri = {}
        for _, act in ipairs(st.turnActions) do
          if act.battler ~= nil and act.kind == "move" then pri[act.battler] = Moves.priority(act.move) end
        end
      end
      ids = State.speedOrder(st, adapter, { priority = pri })
    end
    local out = {}
    for _, id in ipairs(ids) do
      if State.isPresent(st, id) then out[#out + 1] = State.battler(st, id) end
    end
    return out
  end
  local list = adapter:activeBattlers() or {}
  local a, b = list[1], list[2]
  if a and b then
    -- pokefirered/src/battle_util.c:484
    local ids = st and st._endTurnOrder
    if ids and ids[1] and ids[2] then
      if ids[1] == b.id and ids[2] == a.id then
        list[1], list[2] = b, a
      elseif ids[1] == a.id then
        list[1], list[2] = a, b
      end
      return list
    end
    local sa, sb = battlerSpeed(a, adapter), battlerSpeed(b, adapter)
    if sb > sa or (sb == sa and adapter:roll(0, 1) == 1) then
      list[1], list[2] = b, a
    end
  end
  return list
end
Residuals.sortedBattlers = sortedBattlers

local function sideHasLiving(adapter, side)
  local st = adapter._st
  local party = side == "player" and st.playerParty or st.foeParty
  local active = adapter:activeBattlers() or {}
  local limit = side == "player" and st.playerHalf or nil
  local view = {}
  for i, mon in ipairs(party or {}) do
    if not limit or i <= limit then view[i] = mon end
  end
  for _, b in ipairs(active) do
    if b.side == side and (not limit or (b.partyIndex or 1) <= limit) then
      view[b.partyIndex or 1] = b.mon
    end
  end
  local Engine = package.loaded["src.core.game3.battle.engine"]
    or require("src.core.game3.battle.engine")
  return Engine.hasLivingMons(view)
end

local function runStepAndRecord(adapter, battler, phase, fn, events, fieldResidual)
  if battler and adapter:isFainted(battler) then return false end
  if adapter:isBattleDecided() then return false end

  if adapter.prepareFaintStep then adapter:prepareFaintStep(battler, phase) end

  local active = adapter:activeBattlers() or {}
  if fieldResidual then
    local ordered = {}
    for _, side in ipairs({ "player", "enemy" }) do
      for _, b in ipairs(active) do
        if b.side == side then ordered[#ordered + 1] = b end
      end
    end
    active = ordered
  else
    local sequencing = BattleProfile.rule(adapter._st, "sequencingPolicy")
    if sequencing then active = sequencing.residualOrder(adapter, battler, phase, active) end
  end
  local hpBefore = {}
  for _, b in ipairs(active) do
    if b and b.side then
      hpBefore[b] = adapter:hp(b)
    end
  end

  local capturedMsgs = {}
  local prevSay = adapter._say
  adapter._say = function(text)
    capturedMsgs[#capturedMsgs + 1] = tostring(text or "")
  end
  local mark = adapter.eventMark and adapter:eventMark() or 0

  local opts = EffectCtx.borrowOpts(phase)
  local ctx = EffectCtx.push(adapter, nil, battler, nil, nil, adapter:rng(), opts)
  local ok, err = pcall(fn, ctx)
  EffectCtx.pop()

  local terminalPlayer = fieldResidual and ok and not sideHasLiving(adapter, "player")
  local hpChanges = {}
  local faints = {}
  for _, b in ipairs(active) do
    if b and b.side then
      local before = hpBefore[b] or 0
      local after = adapter:hp(b)
      if before ~= after then
        hpChanges[#hpChanges + 1] = {
          side = b.side,
          battler = b.id,
          from = before,
          to = after,
          maxHp = adapter:maxHp(b),
        }
      end
      if adapter:isFainted(b) and before > 0 then
        if terminalPlayer and b.side == "enemy" then
          b._expGiven = true
        else
          faints[#faints + 1] = { side = b.side, battler = b.id }
          if not b._faintAnnounced then
            b._faintAnnounced = true
            if adapter.pushEvent then adapter:pushEvent({ kind = "faint", side = b.side, battler = b.id }) end
            adapter:sayText("STRINGID_ATTACKERFAINTED", { atk = b })
          end
          adapter:emitFaint(b)
        end
      end
    end
  end

  adapter._say = prevSay
  if not ok then error(err, 0) end

  if #capturedMsgs > 0 or #hpChanges > 0 or #faints > 0 then
    events[#events + 1] = {
      phase = phase,
      target = battler,
      msgs = capturedMsgs,
      hpChanges = hpChanges,
      faints = faints,
      events = adapter.eventsSince and adapter:eventsSince(mark) or {},
    }
  end

  if battler and adapter:isFainted(battler) then
    if Rules.shouldHaltBattlerOnFaint(phase) then
      return true
    end
  end
  return false
end

local function publicScalar(value)
  local kind = type(value)
  if kind == "string" or kind == "boolean" then return value, true end
  if kind == "number" and value == value
      and value < math.huge and value > -math.huge then
    return value, true
  end
  return nil, false
end

local function publicDataCopy(value, visiting)
  local scalar, ok = publicScalar(value)
  if ok then return scalar, true end
  if type(value) ~= "table" then return nil, false end
  visiting = visiting or {}
  if visiting[value] then return nil, false end
  visiting[value] = true
  local copy = {}
  for key, child in next, value do
    local copiedKey, keyOk = publicScalar(key)
    local copiedChild, childOk = publicDataCopy(child, visiting)
    if keyOk and childOk then copy[copiedKey] = copiedChild end
  end
  visiting[value] = nil
  return copy, true
end

local function collectFieldResiduals(adapter, events)
  if not ModRuntime.wantsHook("battle.field_residual") then return end
  local st = adapter._st
  if not st or adapter:isBattleDecided() then return end
  local turn = st.turn or 0
  if st._modFieldResidualTurn == turn then return end
  if not sideHasLiving(adapter, "player") or not sideHasLiving(adapter, "enemy") then return end
  st._modFieldResidualTurn = turn

  local hooks, session = ModRuntime.hooks, st.session
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and Runtime._game
  local runtimeSession = Runtime and Runtime.session
  local gameSession = game and game.session
  local Battle = package.loaded["src.core.game3.battle.init"] or package.loaded["src.core.game3.battle"]
  local current = Battle and Battle.getState and Battle.getState() == st
  local typeNames = require("src.online.xgen.Identity").GEN3_TYPES
  local active, mons, views = {}, {}, {}
  for _, b in ipairs(adapter:activeBattlers() or {}) do
    active[b.id] = b
    mons[b] = b.mon
    local view = publicDataCopy({
      side = b.side,
      name = adapter:displayName(b),
      hp = adapter:hp(b),
      maxHp = adapter:maxHp(b),
      types = { typeNames[b.type1], typeNames[b.type2] },
      vanished = b.semiInvulnerable and true or false,
      battlerId = b.id,
    })
    views[b.id] = view
    if st[b.side] == b then views[b.side] = view end
  end
  local field = st.field or {}
  local rows = ModRuntime.call("battle.field_residual", function() return {} end, {
    field = publicDataCopy({ weather = st.weather, tokens = field.tokens or {} }),
    battlers = views,
    turn = turn,
  })
  if type(rows) ~= "table" or getmetatable(rows) ~= nil then return end
  if adapter._st ~= st or adapter:isBattleDecided() or (st.turn or 0) ~= turn
      or st.session ~= session or ModRuntime.hooks ~= hooks
      or (Runtime and (Runtime._game ~= game or Runtime.session ~= runtimeSession))
      or (game and game.session ~= gameSession)
      or (current and Battle.getState() ~= st) then return end
  for _, b in ipairs(adapter:activeBattlers() or {}) do
    if active[b.id] ~= b or mons[b] ~= b.mon then return end
    active[b.id] = nil
  end
  if next(active) ~= nil then return end
  if not sideHasLiving(adapter, "player") or not sideHasLiving(adapter, "enemy") then return end

  local accepted = {}
  for _, row in ipairs(rows) do
    if type(row) == "table" and getmetatable(row) == nil
        and (row.side == "player" or row.side == "enemy") then
      local id = row.battlerId
      if id == nil then id = row.battler end
      local b = st[row.side]
      if id ~= nil then
        b = nil
        if type(id) == "number" and id >= 0 and id <= 3 and id == math.floor(id) then
          for target in pairs(mons) do
            if target.id == id and target.side == row.side then b = target break end
          end
        end
      end
      local amount = row.amount
      if b and mons[b] and type(amount) == "number" and amount > 0
          and amount < math.huge and amount == math.floor(amount)
          and (row.message == nil or type(row.message) == "string") then
        accepted[#accepted + 1] = { target = b, amount = amount, message = row.message }
      end
    end
  end
  if #accepted == 0 then return end
  runStepAndRecord(adapter, nil, "field_residual", function()
    for _, row in ipairs(accepted) do
      local b = row.target
      if not adapter:isFainted(b) then
        local amount = math.min(row.amount, adapter:hp(b))
        if row.message and row.message ~= "" then adapter:say(row.message) end
        if adapter.prepareFaintStep then adapter:prepareFaintStep(b, "field_residual") end
        adapter:applyHpLoss(b, amount)
      end
    end
  end, events, true)
end

local function run_phase(adapter, phase, battler, events)
  local list = handlers[phase]
  if not list then return false end
  for _, fn in ipairs(list) do
    if adapter:isBattleDecided() then return true end
    if runStepAndRecord(adapter, battler, phase, fn, events) then return true end
  end
  return false
end

function Residuals.collectEvents(adapter)
  local events = {}
  if not adapter or adapter:isBattleDecided() then return events end

  local Engine = package.loaded["src.core.game3.battle.engine"]
  if Engine and Engine.refreshLinks then Engine.refreshLinks(adapter._st) end
  -- pokefirered/src/battle_main.c:2957
  for _, b in ipairs(adapter:activeBattlers()) do
    b.expProtected = nil
    b.expEnduring = nil
  end

  local st = adapter._st
  if st then
    st._endTurnOrder = nil
    -- pokefirered/src/battle_util.c:484
    local order = {}
    for _, b in ipairs(sortedBattlers(adapter)) do order[#order + 1] = b.id end
    st._endTurnOrder = order
    if st.double then
      -- pokefirered/src/battle_util.c:484
      st.turnOrder = order
    end
  end

  for _, phase in ipairs(Rules.FIELD_PHASES_ORDER) do
    if adapter:isBattleDecided() then break end
    run_phase(adapter, phase, nil, events)
  end

  if not adapter:isBattleDecided() then
    for _, battler in ipairs(sortedBattlers(adapter)) do
      for _, phase in ipairs(Rules.BATTLER_PHASES_ORDER) do
        if adapter:isBattleDecided() or adapter:isFainted(battler) then break end
        if run_phase(adapter, phase, battler, events) then break end
      end
    end
  end

  for _, phase in ipairs(Rules.POST_PHASES_ORDER) do
    if adapter:isBattleDecided() then break end
    run_phase(adapter, phase, nil, events)
  end

  collectFieldResiduals(adapter, events)

  if st then st._endTurnOrder = nil end
  return events
end

function Residuals.runTurn(adapter)
  return Residuals.collectEvents(adapter)
end

return Residuals
