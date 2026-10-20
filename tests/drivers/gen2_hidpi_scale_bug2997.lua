local U = require("tests.drivers.util")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2-hidpi-2997"
  local fails = 0
  local function ok(cond, msg)
    if not cond then fails = fails + 1 end
    print("[2997] " .. (cond and "PASS " or "FAIL ") .. msg)
  end
  U.wait(30)
  local _, _, flags = love.window.getMode()
  flags.resizable, flags.fullscreen = true, false
  flags.minwidth, flags.minheight = 1, 1
  flags.highdpi = true
  love.window.setMode(806, 360, flags)
  U.wait(5)
  local function ratio()
    return love.graphics.getPixelDimensions() / love.graphics.getDimensions()
  end
  local d = ratio()
  local pw, ph = love.graphics.getPixelDimensions()
  if d < 1.5 then
    love.window.setMode(1612, 720, flags)
    U.wait(5)
    d = ratio()
    pw, ph = love.graphics.getPixelDimensions()
  end
  print(string.format("[2997] surface %dx%d px, dpi %.3f", pw, ph, d))
  ok(d > 1, "the surface is high-DPI")
  local world = game.world
  if world and world.map then
    world:warpToMapId("NEW_BARK_TOWN", 6, 6, "down")
    for _ = 1, 120 do
      if not world:busy() then break end
      U.wait(1)
    end
  end
  U.wait(20)
  local w, h = love.graphics.getDimensions()
  local scale, ox, oy = game:frameFit(w, h)
  local k = scale * d
  local want = math.floor(math.min(pw / 160, ph / 144))
  ok(math.abs(k - want) < 1e-6,
    string.format("Gen 2 fit is %.3f framebuffer px per GB px (Gen 1 rule: %d)", k, want))
  ok(math.abs(world:fitScale() * d - want) < 1e-6,
    string.format("world fit scale %.3f px matches", world:fitScale() * d))
  local seen
  local drawScene = game.drawScene
  game.drawScene = function(self, sw, sh)
    seen = { sw, sh }
    return drawScene(self, sw, sh)
  end
  print(string.format("[2997] origin %.2f,%.2f units", ox, oy))
  U.still(game, out .. "/2997_gen2_hidpi_overworld.png")
  game.drawScene = nil
  ok(seen and seen[1] == w and seen[2] == h,
    string.format("the scene is handed LOVE units (%sx%s, window %dx%d)",
      tostring(seen and seen[1]), tostring(seen and seen[2]), w, h))
  U.tap(game, "start")
  U.wait(20)
  U.still(game, out .. "/2997_gen2_hidpi_start_menu.png")
  U.tap(game, "b")
  U.wait(20)
  world:warpToMapId("NEW_BARK_TOWN", 13, 7, "up")
  for _ = 1, 120 do
    if not world:busy() then break end
    U.wait(1)
  end
  U.wait(10)
  U.hold(game, "up", 24)
  local n = 0
  for _ = 1, 90 do
    U.wait(1)
    if world.fade and n < 4 then
      n = n + 1
      U.still(game, string.format("%s/2997_gen2_hidpi_door_fade_%d.png", out, n))
    end
    if world.map and world.map.id == "PLAYERS_HOUSE_1F" and not world:busy() then break end
  end
  ok(world.map and world.map.id == "PLAYERS_HOUSE_1F", "walked in the front door")
  U.wait(60)
  U.still(game, out .. "/2997_gen2_hidpi_house.png")
  print("[2997] " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
  love.event.quit(fails == 0 and 0 or 1)
end
