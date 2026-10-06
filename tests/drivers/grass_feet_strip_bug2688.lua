-- data/sprites/facings.asm:51
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local Assets = require("src.render.Assets")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "."

  local fails = 0
  local function check(cond, label)
    if cond then print("PASS " .. label) else
      fails = fails + 1
      print("FAIL " .. label)
    end
  end

  game.save.flags.EVENT_GOT_STARTER = true
  local Pokemon = require("src.pokemon.Pokemon")
  table.insert(game.save.party, Pokemon.new(game.data, "CHARMANDER", 5))
  game.save.options = game.save.options or {}
  local savedSpeed = game.speedOverride
  game.speedOverride = 1

  local function grab()
    local got
    love.graphics.captureScreenshot(function(id) got = id end)
    for _ = 1, 600 do
      if got then return got end
      coroutine.yield()
    end
    return nil
  end

  local function frameRows(sprite)
    local ok, id = pcall(Assets.imageData, sprite.def.image)
    if not ok or not id then return 0, 15 end
    local first, last
    for y = 0, math.min(sprite.frameHeight, id:getHeight()) - 1 do
      for x = 0, math.min(sprite.frameWidth, id:getWidth()) - 1 do
        local r = id:getPixel(x, y)
        if r < 0.83 then
          first = first or y
          last = y
          break
        end
      end
    end
    return first or 0, last or 15
  end

  local function differs(a, b, x, y)
    local r1, g1, b1 = a:getPixel(x, y)
    local r2, g2, b2 = b:getPixel(x, y)
    return math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2) > 0.05
  end

  local function measure(tag)
    local ow = game.overworld
    local r = ow.map.renderer
    U.wait(4)
    local withGrass = grab()
    r.drawStrip = function() end
    r.markStripRedraw = function() end
    U.wait(2)
    local noGrass = grab()
    ow.playerHidden = true
    U.wait(2)
    local noPlayer = grab()
    ow.playerHidden = false
    r.drawStrip = nil
    r.markStripRedraw = nil
    U.wait(2)
    if not (withGrass and noGrass and noPlayer) then
      check(false, tag .. " captured three frames")
      return
    end
    local w, h = withGrass:getDimensions()
    local x0, y0, x1, y1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        if differs(noGrass, noPlayer, x, y) then
          x0 = math.min(x0 or x, x); x1 = math.max(x1 or x, x)
          y0 = math.min(y0 or y, y); y1 = math.max(y1 or y, y)
        end
      end
    end
    if not y0 then
      check(false, tag .. " found the player sprite on screen")
      return
    end
    local first, last = frameRows(ow.player.sprite)
    local scale = (y1 - y0 + 1) / (last - first + 1)
    local top = y0 - first * scale
    local rows = {}
    for y = math.floor(top), math.floor(top + 20 * scale) do
      if y >= 0 and y < h then
        for x = x0, x1 do
          if differs(withGrass, noGrass, x, y) then
            local row = math.floor((y - top) / scale)
            rows[row] = (rows[row] or 0) + 1
          end
        end
      end
    end
    local above, mid, low = 0, 0, 0
    for row, n in pairs(rows) do
      if row < 8 then above = above + n
      elseif row < 12 then mid = mid + n
      else low = low + n end
    end
    U.log(tag, "scale=" .. scale, "rows0-7=" .. above, "rows8-11=" .. mid,
          "rows12-15=" .. low)
    check(above == 0, tag .. " grass leaves sprite rows 0-7 alone")
    check(mid > 0, tag .. " grass covers sprite rows 8-11")
    check(low > 0, tag .. " grass covers sprite rows 12-15")
  end

  local modes = {
    { "gbc", "sgb" }, { "redpp", "advanced" }, { "ogred", "ogred" }, { "og", "og" },
  }
  for _, m in ipairs(modes) do
    game.save.options.colors = m[1]
    PaletteFX.setMode(m[1])
    U.teleport(game, "ROUTE_1", 10, 6, "down")
    U.wait(20)
    check(game.overworld.map:isGrassCell(game.overworld.player.cellX,
                                         game.overworld.player.cellY),
          m[2] .. " player stands in tall grass")
    measure(m[2])
  end

  for i, m in ipairs(modes) do
    game.save.options.colors = m[1]
    PaletteFX.setMode(m[1])
    U.teleport(game, "ROUTE_1", 10, 6, "down")
    U.wait(20)
    U.shot(game, DIR .. "/2688_0" .. i .. "_" .. m[2] .. "_grass_from_shoulders_down.png")
  end

  game.save.options.colors = "gbc"
  PaletteFX.setMode("gbc")
  game.speedOverride = savedSpeed
  U.wait(2)
  love.event.quit(fails == 0 and 0 or 1)
end
