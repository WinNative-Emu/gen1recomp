-- Driver: the Oak speech from NEW GAME through the shrink-away beat
-- (engine/movie/oak_speech/oak_speech.asm .next): RedPicFront ->
-- ShrinkPic1 -> ShrinkPic2 -> walking sprite -> fade to white ->
-- Pallet Town.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Oak = require("src.ui.OakSpeech")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local failed = false
  local function check(label, ok)
    print((ok and "PASS " or "FAIL ") .. label)
    failed = failed or not ok
    return ok
  end

  U.wait(5)
  U.tap(game, "start")
  U.wait(10)
  local title = game.stack:top()
  for _ = 1, 60 do
    U.tap(game, "a")
    U.wait(5)
    if game.stack:top() ~= title then break end
  end
  local ok, saved = pcall(function()
    return require("src.core.SaveData").load() ~= nil
  end)
  if ok and saved then U.tap(game, "down") U.wait(3) end
  U.tap(game, "a")
  U.wait(10)

  local function top() return game.stack:top() end
  local function speechState()
    for _, s in ipairs(game.stack.states or {}) do
      if getmetatable(s) == Oak then return s end
    end
  end
  local s
  for _ = 1, 4000 do
    s = speechState()
    if s and s.shrink then break end
    U.tap(game, "a")
    U.wait(2)
  end
  check("shrink beat entered", s ~= nil and s.shrink ~= nil)
  if not (s and s.shrink) then love.event.quit(1) return end

  local function frameNow()
    return (s.shrink and s.shrink.frame) or -1
  end
  local function at(target, name, wantPic, wantWalk)
    for _ = 1, 400 do
      if not s.shrink or s.shrink.frame >= target then break end
      U.wait(1)
    end
    local f = frameNow()
    local shot = U.still(game, DIR .. "/" .. name .. ".png")
    U.log(name .. " frame:", f)
    check(name .. " lands at frame " .. target .. " (got " .. f .. ")", f == target)
    check(name .. " shows the expected beat", s.pic == wantPic and (s.walkVisible or false) == wantWalk)
    check(name .. " shot reached disk", shot)
  end

  at(Oak.SHRINK_PIC1_AT - 1, "shrink_1_redpic", s.playerPic, false)
  at(Oak.SHRINK_PIC1_AT + 2, "shrink_2_pic1", s.shrinkPic1, false)
  at(Oak.SHRINK_PIC2_AT + 2, "shrink_3_pic2", s.shrinkPic2, false)
  at(Oak.SHRINK_WALK_AT + 2, "shrink_4_sprite", nil, true)
  at(Oak.SHRINK_FADE_AT + 2, "shrink_5_fade", nil, true)
  check("shrink_5_fade is mid fade", s.fadeLevel ~= nil)

  for _ = 1, 400 do
    if top() == game.overworld and game.overworld then break end
    U.wait(1)
  end
  U.wait(10)
  local shot = U.shot(game, DIR .. "/shrink_6_overworld.png")
  U.log("after speech: top==overworld:", tostring(top() == game.overworld),
        "map:", game.overworld and game.overworld.map
                and game.overworld.map.id or "?")
  check("speech hands off to the overworld", game.overworld ~= nil and top() == game.overworld)
  check("shrink_6_overworld shot reached disk", shot)
  love.event.quit(failed and 1 or 0)
end
