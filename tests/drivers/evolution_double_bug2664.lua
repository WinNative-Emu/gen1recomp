-- engine/pokemon/evos_moves.asm:156
-- engine/battle/end_of_battle.asm:42
--   POKEPORT_DRIVER=tests/drivers/evolution_double_bug2664.lua POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Growth = require("src.pokemon.Growth")
  local BattleState = require("src.battle.BattleState")
  local Music = require("src.core.Music")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/evo2664"

  local failed = false
  local function check(label, ok)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = true end
    return ok
  end

  local ok, err = pcall(function()
    game.save.options = game.save.options or {}
    game.save.options.textSpeed = 1
    local pin = function(_, b) return b end
    local dratini = Pokemon.new(game.data, "DRATINI", 29, pin)
    local def = game.data.pokemon.DRATINI
    dratini.exp = Growth.expForLevel(def.growthRate, 30, game.data.growth_rates) - 1
    dratini.moves = { { id = dratini.moves[1].id, pp = dratini.moves[1].pp } }
    local tentacool = Pokemon.new(game.data, "TENTACOOL", 30, pin)
    tentacool.moves = { tentacool.moves[1] }
    game.save.party = { dratini, tentacool }

    U.teleport(game, "ROUTE_1", 5, 5, "down")
    local ow = game.overworld

    local restores = 0
    local realRestore = Music.restoreMap
    Music.restoreMap = function(...)
      restores = restores + 1
      return realRestore(...)
    end

    local battle = BattleState.newWild(game, "RATTATA", 2)
    battle.rng = function(a, _) return a end
    battle.enemy.mon.hp = 1
    battle.enemy.mon.stats.speed = 1
    battle.leveledUp = { [tentacool] = true }
    ow:pushBattle(battle)

    for _ = 1, 400 do
      if battle.phase == "menu" then break end
      U.tap(game, "a")
      U.wait(3)
    end
    if not check("reached the FIGHT menu", battle.phase == "menu") then return end
    U.tap(game, "a")
    for _ = 1, 60 do
      if battle.phase == "moveSelect" then break end
      U.wait(1)
    end
    U.tap(game, "a")

    local function inStack(state)
      for i, s in ipairs(game.stack.states) do
        if s == state then return i end
      end
    end

    local firstIntro, secondIntro, shot = nil, nil, false
    local belowSecond, restoresAtSecond, baseAtSecond, battleAtSecond
    for _ = 1, 20000 do
      local top = game.stack:top()
      if top and top.evoIntro then
        if not firstIntro then
          firstIntro = top
        elseif top ~= firstIntro and not secondIntro then
          secondIntro = top
          local i = inStack(top)
          belowSecond = game.stack.states[i - 1]
          restoresAtSecond = restores
          baseAtSecond = game.stack:visibleBase()
          battleAtSecond = inStack(battle)
        end
      end
      if secondIntro and not shot then
        local i = inStack(secondIntro)
        if i and i == #game.stack.states - 1 then
          shot = U.still(game, DIR .. "/2664_01_second_intro_on_blank.png")
        end
      end
      if not inStack(battle) then break end
      U.tap(game, "a")
      U.wait(2)
    end

    check("first mon evolved", dratini.species == "DRAGONAIR")
    check("second mon evolved", tentacool.species == "TENTACRUEL")
    if check("second IsEvolvingText box opened", secondIntro ~= nil) then
      check("second intro sits on an opaque blank screen",
        belowSecond ~= nil and belowSecond.evoClear == true
        and belowSecond.isOpaque == true)
      check("battle screen is not drawn under the second intro",
        battleAtSecond ~= nil and baseAtSecond > battleAtSecond)
      check("no map music between the two evolutions", restoresAtSecond == 0)
    end
    check("shot of the second intro captured", shot)
    check("battle closed after the evolutions", inStack(battle) == nil)
    local stray = false
    for _, s in ipairs(game.stack.states) do
      if s.evoClear or s.evoIntro then stray = true end
    end
    check("no evolution layers left on the stack", not stray)
    Music.restoreMap = realRestore
  end)
  if not ok then
    print("FAIL driver error: " .. tostring(err))
    failed = true
  end
  love.event.quit(failed and 1 or 0)
end
