local ModRuntime = require("src.mods.Runtime")
local State = setmetatable({}, { __index = function(_, key)
  return require("src.core.game3.battle.state")[key]
end })

local ModBattle = {}

local provider, bound

function ModBattle.setDataProvider(fn)
  provider = fn
end

function ModBattle.bind(modData)
  bound = modData
end

local function data()
  if provider then return provider() end
  if bound then return bound end
  local R = package.loaded["src.core.game3.runtime"]
  local game = R and R._game
  return game and game.data or nil
end
ModBattle.data = data

local function registry(key)
  local d = data()
  local reg = d and d[key]
  if type(reg) == "table" and next(reg) ~= nil then return reg end
  return nil
end

function ModBattle.hasEffects()
  return registry("gen3MoveEffects") ~= nil
end

function ModBattle.effectRecord(move)
  local id = move and move._modEffectId
  if not id or tonumber(move.effect) ~= 0 then return nil end
  local reg = registry("gen3MoveEffects")
  local record = reg and reg[id]
  if type(record) ~= "table" then return nil end
  return record, id
end

function ModBattle.statusRecord(id)
  if not id then return nil end
  local reg = registry("gen3Statuses")
  return reg and reg[id] or nil
end

function ModBattle.aiRecord(id)
  if not id then return nil end
  local reg = registry("gen3AiClasses")
  return reg and reg[id] or nil
end

local function moveKey(moveId)
  local G3 = require("src.mods.Gen3Compat")
  local num = tonumber(moveId)
  if not num and type(moveId) == "string" then num = G3.moveId(moveId) end
  if not num then return nil, nil end
  return G3.moveName(num), num
end

function ModBattle.animScript(moveId)
  local reg = registry("gen3BattleAnims")
  if not reg then return nil end
  local record = type(moveId) == "string" and reg[moveId] or nil
  if not record then
    local key, num = moveKey(moveId)
    record = (key and reg[key]) or (num and reg[tostring(num)])
  end
  local seq = type(record) == "table" and record.seq
  if type(seq) ~= "table" or #seq == 0 then return nil end
  return seq
end

local function failedList()
  return { failed = true }
end

local function ctxFor(M, record)
  local ad, st = M.adapter, M.st
  local G3 = require("src.mods.Gen3Compat")
  local ctx
  ctx = {
    battle = st, data = data(), rng = ad:rng(), ruleset = nil,
    user = M.user, target = M.target,
    move = G3.moveView(M.move), moveInst = { id = M.moveId, pp = 1 },
    isCalled = M.opts and M.opts.called and true or false,
    field = st and st.field,
    displayName = function(b) return ad:displayName(b) end,
    say = function(text) ad:say(text) end,
    sayNext = function(text) ad:say(text) end,
    anim = function(name)
      local _, num = moveKey(name)
      if not num and not ModBattle.animScript(name) then return end
      ad:pushEvent({
        kind = "move", moveId = num or name,
        attacker = M.user and M.user.side, target = M.target and M.target.side,
        attackerId = M.user and State.idOf(M.user),
        targetId = M.target and State.idOf(M.target), turn = 0,
      })
    end,
    drain = function() end,
    damage = function(who, amount)
      return ad:applyHpLoss(who, math.max(0, math.floor(amount or 0)), { hit = true })
    end,
    inflict = function(who, statusId, opts)
      return ModBattle.inflict(M, who, statusId, opts)
    end,
    cure = function(who)
      ad:clearStatus(who)
      ModBattle.clearStatus(who)
    end,
    changeStage = function(who, stat, delta)
      local Secondary = require("src.core.game3.battle.effects.secondary")
      local key = ({ special = "spAtk" })[stat] or stat
      local before = who.stages and who.stages[key] or 0
      Secondary.changeStat(ad, who, key, delta, { allowPtr = true, user = who == M.user })
      if (who.stages and who.stages[key] or 0) == before then return failedList() end
      return {}
    end,
    computeDamage = function(opts)
      local Damage = require("src.core.game3.battle.damage")
      opts = opts or {}
      opts.adapter = opts.adapter or ad
      opts.rng = opts.rng or ad:rng()
      opts.st = opts.st or st
      return Damage.calc(M.user, M.target, M.move, opts)
    end,
    accuracyRoll = function()
      return M:accuracyCheck("normal", false)
    end,
    callMove = function(moveId)
      local Engine = require("src.core.game3.battle.engine")
      local out = {}
      return Engine.resolveMove(M.user, M.target, moveId, nil, ad, st, out, { called = true })
    end,
    side = function(who) return who and who.side end,
  }
  ctx.record = record
  return ctx
end

local NATIVE = {
  SLP = "SLEEP", PSN = "POISON", BRN = "BURN", PAR = "PARALYSIS",
  FRZ = "FREEZE", TOX = "TOXIC",
}

function ModBattle.clearStatus(battler)
  if not battler then return end
  battler.modStatus = nil
  battler.modStatusState = nil
end

function ModBattle.inflict(M, who, statusId, opts)
  opts = opts or {}
  local ad = M.adapter
  if not who then return failedList() end
  local native = NATIVE[statusId]
  if native then
    if who.modStatus then return failedList() end
    local Secondary = require("src.core.game3.battle.effects.secondary")
    local prev = M.target
    M.target = who
    local landed = Secondary.set(M, native, not opts.secondary, false, false)
    M.target = prev
    if landed then return {} end
    return failedList()
  end
  local record = ModBattle.statusRecord(statusId)
  if not record then return failedList() end
  if who.modStatus or ad:status(who) then return failedList() end
  if (who.substituteHP or 0) > 0 and opts.secondary then return failedList() end
  if record.canInflict and not record.canInflict(who, opts) then return failedList() end
  who.modStatus = statusId
  who.modStatusState = {}
  local display = ad:displayName(who)
  local msgs
  if record.onInflict then
    msgs = record.onInflict(M.st, who, opts, display)
  else
    msgs = { display .. " was afflicted by " .. (record.label or tostring(statusId)) .. "!" }
  end
  if ModRuntime.wants("battle.status_inflicted") then
    ModRuntime.emit("battle.status_inflicted", {
      battle = M.st, target = who, status = statusId, source = M.user,
      side = who.side, battlerId = State.idOf(who),
      sourceId = M.user and State.idOf(M.user) or nil,
    })
  end
  ad:pushEvent({ kind = "status_apply", battler = State.idOf(who), side = who.side, status = statusId })
  return msgs or {}
end

local function say_all(ad, msgs)
  for _, text in ipairs(msgs or {}) do ad:say(text) end
end

local MISS_TEXT = {
  didntAffect = "STRINGID_ITDOESNTAFFECT",
  evadedAttack = "STRINGID_PKMNAVOIDEDATTACK",
}

function ModBattle.runPrimary(M, record)
  local ad = M.adapter
  if record.kind ~= "primary" or type(record.run) ~= "function" then
    return false
  end
  local ctx = ctxFor(M, record)
  if record.accuracyChecked then
    if not M:accuracyCheck("normal", false) then
      local kind = record.missText
      if kind == "butItFailed" then
        M.failed = true
        ad:sayFail()
      elseif MISS_TEXT[kind] then
        ad:sayText(MISS_TEXT[kind], { def = M.target, atk = M.user })
      else
        M:sayId("STRINGID_ATTACKMISSED", { atk = M.user })
      end
      return true
    end
  end
  local msgs = record.run(ctx)
  if type(msgs) ~= "table" or msgs.failed then
    M.failed = true
    say_all(ad, type(msgs) == "table" and msgs or nil)
    return true
  end
  M:attackAnimation()
  say_all(ad, msgs)
  return true
end

function ModBattle.runAfterHit(M, record)
  local ad = M.adapter
  local target = M.target
  if record.kind == "primary" or type(record.run) ~= "function" then return end
  if not target or ad:isFainted(target) or (M.totalDealt or 0) <= 0 then return end
  say_all(ad, record.run(ctxFor(M, record)))
end

function ModBattle.statusSlotRecord(battler)
  if not battler or not battler.modStatus then return nil end
  return ModBattle.statusRecord(battler.modStatus)
end

function ModBattle.beforeMove(M, early)
  local user = M.user
  local record = ModBattle.statusSlotRecord(user)
  if not record or type(record.beforeMove) ~= "function" then return true end
  local priority = record.beforeMovePriority or 0
  if (priority > 20) ~= (early == true) then return true end
  local ad = M.adapter
  local canMove, msgs = record.beforeMove(user, ad:rng(), M.st)
  say_all(ad, msgs)
  if canMove == false then
    user.expUnableToMove = true
    return false
  end
  return true
end

function ModBattle.residual(adapter, battler)
  if not battler or not battler.modStatus or adapter:isFainted(battler) then return end
  local record = ModBattle.statusRecord(battler.modStatus)
  if not record or type(record.residual) ~= "function" then return end
  local before = adapter:hp(battler)
  local msgs = record.residual(battler, adapter:rng(), adapter._st)
  say_all(adapter, msgs)
  local after = adapter:hp(battler)
  if after ~= before then
    adapter:recordHp(battler, before, after, "hp")
  end
end

function ModBattle.label(battler)
  local record = ModBattle.statusSlotRecord(battler)
  if not record then return nil end
  return record.hudLabel or record.label or battler.modStatus
end

function ModBattle.catchBonus(battler)
  local record = ModBattle.statusSlotRecord(battler)
  return record and tonumber(record.catchBonus) or 0
end

function ModBattle.penalty(battler, stat, value)
  local record = ModBattle.statusSlotRecord(battler)
  local penalty = record and record.statPenalty
  local named = penalty and penalty.stat
  if named == "special" then named = (stat == "spAtk" or stat == "spDef") and stat or nil end
  if penalty and named == stat then
    return math.max(1, math.floor(value / math.max(1, penalty.div or 1)))
  end
  return value
end

function ModBattle.switchOut(st, battler)
  if not battler or not battler.modStatus then return end
  local record = ModBattle.statusRecord(battler.modStatus)
  if not record or record.cureOnSwitch then return end
  st.modParked = st.modParked or {}
  st.modParked[State.partyMon(battler)] = {
    id = battler.modStatus, state = battler.modStatusState,
  }
end

function ModBattle.switchIn(st, battler)
  if not battler or not st.modParked then return end
  local mon = State.partyMon(battler)
  local parked = st.modParked[mon]
  if not parked then return end
  st.modParked[mon] = nil
  if not battler.mon or (tonumber(battler.mon.hp) or 0) <= 0 then return end
  battler.modStatus, battler.modStatusState = parked.id, parked.state
end

local function moveNum(mv)
  local n = tonumber(mv)
  if n then return n end
  if mv == nil or mv == "" then return 0 end
  local Moves = require("src.core.game3.battle.moves")
  return Moves.numForName and Moves.numForName(mv) or 0
end

local function aiView(st, b, target, rng)
  return { battle = st, user = b, target = target, data = data(), rng = rng }
end

function ModBattle.aiClassFor(st)
  if not st or st.wild or not st.aiClass then return nil end
  return ModBattle.aiRecord(st.aiClass), st.aiClass
end

function ModBattle.aiBrainSlot(st, b, target, rng, bad)
  local record = ModBattle.aiClassFor(st)
  if not record or record.kind ~= "brain" or type(record.brain) ~= "function" then return nil end
  local G3 = require("src.mods.Gen3Compat")
  local view = aiView(st, b, target, rng)
  view.moves = {}
  for slot = 1, 4 do
    local mv = b.mon and b.mon.moves and b.mon.moves[slot]
    if moveNum(mv) ~= 0 then
      view.moves[#view.moves + 1] = {
        slot = slot, move = G3.moveView(mv), usable = not (bad and bad[slot]),
      }
    end
  end
  local pick = record.brain(view)
  local slot = type(pick) == "table" and tonumber(pick.slot) or tonumber(pick)
  if not slot or slot < 1 or slot > 4 or slot ~= math.floor(slot) then return nil end
  if bad and bad[slot] then return nil end
  if moveNum(b.mon and b.mon.moves and b.mon.moves[slot]) == 0 then return nil end
  return slot
end

function ModBattle.aiLayers(st)
  local layers = {}
  if not st or st.wild then return layers end
  local function add(id)
    local record = ModBattle.aiRecord(id)
    if record and type(record.score) == "function" and (record.kind == nil or record.kind == "layer") then
      layers[#layers + 1] = record.score
    end
  end
  for _, id in ipairs(st.aiMods or {}) do add(id) end
  add(st.aiClass)
  return layers
end

function ModBattle.applyLayers(st, b, target, rng, scores, bad)
  local layers = ModBattle.aiLayers(st)
  if #layers == 0 then return end
  local G3 = require("src.mods.Gen3Compat")
  local view = aiView(st, b, target, rng)
  for slot = 1, 4 do
    local mv = b.mon and b.mon.moves and b.mon.moves[slot]
    if moveNum(mv) ~= 0 and not (bad and bad[slot]) then
      local def = G3.moveView(mv)
      for _, score in ipairs(layers) do
        scores[slot] = score(view, def, scores[slot]) or scores[slot]
      end
    end
  end
end

local function switchSlot(st, b)
  local party = b.side == "player" and st.playerParty or st.foeParty
  local held = {}
  for _, other in ipairs(State.present(st)) do
    if other.side == b.side then held[other.partyIndex or 1] = true end
  end
  for i, mon in ipairs(party or {}) do
    if not held[i] and (tonumber(mon.hp) or 0) > 0 and not mon.isEgg then return i end
  end
  return nil
end

function ModBattle.classAction(st, id, rng)
  local record = ModBattle.aiClassFor(st)
  if not record or (record.kind ~= nil and record.kind ~= "class") then return nil end
  if id % 2 ~= 1 then return nil end
  local b = State.battler(st, id)
  if not b or not b.mon then return nil end
  st.modAiUses = st.modAiUses or {}
  local mon = State.partyMon(b)
  local left = st.modAiUses[mon]
  if left == nil then left = tonumber(record.uses) or 0 end
  if left <= 0 then return nil end
  local roll = rng(0, 255)
  local function switchAction()
    local slot = switchSlot(st, b)
    if not slot then return nil end
    st.monToSwitchInto = st.monToSwitchInto or {}
    st.monToSwitchInto[id] = slot
    return { kind = "switch", slot = slot, user = "enemy", battler = id }
  end
  local function itemAction()
    if not record.item then return nil end
    local G3 = require("src.mods.Gen3Compat")
    local use = require("src.core.game3.battle.ai_items").useStocked(st, id, G3.itemId(record.item))
    if not use then return nil end
    return { kind = "item", item = use.item, aiItemType = use.aiItemType,
      aiItemFlags = use.aiItemFlags, user = "enemy", battler = id, target = id }
  end
  local action
  if record.switchChance and roll < record.switchChance then
    action = switchAction()
  elseif record.onStatus then
    if b.mon.status or b.status or b.modStatus then action = itemAction() end
  elseif record.chance and roll >= record.chance then
    action = nil
  elseif record.switch then
    action = switchAction()
  elseif record.hpBelow then
    local hp, maxHp = tonumber(b.mon.hp) or 0, tonumber(b.mon.maxHp) or 1
    if hp >= math.floor(maxHp / record.hpBelow) then
      if record.switchBelow and hp < math.floor(maxHp / record.switchBelow) then
        action = switchAction()
      end
    else
      action = itemAction()
    end
  else
    action = itemAction()
  end
  if action then st.modAiUses[mon] = left - 1 end
  return action
end

return ModBattle
