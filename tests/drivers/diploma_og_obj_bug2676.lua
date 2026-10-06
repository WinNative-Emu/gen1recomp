-- engine/events/diploma.asm:44
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local P = require("src.render.PaletteFX")
  local Diploma = require("src.ui.Diploma")
  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/shots"

  local fails = 0
  local function check(label, ok, detail)
    print((ok and "PASS " or "FAIL ") .. label
      .. (detail ~= nil and ("  [" .. tostring(detail) .. "]") or ""))
    if not ok then fails = fails + 1 end
    return ok
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

  local function near(R, G, B, c)
    return math.abs(R - c[1]) <= 12 and math.abs(G - c[2]) <= 12
       and math.abs(B - c[3]) <= 12
  end

  local function letterbox(img)
    local W, H = img:getWidth(), img:getHeight()
    local x1, y1, x2, y2 = W, H, -1, -1
    for y = 0, H - 1 do
      for x = 0, W - 1 do
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
      return x1, y1, bh / 144
    end
    local s = math.min(W / 160, H / 144)
    return math.floor((W - 160 * s) / 2), math.floor((H - 144 * s) / 2), s
  end

  local function load(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    local ok, img = pcall(function()
      return love.image.newImageData(
        love.filesystem.newFileData(bytes, "shot.png"))
    end)
    if not ok then return nil end
    return img
  end

  local function census(img, objRamp, bgRamp, bx1, by1, bx2, by2)
    local W, H = img:getWidth(), img:getHeight()
    local ox, oy, s = letterbox(img)
    local c = { obj = 0, bg = 0, grey = 0, ink = 0, nonwhite = 0 }
    for gy = by1, by2 - 1 do
      for gx = bx1, bx2 - 1 do
        local x = ox + math.floor((gx + 0.5) * s)
        local y = oy + math.floor((gy + 0.5) * s)
        if x >= 0 and x < W and y >= 0 and y < H then
          local r, g, b = img:getPixel(x, y)
          local R = math.floor(r * 255 + 0.5)
          local G = math.floor(g * 255 + 0.5)
          local B = math.floor(b * 255 + 0.5)
          if R < 30 and G < 30 and B < 30 then c.ink = c.ink + 1 end
          if not (R > 230 and G > 230 and B > 230) then
            c.nonwhite = c.nonwhite + 1
          end
          if R == G and G == B and R > 60 and R < 240 then c.grey = c.grey + 1 end
          for _, k in ipairs(objRamp or {}) do
            if near(R, G, B, k) then c.obj = c.obj + 1 break end
          end
          for _, k in ipairs(bgRamp or {}) do
            if near(R, G, B, k) then c.bg = c.bg + 1 break end
          end
        end
      end
    end
    return c
  end

  U.wait(5)
  U.teleport(game, "CELADON_MANSION_3F", 2, 4, "up")
  game.save.player.name = "RED"
  local d = Diploma.new(game)
  game.stack:push(d)

  game.save.options.colors = "ogred"
  P.applyOptions(game.save.options)
  check("COLORS ogred uses the sprite OBJ path", P.usesSpriteObp() == true,
    P.mode)
  local objRamp = { P.ogObjBase()[2], P.ogObjBase()[3] }
  local bgRamp = { P.ogBg()[2], P.ogBg()[3] }
  waitRendered(4)
  local maxRedraws = 0
  for _ = 1, 4 do
    waitRendered(1)
    local n = #P.uiSpriteRedraws()
    if n > maxRedraws then maxRedraws = n end
  end
  check("ogred records the pic and the text overlay for replay",
    maxRedraws == 2, maxRedraws)

  local shot1 = SHOT_DIR .. "/2676_01_ogred_player_obj_green.png"
  if check("shot ogred", U.shot(game, shot1)) then
    local img = load(shot1)
    if check("ogred shot decodes", img ~= nil) then
      local body = census(img, objRamp, bgRamp, 115, 80, 152, 136)
      check("ogred player wears the OBJ ramp", body.obj > 200, body.obj)
      check("ogred player has no BG-red pixels", body.bg == 0, body.bg)
      check("ogred player has no DMG grey", body.grey == 0, body.grey)
      local fist = census(img, objRamp, nil, 152, 100, 155, 116)
      check("ogred fist reaches columns 152-154", fist.obj > 0, fist.obj)
      local r = census(img, objRamp, nil, 120, 96, 128, 104)
      check("ogred the r of your stays in front of the player", r.ink > 4,
        r.ink)
      local gf = census(img, objRamp, nil, 115, 128, 152, 136)
      check("ogred GAME FREAK stays in front of the player", gf.ink > 20,
        gf.ink)
    end
  end

  P.applyOptions({ colors = "gbc" })
  waitRendered(4)
  local gbcRedraws = 0
  for _ = 1, 4 do
    waitRendered(1)
    local n = #P.uiSpriteRedraws()
    if n > gbcRedraws then gbcRedraws = n end
  end
  check("gbc records no OBJ replay", gbcRedraws == 0, gbcRedraws)
  local shot2 = SHOT_DIR .. "/2676_02_gbc_fist_uncropped.png"
  if check("shot gbc", U.shot(game, shot2)) then
    local img = load(shot2)
    if check("gbc shot decodes", img ~= nil) then
      local body = census(img, objRamp, nil, 115, 80, 152, 136)
      check("gbc player never wears the OG OBJ ramp", body.obj == 0, body.obj)
      local fist = census(img, nil, nil, 152, 100, 155, 116)
      check("gbc fist reaches columns 152-154", fist.nonwhite > 0,
        fist.nonwhite)
    end
  end

  game.save.options.colors = "ogred"
  P.applyOptions(game.save.options)
  waitRendered(2)
  print(fails == 0 and "PASS diploma_2676_all" or "FAIL diploma_2676_all")
  love.event.quit(fails == 0 and 0 or 1)
end
