return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Oak = require("src.ui.OakSpeech")
  local TB = require("src.render.TextBox")
  local PF = require("src.render.PaletteFX")
  local dir = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local failed = false
  local function check(label, ok)
    print((ok and "PASS " or "FAIL ") .. label)
    failed = failed or not ok
    return ok
  end
  local origMode = PF.mode

  while game.stack:top() do game.stack:pop() end
  game.save.options.textSpeed = 1
  local speech = Oak.new(game, function() end)
  game.stack:push(speech)
  local legend
  for i, step in ipairs(speech.steps) do if step.id == "legend" then legend = i end end

  for _ = 1, 4000 do
    if speech.step == legend then break end
    U.tap(game, "a")
    U.wait(2)
  end
  check("reached legend step", speech.step == legend)

  local arrowOnLast, aPresses = false, 0
  for _ = 1, 2000 do
    if speech.shrink then break end
    local top = game.stack:top()
    if getmetatable(top) == TB then
      if top.waiting then
        U.tap(game, "a")
        aPresses = aPresses + 1
      else
        if top.done and top:arrowVisible() then arrowOnLast = true end
        U.wait(1)
      end
    else
      U.wait(1)
    end
  end
  check("legend last page has no arrow", not arrowOnLast)
  check("legend closes into the shrink with no A press", speech.shrink ~= nil)

  local firstSeen = {}
  local function tag()
    if speech.pic == speech.playerPic then return "red" end
    if speech.pic == speech.shrinkPic1 then return "p1" end
    if speech.pic == speech.shrinkPic2 then return "p2" end
    if speech.walkVisible then return "walk" end
    return "none"
  end
  local shots = {}
  local replayOg, bakedOg = false, false
  for _ = 1, 400 do
    local s = speech.shrink
    if not s then break end
    local f = s.frame
    local t = tag()
    if f > 0 and not firstSeen[t] then firstSeen[t] = f end
    if f == Oak.SHRINK_PIC1_AT + 20 and not shots.p1 then
      shots.p1 = U.still(game, dir .. "/2685_01_shrinkpic1_held.png")
    elseif f == Oak.SHRINK_PIC2_AT + 16 and not shots.p2 then
      shots.p2 = U.still(game, dir .. "/2685_02_shrinkpic2_held.png")
    elseif f == Oak.SHRINK_WALK_AT + 10 and not shots.walk then
      shots.walk = U.still(game, dir .. "/2685_03_walk_sprite_" .. origMode .. ".png")
      PF.setMode("ogred")
      U.wait(1)
    elseif f == Oak.SHRINK_WALK_AT + 20 and not shots.walkOg then
      shots.walkOg = U.still(game, dir .. "/2685_04_walk_sprite_ogred_green.png")
      local r = PF.uiSpriteRedraws()
      replayOg = r[1] ~= nil
      bakedOg = r[1] ~= nil and r[1].image ~= speech.walkSheet
    elseif f == Oak.SHRINK_FADE_AT + 10 and not shots.fade then
      shots.fade = U.still(game, dir .. "/2685_05_fade_ogred_sprite_lightened.png")
    else
      U.wait(1)
    end
  end
  PF.setMode(origMode)

  U.log("first frames red/p1/p2/walk:", tostring(firstSeen.red), tostring(firstSeen.p1),
        tostring(firstSeen.p2), tostring(firstSeen.walk))
  check("RedPicFront held >= 30 frames", (firstSeen.p1 or 0) - 1 >= 30)
  check("ShrinkPic1 held >= 30 frames",
    firstSeen.p1 and firstSeen.p2 and firstSeen.p2 - firstSeen.p1 >= 30)
  check("ShrinkPic2 held >= 25 frames",
    firstSeen.p2 and firstSeen.walk and firstSeen.walk - firstSeen.p2 >= 25)
  check("OG RED walk sprite is OBJ-baked and replayed", replayOg and bakedOg)
  check("shrink finished", speech.shrink == nil)
  check("shots written", shots.p1 and shots.p2 and shots.walk and shots.walkOg and shots.fade)
  love.event.quit(failed and 1 or 0)
end
