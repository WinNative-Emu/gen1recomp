-- engine/tilesets/timeofday_pals.asm:65-91
local U = require("tests.drivers.util")
local FaithfulRes = require("src.core.FaithfulRes")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2-faithful-fade-2991"
  local fails = 0
  local function ok(cond, msg)
    if not cond then fails = fails + 1 end
    print("[2991] " .. (cond and "PASS " or "FAIL ") .. msg)
    return cond
  end
  if not ok(os.getenv("POKEPORT_FORCE_MOBILE") == "1",
      "POKEPORT_FORCE_MOBILE=1 is set") then
    love.event.quit(1)
    return
  end

  local function loadShot(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    local okImg, img = pcall(function()
      return love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
    end)
    return okImg and img or nil
  end
  local function px(img, x, y)
    local r, g, b = img:getPixel(math.floor(x), math.floor(y))
    return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
      math.floor(b * 255 + 0.5)
  end
  local function same(img, ax, ay, bx, by)
    local r1, g1, b1 = px(img, ax, ay)
    local r2, g2, b2 = px(img, bx, by)
    return r1 == r2 and g1 == g2 and b1 == b2,
      string.format("(%d,%d,%d) vs (%d,%d,%d)", r1, g1, b1, r2, g2, b2)
  end

  U.wait(60)
  local world = game.world
  local _, _, flags = love.window.getMode()
  flags.resizable, flags.fullscreen = true, false
  flags.minwidth, flags.minheight = 1, 1
  love.window.setMode(1612, 720, flags)
  U.wait(5)
  game.options.faithfulRes = 1
  FaithfulRes.apply(1)
  ok(FaithfulRes.scaleCap() ~= nil, "the mobile scale lock is on")

  world:warpToMapId("PLAYERS_HOUSE_1F", 9, 1, "down")
  for _ = 1, 120 do
    if not world:busy() then break end
    U.wait(1)
  end
  U.wait(20)

  local pw, ph = love.graphics.getPixelDimensions()
  local k = math.floor(math.min(pw / 160, ph / 144))
  local bw, bh = 160 * k, 144 * k
  local bx, by = math.floor((pw - bw) / 2), math.floor((ph - bh) / 2)

  local function check(img, tag)
    if not ok(img ~= nil, tag .. ": shot loaded") then return end
    local r, g, b = px(img, 1, ph / 2)
    ok(r == 0 and g == 0 and b == 0, tag .. ": left bar is black")
    r, g, b = px(img, pw - 2, ph / 2)
    ok(r == 0 and g == 0 and b == 0, tag .. ": right bar is black")
    local eq, why = same(img, bx + bw * 0.1, by + bh * 0.05,
      bx + bw * 0.9, by + bh * 0.05)
    ok(eq, tag .. ": void left and right of the viewport match " .. why)
  end

  local still = out .. "/2991_house_1f_still.png"
  U.still(game, still)
  check(loadShot(still), "standing")

  U.hold(game, "up", 8)
  local n = 0
  for _ = 1, 90 do
    U.wait(1)
    if world.fade and not world.fadeHold and n < 6 then
      n = n + 1
      local path = string.format("%s/2991_stairs_fade_%d.png", out, n)
      U.still(game, path)
      check(loadShot(path), "fade step " .. n)
    end
    if world.map and world.map.id == "PLAYERS_HOUSE_2F" and not world:busy() then
      break
    end
  end
  ok(n > 0, "caught " .. n .. " fade frames")
  ok(world.map and world.map.id == "PLAYERS_HOUSE_2F", "reached the 2F")
  U.wait(20)
  local after = out .. "/2991_house_2f_still.png"
  U.still(game, after)
  check(loadShot(after), "2F")

  print("[2991] " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
  love.event.quit(fails == 0 and 0 or 1)
end
