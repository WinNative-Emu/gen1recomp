-- engine/events/pokedex_rating.asm:33
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TextBox = require("src.render.TextBox")
  local Sound = require("src.core.Sound")
  local Timing = require("src.core.Timing")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"

  local ok = true
  local function check(label, pass)
    print((pass and "PASS " or "FAIL ") .. label)
    if not pass then ok = false end
    return pass
  end
  local realPlay = Sound.play
  local plays = {}
  Sound.play = function(data, name, ...)
    plays[#plays + 1] = name
    return realPlay(data, name, ...)
  end
  local function finish()
    Sound.play = realPlay
    print(ok and "PASS dex_rating_complete_2674" or "FAIL dex_rating_complete_2674")
    love.event.quit(ok and 0 or 1)
    while true do coroutine.yield() end
  end

  U.teleport(game, "OAKS_LAB", 5, 3, "up")
  U.wait(10)
  local ow = game.overworld
  if not check("overworld is up", ow ~= nil) then finish() end
  local full = {}
  for i = 1, 151 do full[i] = true end
  game.save.pokedex = { seen = full, owned = full }
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1

  local closed = false
  ow:dexRating(function() closed = true end)
  local box = game.stack:top()
  if not check("rating box pushed", getmetatable(box) == TextBox) then finish() end

  local SPACE = 0x7F
  local target
  for _ = 1, 6000 do
    U.wait(1)
    if box.waiting and box.contAdvance and #box.shown == 2 and #box.shown[2] == 18 then
      target = true
      break
    end
    if box.waiting and not box.contAdvance and (box.preWait or 0) == 0 then
      U.tap(game, "a")
    end
    if box.done then break end
  end
  if not check("reached the cont wait under an 18-tile line", target) then finish() end
  check("the cont line is the Own150To151 text",
    (box.pages[box.pageIndex][box.lineIndex] or ""):find("complete", 1, true) ~= nil)
  check("arrow is up over cell (18,16)", box:arrowVisible() and box.fixedGen1Rows)
  local early = false
  for _, name in ipairs(plays) do
    if name == "Get_Item2" or name == "Pokedex_Rating" then early = true end
  end
  check("no rating jingle yet", not early)
  for _ = 1, 120 do
    if box.blink % 60 < 30 then break end
    U.wait(1)
  end
  U.still(game, DIR .. "/2674_01_arrow_replaces_bang.png")

  for _ = 1, Timing.TEXT_PRE_ADVANCE + 2 do U.wait(1) end
  U.tap(game, "a")
  U.wait(2)
  check("scrolled line carries a space in column 18",
    box.shown[1] and box.shown[1][18] == SPACE)

  for _ = 1, 6000 do
    if box.done and not box.auto then break end
    U.wait(1)
  end
  check("box finished typing and the jingle wait is over", box.done and not box.auto)
  local rated
  for _, name in ipairs(plays) do
    if name == "Get_Item2" then rated = true end
    if name == "Pokedex_Rating" then rated = false break end
  end
  check("151 owned plays SFX_GET_ITEM_2", rated == true)
  for _ = 1, 120 do
    if box.blink % 60 < 30 then break end
    U.wait(1)
  end
  U.still(game, DIR .. "/2674_02_complete_without_bang.png")

  U.tap(game, "a")
  U.wait(5)
  check("A closes the rating", closed)
  finish()
end
