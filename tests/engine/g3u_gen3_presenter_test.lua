package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._g3u_fixture")
local L = require("tests.support.g3u_loopback")
local Table = require("src.battle.g3u.Table")
local Scope = require("src.battle.g3u.Scope")
local BS = require("src.online.union.BattleSession")
local P = require("src.ui.g3u.Gen3Presenter")

T.eq(type(P.start), "function", "Gen3Presenter.start exists")
T.eq(type(P.startNative), "function", "Gen3Presenter.startNative exists")

do
  T.eq(P.sideOf(1, 1), "player", "my seat shows on the player side")
  T.eq(P.sideOf(0, 1), "enemy", "the peer seat shows on the enemy side")
  T.eq(P.idOf(0, 0), 0, "seat 0 as seat 0 is battler 0")
  T.eq(P.idOf(0, 1), 1, "seat 0 as seat 1 is battler 1")

  local mv = P.map({ kind = "move", moveId = 33, user = 0, target = 1, turn = 0 }, 1)
  T.eq(mv.act, "anim", "move maps to an anim")
  T.eq(mv.ev.kind, "move", "move anim keeps its kind")
  T.eq(mv.ev.attacker, "enemy", "seat 0 attacking seat 1 is the enemy from seat 1")
  T.eq(mv.ev.targetId, 0, "the target battler id is mine")
  T.eq(mv.ev.moveId, 33, "move id passes through")

  local hit = P.map({ kind = "hp", side = 1, from = 50, to = 20, max = 60, hit = true }, 1)
  T.eq(hit.act, "hp", "hp maps to hp")
  T.eq(hit.ev.kind, "hit", "a hit hp event plays the hit flash")
  T.eq(hit.ev.side, "player", "hp on my seat is the player side")
  T.eq(hit.ev.maxHp, 60, "hp carries max")
  T.eq(hit.to, 20, "hp target value kept for the display state")
  local drain = P.map({ kind = "hp", side = 0, from = 5, to = 10, max = 60 }, 1)
  T.eq(drain.ev.kind, "hp", "a plain hp event has no hit flash")

  local st = P.map({ kind = "status", side = 0, status = "PAR" }, 0)
  T.eq(st.ev.kind, "status_apply", "status maps to status_apply")
  T.eq(st.status, "PAR", "status value kept")
  local cl = P.map({ kind = "status", side = 0, status = "NONE" }, 0)
  T.eq(cl.ev.kind, "status_clear", "NONE clears the status")
  T.eq(cl.status, nil, "cleared status is nil")

  T.eq(P.map({ kind = "stage", side = 0, stat = "attack", delta = 2 }, 0).act, "stage", "stage maps to stage")
  local f = P.map({ kind = "faint", side = 0 }, 1)
  T.eq(f.ev.kind, "faint", "faint plays faint")
  T.eq(f.ev.battler, 1, "seat 0 fainting is battler 1 from seat 1")
  T.eq(P.map({ kind = "withdraw", side = 0, index = 1, reason = "switch" }, 0).act, "withdraw", "withdraw")
  local so = P.map({ kind = "sendout", side = 1, index = 2, reason = "switch" }, 0)
  T.eq(so.act, "sendout", "sendout")
  T.eq(so.index, 2, "sendout index")
  T.eq(P.map({ kind = "weather", weather = "RAIN", turns = 5 }, 0).act, "weather", "weather")
  local an = P.map({ kind = "anim", anim = "status", name = "SLEEP", user = 1, target = 1 }, 1)
  T.eq(an.ev.kind, "anim", "anim maps to anim")
  T.eq(an.ev.attacker, "player", "anim user resolved by seat")
  T.eq(an.ev.name, "SLEEP", "anim name kept")
  T.eq(P.map({ kind = "need_replacement", side = 0 }, 0).act, "none", "need_replacement draws nothing")
  T.eq(P.map({ kind = "end", result = { winner = 0 } }, 0).act, "end", "end")
  T.eq(P.map({ kind = "ready" }, 0).act, "ready", "ready")
  T.eq(P.map({ kind = "prompt", what = "move" }, 0).act, "prompt", "prompt")
  T.eq(P.map({ kind = "waiting", what = "move" }, 0).act, "wait", "waiting")
  T.eq(P.map({ kind = "over", outcome = "win", why = "faint" }, 0).why, "faint", "over keeps why")
  local msg = P.map({ kind = "msg", id = "STRINGID_CRITICALHIT", fill = {} }, 0)
  T.eq(msg.act, "text", "msg maps to text")
  T.eq(msg.id, "STRINGID_CRITICALHIT", "msg id kept")
end

do
  local m = P.menu({ { kind = "move", slot = 1 }, { kind = "move", slot = 3 }, { kind = "switch", index = 2 },
    { kind = "switch", index = 4 }, { kind = "forfeit" } })
  T.check(m.moves[1] and m.moves[3] and not m.moves[2] and not m.moves[4], "only legal move slots are offered")
  T.check(m.switches[2] and m.switches[4] and not m.switches[1], "only legal party slots are offered")
  T.eq(m.count, 2, "two legal switches")
  T.check(m.forfeit ~= nil, "forfeit offered")
  T.eq(m.locked, nil, "nothing locked")
  local s = P.menu({ { kind = "move", slot = 0 }, { kind = "forfeit" } })
  T.check(s.struggle ~= nil and next(s.moves) == nil, "Struggle only when no move is usable")
  local lk = P.menu({ { kind = "move", slot = 2, locked = true }, { kind = "forfeit" } })
  T.eq(lk.locked and lk.locked.slot, 2, "a locked move is picked out for auto-submit")
  T.eq(next(lk.switches), nil, "a locked turn offers no switch")
  local r = P.menu({ { kind = "switch", index = 3 } })
  T.check(r.switches[3] and r.count == 1 and r.forfeit == nil, "replacement menu is the legal indices only")
end

local R = {
  mon = function(seat, index) return "S" .. tostring(seat) .. "I" .. tostring(index) end,
  move = function(n) return "MOVE" .. n end,
  species = function(n) return "SPECIES" .. n end,
  ability = function(n) return "ABILITY" .. n end,
  type = function(n) return "TYPE" .. n end,
  stat = function(k) return "STAT_" .. k end,
  change = function(d) return d > 0 and "rose!" or "fell!" end,
}

do
  local fill = { atk = { side = 0, index = 2 }, def = { side = 1, index = 1 }, currentMove = 33,
    buff1 = { move = 30 } }
  local a = P.resolveFill(fill, 1, R)
  T.eq(a.atk.side, "enemy", "attacker on seat 0 resolves to the enemy side for seat 1")
  T.eq(a.atk.name, "S0I2", "attacker name comes from seat 0 party slot 2")
  T.eq(a.def.side, "player", "defender on my seat resolves to the player side")
  T.eq(a.def.name, "S1I1", "defender name from my party")
  T.eq(a.currentMove, 33, "numeric move ids pass through")
  T.eq(a.buff1, "MOVE30", "move tokens become names")
  local b = P.resolveFill(fill, 0, R)
  T.eq(b.atk.side, "player", "same fill from seat 0: attacker is mine")
  T.eq(b.def.side, "enemy", "same fill from seat 0: defender is the foe")
  local s = P.resolveFill({ atk = { side = 0, index = 1 }, def = { side = 0, index = 1 }, stat = "defense",
    delta = -2 }, 0, R)
  T.eq(s.buff1, "STAT_defense", "stat messages carry the stat name")
  T.eq(s.buff2, "fell!", "stat messages carry the change text")
  T.eq(s.stat, nil, "stat key removed")
  local w = P.resolveFill({ buff1 = "attack", def = { side = 1, index = 3 } }, 0, R)
  T.eq(w.buff1, "STAT_attack", "bare stat keys in buff1 become names")
  local e = P.resolveFill({ atk = "enemy", buff1 = { move = 113 } }, 1, R)
  T.eq(e.atk, "player", "an engine side name on seat 1 is my side")
  local e0 = P.resolveFill({ atk = "enemy" }, 0, R)
  T.eq(e0.atk, "enemy", "an engine side name on seat 0 stays")
  local sp = P.resolveFill({ buff1 = { species = 87 }, side = 1 }, 1, R)
  T.eq(sp.buff1, "SPECIES87", "species tokens become names")
  T.eq(sp.side, "player", "a numeric side resolves by seat")
  T.eq(P.resolveFill({ buff1 = { type = 12 } }, 0, R).buff1, "TYPE12", "type tokens become names")
end

do
  local s = P.newScript(1)
  s:push({
    { kind = "ready" },
    { kind = "sendout", side = 0, index = 1, reason = "start" },
    { kind = "sendout", side = 1, index = 1, reason = "start" },
    { kind = "prompt", what = "move", turn = 1 },
  })
  T.eq(s:next().kind, "ready", "ready first")
  local seg = s:next()
  T.eq(seg.kind, "segment", "start sendouts form a segment")
  T.eq(#seg.ops, 2, "both sendouts in one segment")
  T.eq(s:next().kind, "prompt", "then the prompt")
  T.eq(s:next(), nil, "queue drained")
  s:push({
    { kind = "withdraw", side = 1, index = 1, reason = "switch" },
    { kind = "sendout", side = 1, index = 2, reason = "switch" },
    { kind = "msg", id = "STRINGID_USEDMOVE", fill = {} },
    { kind = "withdraw", side = 1, index = 2, reason = "roar" },
    { kind = "sendout", side = 1, index = 3, reason = "roar" },
    { kind = "msg", id = "STRINGID_PKMNWASDRAGGEDOUT", fill = {} },
    { kind = "prompt", what = "move", turn = 2 },
  })
  local a = s:next()
  T.eq(#a.ops, 4, "a second sendout of one side starts a new segment")
  local b = s:next()
  T.eq(b.ops[1].act, "sendout", "the second segment starts with the roar switch")
  T.eq(b.ops[1].index, 3, "roar sendout index")
  T.eq(s:next().kind, "prompt", "prompt after both segments")
end

local function live()
  local M = Scope.modules()
  local Pokemon, Moves = M["src.core.game3.pokemon"], M["src.core.game3.battle.moves"]
  local BattleText, Adapter = M["src.core.game3.battle.battle_text"], M["src.core.game3.battle.adapter"]
  return {
    rawget(Pokemon, "_names"), rawget(Pokemon, "_types"), rawget(Pokemon, "_stats"), rawget(Pokemon, "_moveNames"),
    rawget(Pokemon, "install"), rawget(Moves, "_rom"), rawget(Moves, "BY_NUM"), rawget(Moves, "_romLoaded"),
    rawget(Moves, "loadRomPack"), rawget(BattleText, "get"), rawget(Adapter, "textSink"), math.random,
  }
end

do
  local data = F.gen1()
  local t = assert(Table.build(data, 1))
  local before = live()
  local seen, bad, prompts, overs, refs, readyFirst = {}, 0, 0, 0, 0, nil
  local okSeat = true
  for seed = 1, 12 do
    local rnd = L.lcg(seed)
    local na, nb = L.pair()
    local go = { seed = seed * 7, size = 3 }
    local gens = { [0] = 1, [1] = 3 }
    local a = BS.new({ net = na, seat = 0, go = go, gens = gens, data = data, records = F.randomParty(t, rnd, 3),
      names = { [0] = "RED", [1] = "MAY" } })
    local b = BS.new({ net = nb, seat = 1, go = go, gens = gens, records = F.randomParty(t, rnd, 3),
      names = { [0] = "RED", [1] = "MAY" } })
    local ba = L.bot(a, { seed = seed, switches = true })
    local bb = L.bot(b, { seed = seed + 3, switches = true })
    local script = P.newScript(1)
    local first = true
    for _ = 1, 4000 do
      ba() bb()
      script:push(b:events())
      while true do
        local beat = script:next()
        if not beat then break end
        if first then
          readyFirst = (readyFirst == nil or readyFirst) and beat.kind == "ready"
          first = false
        end
        if beat.kind == "prompt" then prompts = prompts + 1 end
        if beat.kind == "over" then overs = overs + 1 end
        for _, op in ipairs(beat.ops or {}) do
          seen[op.act] = true
          if op.act == "text" then
            local fill = P.resolveFill(op.fill, 1, R)
            for k, v in pairs(op.fill) do
              if type(v) == "table" and type(v.side) == "number" and v.index then
                refs = refs + 1
                local r = fill[k]
                if not (type(r) == "table" and r.side == P.sideOf(v.side, 1)
                    and r.name == R.mon(v.side, v.index)) then okSeat = false end
              end
            end
            for _, v in pairs(fill) do
              if type(v) == "table" and type(v.side) == "number" then bad = bad + 1 end
            end
          end
        end
      end
      if a.result and b.result then break end
    end
  end
  T.check(readyFirst, "every presented battle starts with ready")
  T.eq(overs, 12, "every presented battle ends with exactly one over")
  T.check(prompts > 12, "prompts reach the presenter")
  T.check(refs > 0 and okSeat, "every battler ref in a message resolves to the seat's own side and party slot")
  T.eq(bad, 0, "no raw seat refs reach BattleText")
  for _, k in ipairs({ "text", "anim", "hp", "faint", "withdraw", "sendout" }) do
    T.check(seen[k], "a real battle produces " .. k .. " ops")
  end
  local after = live()
  local same = true
  for i = 1, #before do if before[i] ~= after[i] then same = false end end
  T.check(same, "live Gen 3 data is the same table set before and after presented battles")
end

T.finish("g3u_gen3_presenter")
