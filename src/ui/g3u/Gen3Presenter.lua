local M = {}

M.LAYER = "g3u_battle"
M.RULES_TEXT = "Union rules: Gen 3 battle mechanics. Abilities and held items are off."
M.NATIVE_WAIT = 60

local S = function(text, ...) return require("src.core.Strings")(text, ...) end

local END_TEXT = {
  desync = "The battle fell out of sync.\nIt ended in a draw.",
  disconnect = "The link with the other player\nwas lost.",
  illegal = "The other player sent something\nthat can't be used. It's a draw.",
  bad_table = "The battle rules couldn't be agreed.",
  bad_party = "A team couldn't be used in\nthis battle.",
  error = "The battle couldn't continue.",
}

local ENGINE_SEAT = { player = 0, enemy = 1 }
local CONTROL = { ready = true, prompt = true, wait = true, over = true }
local BATTLER_KEYS = {
  atk = true, def = true, eff = true, active = true, scrActive = true, atkMon1 = true, atkPartner = true,
  scrActivePartyMon = true, playerMon1 = true, playerMon2 = true, opponentMon1 = true, opponentMon2 = true,
  linkPlayerMon1 = true, linkPlayerMon2 = true, linkOpponentMon1 = true, linkOpponentMon2 = true,
}
local BUFF_KEYS = { buff1 = true, buff2 = true, buff3 = true }
local STAT_KEYS = { attack = true, defense = true, speed = true, spAtk = true, spDef = true, accuracy = true,
  evasion = true }
local SWITCH_TEXT_IDS = { STRINGID_SWITCHINMON = true, STRINGID_PKMNWASDRAGGEDOUT = true }
local EFFECTIVENESS = { STRINGID_SUPEREFFECTIVE = 2, STRINGID_NOTVERYEFFECTIVE = 0.5, STRINGID_ITDOESNTAFFECT = 0 }
local GENDER = { [0] = "M", [1] = "F", [2] = "U" }
local INPUT_PHASES = { menu = true, moves = true, party = true, confirm = true }

function M.sideOf(seat, mySeat)
  if seat == nil then return nil end
  return seat == mySeat and "player" or "enemy"
end

function M.idOf(seat, mySeat)
  if seat == nil then return nil end
  return seat == mySeat and 0 or 1
end

function M.map(ev, mySeat)
  local k = ev and ev.kind
  local function side(s) return M.sideOf(s, mySeat) end
  local function id(s) return M.idOf(s, mySeat) end
  if k == "msg" then return { act = "text", id = ev.id, fill = ev.fill or {} } end
  if k == "move" then
    return { act = "anim", ev = { kind = "move", moveId = ev.moveId, attacker = side(ev.user), target = side(ev.target),
      attackerId = id(ev.user), targetId = id(ev.target), turn = ev.turn or 0 } }
  end
  if k == "hp" then
    return { act = "hp", seat = ev.side, to = ev.to, max = ev.max,
      ev = { kind = ev.hit and "hit" or "hp", side = side(ev.side), battler = id(ev.side), from = ev.from, to = ev.to,
        maxHp = ev.max } }
  end
  if k == "status" then
    local none = ev.status == nil or ev.status == "NONE"
    return { act = "status", seat = ev.side, status = (not none) and ev.status or nil,
      ev = { kind = none and "status_clear" or "status_apply", side = side(ev.side), battler = id(ev.side),
        status = (not none) and ev.status or nil } }
  end
  if k == "stage" then return { act = "stage", seat = ev.side, stat = ev.stat, delta = ev.delta or 0 } end
  if k == "faint" then
    return { act = "faint", seat = ev.side, ev = { kind = "faint", side = side(ev.side), battler = id(ev.side) } }
  end
  if k == "withdraw" then return { act = "withdraw", seat = ev.side, index = ev.index, reason = ev.reason } end
  if k == "sendout" then return { act = "sendout", seat = ev.side, index = ev.index, reason = ev.reason } end
  if k == "weather" then return { act = "weather", weather = ev.weather, turns = ev.turns } end
  if k == "anim" then
    return { act = "anim", ev = { kind = "anim", anim = ev.anim, name = ev.name, attacker = side(ev.user),
      target = side(ev.target), attackerId = id(ev.user), targetId = id(ev.target), arg = ev.arg } }
  end
  if k == "end" then return { act = "end", result = ev.result } end
  if k == "ready" then return { act = "ready" } end
  if k == "prompt" then return { act = "prompt", what = ev.what, reason = ev.reason, turn = ev.turn } end
  if k == "waiting" then return { act = "wait", what = ev.what } end
  if k == "over" then return { act = "over", outcome = ev.outcome, why = ev.why, detail = ev.detail } end
  return { act = "none" }
end

function M.menu(legal)
  local out = { moves = {}, switches = {}, struggle = nil, locked = nil, forfeit = nil, count = 0 }
  for _, a in ipairs(legal or {}) do
    if a.kind == "move" then
      if a.locked then out.locked = a
      elseif a.slot == 0 then out.struggle = a
      else out.moves[a.slot] = a end
    elseif a.kind == "switch" then
      out.switches[a.index] = a
      out.count = out.count + 1
    elseif a.kind == "forfeit" then
      out.forfeit = a
    end
  end
  return out
end

local function resolveValue(k, v, mySeat, R, depth)
  local t = type(v)
  if t == "table" then
    if v.side ~= nil and (v.index ~= nil or BATTLER_KEYS[k]) and type(v.side) == "number" then
      return { side = M.sideOf(v.side, mySeat), name = R.mon(v.side, v.index) }
    end
    if v.move ~= nil then return R.move(v.move) end
    if v.species ~= nil then return R.species(v.species) end
    if v.ability ~= nil then return R.ability(v.ability) end
    if v.type ~= nil then return R.type(v.type) end
    if depth > 2 then return nil end
    local out = {}
    for kk, vv in pairs(v) do out[kk] = resolveValue(kk, vv, mySeat, R, depth + 1) end
    return out
  end
  if t == "string" then
    if (BATTLER_KEYS[k] or k == "side") and ENGINE_SEAT[v] ~= nil then return M.sideOf(ENGINE_SEAT[v], mySeat) end
    if BUFF_KEYS[k] and STAT_KEYS[v] then return R.stat(v) end
    return v
  end
  if t == "number" and k == "side" then return M.sideOf(v, mySeat) end
  return v
end

function M.resolveFill(fill, mySeat, R)
  local out = {}
  for k, v in pairs(fill or {}) do
    if k ~= "stat" and k ~= "delta" then out[k] = resolveValue(k, v, mySeat, R, 0) end
  end
  if fill and fill.stat ~= nil and fill.delta ~= nil then
    out.buff1 = R.stat(fill.stat)
    out.buff2 = R.change(fill.delta)
  end
  return out
end

local Script = {}
Script.__index = Script

function M.newScript(mySeat)
  return setmetatable({ seat = mySeat, queue = {}, qi = 1 }, Script)
end

function Script:push(events)
  for _, ev in ipairs(events or {}) do self.queue[#self.queue + 1] = ev end
end

function Script:pending()
  return self.qi <= #self.queue
end

function Script:next()
  local ops, sent = {}, {}
  while self.qi <= #self.queue do
    local ev = self.queue[self.qi]
    local a = M.map(ev, self.seat)
    if CONTROL[a.act] then
      if #ops > 0 then return { kind = "segment", ops = ops } end
      self.qi = self.qi + 1
      return { kind = a.act, action = a, ev = ev }
    end
    if a.act == "sendout" then
      if sent[a.seat] then return { kind = "segment", ops = ops } end
      sent[a.seat] = true
    end
    if a.act ~= "none" then ops[#ops + 1] = a end
    self.qi = self.qi + 1
  end
  if #ops > 0 then return { kind = "segment", ops = ops } end
  return nil
end

M.Script = Script

local function lazy(name) return package.loaded[name] or require(name) end

local function once(fn)
  local done = false
  return function(...)
    if done then return end
    done = true
    if fn then return fn(...) end
  end
end

local function nameOf(mon)
  if not mon then return "" end
  if type(mon.nickname) == "string" and mon.nickname ~= "" then return mon.nickname end
  return lazy("src.core.game3.pokemon").name(mon.species)
end

local function dispMon(rec, t)
  local Pokemon = lazy("src.core.game3.pokemon")
  local Policy = lazy("src.online.xgen.Policy")
  local moves, pp, maxPp, ups, types = {}, {}, {}, {}, {}
  for i, mv in ipairs(rec.moves or {}) do
    moves[i], pp[i], ups[i] = mv.id, mv.pp, mv.ppUps or 0
    local row = t and t.moves and t.moves[mv.id]
    maxPp[i] = row and math.min(64, Policy.maxPp(row[4], ups[i])) or mv.pp
    types[i] = row and row[2]
  end
  local mon = {
    species = Pokemon.speciesFromNational(rec.species) or rec.species, level = rec.level, hp = rec.hp,
    maxHp = rec.maxHp, attack = rec.atk, defense = rec.def, spAtk = rec.spAtk, spDef = rec.spDef,
    speed = rec.speed, moves = moves, pp = pp, maxPp = maxPp, ppUps = ups, moveTypes = types,
    nickname = rec.nickname, gender = GENDER[rec.gender] or "U", personality = rec.gender == 1 and 0 or 255, isShiny = false, otId = 0, otSecretId = 0,
    friendship = rec.friendship or 0, ability = 0, abilityId = 0, item = 0, heldItem = 0,
    ivs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
    evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
  }
  lazy("src.core.game3.battle.experience").syncExpToLevel(mon)
  return mon
end

local function trainerPic(gender)
  local okC, C = pcall(function() return lazy("src.core.game3.constants").active() end)
  if not okC or not C then return nil end
  local function id(name)
    local ok, v = pcall(C.id, C, "trainer_classes", name)
    return ok and v or nil
  end
  if gender == 1 then return id("TRAINER_PIC_LEAF") or id("TRAINER_PIC_MAY") end
  return id("TRAINER_PIC_RED") or id("TRAINER_PIC_BRENDAN")
end

local function playerGender(session)
  local g = session and session.gender
  if g == 1 or g == "female" or g == "F" then return 1 end
  return 0
end

local function battleSong()
  local ok, song = pcall(function()
    local LB = lazy("src.core.game3.link.battle")
    local songs = lazy("src.core.game3.link.family").linkBattleSongs()
    return LB[songs.trainer]
  end)
  return ok and song or nil
end

-- pokefirered/src/battle_message.c:1281
local function standbyText()
  local RomText = lazy("src.core.game3.rom_text")
  for _, key in ipairs({ "gText_LinkStandby", "BattleText_LinkStandby" }) do
    if RomText.has(key) then return RomText.plain(key) end
  end
  return nil
end

local function playSe(id)
  pcall(function() lazy("src.core.game3.audio").playSe(lazy("src.core.game3.se_ids")[id]) end)
end

local Run = {}
Run.__index = Run

function Run:R()
  if self._R then return self._R end
  local Pokemon = lazy("src.core.game3.pokemon")
  local Types = lazy("src.core.game3.battle.types")
  local Secondary = lazy("src.core.game3.battle.effects.secondary")
  local RomText = lazy("src.core.game3.rom_text")
  self._R = {
    mon = function(seat, index)
      local party = self.disp[seat] or {}
      local i = index or self.active[seat] or 1
      return nameOf(party[i])
    end,
    move = function(n) return Pokemon.moveName(n) end,
    species = function(n) return Pokemon.name(Pokemon.speciesFromNational(n) or n) end,
    ability = function(n) return Pokemon.abilityName(n) or "" end,
    type = function(n) return Types.name(n) end,
    stat = function(k) return Secondary.statName(k) end,
    change = function(delta)
      if delta >= 2 then return Secondary.sharpChange("STRINGID_STATSHARPLY", "STRINGID_STATROSE") end
      if delta >= 1 then return RomText.plain("STRINGID_STATROSE") end
      if delta <= -2 then return Secondary.sharpChange("STRINGID_STATHARSHLY", "STRINGID_STATFELL") end
      return RomText.plain("STRINGID_STATFELL")
    end,
  }
  return self._R
end

function Run:text(id, fill)
  local BattleText = lazy("src.core.game3.battle.battle_text")
  local Adapter = lazy("src.core.game3.battle.adapter")
  local resolved = M.resolveFill(fill, self.bs.seat, self:R())
  local ok, out = pcall(BattleText.get, id, Adapter.fill(self.pst, resolved))
  if ok then return out end
  print("[g3u/gen3] no text for " .. tostring(id) .. ": " .. tostring(out))
  return nil
end

function Run:pushMsg(text, wait, id)
  local Ui = lazy("src.core.game3.battle.ui")
  local AnimSeq = lazy("src.core.game3.battle.anim_seq")
  Ui.pushTimed(text, tonumber(wait) or (AnimSeq.isMoveUsedId(id) and 0 or 64))
end

function Run:standby()
  local Ui = lazy("src.core.game3.battle.ui")
  local Message = lazy("src.ui.game3.message")
  local text = standbyText()
  Ui._mode = "none"
  if not text then return end
  Ui._timed = nil
  Ui._showing = false
  Ui._linger = true
  Message.show(text, { frame = "battle", battle = true, stay = true })
end

function Run:battlerFor(seat)
  local State = lazy("src.core.game3.battle.state")
  local id = M.idOf(seat, self.bs.seat)
  return State.battler(self.pst, id), id
end

function Run:setActive(seat, index)
  local State = lazy("src.core.game3.battle.state")
  local id = M.idOf(seat, self.bs.seat)
  local party = self.disp[seat]
  local b = State.makeBattler(party[index], State.sideOf(id), { partyIndex = index, id = id })
  if id == 0 then self.pst.player = b else self.pst.enemy = b end
  if self.pst.battlers then self.pst.battlers[id] = b end
  self.active[seat] = index
  return b
end

function Run:apply(ops)
  local SwitchSeq = lazy("src.core.game3.battle.switch_seq")
  local evs, pending = {}, {}
  local function add(ev) evs[#evs + 1] = ev end
  local function msg(text, id) if text then add({ kind = "msg", text = text, id = id }) end end
  for i, op in ipairs(ops) do
    local a = op.act
    if a == "text" then
      msg(self:text(op.id, op.fill), op.id)
    elseif a == "anim" then
      add(op.ev)
    elseif a == "hp" then
      local b = self:battlerFor(op.seat)
      if b and b.mon then
        b.mon.hp = op.to
        b.fainted = (op.to or 0) <= 0
      end
      if op.ev.kind == "hit" then
        for j = i + 1, #ops do
          local o = ops[j]
          if o.act == "anim" and o.ev.kind == "move" then break end
          if o.act == "text" and EFFECTIVENESS[o.id] ~= nil then
            op.ev.effectiveness = EFFECTIVENESS[o.id]
            break
          end
        end
      end
      add(op.ev)
    elseif a == "status" then
      local b = self:battlerFor(op.seat)
      if b then
        b.status = op.status
        if b.mon then b.mon.status = op.status end
      end
      add(op.ev)
    elseif a == "faint" then
      local b = self:battlerFor(op.seat)
      if b and b.mon then b.mon.hp, b.fainted = 0, true end
      add(op.ev)
    elseif a == "stage" then
      local b = self:battlerFor(op.seat)
      if b and b.stages and op.stat then
        b.stages[op.stat] = math.max(-6, math.min(6, (b.stages[op.stat] or 0) + op.delta))
      end
    elseif a == "weather" then
      self.pst.weather = op.weather ~= "NONE" and op.weather or nil
      self.pst.weatherTurns = op.turns
    elseif a == "withdraw" then
      local b, id = self:battlerFor(op.seat)
      local alive = b and b.mon and (tonumber(b.mon.hp) or 0) > 0
      pending[op.seat] = op.index
      if alive and op.reason == "switch" then msg(SwitchSeq.returnText(self.pst, id), "STRINGID_RETURNMON") end
    elseif a == "sendout" then
      if op.reason == "start" then
        self:setActive(op.seat, op.index)
      else
        local from = pending[op.seat] or self.active[op.seat]
        pending[op.seat] = nil
        local b, id = self:setActive(op.seat, op.index), M.idOf(op.seat, self.bs.seat)
        local nxt = ops[i + 1]
        local engineText = nxt and nxt.act == "text" and SWITCH_TEXT_IDS[nxt.id]
        local own = op.reason ~= "roar" and not engineText
        add({ kind = "switch", side = b.side, battler = id, from = from, to = op.index,
          reason = (own or engineText) and "baton_pass" or op.reason })
        if own then
          msg(lazy("src.core.game3.battle.battle_text").get("STRINGID_SWITCHINMON",
            SwitchSeq.switchInFill(self.pst, b)), "STRINGID_SWITCHINMON")
        end
        SwitchSeq.stampSwitchIn(self.pst)
      end
    end
  end
  return evs
end

function Run:syncMoves()
  local party = self.bs:myParty()
  local live = party and party[self.active[self.bs.seat]]
  local b = self.pst.player
  if not (live and b and b.mon) then return end
  local rows = self.bs.table and self.bs.table.moves or {}
  b.mon.moveTypes = b.mon.moveTypes or {}
  for i = 1, 4 do
    b.mon.moves[i] = live.moves and live.moves[i]
    b.mon.pp[i] = live.pp and live.pp[i]
    local row = rows[b.mon.moves[i] or -1]
    b.mon.moveTypes[i] = row and row[2]
  end
end

function Run:begin()
  local State = lazy("src.core.game3.battle.state")
  local Ui = lazy("src.core.game3.battle.ui")
  local Anim = lazy("src.core.game3.battle.anim")
  local AnimSeq = lazy("src.core.game3.battle.anim_seq")
  local IntroSeq = lazy("src.core.game3.battle.intro_seq")
  local SwitchSeq = lazy("src.core.game3.battle.switch_seq")
  local BattleBg = lazy("src.core.game3.battle.bg")
  local Battle = lazy("src.core.game3.battle")
  local bs = self.bs
  local t = bs.table
  self.disp = { [0] = {}, [1] = {} }
  for seat = 0, 1 do
    for i, rec in ipairs(self.parties[seat] or {}) do self.disp[seat][i] = dispMon(rec, t) end
  end
  self.active = { [0] = 1, [1] = 1 }
  local mine, foe = bs.seat, bs.peer
  local pst = State.new({ playerParty = self.disp[mine], foeParty = self.disp[foe], playerIndex = 1, foeIndex = 1,
    rng = function() return 0 end })
  pst.link = true
  pst.g3u = true
  pst.session = self.session
  pst.playerName = self.names.me or (self.session and self.session.name)
  pst.peerName = self.names.foe or ""
  pst.trainerName = pst.peerName
  pst.trainerClassName = ""
  pst.trainerPicId = trainerPic(self.opts.foeGender)
  pst.playerGender = playerGender(self.session)
  self.pst = pst
  self.prevSt = Battle._st
  Battle._st = pst
  Ui.reset({})
  Ui.bindState(pst, self.session)
  Anim.reset({ double = false })
  AnimSeq.reset()
  IntroSeq.reset()
  SwitchSeq.reset()
  BattleBg.setTerrain(BattleBg.resolveOverride(BattleBg.resolveOpts({}), { link = true, trainer = true }))
  Anim.syncDisplayFromState(pst)
  SwitchSeq.stampSwitchIn(pst)
  local pushMsg = function(text) Ui.push(text) end
  if IntroSeq.begin(pst, { pushMsg = pushMsg, trainerPicId = pst.trainerPicId, playerGender = pst.playerGender }) then
    local texts = { IntroSeq.introText(pst), IntroSeq.sendOutText(pst, "enemy") }
    local n, rulesAt = 0, nil
    for i, step in ipairs(IntroSeq._steps or {}) do
      if step.kind == "msg" and n < 2 then
        n = n + 1
        step.data.text = texts[n]
        if n == 1 then rulesAt = i + 1 end
      end
    end
    table.insert(IntroSeq._steps, rulesAt or 1, { kind = "msg", data = { text = S(M.RULES_TEXT) } })
  else
    Ui.push(IntroSeq.introText(pst))
    Ui.push(S(M.RULES_TEXT))
    Ui.push(IntroSeq.sendOutText(pst, "enemy"))
    Ui.push(IntroSeq.sendOutText(pst, "player"))
  end
  self.phase = "intro"
end

function Run:openMenu()
  local Ui = lazy("src.core.game3.battle.ui")
  self:syncMoves()
  local menu = M.menu(self.bs:legal())
  self.legal = menu
  if menu.locked then
    self.bs:choose({ kind = "move", slot = menu.locked.slot, locked = true })
    return self:afterChoice()
  end
  Ui.openMenu(0)
  self.phase = "menu"
end

function Run:afterChoice()
  self.phase = "play"
  self:standby()
end

function Run:choose(act)
  if self.bs:choose(act) then return self:afterChoice() end
  self.phase = "menu"
end

function Run:selMsg(text, back)
  local Ui = lazy("src.core.game3.battle.ui")
  Ui._mode = "none"
  if text then Ui.push(text) end
  self.phase = "selmsg"
  self.selBack = back
end

function Run:moveError(slot)
  local Commands = lazy("src.core.game3.battle.commands")
  local State = lazy("src.core.game3.battle.state")
  local st = self.bs.match and self.bs.match.st
  local function proxy(b, side)
    if not b then return nil end
    return setmetatable({ side = side }, { __index = b })
  end
  local view = st and { wild = false, player = proxy(State.battler(st, self.bs.seat), "player"),
    enemy = proxy(State.battler(st, self.bs.peer), "enemy") }
  local ok, err = pcall(Commands.selectionError, view, slot)
  if ok and err then return err end
  local mon = self.pst.player and self.pst.player.mon
  if mon and (tonumber(mon.pp[slot]) or 0) == 0 then return self:text("STRINGID_NOPPLEFT", {}) end
  return self:text("STRINGID_PKMNMOVEISDISABLED", { active = { side = self.bs.seat, index = self.active[self.bs.seat] },
    currentMove = mon and mon.moves[slot] })
end

function Run:openParty(forced)
  local PartyMenu = lazy("src.ui.game3.party_menu")
  local Commands = lazy("src.core.game3.battle.commands")
  local RomText = lazy("src.core.game3.rom_text")
  local Ui = lazy("src.core.game3.battle.ui")
  local menu = M.menu(self.bs:legal())
  local pst = self.pst
  local activeSlot = self.active[self.bs.seat]
  Ui._mode = "party"
  self.phase = "party"
  self.partyForced = forced
  self.partyPick = nil
  PartyMenu.show(pst.playerParty, nil, {
    mode = forced and "battle_faint" or "battle_switch",
    session = self.session,
    activeSlot = activeSlot,
    battle = true,
    validate = function(slot)
      if menu.switches[slot] then return nil end
      local why = Commands.switchError(pst, slot, forced)
      if why then return why end
      local ok, txt = pcall(RomText.ascii, "gText_PkmnCantSwitchOut", { stringVars = { nameOf(pst.player.mon) } })
      return ok and txt or ""
    end,
    onSelect = function(slot)
      if slot ~= nil and menu.switches[slot] then self.partyPick = slot end
    end,
  })
end

function Run:partyStep()
  local PartyMenu = package.loaded["src.ui.game3.party_menu"]
  if PartyMenu and PartyMenu.isOpen() then return end
  local Ui = lazy("src.core.game3.battle.ui")
  local slot, forced = self.partyPick, self.partyForced
  self.partyPick = nil
  if slot then
    if forced then
      if self.bs:pickReplacement(slot) then return self:afterChoice() end
      return self:openParty(true)
    end
    return self:choose({ kind = "switch", index = slot })
  end
  if forced then return self:openParty(true) end
  Ui._mode = "menu"
  self.phase = "menu"
end

function Run:handleMenu(input)
  local Ui = lazy("src.core.game3.battle.ui")
  local function nav(index, maxN)
    local c = (index or 1) - 1
    if input:wasPressed("left") or input:wasPressed("right") then
      c = (c % 2 == 0) and (c + 1) or (c - 1)
    elseif input:wasPressed("up") or input:wasPressed("down") then
      c = (c < 2) and (c + 2) or (c - 2)
    else
      return index, false
    end
    if c < 0 or c >= maxN then return index, false end
    return c + 1, true
  end
  if self.phase == "menu" then
    local idx, moved = nav(Ui._menuIndex, 4)
    if moved then
      Ui._menuIndex = idx
      playSe("SE_SELECT")
      return
    end
    if not input:wasPressed("a") then return end
    playSe("SE_SELECT")
    local pick = Ui._menuIndex
    if pick == 1 then
      local menu = self.legal
      if menu.struggle then
        local text = self:text("STRINGID_PKMNHASNOMOVESLEFT",
          { active = { side = self.bs.seat, index = self.active[self.bs.seat] } })
        self.afterSel = { kind = "move", slot = 0 }
        return self:selMsg(text, "choose")
      end
      Ui._openMoveMenu()
      self.phase = "moves"
    elseif pick == 2 then
      self:selMsg(self:text("STRINGID_ITEMSCANTBEUSEDNOW", {}), "menu")
    elseif pick == 3 then
      self:openParty(false)
    else
      self:confirmForfeit()
    end
  elseif self.phase == "moves" then
    local mon = self.pst.player and self.pst.player.mon
    local n = 0
    for i = 1, 4 do if mon and mon.moves[i] and mon.moves[i] ~= 0 then n = i end end
    local idx, moved = nav(Ui._moveIndex, math.max(1, n))
    if moved then
      Ui._moveIndex = idx
      playSe("SE_SELECT")
      return
    end
    if input:wasPressed("a") then
      playSe("SE_SELECT")
      local slot = Ui._moveIndex
      if self.legal.moves[slot] then return self:choose({ kind = "move", slot = slot }) end
      return self:selMsg(self:moveError(slot), "moves")
    elseif input:wasPressed("b") then
      playSe("SE_SELECT")
      Ui._mode = "menu"
      self.phase = "menu"
    end
  end
end

function Run:confirmForfeit()
  local Ui = lazy("src.core.game3.battle.ui")
  local RomText = lazy("src.core.game3.rom_text")
  local text
  if RomText.has("sText_QuestionForfeitMatch") then
    text = RomText.plain("sText_QuestionForfeitMatch")
  else
    text = S("Would you like to forfeit\nthis Union battle?")
  end
  Ui._mode = "none"
  self.phase = "confirm"
  Ui.askYesNo(text, function(yes)
    if self.phase ~= "confirm" then return end
    if yes and self.bs.phase == "choose" then
      self.bs:forfeit()
      return self:afterChoice()
    end
    Ui._mode = "menu"
    self.phase = "menu"
    Ui._linger = false
  end)
end

function Run:endText(over)
  local why = over.why
  if why == "faint" or why == "forfeit" then
    local word = ({ win = "won", lose = "lost", draw = "drew" })[over.outcome] or "drew"
    local BattleText = lazy("src.core.game3.battle.battle_text")
    local Adapter = lazy("src.core.game3.battle.adapter")
    local ok, text = pcall(BattleText.get, "STRINGID_BATTLEEND",
      Adapter.fill(self.pst, { outcome = word, linkRan = why == "forfeit" or nil }))
    return ok and text or nil
  end
  return S(END_TEXT[why] or END_TEXT.error)
end

function Run:handleInput(input)
  if not input then return end
  local Choice = lazy("src.ui.game3.choice")
  local Message = lazy("src.ui.game3.message")
  if Message.setSpeedUp then Message.setSpeedUp(input:isDown("a") or input:isDown("b")) end
  if Choice.active then
    if input:wasPressed("up") then Choice.move(-1)
    elseif input:wasPressed("down") then Choice.move(1)
    elseif input:wasPressed("a") then Choice.confirm()
    elseif input:wasPressed("b") then Choice.cancel() end
    return
  end
  if self.phase == "menu" or self.phase == "moves" then return self:handleMenu(input) end
end

function Run:playNext()
  local Ui = lazy("src.core.game3.battle.ui")
  local AnimSeq = lazy("src.core.game3.battle.anim_seq")
  local beat = self.script:next()
  if not beat then return false end
  if beat.kind == "segment" then
    local evs = self:apply(beat.ops)
    if #evs > 0 then
      AnimSeq.beginEvents(evs, function(text, wait, id) self:pushMsg(text, wait, id) end)
      self.phase = "animating"
    end
    return true
  end
  local a = beat.action
  if beat.kind == "prompt" then
    if a.what == "replace" then
      self:openParty(true)
    else
      self:openMenu()
    end
  elseif beat.kind == "wait" then
    if a.what == "replace" then self:standby() end
  elseif beat.kind == "over" then
    self.over = a
    Ui._mode = "none"
    local text = self:endText(a)
    if text then Ui.push(text) end
    self.phase = "ending"
  end
  return true
end

function Run:finish()
  if self.phase == "done" or self.phase == "fading" then return end
  self.phase = "fading"
  local Fade = lazy("src.ui.game3.fade")
  pcall(function() lazy("src.core.game3.audio").fadeOutBgm(5) end)
  Fade.begin(Fade.MODE.TO_BLACK, 1, function() self:close() end)
end

function Run:close()
  if self.phase == "done" then return end
  self.phase = "done"
  local Stack = lazy("src.ui.game3.stack")
  local Battle = lazy("src.core.game3.battle")
  local Fade = lazy("src.ui.game3.fade")
  for _, name in ipairs({ "src.core.game3.battle.anim_seq", "src.core.game3.battle.intro_seq",
    "src.core.game3.battle.switch_seq" }) do
    pcall(function() lazy(name).reset() end)
  end
  pcall(function() lazy("src.core.game3.battle.anim").reset({ headless = true }) end)
  pcall(function()
    local PartyMenu = package.loaded["src.ui.game3.party_menu"]
    if PartyMenu and PartyMenu.isOpen() then PartyMenu._onClose = nil PartyMenu.close() end
  end)
  pcall(function()
    local Ui = lazy("src.core.game3.battle.ui")
    Ui.reset({ headless = true })
    Ui.bindState(nil)
  end)
  pcall(function()
    local Message = lazy("src.ui.game3.message")
    Message.setFrame("dialogue")
    Message.close()
  end)
  if Battle._st == self.pst then Battle._st = self.prevSt end
  Stack.pop(M.LAYER)
  if self.task then lazy("src.core.game3.task").cancel(self.task.id) end
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.unlock then Field.unlock() end
  pcall(function() lazy("src.core.game3.audio").restoreMapSong() end)
  Fade.begin(Fade.MODE.FROM_BLACK, 1)
  self.onDone(self.bs.result)
end

function Run:abort(why)
  print("[g3u/gen3] presenter failed: " .. tostring(why))
  if not self.bs.result then pcall(self.bs.quit, self.bs) end
  if self.phase == "connect" then
    self:connectFailed()
    return
  end
  self.phase = "fading"
  local Fade = lazy("src.ui.game3.fade")
  Fade.clear()
  self.phase = "x"
  self:close()
end

function Run:connectFailed()
  self.phase = "done"
  local Message = lazy("src.ui.game3.message")
  if self.task then lazy("src.core.game3.task").cancel(self.task.id) end
  local Field = package.loaded["src.core.game3.field"]
  local r = self.bs.result or {}
  Message.show(S(END_TEXT[r.why] or END_TEXT.error), { done = function()
    if Field and Field.unlock then Field.unlock() end
    self.onDone(self.bs.result)
  end })
end

function Run:pushLayer()
  local Stack = lazy("src.ui.game3.stack")
  local run = self
  local layer = {
    isMenu = false,
    update = function() end,
    handleInput = function(input) run:handleInput(input) end,
    draw = function() run:draw() end,
  }
  self.layer = layer
  Stack.push(M.LAYER, layer, {
    hideBelow = true,
    fullscreen = function()
      local Fade = package.loaded["src.ui.game3.fade"]
      return not (Fade and (Fade.active or (Fade.t or 0) > 0))
    end,
  })
end

function Run:draw()
  if not self.pst then return end
  local Ui = lazy("src.core.game3.battle.ui")
  local Display = lazy("src.core.game3.display")
  local Message = lazy("src.ui.game3.message")
  local Choice = lazy("src.ui.game3.choice")
  local Bg = lazy("src.core.game3.bg")
  Ui.draw(Display.W, Display.H)
  if Message.isOpen() then Message.draw() end
  if Choice.active and Choice.draw then Choice.draw() end
  if Bg.hasVisible() then Bg.flushAll() end
end

function Run:connectStep()
  local Message = lazy("src.ui.game3.message")
  while self.script:pending() do
    local q = self.script.queue[self.script.qi]
    if q.kind == "ready" then
      self.script.qi = self.script.qi + 1
      self.parties = q.parties
      if Message.isOpen() then Message.close() end
      self.phase = "transition"
      return self:startTransition()
    end
    if q.kind == "over" then
      if Message.isOpen() then Message.close() end
      return self:connectFailed()
    end
    self.script.qi = self.script.qi + 1
  end
end

function Run:startTransition()
  local BattleTransition = lazy("src.core.game3.battle_transition")
  local song = battleSong()
  if song then pcall(function() lazy("src.core.game3.audio").playSong(song) end) end
  local function go()
    local ok, err = pcall(function()
      self:pushLayer()
      self:begin()
    end)
    if not ok then self:abort(err) end
  end
  local mine = self.parties[self.bs.seat] or {}
  local foe = self.parties[self.bs.peer] or {}
  local pickOpts = { wild = false, playerLevel = mine[1] and mine[1].level or 5,
    enemyLevel = foe[1] and foe[1].level or 5, playerGender = playerGender(self.session) }
  local ok = pcall(function()
    BattleTransition.start(BattleTransition.pick(pickOpts), pickOpts, go)
  end)
  if not ok then go() end
end

function Run:interrupt()
  local Ui = lazy("src.core.game3.battle.ui")
  local Choice = package.loaded["src.ui.game3.choice"]
  if Choice and Choice.active then Choice.reset() end
  local PartyMenu = package.loaded["src.ui.game3.party_menu"]
  if PartyMenu and PartyMenu.isOpen() then
    PartyMenu._onClose = nil
    PartyMenu._onSelect = nil
    PartyMenu.close()
  end
  Ui._mode = "none"
  Ui._pendingYesNo = nil
  self.partyPick = nil
  self.phase = "play"
end

function Run:step(dt)
  local bs = self.bs
  bs:update()
  self.script:push(bs:events())
  if self.phase == "connect" then return self:connectStep() end
  if self.phase == "transition" or self.phase == "done" or self.phase == "fading" or self.phase == "x" then return end
  local Ui = lazy("src.core.game3.battle.ui")
  local Anim = lazy("src.core.game3.battle.anim")
  local AnimSeq = lazy("src.core.game3.battle.anim_seq")
  local IntroSeq = lazy("src.core.game3.battle.intro_seq")
  local Message = lazy("src.ui.game3.message")
  Anim.update(dt or 0)
  pcall(function() lazy("src.core.game3.audio").tickCry(dt or 1 / 60) end)
  local PartyMenu = package.loaded["src.ui.game3.party_menu"]
  if PartyMenu and PartyMenu.isOpen() and PartyMenu.update then PartyMenu.update(dt or 1 / 60) end
  if not (PartyMenu and PartyMenu.isOpen()) and Message.tick then Message.tick() end
  if bs.result and INPUT_PHASES[self.phase] then self:interrupt() end
  local phase = self.phase
  if phase == "intro" then
    if not Ui.pump() then return end
    if IntroSeq.update() then self.phase = "play" end
    return
  end
  if phase == "menu" or phase == "moves" then
    Ui.tick()
    Ui.pump()
    return
  end
  if phase == "confirm" then
    Ui.pump()
    return
  end
  if phase == "party" then return self:partyStep() end
  if phase == "selmsg" then
    if not Ui.pump() then return end
    local back = self.selBack
    self.selBack = nil
    if back == "choose" then
      local act = self.afterSel
      self.afterSel = nil
      return self:choose(act)
    end
    Ui._mode = (back == "moves") and "moves" or "menu"
    self.phase = back == "moves" and "moves" or "menu"
    return
  end
  if phase == "animating" then
    if Anim.busy() then return end
    if not Ui.pump() then return end
    if AnimSeq.update() then self.phase = "play" end
    return
  end
  if phase == "play" then
    if Anim.busy() or not Ui.pump() then return end
    for _ = 1, 8 do
      if self.phase ~= "play" then break end
      if not self:playNext() then break end
    end
    return
  end
  if phase == "ending" then
    if Anim.busy() or not Ui.pump() then return end
    self:finish()
  end
end

function M.start(game, bs, opts)
  opts = opts or {}
  if type(bs) ~= "table" then return nil, "no_session" end
  local Battle = lazy("src.core.game3.battle")
  if Battle.isActive() then return nil, "battle_active" end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession() or nil
  local run = setmetatable({
    game = game, bs = bs, opts = opts, session = session, names = opts.names or {},
    script = M.newScript(bs.seat), phase = "connect", onDone = once(opts.onDone),
  }, Run)
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.lock then Field.lock() end
  pcall(function()
    local text = standbyText()
    if text then lazy("src.ui.game3.message").show(text, { stay = true }) end
  end)
  run.task = lazy("src.core.game3.task").spawn(function(_, dt)
    local ok, err = pcall(run.step, run, dt)
    if not ok then run:abort(err) end
    return run.phase == "done"
  end)
  return { kind = "gen3", run = run, bs = bs, stop = function() run:abort("stopped") end }
end

function M.nativeTeam(session)
  local size = tonumber(session and session.go and session.go.size) or 6
  local out = {}
  for _, i in ipairs(type(session and session.team) == "table" and session.team or {}) do
    if #out < size and tonumber(i) then out[#out + 1] = tonumber(i) end
  end
  if #out == 0 then
    if size >= 6 then return nil end
    for i = 1, size do out[i] = i end
  end
  return out
end

function M.startNative(game, session, opts)
  opts = opts or {}
  session = session or {}
  local done = once(opts.onDone)
  local Battle = lazy("src.core.game3.battle")
  if Battle.isActive() then return nil, "battle_active" end
  local L = lazy("src.core.game3.link")
  local LB = lazy("src.core.game3.link.battle")
  local Game3Link = lazy("src.link.Game3Link")
  local Task = lazy("src.core.game3.task")
  local Message = lazy("src.ui.game3.message")
  if type(session.net) ~= "table" then return nil, "no_session" end
  local lk, why = L.openRelay({ session = session.net, client = session.client,
    linkType = Game3Link.LINKTYPE.BATTLE })
  if not lk then return nil, why or "no_link" end
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.lock then Field.lock() end
  local standby = standbyText()
  if standby then Message.show(standby, { stay = true }) end
  local h = { kind = "native", gen = 3, stage = "link", waited = 0 }
  local function leave(word)
    if h.stage == "over" then return end
    h.stage = "over"
    h.result = word
    L.closeLink("exit_link_room")
    done(word)
  end
  local function fail(reason)
    if Message.isOpen() then Message.close() end
    if Field and Field.unlock then Field.unlock() end
    h.why = reason
    if LB.state == "setup" then
      LB.refuse(reason)
    end
    leave("error")
  end
  h.task = Task.spawn(function(_, dt)
    if h.stage == "over" then return true end
    h.waited = h.waited + (tonumber(dt) or 0)
    if h.stage == "link" then
      local live = L.link
      if not (live and live:isOpen()) then fail("link_closed") return true end
      if not live:isReady() then
        if h.waited > M.NATIVE_WAIT then fail("timeout") return true end
        return false
      end
      if Message.isOpen() then Message.close() end
      if Field and Field.unlock then Field.unlock() end
      local ok, err = LB.startUnionRoomBattle(function(word)
        h.word = word or "draw"
        h.stage = "ending"
      end, { team = M.nativeTeam(session) })
      if not ok then fail(err or "setup_failed") return true end
      local seed = tonumber(session.go and session.go.seed)
      if seed then LB.seed = math.floor(seed) % 4294967296 end
      h.stage = "setup"
      return false
    end
    if h.stage == "setup" then
      if LB.state == "setup" then LB.pumpUnionSetup() end
      if LB.state == "battle" then h.stage = "battle" return false end
      if LB.state ~= "setup" and h.stage == "setup" then fail(LB.endReason or "setup_failed") return true end
      if h.waited > M.NATIVE_WAIT * 2 then fail("timeout") return true end
      return false
    end
    if h.stage == "ending" then
      leave(h.word)
      return true
    end
    return false
  end)
  return h
end

return M
