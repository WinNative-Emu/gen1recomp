local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/drv2727"

local function until_(n, fn)
  for _ = 1, n do
    if fn() then return true end
    U.wait(1)
  end
  return fn()
end

local function loadShot(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local bytes = f:read("*a")
  f:close()
  return love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
end

local function hex(r, g, b)
  return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function cellColors(img, cellX, cellY)
  local scale = img:getWidth() / 240
  local seen = {}
  for y = 0, 7 do for x = 0, 7 do
    local px, py = math.floor((cellX + x + 0.5) * scale), math.floor((cellY + y + 0.5) * scale)
    seen[hex(img:getPixel(px, py))] = true
  end end
  return seen
end

return function(game)
  local pass = true
  local function check(cond, label)
    print((cond and "PASS " or "FAIL ") .. label)
    if not cond then pass = false end
  end
  until_(900, function() return game.phase == "boot" and game.boot end)
  local ok, err = xpcall(function()
    local Runtime = require("src.core.game3.runtime")
    local Warp = require("src.core.game3.warp")
    local Message = require("src.ui.game3.message")
    pcall(function() game:_handleBootAction({ action = "new_game", name = "MAY", gender = 1 }) end)
    U.wait(60)
    until_(600, function()
      if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
      return not (Warp.isBusy() or (Message.isOpen and Message.isOpen()))
    end)
    local s = Runtime.getSession()
    local C = require("src.core.game3.constants").active(s)
    local Bag = require("src.core.game3.bag")
    Bag.add(s.bag, C:require("items", "ITEM_POTION"), 3)
    Bag.add(s.bag, C:require("items", "ITEM_LIECHI_BERRY"), 1)
    Bag.add(s.bag, C:require("items", "ITEM_RAZZ_BERRY"), 10)
    Bag.add(s.bag, C:require("items", "ITEM_TM39_ROCK_TOMB"), 1)
    Bag.add(s.bag, C:require("items", "ITEM_HM01_CUT"), 1)
    local BagMenu = require("src.ui.game3.bag_menu")
    local Font = require("src.ui.game3.frlg_font")
    local realDraw = Font.draw
    local calls = {}
    Font.draw = function(str, x, y, opts)
      calls[#calls + 1] = {s = str, x = x, y = y}
      return realDraw(str, x, y, opts)
    end
    local function find(str, y)
      for i = #calls, 1, -1 do
        local c = calls[i]
        if c.s == str and (y == nil or c.y == y) then return c.x, c.y end
      end
    end
    local function rightEdge(str, y)
      local x = find(str, y)
      return x and x + Font.measure(str, {font = "normal"})
    end

    local function capture(gender, tag, pocket, idx)
      s.gender, s.playerGender = gender, gender
      BagMenu.show(s, { session = s, pocket = pocket })
      until_(120, function() return not BagMenu._open end)
      U.wait(10)
      calls = {}
      local path = string.format("%s/2727_%s_%s_%s.png", DIR, idx, tag, pocket:lower())
      U.still(game, path)
      local img = loadShot(path)
      BagMenu.close()
      U.wait(20)
      return img
    end

    for _, who in ipairs({{1, "female", "0"}, {0, "male", "1"}}) do
      local gender, tag, base = who[1], who[2], who[3]
      local img = capture(gender, tag, "BERRY_POUCH", base .. "1")
      local lx, ly = find("36")
      check(lx == 120, tag .. " LIECHI No36 number at x=120")
      check(ly ~= nil and find("×", ly) == 208, tag .. " LIECHI multiply sign at x=208")
      check(ly ~= nil and rightEdge("1", ly) == 232, tag .. " LIECHI count right-aligned to 232")
      local _, ry = find("10")
      check(ry ~= nil and rightEdge("10", ry) == 232 and find("×", ry) == 208, tag .. " RAZZ x10 count right-aligned to 232")
      if img then
        local selectedCell, stripeLeak, idleStripe = 40 + 3 * 8, false, false
        for p = 0, 4 do
          local cx = 40 + p * 8
          local seen = cellColors(img, cx, 72)
          if cx ~= selectedCell and (seen["6bb5d6"] or seen["297ba5"]) then idleStripe = true end
          if seen["297ba5"] then stripeLeak = true end
        end
        if gender == 1 then
          check(not stripeLeak and not idleStripe, "female indicator dots have no blue stripe pixels")
        else
          check(idleStripe, "male indicator dots sit on blue stripes")
        end
      else check(false, tag .. " berry shot readable") end

      capture(gender, tag, "TM_CASE", base .. "2")
      local tx, ty = find("39")
      check(tx == 120, tag .. " TM39 number at x=120")
      check(ty ~= nil and find("ROCK TOMB", ty) == 136, tag .. " TM39 name at x=136")
      check(ty ~= nil and find("×", ty) == 214, tag .. " TM multiply sign at x=214")
      check(ty ~= nil and rightEdge("1", ty) == 232, tag .. " TM count right-aligned to 232")
      local _, hy = find("CUT")
      check(hy ~= nil and find("1", hy) == 129, tag .. " HM01 number at x=129")
      check(hy ~= nil and find("×", hy) == nil, tag .. " HM row has no quantity")

      capture(gender, tag, "ITEMS", base .. "3")
      check(find("×", 16) == 214, tag .. " item multiply sign at x=214")
      check(rightEdge("3", 16) == 232, tag .. " item count right-aligned to 232")
    end
    Font.draw = realDraw
  end, debug.traceback)
  if not ok then print("FAIL driver error: " .. tostring(err)); pass = false end
  love.event.quit(pass and 0 or 1)
  U.wait(10)
end
