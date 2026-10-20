local U = require("tests.drivers.util")

local Mon = require("src.battle.gen2.Mon")

local function battleScreen(game)
  for _ = 1, 900 do
    local top = game.stack:top()
    if top and top.battle then return top end
    U.wait(1)
  end
  error("battle screen never came up")
end

local function atMenu(screen)
  return screen.phase == "menu" and #screen.queue == 0 and not screen.anim
end

local function drain(game, screen, frames)
  for _ = 1, (frames or 400) do
    if atMenu(screen) then return true end
    U.tap(game, "a")
    U.wait(3)
  end
  return false
end

local function giveMoves(mon, game, moves)
  mon.moves = {}
  for i, id in ipairs(moves) do
    local def = assert(game.data.moves[id], id .. " is not in moves.lua")
    mon.moves[i] = { id = id, pp = def.pp, maxPp = def.pp }
  end
  return mon
end

local function newWild(game, species, level, moves)
  return giveMoves(Mon.new(game.data, species, level), game, moves)
end

-- engine/items/item_effects.asm:382
-- engine/battle/core.asm:8268
local function catchAndLeave(game, screen)
  local partySize = #game.save.party
  screen:useItem("MASTER_BALL")
  for _ = 1, 400 do
    if game.save.party[partySize + 1] then break end
    U.tap(game, "a")
    U.wait(3)
  end
  local done = false
  for _ = 1, 900 do
    if screen.phase == "done" then done = true break end
    U.tap(game, "b")
    U.wait(3)
  end
  for _ = 1, 300 do
    local top = game.stack:top()
    if not (top and top.battle) then break end
    U.wait(1)
  end
  U.wait(30)
  return done, game.save.party[partySize + 1]
end

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-rules"
  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")
  local failures = {}
  local function check(ok, what)
    print((ok and "[ok] " or "[FAIL] ") .. what)
    if not ok then failures[#failures + 1] = what end
  end
  local function finish()
    if #failures > 0 then
      for _, what in ipairs(failures) do print("[FAIL] " .. what) end
      print(("[driver] FAIL %d battle-rule checks failed"):format(#failures))
    else
      print("[driver] PASS all battle-rule checks passed")
    end
    print("[driver] shots in " .. out)
    U.wait(2)
    love.event.quit(#failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  -- engine/battle/move_effects/transform.asm:1
  local player = Mon.new(game.data, "SNORLAX", 30)
  giveMoves(player, game, { "GROWL" })
  game.save.party = { player }
  game.save.inventory = { MASTER_BALL = 5 }
  local ditto = newWild(game, "DITTO", 20, { "TRANSFORM" })
  assert(world:startBattle({ wild = ditto }), "startBattle failed")
  local screen = battleScreen(game)
  drain(game, screen, 200)
  U.shot(game, out .. "/00-menu.png")
  print("[driver] enemy shown as " .. tostring(screen:activeMon("enemy")
    and screen:activeMon("enemy").species))

  screen:submit({ kind = "move", move = "GROWL" })
  local sawTransformEvent = false
  for _, event in ipairs(screen.queue) do
    if event.kind == "transform" then sawTransformEvent = true end
  end
  U.wait(1)
  U.shot(game, out .. "/01-submitted.png")
  local shownAtSubmit = screen:activeMon("enemy")
  print("[driver] pic timing: at submit the enemy draws as "
    .. tostring(shownAtSubmit and shownAtSubmit.species)
    .. " (01-submitted.png)")
  check(sawTransformEvent,
    "the round carries a `transform` event for the screen to swap its pic on")

  U.wait(120)
  U.shot(game, out .. "/01z-before-transform-line.png")
  print("[driver] with the box still reading "
    .. tostring(screen.message and screen.message:gsub("\n", " / "))
    .. " the enemy pic is drawn from "
    .. tostring(screen:activeMon("enemy") and screen:activeMon("enemy").species)
    .. " (01z-before-transform-line.png)")

  for step = 1, 6 do
    if atMenu(screen) then break end
    U.tap(game, "a")
    U.wait(24)
    U.shot(game, out .. ("/01%s-step.png"):format(string.char(96 + step)))
    print("[driver] step " .. step .. " message: "
      .. tostring(screen.message and screen.message:gsub("\n", " / ")))
  end
  check(drain(game, screen, 400) and not screen.battle.over,
    "one round later the battle is back at the move menu")
  U.shot(game, out .. "/02-transformed.png")
  local shownAfter = screen:activeMon("enemy")
  print("[driver] pic timing: after TRANSFORM's own line it draws as "
    .. tostring(shownAfter and shownAfter.species) .. " (02-transformed.png)")
  check(ditto.species == "SNORLAX",
    "the rules half lands at once: the battler IS the copy for the rest of "
      .. "the round")
  check(screen.battle:volatile(ditto).preTransform
    and screen.battle:volatile(ditto).preTransform.species == "DITTO",
    "and the record it was is kept for the reload")

  local done, caught = catchAndLeave(game, screen)
  U.shot(game, out .. "/03-caught.png")
  check(caught ~= nil, "the DITTO was caught into the party")
  print(("[driver] battle finished=%s phase=%s"):format(tostring(done),
    tostring(screen.phase)))
  check(done, "the battle screen reached ExitBattle")
  if caught then
    print("[driver] caught record: species=" .. tostring(caught.species)
      .. " move1=" .. tostring(caught.moves and caught.moves[1]
        and caught.moves[1].id))
    check(caught.species == "DITTO",
      "the caught record is the real DITTO (was "
        .. tostring(caught.species) .. ")")
    check(caught.moves and caught.moves[1]
      and caught.moves[1].id == "TRANSFORM",
      "and it kept its own move list")
  end

  -- engine/battle/effect_commands.asm:5670
  local struggler = Mon.new(game.data, "RATTATA", 30)
  giveMoves(struggler, game, { "TACKLE" })
  struggler.moves[1].pp = 0
  game.save.party = { struggler }
  local target = newWild(game, "SNORLAX", 30, { "SPLASH" })
  assert(world:startBattle({ wild = target }), "startBattle failed")
  screen = battleScreen(game)
  drain(game, screen, 200)
  local foeBefore, mineBefore = target.hp, struggler.hp
  screen:submit({ kind = "move", move = "TACKLE" })
  drain(game, screen, 400)
  U.shot(game, out .. "/04-struggle.png")
  local dealt = foeBefore - target.hp
  local recoil = mineBefore - struggler.hp
  print(("[driver] STRUGGLE dealt %d and recoiled %d"):format(dealt, recoil))
  check(dealt > 5, "STRUGGLE deals its 50 power, not chip damage")
  check(recoil == math.max(1, math.floor(dealt / 4)),
    "and the user takes a quarter of it back")
  check(catchAndLeave(game, screen), "the STRUGGLE battle reached ExitBattle")

  -- engine/battle/move_effects/magnitude.asm:1
  -- engine/battle/move_effects/spite.asm:1
  local caster = Mon.new(game.data, "GASTLY", 20)
  giveMoves(caster, game, { "MAGNITUDE", "DREAM_EATER", "SPITE" })
  caster.hp = math.max(1, caster.hp - 10)
  game.save.party = { caster }
  local dummy = newWild(game, "CHANSEY", 50, { "TACKLE" })
  assert(world:startBattle({ wild = dummy }), "startBattle failed")
  screen = battleScreen(game)
  drain(game, screen, 200)

  local before = dummy.hp
  screen:submit({ kind = "move", move = "MAGNITUDE" })
  local sawMagnitude = false
  for _, event in ipairs(screen.queue) do
    if event.text and event.text:match("^Magnitude %d") then
      sawMagnitude = true
    end
  end
  drain(game, screen, 400)
  U.shot(game, out .. "/05-magnitude.png")
  check(sawMagnitude, "MAGNITUDE announces its rolled magnitude")
  check(before - dummy.hp > 1,
    "and hits for the rolled power, not the ROM's stored 1 (dealt "
      .. tostring(before - dummy.hp) .. ")")

  local hpBefore, mineHp = dummy.hp, caster.hp
  screen:submit({ kind = "move", move = "DREAM_EATER" })
  drain(game, screen, 400)
  check(dummy.hp == hpBefore,
    "DREAM EATER misses an awake target outright")
  check(caster.hp <= mineHp, "and saps nothing from it")

  local ppBefore = dummy.moves[1].pp
  check(ppBefore < dummy.moves[1].maxPp and not screen.battle.over,
    "the foe has a last-used move for SPITE to drain")
  screen:submit({ kind = "move", move = "SPITE" })
  drain(game, screen, 400)
  U.shot(game, out .. "/06-spite.png")
  print(("[driver] SPITE took the foe's TACKLE from %d to %d PP")
    :format(ppBefore, dummy.moves[1].pp))
  check(dummy.moves[1].pp < ppBefore - 1,
    "SPITE drains 2-5 PP off the move the target last used")
  check(catchAndLeave(game, screen), "the SPITE battle reached ExitBattle")

  -- engine/battle/core.asm:3801
  local runner = Mon.new(game.data, "RATTATA", 30)
  giveMoves(runner, game, { "TACKLE" })
  game.save.party = { runner }
  local foe = Mon.new(game.data, "GEODUDE", 30)
  giveMoves(foe, game, { "TACKLE" })
  assert(world:startBattle({ trainer = { class = "YOUNGSTER",
    name = "JOEY", party = { foe } } }), "trainer startBattle failed")
  screen = battleScreen(game)
  drain(game, screen, 300)
  local hpAtRun = runner.hp
  local turnAtRun = screen.battle.turn
  screen:submit({ kind = "run" })
  drain(game, screen, 300)
  U.shot(game, out .. "/07-run-refused.png")
  check(runner.hp == hpAtRun,
    "a refused RUN costs no HP: the trainer never got a swing")
  check(screen.battle.turn == turnAtRun + 1 and not screen.battle.over,
    "and the battle is still running")
  check(foe.hp == foe.maxHp, "nor did anything happen to the foe")

  finish()
end
