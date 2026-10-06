-- scripts/AgathasRoom.asm:2
-- scripts/AgathasRoom.asm:108
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")
  local CLOSED, OPEN = 0x3b, 0x0e
  local ok = true

  local function check(label, cond)
    print((cond and "PASS " or "FAIL ") .. label)
    if not cond then ok = false end
    return cond
  end

  local function finish()
    U.wait(5)
    love.event.quit(ok and 0 or 1)
    while true do coroutine.yield() end
  end

  local mon = Pokemon.new(game.data, "MEWTWO", 100)
  mon.moves = { { id = "PSYCHIC_M", pp = 63 } }
  game.save.party = { mon }
  game.save.flags.EVENT_AUTOWALKED_INTO_AGATHAS_ROOM = true
  game.save.flags.EVENT_BEAT_AGATHAS_ROOM_TRAINER_0 = nil
  game.save.defeatedTrainers = game.save.defeatedTrainers or {}
  game.save.defeatedTrainers["AGATHAS_ROOM_obj_1"] = nil

  U.teleport(game, "AGATHAS_ROOM", 5, 3, "up")
  U.wait(30)
  local ow = game.overworld
  if not check("2658 overworld up in AGATHAS_ROOM", ow and ow.map.id == "AGATHAS_ROOM") then
    return finish()
  end
  check("2658 exit shut before the fight", ow.map:blockAt(2, 0) == CLOSED)

  local battle
  for _ = 1, 600 do
    local top = game.stack:top()
    if top ~= ow and top and top.enemy then battle = top break end
    U.tap(game, "a")
    U.wait(2)
  end
  if not check("2658 talking to Agatha starts the battle", battle ~= nil) then
    return finish()
  end

  for _ = 1, 20000 do
    if game.stack:top() ~= battle then
      local inStack = false
      for _, s in ipairs(game.stack.states or {}) do
        if s == battle then inStack = true break end
      end
      if not inStack then break end
    end
    if battle.enemy and battle.enemy.mon and (battle.enemy.mon.hp or 0) > 1 then
      battle.enemy.mon.hp = 1
    end
    U.tap(game, "a")
    U.wait(2)
  end
  local box
  for _ = 1, 3000 do
    local top = game.stack:top()
    if top ~= battle and getmetatable(top) == TextBox then box = top break end
    U.wait(1)
  end
  if not check("2658 after-battle text box shows in the overworld", box ~= nil) then
    return finish()
  end
  U.wait(240)
  check("2658 Agatha beaten", game.save.flags.EVENT_BEAT_AGATHAS_ROOM_TRAINER_0 and true or false)
  check("2658 exit still shut while after-battle text is up",
        ow.map:blockAt(2, 0) == CLOSED)
  U.still(game, DIR .. "/2658_01_after_text_exit_shut.png")

  for _ = 1, 600 do
    if game.stack:top() == ow then break end
    U.tap(game, "a")
    U.wait(4)
  end
  check("2658 after-battle text closed", game.stack:top() == ow)
  U.wait(10)
  check("2658 exit opens after the text closes", ow.map:blockAt(2, 0) == OPEN)
  U.still(game, DIR .. "/2658_02_exit_open_after_text.png")

  finish()
end
