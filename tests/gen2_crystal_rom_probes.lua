local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

return function(data)
  local passed, failed = 0, 0
  local function probe(name, test)
    local ok, reason = pcall(test)
    if ok then
      passed = passed + 1
      print("PASS " .. name)
    else
      failed = failed + 1
      print("FAIL " .. name .. ": " .. tostring(reason))
    end
  end
  local function check(value, message)
    assert(value, message)
  end
  local function fixture(id, species, targetSpecies, roll)
    local dvs = { attack = 15, defense = 15, speed = 15, special = 15 }
    local a = Mon.new(data, species or "MEW", 50, { dvs = dvs })
    local b = Mon.new(data, targetSpecies or "SNORLAX", 50, { dvs = dvs })
    local def = assert(data.moves[id], id)
    a.moves = { { id = id, pp = def.pp, maxPp = def.pp } }
    b.moves = { { id = "TACKLE", pp = data.moves.TACKLE.pp, maxPp = data.moves.TACKLE.pp } }
    local battle = Battle.new({ data = data, party = { a }, wild = b,
      random = function(n) return (roll or 16) % n end })
    return battle, a, b
  end
  local function damage(id, species, targetSpecies, item, targetItem, setup)
    local battle, a, b = fixture(id, species, targetSpecies)
    a.item, b.item = item, targetItem
    if setup then setup(battle, a, b) end
    local before = b.hp
    battle:useMove(a, b, id)
    return before - b.hp, battle, a, b
  end
  probe("Hidden Power DVs", function()
    local amount = damage("HIDDEN_POWER")
    check(amount > 4, "Hidden Power retained ROM stub power")
  end)
  probe("Flail HP band", function()
    local amount = damage("FLAIL", nil, nil, nil, nil, function(_, a) a.hp = 1 end)
    check(amount > 20, "Flail retained ROM stub power")
  end)
  probe("Present power and healing", function()
    local amount = damage("PRESENT")
    local version = require("src.core.GameVersion").get()
    if version == "gold" or version == "silver" then
      check(amount == 1, "Present did not preserve Gold and Silver register arithmetic")
    else
      check(amount > 4, "Present retained ROM stub power")
    end
    local battle, a, b = fixture("PRESENT", nil, nil, 255)
    b.hp = 1
    battle:volatile(a).xAccuracy = true
    battle:useMove(a, b, "PRESENT")
    check(b.hp == 1 + math.floor(b.maxHp / 4), "Present did not heal quarter HP")
  end)
  for _, id in ipairs({ "THUNDER", "TRI_ATTACK" }) do
    probe(id .. " paralysis", function()
      local _, _, _, b = damage(id)
      check(b.status == "paralyze", "secondary status missing")
    end)
  end
  probe("Flame Wheel self thaw", function()
    local battle, a, b = fixture("FLAME_WHEEL")
    a.status = "freeze"
    check(battle:canAct(a, "FLAME_WHEEL"), "frozen Flame Wheel was blocked")
    battle:useMove(a, b, "FLAME_WHEEL")
    check(a.status == nil, "Flame Wheel did not thaw its user")
  end)
  for _, pair in ipairs({ { "GUST", "FLY" }, { "TWISTER", "FLY" }, { "EARTHQUAKE", "DIG" } }) do
    probe(pair[1] .. " hidden damage", function()
      local normal = damage(pair[1])
      local boosted = damage(pair[1], nil, nil, nil, nil, function(battle, _, b)
        battle:volatile(b).chargeMove, battle:volatile(b).vanished = pair[2], true
      end)
      check(boosted >= normal * 2 - 1, "hidden target did not double damage")
    end)
  end
  probe("Stomp Minimize damage", function()
    local normal = damage("STOMP")
    local boosted = damage("STOMP", nil, nil, nil, nil, function(battle, _, b)
      battle:volatile(b).minimized = true
    end)
    check(boosted >= normal * 2 - 1, "Minimize did not double Stomp damage")
  end)
  probe("Jump Kick crash", function()
    local battle, a, b = fixture("JUMP_KICK", nil, nil, 255)
    local before = a.hp
    battle:useMove(a, b, "JUMP_KICK")
    check(a.hp < before and b.hp == b.maxHp, "miss did not crash")
  end)
  probe("Rapid Spin hazards", function()
    local battle, a, b = fixture("RAPID_SPIN")
    local state = battle:volatile(a)
    state.leechSeed, state.wrapCount, state.wrapMoveId = true, 3, "WRAP"
    battle.spikes.player = true
    battle:useMove(a, b, "RAPID_SPIN")
    check(not state.leechSeed and not state.wrapCount and not battle.spikes.player,
      "Rapid Spin left hazards")
  end)
  probe("Swagger", function()
    local battle, a, b = fixture("SWAGGER")
    battle:useMove(a, b, "SWAGGER")
    check(battle.stages.enemy.attack == 2 and battle:volatile(b).confuseCount,
      "Swagger did not raise Attack and confuse")
  end)
  probe("Pain Split", function()
    local battle, a, b = fixture("PAIN_SPLIT")
    a.hp, b.hp = 31, 80
    battle:useMove(a, b, "PAIN_SPLIT")
    check(a.hp == 55 and b.hp == 55, "Pain Split did not share HP")
  end)
  probe("Haze", function()
    local battle, a, b = fixture("HAZE")
    battle.stages.player.attack, battle.stages.enemy.evasion = 3, -2
    battle:useMove(a, b, "HAZE")
    check(battle.stages.player.attack == 0 and battle.stages.enemy.evasion == 0,
      "Haze did not reset both sides")
  end)
  probe("Heal Bell party", function()
    local battle, a, b = fixture("HEAL_BELL")
    local bench = Mon.new(data, "PIKACHU", 20)
    bench.status, a.status, battle.party[2] = "poison", "burn", bench
    battle:useMove(a, b, "HEAL_BELL")
    check(not a.status and not bench.status, "Heal Bell did not cure party")
  end)
  probe("Destiny Bond", function()
    local battle, a, b = fixture("DESTINY_BOND")
    battle:useMove(a, b, "DESTINY_BOND")
    battle:dealDamage(b, a, a.hp, { move = data.moves.TACKLE })
    check(b.hp == 0, "Destiny Bond did not take attacker down")
  end)
  probe("Mimic restore", function()
    local battle, a, b = fixture("MIMIC")
    battle:volatile(b).lastMove = "TACKLE"
    battle:useMove(a, b, "MIMIC")
    check(a.moves[1].id == "TACKLE" and a.moves[1].pp == 5, "Mimic did not copy")
    battle:clearVolatile(a)
    check(a.moves[1].id == "MIMIC", "Mimic did not restore")
  end)
  probe("Conversion types", function()
    local battle, a, b = fixture("CONVERSION", "PORYGON")
    a.moves[2] = { id = "EMBER", pp = data.moves.EMBER.pp }
    battle:useMove(a, b, "CONVERSION")
    check(battle:battlerTypes(a)[1] == "FIRE", "Conversion did not change type")
  end)
  probe("Conversion 2 resistance", function()
    local battle, a, b = fixture("CONVERSION2", "PORYGON")
    battle:volatile(b).lastMove = "TACKLE"
    battle:useMove(a, b, "CONVERSION2")
    local Damage = require("src.battle.gen2.Damage")
    check(Damage.typeMultiplier(data.moves.TACKLE.type, battle:battlerTypes(a),
      data.type_chart.matchups) < 10, "Conversion 2 did not resist last move")
  end)
  probe("Future Sight switch and Dark immunity", function()
    local battle, a, b = fixture("FUTURE_SIGHT", nil, "UMBREON")
    battle:useMove(a, b, "FUTURE_SIGHT")
    battle:clearVolatile(a)
    battle.player = Mon.new(data, "MEW", 50)
    for _ = 1, 3 do battle:tickFutureSight(battle.player) end
    check(b.hp < b.maxHp, "Future Sight lost pending hit or applied immunity")
  end)
  probe("Pursuit outgoing switch", function()
    local battle, a, b = fixture("PURSUIT")
    local bench = Mon.new(data, "SNORLAX", 50)
    bench.moves = { { id = "TACKLE", pp = data.moves.TACKLE.pp } }
    battle.enemyParty, battle.enemyIndex, battle.linkBattle = { b, bench }, 1, true
    battle:takeLinkTurn({ kind = "move", move = "PURSUIT" }, { kind = "switch", index = 2 })
    check(b.hp < b.maxHp and bench.hp == bench.maxHp,
      "Pursuit did not damage only outgoing mon")
    check(a.moves[1].pp == data.moves.PURSUIT.pp - 1, "Pursuit spent wrong PP")
  end)
  probe("Counter through Substitute", function()
    local battle, a, b = fixture("COUNTER")
    battle.moveRuleFirstSide = "enemy"
    battle:volatile(b).lastMove = "TACKLE"
    battle:volatile(a).substitute = 20
    battle:dealDamage(b, a, 12, { move = data.moves.TACKLE })
    battle:useMove(a, b, "COUNTER")
    check(b.hp == b.maxHp, "Counter returned damage absorbed by a Substitute")
  end)
  probe("Triple Kick random hit count", function()
    local battle, a, b = fixture("TRIPLE_KICK")
    battle:useMove(a, b, "TRIPLE_KICK")
    local hits = 0
    for _, event in ipairs(battle.events) do
      if event.kind == "damage" and event.side == "enemy" then hits = hits + 1 end
    end
    check(hits == 2, "Triple Kick did not select two hits from sample one")
  end)
  probe("Rage damage counter", function()
    local normal = damage("RAGE")
    local boosted = damage("RAGE", nil, nil, nil, nil, function(battle, a)
      battle:volatile(a).rageCount = 3
    end)
    check(boosted > normal * 3, "Rage did not multiply damage")
  end)
  probe("High critical move", function()
    local battle, a, b = fixture("SLASH", nil, nil, 32)
    battle:useMove(a, b, "SLASH")
    local critical = false
    for _, event in ipairs(battle.events) do
      if event.kind == "damage" and event.critical then critical = true end
    end
    check(critical, "Slash did not receive high critical threshold")
  end)
  for _, row in ipairs({ { "MAROWAK", "THICK_CLUB", "TACKLE" },
      { "PIKACHU", "LIGHT_BALL", "THUNDERBOLT" } }) do
    probe(row[2] .. " species boost", function()
      local normal = damage(row[3], row[1])
      local boosted = damage(row[3], row[1], nil, row[2])
      check(boosted > normal, "species held item did not increase damage")
    end)
  end
  probe("Metal Powder species defense", function()
    local normal = damage("TACKLE", nil, "DITTO")
    local reduced = damage("TACKLE", nil, "DITTO", nil, "METAL_POWDER")
    check(reduced < normal, "Metal Powder did not raise defense")
  end)
  probe("Immediate paralysis berry", function()
    local battle, a, b = fixture("TACKLE")
    b.item = "PRZCUREBERRY"
    battle:applyStatus(b, "paralyze", a)
    check(not b.status and not b.item, "paralysis berry did not cure immediately")
  end)
  probe("Lost turn cancels Fly", function()
    local battle, a = fixture("FLY")
    local state = battle:volatile(a)
    state.chargeMove, state.vanished, state.flinched = "FLY", true, true
    check(not battle:canAct(a, "FLY"), "flinch allowed action")
    check(not state.chargeMove and not state.vanished, "lost turn retained Fly")
  end)
  print(("Crystal ROM probes %d/%d passed"):format(passed, passed + failed))
  return failed == 0, passed, failed
end
