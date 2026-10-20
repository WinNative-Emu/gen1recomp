-- engine/events/hidden_events/route_15_binoculars.asm:1
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local PicBox = require("src.ui.PicBox")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "."

  local fails = 0
  local function check(cond, label)
    if cond then print("PASS " .. label) else
      fails = fails + 1
      print("FAIL " .. label)
    end
  end

  game.save.flags.EVENT_GOT_STARTER = true
  game.save.options = game.save.options or {}

  local function grab()
    local got
    love.graphics.captureScreenshot(function(id) got = id end)
    for _ = 1, 600 do
      if got then return got end
      coroutine.yield()
    end
    return nil
  end

  local function near(r, g, b, c)
    return math.abs(r * 255 - c[1]) <= 4 and math.abs(g * 255 - c[2]) <= 4
       and math.abs(b * 255 - c[3]) <= 4
  end

  local function countColors(img, colors)
    if not img or #colors == 0 then return 0 end
    local w, h = img:getDimensions()
    local n = 0
    for y = 0, h - 1, 2 do
      for x = 0, w - 1, 2 do
        local r, g, b = img:getPixel(x, y)
        for _, c in ipairs(colors) do
          if near(r, g, b, c) then n = n + 1 break end
        end
      end
    end
    return n
  end

  local function monOnly(monPal, basePal)
    local out = {}
    local mon = PaletteFX.effectiveColors(monPal) or {}
    local base = PaletteFX.effectiveColors(basePal) or {}
    for i = 2, 3 do
      local c = mon[i]
      local shared = false
      for _, b in ipairs(base) do
        if c and math.abs(c[1] - b[1]) + math.abs(c[2] - b[2])
             + math.abs(c[3] - b[3]) <= 12 then
          shared = true
        end
      end
      if c and not shared then out[#out + 1] = c end
    end
    return out
  end

  local function openBox()
    for _ = 1, 120 do
      U.tap(game, "a")
      U.wait(6)
      if getmetatable(game.stack:top()) == PicBox then return true end
    end
    return false
  end

  local function closeBox()
    for _ = 1, 120 do
      if game.stack:top() == game.overworld then return true end
      U.tap(game, "a")
      U.wait(6)
    end
    return game.stack:top() == game.overworld
  end

  local MODES = { "redpp", "gbc", "ogred", "og", "gbc_inv", "classic" }
  for _, mode in ipairs(MODES) do
    game.save.options.colors = mode
    PaletteFX.setMode(mode)
    U.teleport(game, "ROUTE_15_GATE_2F", 1, 3, "up")
    U.wait(20)
    local closed = grab()
    local opened = openBox()
    check(opened, mode .. ": binoculars open the pic box")
    if opened then
      U.wait(20)
      local box = game.stack:top()
      check(box.species == "ARTICUNO", mode .. ": box carries ARTICUNO")
      local open = grab()
      U.still(game, DIR .. "/3021_" .. mode .. "_route15_binoculars_articuno.png")
      local zones = game.overworld:sgbPalettes(game) or {}
      local basePal = zones[1] and zones[1].colors
      local uniq = monOnly(PaletteFX.monPal(game.data, "ARTICUNO"), basePal)
      local gained = countColors(open, uniq) - countColors(closed, uniq)
      print(("[driver] %s: %d BLUEMON-only colors, +%d pixels with the box open")
        :format(mode, #uniq, gained))
      if mode == "redpp" then
        check(#uniq > 0 and gained > 100,
              mode .. ": ARTICUNO is drawn in its own palette")
      else
        check(gained <= 0, mode .. ": box keeps the map palette")
      end
      check(closeBox(), mode .. ": box closes back to the overworld")
    end
  end

  game.save.options.colors = "gbc"
  PaletteFX.setMode("gbc")
  print(fails == 0 and "PASS all" or ("FAIL " .. fails .. " check(s)"))
  love.event.quit(fails == 0 and 0 or 1)
end
