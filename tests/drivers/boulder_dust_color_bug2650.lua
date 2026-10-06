-- engine/overworld/dust_smoke.asm:21
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local OW = require("src.world.OverworldController")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local MAP = "SEAFOAM_ISLANDS_1F"
  local DIRS = { "right", "left", "down", "up" }
  local STEP = { down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }
  local PUSH = "left"

  local ok = true
  local function check(label, pass)
    print((pass and "PASS " or "FAIL ") .. label)
    if not pass then ok = false end
    return pass
  end
  local realDraw = love.graphics.draw
  local function finish()
    love.graphics.draw = realDraw
    for _, d in ipairs(DIRS) do game.input.state[d] = false end
    print(ok and "PASS boulder_dust_color_2650" or "FAIL boulder_dust_color_2650")
    love.event.quit(ok and 0 or 1)
    while true do coroutine.yield() end
  end

  local function upvalue(fn, wanted)
    for i = 1, 200 do
      local name, value = debug.getupvalue(fn, i)
      if not name then return nil end
      if name == wanted then return value end
    end
  end
  local fxDust = upvalue(OW.drawWorld, "fxDust")
  local flashImage = fxDust and upvalue(fxDust, "fieldFxFlashImage")
  if not check("fxDust has an OBP1 flash bake helper", flashImage ~= nil) then finish() end

  U.teleport(game, MAP, 17, 10, "right")
  U.wait(10)
  PaletteFX.setMode("ogred")
  local ow = game.overworld
  game.data.encounters[MAP] = nil
  local rock = ow and ow:npcAtCell(18, 10)
  if not check("boulder present at (18,10) on " .. MAP,
               rock ~= nil and rock.def.sprite == "SPRITE_BOULDER") then
    finish()
  end
  ow.strengthActive = true

  local function free(x, y)
    if not (ow.map:inBounds(x, y) and ow.map:isWalkableCell(x, y)) then return false end
    local n = ow:npcAtCell(x, y)
    return n == nil or n == rock
  end
  local s = STEP[PUSH]
  local cx, cy
  for y = 9, 40 do
    for x = 0, 60 do
      if not cx and free(x, y) and free(x + s[1], y + s[2]) and free(x + 2 * s[1], y + 2 * s[2]) then
        cx, cy = x, y
      end
    end
  end
  if not check("found an open lane for a push", cx ~= nil) then finish() end

  local function setup()
    for _, d in ipairs(DIRS) do game.input.state[d] = false end
    ow.dustAnim = nil
    ow.boulderTried = nil
    rock.cellX, rock.cellY = cx + s[1], cy + s[2]
    rock.px, rock.py = rock.cellX * 16, rock.cellY * 16
    rock.moving, rock.targetX, rock.targetY = false, nil, nil
    local p = ow.player
    p.cellX, p.cellY = cx, cy
    p.px, p.py = cx * 16, cy * 16
    p.moving, p.targetX, p.targetY = false, nil, nil
    p.facing = PUSH
    U.wait(8)
  end
  local function pushUntilDust()
    local first = true
    for _ = 1, 300 do
      if ow.dustAnim and ow.dustAnim.boulder then return ow.dustAnim end
      if first then table.insert(game.input.pressQueue, PUSH); first = false end
      game.input.state[PUSH] = true
      U.wait(1)
    end
    return nil
  end

  local rec
  love.graphics.draw = function(img, ...)
    if rec and (img == rec.flash or img == ow.smokeImg) then
      local _, _, _, a = love.graphics.getColor()
      rec.n = rec.n + 1
      if (img == rec.flash) ~= rec.faded then rec.wrongImg = rec.wrongImg + 1 end
      if a ~= 1 then rec.translucent = rec.translucent + 1 end
    end
    return realDraw(img, ...)
  end
  local function renderFrame(da, flash)
    local update = rawget(game, "update")
    game.update = function() end
    rec = { flash = flash, faded = da.faded, n = 0, wrongImg = 0, translucent = 0 }
    for _ = 1, 4000 do
      if rec.n >= 4 then break end
      coroutine.yield()
    end
    game.update = update
    local r = rec
    rec = nil
    return r
  end

  setup()
  local da = pushUntilDust()
  if not check("boulder dust starts after the push", da ~= nil) then finish() end
  game.input.state[PUSH] = false
  local flash = flashImage(game.data.field.overworldFx.smoke.path, 7)
  local frames, flashFrames, wrong, translucent, missing = 0, 0, 0, 0, 0
  while ow.dustAnim == da and frames < 60 do
    local r = renderFrame(da, flash)
    frames = frames + 1
    if r.faded then flashFrames = flashFrames + 1 end
    if r.n < 4 then missing = missing + 1 end
    wrong = wrong + r.wrongImg
    translucent = translucent + r.translucent
    U.wait(1)
  end
  print(("[driver] dust frames %d flash %d wrong %d translucent %d missing %d")
    :format(frames, flashFrames, wrong, translucent, missing))
  check("every dust frame rendered", missing == 0 and frames >= 23)
  check("OBP1 %10000000 frames use the white/shade-2 flash bake", flashFrames >= 12 and wrong == 0)
  check("dust is never drawn translucent", translucent == 0)
  U.wait(30)

  setup()
  da = pushUntilDust()
  game.input.state[PUSH] = false
  if da then
    while ow.dustAnim == da and not da.faded do U.wait(1) end
    U.still(game, DIR .. "/2650_01_dust_flash_white.png")
    while ow.dustAnim == da and da.faded do U.wait(1) end
    if ow.dustAnim == da then
      U.still(game, DIR .. "/2650_02_dust_identity_floor_ramp.png")
    end
  end
  U.wait(30)
  finish()
end
