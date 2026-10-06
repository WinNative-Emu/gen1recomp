-- engine/menus/main_menu.asm:357
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Font = require("src.render.Font")
  local SaveData = require("src.core.SaveData")
  local GameVersion = require("src.core.GameVersion")
  local TitleState = require("src.ui.TitleState")
  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/shots/2684"

  local fails = 0
  local function check(label, ok, detail)
    print((ok and "PASS " or "FAIL ") .. label .. (detail and ("  " .. tostring(detail)) or ""))
    if not ok then fails = fails + 1 end
    return ok
  end
  local function finish()
    love.event.quit(fails == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  local rendered = 0
  local hostDraw = love.draw
  love.draw = function(...)
    local r = hostDraw(...)
    rendered = rendered + 1
    return r
  end
  local function waitRendered(n)
    local target = rendered + (n or 2)
    for _ = 1, 2400 do
      if rendered >= target then return true end
      U.wait(1)
    end
    return false
  end
  local function waitFor(pred, limit)
    for _ = 1, limit or 1800 do
      if pred() then return true end
      U.wait(1)
    end
    return false
  end

  local function letterbox(img)
    local W, H = img:getWidth(), img:getHeight()
    local x1, y1, x2, y2 = W, H, -1, -1
    for y = 0, H - 1, 2 do
      for x = 0, W - 1, 2 do
        local r, g, b = img:getPixel(x, y)
        if r > 0.02 or g > 0.02 or b > 0.02 then
          if x < x1 then x1 = x end
          if x > x2 then x2 = x end
          if y < y1 then y1 = y end
          if y > y2 then y2 = y end
        end
      end
    end
    local bw, bh = x2 - x1 + 1, y2 - y1 + 1
    if x2 >= x1 and math.abs(bw / 160 - bh / 144) < 0.05 then
      return x1, y1, bw / 160, bh / 144
    end
    local s = math.min(W / 160, H / 144)
    return math.floor((W - 160 * s) / 2), math.floor((H - 144 * s) / 2), s, s
  end
  local function inkInTile(img, ox, oy, sx, sy, col, row)
    local W, H = img:getWidth(), img:getHeight()
    local n = 0
    for py = 1, 6 do
      for px = 1, 6 do
        local x = math.floor(ox + (col * 8 + px + 0.5) * sx)
        local y = math.floor(oy + (row * 8 + py + 0.5) * sy)
        if x >= 0 and y >= 0 and x < W and y < H then
          local r, g, b = img:getPixel(x, y)
          if (r + g + b) / 3 < 0.35 then n = n + 1 end
        end
      end
    end
    return n
  end

  U.wait(5)
  local title
  local reached = false
  for _ = 1, 120 do
    title = game.stack:top()
    if title ~= nil and title.screenId == "TitleState"
       and type(title.openMenu) == "function" then
      reached = true
      break
    end
    U.tap(game, "start")
    U.wait(10)
  end
  if not check("reached the title screen", reached) then
    print("top state: " .. tostring(title and title.screenId))
    return finish()
  end
  check("title reached its loop", waitFor(function()
    return title.phase == "loop"
  end))
  waitRendered(3)

  local saveName = SaveData.saveFilename(GameVersion.get())
  if not love.filesystem.getInfo(saveName) then
    love.filesystem.write(saveName, "return {}")
  end
  local owned = {}
  for i = 1, 151 do owned[i] = true end
  local inventory = {}
  for _, id in ipairs({ "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE",
      "RAINBOWBADGE", "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE",
      "EARTHBADGE" }) do
    inventory[id] = 1
  end
  local savedLoad = SaveData.load
  SaveData.load = function()
    return { player = { name = "RED" }, inventory = inventory,
             pokedex = { owned = owned }, playTime = 47 * 3600 + 27 * 60 }
  end

  U.tap(game, "start")
  check("START leaves the title for the main menu", waitFor(function()
    local top = game.stack:top()
    return title.menuOpen and top ~= title and top and top.titleUiBox ~= nil
  end, 1200))
  waitRendered(3)
  local menu = game.stack:top()
  check("main menu opens on CONTINUE", menu and menu.items
        and menu.items[1] and menu.items[1].label == require("src.core.Strings")("CONTINUE"))
  U.tap(game, "a")
  local info
  check("CONTINUE opens the info window", waitFor(function()
    info = game.stack:top()
    return info ~= menu and info and info.titleUiBox
      and info.titleUiBox[1] == 4 and info.titleUiBox[2] == 7
  end, 300))
  SaveData.load = savedLoad
  if not info or info == menu then return finish() end

  local drawn = {}
  local realDraw = Font.draw
  Font.draw = function(text, x, y, ...)
    drawn[text] = { x, y }
    return realDraw(text, x, y, ...)
  end
  waitRendered(3)
  Font.draw = realDraw

  local b, d, t = drawn[" 8"], drawn["151"], drawn[" 47:27"]
  check("badge count drawn at hlcoord 17,11",
        b and b[1] == 17 * 8 and b[2] == 11 * 8, b and (b[1] .. "," .. b[2]))
  check("dex count drawn at hlcoord 16,13",
        d and d[1] == 16 * 8 and d[2] == 13 * 8, d and (d[1] .. "," .. d[2]))
  check("play time drawn at hlcoord 13,15",
        t and t[1] == 13 * 8 and t[2] == 15 * 8, t and (t[1] .. "," .. t[2]))

  local shot = SHOT_DIR .. "/2684_01_continue_counts_flush_right.png"
  if check("info window shot", U.still(game, shot)) then
    local f = io.open(shot, "rb")
    local bytes = f and f:read("*a")
    if f then f:close() end
    local ok, img = pcall(function()
      return love.image.newImageData(love.filesystem.newFileData(bytes, "s.png"))
    end)
    if check("shot decodes", ok and img) then
      local ox, oy, sx, sy = letterbox(img)
      check("badge 8 inks col 18 row 11", inkInTile(img, ox, oy, sx, sy, 18, 11) > 0)
      check("col 17 row 11 stays blank", inkInTile(img, ox, oy, sx, sy, 17, 11) == 0)
      check("dex 151 inks col 18 row 13", inkInTile(img, ox, oy, sx, sy, 18, 13) > 0)
      check("col 15 row 13 stays blank", inkInTile(img, ox, oy, sx, sy, 15, 13) == 0)
      check("time inks col 18 row 15", inkInTile(img, ox, oy, sx, sy, 18, 15) > 0)
    end
  end

  game.stack:pop()
  waitRendered(2)
  print(fails == 0 and "PASS continue_info_counts_bug2684" or "FAIL continue_info_counts_bug2684")
  return finish()
end
