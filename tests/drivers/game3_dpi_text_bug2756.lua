local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or ".bazinga/BSA/10-07-26-02-gen3text/shots/2756"
local DENSITIES = { 0.75, 0.9 }

local fake = DENSITIES[1]
local rawNew = love.graphics.newCanvas
love.graphics.newCanvas = function(w, h, opts)
  if type(opts) ~= "table" then opts = {} end
  if opts.dpiscale == nil then opts.dpiscale = fake end
  return rawNew(w, h, opts)
end

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
end

local function flatten(src)
  local c = rawNew(240, 160, { dpiscale = 1 })
  love.graphics.push("all")
  love.graphics.setCanvas(c)
  love.graphics.origin()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(src, 0, 0)
  love.graphics.pop()
  return c:newImageData()
end

local function reference(fn)
  local c = rawNew(240, 160, { dpiscale = 1 })
  love.graphics.push("all")
  love.graphics.setCanvas(c)
  love.graphics.origin()
  love.graphics.setScissor()
  love.graphics.setShader()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  fn()
  love.graphics.pop()
  return c:newImageData()
end

local function diff(a, b)
  local n = 0
  for y = 0, 159 do
    for x = 0, 239 do
      local r1, g1, b1, a1 = a:getPixel(x, y)
      local r2, g2, b2, a2 = b:getPixel(x, y)
      if math.abs(a1 - a2) > 0.01 or math.abs(r1 - r2) > 0.01
          or math.abs(g1 - g2) > 0.01 or math.abs(b1 - b2) > 0.01 then
        n = n + 1
      end
    end
  end
  return n
end

local function inked(img)
  local n = 0
  for y = 0, 159 do
    for x = 0, 239 do
      local _, _, _, a = img:getPixel(x, y)
      if a > 0.01 then n = n + 1 end
    end
  end
  return n
end

local function measure(s, moment, layers)
  for _, d in ipairs(DENSITIES) do
    fake = d
    s._canvases = nil
    for _, layer in ipairs(layers) do
      local key, fn = layer[1], layer[2]
      local canvas = s:renderToCanvas(key, fn)
      local got = flatten(canvas)
      local ref = reference(fn)
      local n = diff(got, ref)
      local ink = inked(ref)
      print(("[2756] %s %s density %.2f: canvas %dx%d texels, %d of %d ink px differ")
        :format(moment, key, d, canvas:getPixelWidth(), canvas:getPixelHeight(), n, ink))
      check(ink > 0, ("%s %s reference has text (density %.2f)"):format(moment, key, d))
      check(canvas:getPixelWidth() == 240 and canvas:getPixelHeight() == 160,
        ("%s %s canvas is 240x160 texels at density %.2f"):format(moment, key, d))
      check(n == 0, ("%s %s matches density-1 render at density %.2f"):format(moment, key, d))
    end
  end
end

local function shots(game, s, prefix)
  for _, d in ipairs(DENSITIES) do
    fake = d
    s._canvases = nil
    U.wait(2)
    local tag = tostring(math.floor(d * 100 + 0.5))
    U.still(game, ("%s/%s_dpi%s.png"):format(DIR, prefix, tag))
  end
  fake = DENSITIES[1]
end

return function(game)
  local ok, err = pcall(function()
    local function scene() return game.boot and game.boot.newGame end
    local function press(k) U.tap(game, k) U.wait(1) end
    local function waitFor(pred, limit)
      for _ = 1, limit or 3000 do
        if pred() then return true end
        U.wait(1)
      end
      return false
    end
    for _ = 1, 600 do
      if game.boot and game.boot.phase == "intro" then press("start") end
      if game.boot and game.boot.phase == "title" then break end
      U.wait(1)
    end
    for _ = 1, 600 do
      if game.boot.phase == "title" then press("a") U.wait(2) end
      if game.boot.phase == "menu" then break end
      U.wait(1)
    end
    waitFor(function() return game.boot.phase == "menu" and (game.boot.fadeT or 0) == 0 end, 600)
    U.wait(10)
    press("a")
    if not waitFor(function() return scene() ~= nil end, 600) then
      check(false, "new game scene opened")
      return
    end
    check(true, "new game scene opened")
    waitFor(function() return scene().win and scene().win.guide ~= nil and not scene():fadeActive() end, 1500)
    U.wait(30)
    press("a")
    local onPage2 = waitFor(function() return scene().currentPage == 2 and not scene():fadeActive() end, 1500)
    check(onPage2, "controls guide page 2 reached")
    U.wait(10)
    local s = scene()
    shots(game, s, "2756_01_controls_guide_page2")
    measure(s, "controls guide", {
      { "bg0", function() s:drawBg0Text() end },
      { "topbar", function() s:drawTopBar() end },
    })

    local inOak = false
    for _ = 1, 400 do
      s = scene()
      if s and s.section == "oak" and s.win.dialog and s.printer then inOak = true break end
      if s and not s:fadeActive() then press("a") end
      U.wait(8)
    end
    check(inOak, "oak speech dialog reached")
    if not inOak then return end
    U.wait(150)
    shots(game, s, "2756_02_oak_speech_welcome")
    measure(s, "oak speech", {
      { "bg0", function() s:drawBg0Text() end },
    })
  end)
  if not ok then
    print("FAIL driver error: " .. tostring(err))
    failures = failures + 1
  end
  print(("[2756] %d failure(s)"):format(failures))
  love.event.quit(failures == 0 and 0 or 1)
end
