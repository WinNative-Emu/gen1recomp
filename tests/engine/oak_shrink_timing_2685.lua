-- engine/movie/oak_speech/oak_speech.asm:112
-- home/fade.asm:24
-- data/text/text_2.asm:1742

package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local T = require("tests.harness")
local eq, check = T.eq, T.check
local OakSpeech = require("src.ui.OakSpeech")
local TextBox = require("src.render.TextBox")
local PaletteFX = require("src.render.PaletteFX")
local SpriteRenderer = require("src.render.SpriteRenderer")
local Transition = require("src.render.Transition")
local Music = require("src.core.Music")
local Sound = require("src.core.Sound")
local Version = require("src.core.GameVersion")

local origFadeOut, origPlay, origPress = Music.fadeOut, Sound.play, Sound.playPress
Music.fadeOut = function() end
Sound.play = function() end
Sound.playPress = function() end

local function stub(fields)
  local s = setmetatable(fields or {}, OakSpeech)
  return s
end

do
  local player, p1, p2 = { tag = "player" }, { tag = "p1" }, { tag = "p2" }
  local speech = stub({ playerPic = player, shrinkPic1 = p1, shrinkPic2 = p2,
                        pic = player })
  local finishes = 0
  speech.finish = function() finishes = finishes + 1 end
  speech.shrink = { frame = 0 }
  local pics, walk, fade = {}, {}, {}
  for f = 1, 200 do
    speech:update(0)
    pics[f], walk[f], fade[f] = speech.pic, speech.walkVisible, speech.fadeLevel
  end
  local function span(want)
    local first, last
    for f = 1, 200 do
      if pics[f] == want then
        first = first or f
        last = f
      end
    end
    return first, last
  end
  local _, redLast = span(player)
  local p1First, p1Last = span(p1)
  local p2First, p2Last = span(p2)
  check(redLast and redLast >= 30,
    "RedPicFront holds through ShrinkPic1's decompress (got " .. tostring(redLast) .. ")")
  eq(p1First, OakSpeech.SHRINK_PIC1_AT, "ShrinkPic1 lands on its frame")
  check(p1Last and p1First and p1Last - p1First + 1 >= 30,
    "ShrinkPic1 holds ~40 frames, not 4")
  eq(p2First, OakSpeech.SHRINK_PIC2_AT, "ShrinkPic2 lands on its frame")
  check(p2Last and p2First and p2Last - p2First + 1 >= 25,
    "ShrinkPic2 holds ~32 frames")
  eq(pics[OakSpeech.SHRINK_WALK_AT], nil, "the pic area clears")
  check(walk[OakSpeech.SHRINK_WALK_AT] and not walk[OakSpeech.SHRINK_WALK_AT - 1],
    "and the walking sprite appears on the same frame")
  eq(OakSpeech.SHRINK_FADE_AT - OakSpeech.SHRINK_WALK_AT, 50,
    "the walking sprite stands for ld c, 50")
  eq(fade[OakSpeech.SHRINK_FADE_AT - 1], nil, "no fade before GBFadeOutToWhite")
  eq(fade[OakSpeech.SHRINK_FADE_AT], 1, "FadePal6 first")
  eq(fade[OakSpeech.SHRINK_FADE_AT + 8], 2, "FadePal7 eight frames later")
  eq(fade[OakSpeech.SHRINK_FADE_AT + 16], 3, "FadePal8 eight frames after that")
  eq(OakSpeech.SHRINK_END - OakSpeech.SHRINK_FADE_AT, 24, "3 palettes x 8 frames")
  eq(finishes, 1, "finish runs once")
end

do
  local steps = {}
  for _, step in ipairs(OakSpeech.defaultSteps({})) do steps[step.id] = step end
  check(steps.legend and steps.legend.auto,
    "OakSpeechText3 ends on done, so PrintText returns without a button wait")

  Version.set("red")
  local pressed = false
  local game = { data = { text = { _OakSpeechText3 = "A\nB{DONE}" } },
                 save = { player = { name = "RED" }, options = { textSpeed = 1 } },
                 input = { wasPressed = function() return pressed end,
                           isDown = function() return false end } }
  game.stack = { push = function(s, b) s.box = b end,
                 pop = function(s) s.box = nil end }
  local advanced = 0
  local speech = stub({ game = game })
  speech.advance = function() advanced = advanced + 1 end
  speech:runStep(steps.legend)
  for _ = 1, 24 do speech:update(0) end
  local box = game.stack.box
  eq(getmetatable(box), TextBox, "the legend page is a real text box")
  local sawArrow = false
  for _ = 1, 300 do
    if not game.stack.box then break end
    box:update()
    if game.stack.box and box.done and box:arrowVisible() then sawArrow = true end
  end
  check(not sawArrow, "no blinking arrow on the last page")
  eq(game.stack.box, nil, "the box closes on its own")
  eq(advanced, 1, "and the shrink starts with no A press")
end

local origObp = SpriteRenderer.obpImage
local origDraw = love.graphics.draw

local function drawWalk(mode, fadeLevel)
  PaletteFX.mode = mode
  PaletteFX.clearSpriteRedraws()
  PaletteFX.setShadeMap(nil)
  PaletteFX.setFadeObp(nil)
  PaletteFX.setPass("ui")
  local baked = { tag = "baked" }
  local got = {}
  SpriteRenderer.obpImage = function(path, colors, group)
    got.path, got.colors, got.group = path, colors, group
    return baked
  end
  local drawn = {}
  love.graphics.draw = function(img) drawn[#drawn + 1] = img end
  local sheet = love.graphics.newImage("missing.png")
  local speech = stub({ game = {}, walkVisible = true, walkSheet = sheet,
                        walkPath = "red.png", walkDef = { image = "red.png" },
                        fadeLevel = fadeLevel })
  speech:draw()
  love.graphics.draw = origDraw
  SpriteRenderer.obpImage = origObp
  local shadeMap = PaletteFX.shadeMap()
  local redraws = #PaletteFX.uiSpriteRedraws()
  PaletteFX.setFadeObp(nil)
  PaletteFX.setShadeMap(nil)
  return got, drawn, baked, sheet, redraws, shadeMap
end

do
  Version.set("red")
  local got, drawn, baked, sheet, redraws = drawWalk("ogred")
  eq(got.path, "red.png", "OG RED bakes the RedSprite sheet")
  local want = PaletteFX.ogObjNormal()
  eq(got.colors, want, "through the boot-ROM OBJ palette at rOBP0 = $D0")
  check(drawn[1] == baked and drawn[1] ~= sheet, "and draws the baked sheet")
  eq(redraws, 1, "replayed past the red BG zone pass")

  got, drawn, baked, sheet, redraws = drawWalk("gbc")
  eq(got.colors, PaletteFX.OBP0_SHADES,
    "SGB keeps the sprite in DMG shades through the OBP0 lift")
  eq(redraws, 0, "and lets the zone palette color it")

  Version.set("blue")
  got = drawWalk("ogred")
  eq(got.colors, PaletteFX.ogObjNormal(), "OG BLUE bakes Blue's pink OBJ ramp")
  Version.set("red")
end

do
  Version.set("red")
  local raw = PaletteFX.ogObjBase()
  local got, drawn, _, _, redraws, shadeMap = drawWalk("ogred", 1)
  eq(shadeMap, Transition.shadeMapFor(0x90), "FadePal6 rBGP")
  check(got.colors and got.colors[2] == raw[1] and got.colors[3] == raw[1]
        and got.colors[4] == raw[3],
    "FadePal6 rOBP0 $80 lightens the baked sprite")
  eq(redraws, 1, "and the faded sprite still replays")
  got, drawn, _, _, redraws, shadeMap = drawWalk("ogred", 3)
  eq(shadeMap, Transition.shadeMapFor(0x00), "FadePal8 rBGP is solid white")
  check(got.colors and got.colors[4] == raw[1], "and so is the sprite")
end

PaletteFX.mode = "gbc"
Music.fadeOut, Sound.play, Sound.playPress = origFadeOut, origPlay, origPress

T.finish("oak_shrink_timing_2685")
