local U = require("tests.drivers.util")
local CardFlip = require("src.ui.gen2.CardFlip")

return function(game)
  local failed = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = failed + 1 end
    return ok
  end
  local function finish()
    love.event.quit(failed == 0 and 0 or 1)
  end
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2-card-flip-3042"
  U.wait(60)
  if not check(game.world and game.world.map and game.save and game.stack,
    "3042 Gen 2 field booted") then return finish() end
  game.world:warpToMapId("GOLDENROD_GAME_CORNER", 5, 5, "down")
  U.wait(30)
  local coins = game.save.player.coins
  game.save.player.coins = 1000
  if not check(game.world:gameCornerGame("cardflip"), "3042 Card Flip opens") then
    game.save.player.coins = coins
    return finish()
  end
  local flip = game.stack:top()
  if not check(getmetatable(flip) == CardFlip, "3042 actual Card Flip screen is active") then
    game.save.player.coins = coins
    return finish()
  end
  local gfx = game.data.gen2MenuGfx.cardFlip
  check(#gfx.faceDown == 30 and #gfx.faceUp == 30 and #gfx.deck == 48,
    "3042 all 108 cached face and deck bytes are present")
  U.tap(game, "a")
  U.tap(game, "a")
  if not check(flip.phase == "bet", "3042 wager phase accepts input") then
    game.save.player.coins = coins
    return finish()
  end
  U.tap(game, "right")
  U.tap(game, "up")
  U.tap(game, "up")
  local x, y, w, h = flip:cursorBounds()
  check(flip.cursorX == 3 and flip.cursorY == 0 and x == 96 and y == 0 and w == 32 and h == 8,
    "3042 Jigglypuff enters centered left Pokemon pair")
  flip.betBlink = 0
  check(U.still(game, dir .. "/3042_jigglypuff_pair_center.png"), "3042 left pair screenshot written")
  U.tap(game, "down")
  U.tap(game, "right")
  U.tap(game, "right")
  U.tap(game, "up")
  x, y, w, h = flip:cursorBounds()
  check(flip.cursorX == 5 and flip.cursorY == 0 and x == 128 and y == 0 and w == 32 and h == 8,
    "3042 Oddish enters centered right Pokemon pair")
  flip.betBlink = 0
  check(U.still(game, dir .. "/3042_oddish_pair_center.png"), "3042 right pair screenshot written")

  flip.deck = { 0, 4, 1, 5, 2, 6, 3, 7 }
  for card = 8, 23 do flip.deck[#flip.deck + 1] = card end
  for mon = 0, 3 do
    if mon > 0 then
      U.tap(game, "a")
      U.tap(game, "a")
      U.tap(game, "a")
    end
    flip.which = 1
    flip.cursorX, flip.cursorY = mon + 2, 3
    U.tap(game, "a")
    U.wait(170)
    check(flip.phase == "result" and flip.faceUp == CardFlip.card(1, mon),
      "3042 level 2 " .. CardFlip.MONS[mon] .. " face-up result")
    check(U.still(game, dir .. "/3042_level2_" .. CardFlip.MONS[mon]:lower() .. ".png"),
      "3042 " .. CardFlip.MONS[mon] .. " face screenshot written")
  end
  U.tap(game, "a")
  U.tap(game, "a")
  U.tap(game, "a")
  flip.cursorX, flip.cursorY = 5, 3
  check(flip.discarded[7] and flip.phase == "bet", "3042 discarded Oddish cell remains reachable")
  flip.betBlink = 0
  check(U.still(game, dir .. "/3042_discarded_wager_allowed.png"), "3042 discarded wager screenshot written")
  U.tap(game, "a")
  check(flip.phase == "flipping" and flip.payoutLeft == 0,
    "3042 discarded exact-card wager is accepted and loses")
  flip:quit()
  game.save.player.coins = coins
  finish()
end
