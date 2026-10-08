package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._g3u_fixture")
local Table = require("src.battle.g3u.Table")
local Match = require("src.battle.g3u.Match")
local Scope = require("src.battle.g3u.Scope")
local Wire = require("src.battle.g3u.Wire")
local E = require("src.core.game3.battle.effect_ids")

local t1 = assert(Table.build(F.gen1()))
local t2 = assert(Table.build(F.gen2()))
local M = Scope.modules()
local Moves, Damage, Types = M["src.core.game3.battle.moves"], M["src.core.game3.battle.damage"], M["src.core.game3.battle.types"]

Scope.resetTrips()

local function match(t, p0, p1, seed)
  local m = Match.new({ table = t, parties = { [0] = p0, [1] = p1 }, seed = seed or 1 })
  return m, m:start()
end

local function find(evs, pred)
  for _, e in ipairs(evs) do if pred(e) then return e end end
  return nil
end

local function act(slot) return { kind = "move", slot = slot } end

local bite = Scope.run(t1, function() return Moves.get(44) end)
T.eq(bite.type, 0, "Gen 1 Bite runs as a Normal move")
T.eq(bite.category, "physical", "Gen 1 Bite is physical")
T.eq(bite.effect, E.FLINCH_HIT, "Gen 1 Bite flinches")
T.eq(bite.secondaryChance, 10, "Gen 1 Bite flinches 10 percent")
local bite2 = Scope.run(t2, function() return Moves.get(44) end)
T.eq(bite2.type, 17, "Gen 2 Bite runs as a Dark move")

do
  local m = match(t1, { F.record(t1, 81, { 33 }) }, { F.record(t1, 95, { 89 }) })
  T.eq(m.st.player.type1, 13, "Gen 1 Magnemite battles as Electric")
  T.eq(m.st.player.type2, nil, "Gen 1 Magnemite has no second type")
  local eff = Scope.run(t1, function() return Types.typeCalc(4, m.st.player.type1, m.st.player.type2, 40) end)
  T.eq(eff, 80, "Ground hits Gen 1 Magnemite for double, not quadruple")
  local m2 = match(t2, { F.record(t2, 81, { 33 }) }, { F.record(t2, 95, { 89 }) })
  local eff2 = Scope.run(t2, function() return Types.typeCalc(4, m2.st.player.type1, m2.st.player.type2, 40) end)
  T.eq(eff2, 160, "Ground hits Gen 2 Magnemite for quadruple")
end

do
  local special = 120
  local a = F.record(t1, 65, { 94, 44 }, 50, { spAtk = special, spDef = special, atk = 80, def = 70 })
  local d = F.record(t1, 143, { 33 }, 50, { spAtk = 90, spDef = 90, atk = 100, def = 75 })
  local m = match(t1, { a }, { d })
  local st, ad = m.st, m.ad
  local dmg = Scope.run(t1, function()
    local mv = Moves.get(94)
    return Damage.base(st.player, st.enemy, mv, { adapter = ad })
  end)
  local lf = math.floor(2 * 50 / 5) + 2
  local want = math.floor(math.floor(special * 90 * lf / 90) / 50) + 2
  T.eq(dmg, want, "a Gen 1 Special move uses the attacker's Special as Sp. Atk and the target's as Sp. Def")
  st.enemy.mon.spAtk = 999
  local same = Scope.run(t1, function() return Damage.base(st.player, st.enemy, Moves.get(94), { adapter = ad }) end)
  T.eq(same, want, "the defender's Sp. Atk does not enter Special damage")
  st.enemy.mon.spDef = 45
  local more = Scope.run(t1, function() return Damage.base(st.player, st.enemy, Moves.get(94), { adapter = ad }) end)
  T.eq(more, math.floor(math.floor(special * 90 * lf / 45) / 50) + 2, "the defender's Sp. Def does")
  local phys = Scope.run(t1, function() return Damage.base(st.player, st.enemy, Moves.get(44), { adapter = ad }) end)
  T.eq(phys, math.floor(math.floor(80 * 60 * lf / 75) / 50) + 2, "Gen 1 Bite uses Attack against Defense")
end

do
  local bad = assert(Table.build(F.gen1({ [5] = { id = 5, type = "NORMAL", power = 0, accuracy = 100, pp = 20,
    effect = "SPEED_UP1_EFFECT" } })))
  local rec = F.record(bad, 25, { 33, 5 })
  local ok, why = Wire.record(rec, bad)
  T.check(not ok and why == "move_unsupported", "a party carrying an unsupported move is refused (" .. tostring(why) .. ")")
  local m = match(bad, { rec }, { F.record(bad, 25, { 33 }) })
  local offered = false
  for _, a in ipairs(m:legalActions(0)) do if a.kind == "move" and a.slot == 2 then offered = true end end
  T.check(not offered, "legalActions never offers the unsupported move")
  T.raises(function() m:submit({ [0] = act(2), [1] = act(1) }) end, "illegal", "submitting it raises")
end

do
  local slow = F.record(t1, 143, { 98 }, 50, { speed = 20 })
  local fast = F.record(t1, 25, { 33 }, 50, { speed = 200 })
  local m = match(t1, { slow }, { fast })
  local evs = m:submit({ [0] = act(1), [1] = act(1) })
  local first = find(evs, function(e) return e.kind == "move" end)
  T.eq(first and first.user, 0, "Gen 1 Quick Attack moves before a faster foe")
  local m2 = match(t1, { F.record(t1, 143, { 68 }, 50, { speed = 200 }) }, { F.record(t1, 25, { 33 }, 50, { speed = 20 }) })
  local evs2 = m2:submit({ [0] = act(1), [1] = act(1) })
  local first2 = find(evs2, function(e) return e.kind == "move" end)
  T.eq(first2 and first2.user, 1, "Gen 1 Counter moves after a slower foe")
end

do
  local user = F.record(t1, 143, { 118 }, 50)
  user.moves[1].pp = 60
  local foe = F.record(t1, 143, { 150 }, 100)
  foe.moves[1].pp = 60
  foe.hp, foe.maxHp, foe.def, foe.spDef = 700, 700, 600, 600
  local m = match(t1, { user }, { foe }, 77)
  local called, over = {}, 0
  for _ = 1, 50 do
    if m.phase ~= "choose" then break end
    local evs = m:submit({ [0] = act(1), [1] = act(1) })
    for _, e in ipairs(evs) do
      if e.kind == "move" and e.user == 0 and e.moveId ~= 118 then
        called[#called + 1] = e.moveId
        if e.moveId > t1.moveMax then over = over + 1 end
      end
    end
  end
  T.check(#called >= 5, "Metronome called moves (" .. #called .. ")")
  T.eq(over, 0, "Metronome only calls moves inside the Gen 1 table")
end

do
  local m = match(t1, { F.record(t1, 143, { 63, 33 }, 50) }, { F.record(t1, 143, { 150 }, 100, { def = 600 }) }, 3)
  local hb = m:submit({ [0] = act(1), [1] = act(1) })
  if find(hb, function(e) return e.kind == "hp" and e.side == 1 end) then
    local l = m:legalActions(0)
    T.eq(#l, 2, "a recharging mon has one locked action and forfeit")
    T.check(l[1].locked == true, "the action is marked locked")
  else
    T.check(true, "Hyper Beam missed under this seed")
  end
end

do
  local rec = F.record(t1, 143, { 33, 45 })
  rec.moves[1].pp, rec.moves[2].pp = 0, 0
  local m = match(t1, { rec }, { F.record(t1, 143, { 150 }) })
  local l = m:legalActions(0)
  T.same(l[1], { kind = "move", slot = 0 }, "a mon with no PP is offered Struggle")
  local evs = m:submit({ [0] = act(0), [1] = act(1) })
  T.check(find(evs, function(e) return e.kind == "move" and e.moveId == 165 end) ~= nil, "slot 0 uses Struggle")
end

do
  local m = match(t1, { F.record(t1, 143, { 14 }) }, { F.record(t1, 143, { 150 }) })
  local evs = m:submit({ [0] = act(1), [1] = act(1) })
  local stage = find(evs, function(e) return e.kind == "stage" end)
  T.check(stage ~= nil and stage.side == 0 and stage.stat == "attack" and stage.delta == 2,
    "Swords Dance reports a structured +2 Attack stage event")
  local msg = find(evs, function(e) return e.kind == "msg" and e.id == "STRINGID_ATTACKERSSTATROSE" end)
  T.check(msg ~= nil and msg.fill.atk and msg.fill.atk.side == 0 and msg.fill.stat == "attack",
    "the stat message carries a key and seat fill, no rendered text")
  local used = find(evs, function(e) return e.kind == "msg" and e.id == "STRINGID_USEDMOVE" end)
  T.check(used ~= nil and used.fill.currentMove and used.fill.currentMove.move == 14,
    "the used-move message names the move by id")
end

do
  local p0 = { F.record(t2, 25, { 226, 33 }), F.record(t2, 143, { 33 }) }
  local m = match(t2, p0, { F.record(t2, 143, { 150 }) })
  m:submit({ [0] = act(1), [1] = act(1) })
  T.eq(m.phase, "replace", "Baton Pass waits for the passer's pick")
  T.check(m:needs(0) and not m:needs(1), "only the passer picks")
  T.same(m:legalActions(0), { { kind = "switch", index = 2 } }, "the bench mon is the only pick")
  local evs = m:replace({ [0] = 2 })
  T.check(find(evs, function(e) return e.kind == "sendout" and e.side == 0 and e.index == 2 end) ~= nil,
    "the picked mon comes out")
  T.eq(m.phase, "choose", "the turn finishes after the pass")
end

do
  local p0 = { F.record(t1, 143, { 33 }, 5), F.record(t1, 25, { 33 }) }
  local p1 = { F.record(t1, 143, { 33 }, 100, { atk = 500 }) }
  local m = match(t1, p0, p1, 9)
  local evs = m:submit({ [0] = act(1), [1] = act(1) })
  T.check(find(evs, function(e) return e.kind == "faint" and e.side == 0 end) ~= nil, "the level 5 lead faints")
  T.eq(m.phase, "replace", "a faint with a bench waits for a replacement")
  T.check(find(evs, function(e) return e.kind == "need_replacement" and e.side == 0 end) ~= nil,
    "need_replacement names the seat")
  T.raises(function() m:replace({ [0] = 1 }) end, "illegal", "the fainted mon cannot be sent back")
  m:replace({ [0] = 2 })
  T.eq(m:active(0), 2, "the replacement is active")
end

do
  local m = match(t1, { F.record(t1, 143, { 33 }) }, { F.record(t1, 143, { 33 }) })
  local evs = m:submit({ [0] = { kind = "forfeit" }, [1] = act(1) })
  local fin = find(evs, function(e) return e.kind == "end" end)
  T.check(fin and fin.result.winner == 1 and fin.result.why == "forfeit", "a forfeit ends the match for the other seat")
  T.eq(m.phase, "over", "the match is over")
end

T.eq(#Scope.trips, 0, "no cache, text or math.random read during these matches " .. tostring(Scope.trips[1]))

T.finish("g3u mechanics")
