-- scripts/OaksLab.asm:918
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TextBox = require("src.render.TextBox")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/shots"

  local MAP = "OAKS_LAB"
  local OWN = "OAKSLAB_SQUIRTLE_POKE_BALL"
  local RIVAL = "OAKSLAB_BULBASAUR_POKE_BALL"
  local LIMIT = 120000
  local failed = false

  local function check(label, ok)
    if ok then print("PASS " .. label) else print("FAIL " .. label) failed = true end
    return ok
  end

  local function finish()
    print(failed and "FAIL oak_starter_ball_hide_bug2686"
                 or "PASS oak_starter_ball_hide_bug2686")
    love.event.quit(failed and 1 or 0)
    while true do coroutine.yield() end
  end

  local function ballShown(name)
    local ow = game.overworld
    for _, n in ipairs(ow and ow.npcs or {}) do
      if n.def and n.def.name == name then return true end
    end
    return false
  end

  local function boxText()
    local states = game.stack.states or {}
    for i = #states, 1, -1 do
      local s = states[i]
      if getmetatable(s) == TextBox then
        local out = {}
        for _, page in ipairs(s.pages or {}) do
          for _, line in ipairs(page) do out[#out + 1] = line end
        end
        return table.concat(out, " "):lower(), s
      end
    end
    return "", nil
  end

  local function scriptRunning()
    local ow = game.overworld
    return ow and ow.runner and ow.runner:isRunning()
  end

  local save = game.save
  save.player.name = (save.player.name and save.player.name ~= "")
    and save.player.name or "RED"
  save.party = {}
  save.flags.EVENT_FOLLOWED_OAK_INTO_LAB = true
  save.flags.EVENT_FOLLOWED_OAK_INTO_LAB_2 = true
  save.flags.EVENT_GOT_STARTER = nil
  save.objectToggles = save.objectToggles or {}
  save.objectToggles[MAP] = save.objectToggles[MAP] or {}
  local tog = save.objectToggles[MAP]
  tog.OAKSLAB_OAK1 = true
  tog.OAKSLAB_OAK2 = false
  tog.OAKSLAB_RIVAL = true
  tog.OAKSLAB_CHARMANDER_POKE_BALL = true
  tog.OAKSLAB_SQUIRTLE_POKE_BALL = true
  tog.OAKSLAB_BULBASAUR_POKE_BALL = true

  U.teleport(game, MAP, 7, 4, "up")
  U.wait(20)
  check("squirtle_ball_on_table_before_pick", ballShown(OWN))
  check("rival_counter_ball_on_table_before_pick", ballShown(RIVAL))

  U.tap(game, "a")
  U.wait(10)

  local sawEnergetic = false
  for _ = 1, LIMIT do
    local txt = boxText()
    if txt:find("energetic", 1, true) then sawEnergetic = true break end
    if U.frame() % 6 == 0 then U.tap(game, "a") else U.wait(1) end
  end
  check("energetic_line_reached", sawEnergetic)
  if not sawEnergetic then finish() end
  check("ball_gone_when_energetic_line_opens", not ballShown(OWN))
  check("rival_ball_still_there_on_energetic_line", ballShown(RIVAL))
  check("no_starter_yet_on_energetic_line", #save.party == 0)
  U.wait(90)
  U.shot(game, DIR .. "/2686_01_energetic_line_ball_gone.png")

  local sawReceived = false
  for _ = 1, LIMIT do
    local txt = boxText()
    if txt:find("received", 1, true) then sawReceived = true break end
    if U.frame() % 6 == 0 then U.tap(game, "a") else U.wait(1) end
  end
  check("received_line_reached", sawReceived)
  check("ball_gone_on_received_line", not ballShown(OWN))
  U.wait(120)
  U.shot(game, DIR .. "/2686_02_received_line_ball_gone.png")

  local sawNick, nickBox = false, nil
  for _ = 1, LIMIT do
    local txt, box = boxText()
    if txt:find("nickname", 1, true) then sawNick, nickBox = true, box break end
    if U.frame() % 6 == 0 then U.tap(game, "a") else U.wait(1) end
  end
  check("nickname_prompt_reached", sawNick)
  if not sawNick then finish() end
  check("ball_gone_on_nickname_prompt", not ballShown(OWN))
  check("rival_ball_still_there_on_nickname_prompt", ballShown(RIVAL))
  for _ = 1, LIMIT do
    if nickBox.choicePushed then break end
    U.wait(1)
  end
  U.wait(20)
  U.shot(game, DIR .. "/2686_03_nickname_prompt_ball_gone.png")
  for _ = 1, LIMIT do
    local _, box = boxText()
    if box ~= nickBox then break end
    if U.frame() % 6 == 0 then U.tap(game, "b") else U.wait(1) end
  end

  for _ = 1, LIMIT do
    if not scriptRunning() and game.stack:top() == game.overworld then break end
    local _, box = boxText()
    if box and box.done and not box.choice then U.tap(game, "a") else U.wait(1) end
  end
  U.wait(20)
  check("script_finished", not scriptRunning())
  check("player_got_squirtle",
    save.party[1] ~= nil and save.party[1].species == "SQUIRTLE")
  check("own_ball_still_hidden_after_pick", not ballShown(OWN))
  check("rival_took_bulbasaur_ball", not ballShown(RIVAL))
  check("charmander_ball_left_on_table",
    ballShown("OAKSLAB_CHARMANDER_POKE_BALL"))
  U.shot(game, DIR .. "/2686_04_after_rival_pick.png")
  finish()
end
