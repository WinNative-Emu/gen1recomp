local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_party_sprites_2756"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS party_sprites_2756")
    love.event.quit(0)
  else
    print("FAIL party_sprites_2756 failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local Display = require("src.core.game3.display")
  local Oam = require("src.core.game3.oam")
  local PartyMenu = require("src.ui.game3.party_menu")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local BoxStorageUI = require("src.ui.game3.box_storage_ui")
  local Storage = require("src.core.game3.storage")
  local version = require("src.core.GameVersion").get()
  local C = require("src.core.game3.constants").of(version)

  local session = Runtime.getSession()
  if not result(session ~= nil, version .. ": new game reached the game3 field") then return finish() end

  session.party = {}
  Party.giveMon(session, C:require("species", "SPECIES_SALAMENCE"), 50)
  Party.giveMon(session, C:require("species", "SPECIES_MAGCARGO"), 38)
  Party.giveMon(session, C:require("species", "SPECIES_SMEARGLE"), 100)
  Storage.ensure(session)
  Display.mirrorForTests = true

  local draws = {}
  local realDraw = love.graphics.draw
  local recording = false
  love.graphics.draw = function(img, a, b, c, d, e, ...)
    if recording then
      local quad = type(a) == "userdata" and a.typeOf and a:typeOf("Quad")
      local tx, ty = love.graphics.transformPoint(0, 0)
      local ux, uy = love.graphics.transformPoint(1, 1)
      if quad then
        local _, _, qw, qh = a:getViewport()
        draws[#draws + 1] = { img = img, x = b, y = c, sx = (d and e) or 1, sy = e or 1, w = qw, h = qh,
          tsx = ux - tx, tsy = uy - ty }
      elseif img and img.getDimensions then
        local iw, ih = img:getDimensions()
        draws[#draws + 1] = { img = img, x = a, y = b, sx = d or 1, sy = e or d or 1, w = iw, h = ih,
          tsx = ux - tx, tsy = uy - ty }
      end
    end
    return realDraw(img, a, b, c, d, e, ...)
  end
  local function record()
    draws = {}
    recording = true
    for _ = 1, 4000 do
      if #draws > 0 then break end
      U.wait(1)
    end
    U.wait(1)
    recording = false
  end
  local function findDraws(img)
    local out = {}
    for _, d in ipairs(draws) do if d.img == img then out[#out + 1] = d end end
    return out
  end
  local function native(name)
    U.wait(2)
    local canvas = Display._canvas
    if canvas then
      local data = canvas:newImageData():encode("png"):getString()
      os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
      local f = io.open(DIR .. "/" .. name .. "_native.png", "wb")
      if f then f:write(data); f:close() end
    end
    U.still(game, DIR .. "/" .. name .. ".png")
  end

  local function iconChecks(label, expect)
    for i, mon in ipairs(session.party) do
      local icon = Pokemon.monIcon(mon)
      local hits = icon and findDraws(icon.image) or {}
      local d = hits[1]
      local ex, ey = expect(i)
      local ok = d and d.w == 32 and d.h == 32 and d.sx == 1 and d.sy == 1 and d.tsx == 1 and d.tsy == 1
        and d.x >= ex - 16 - 4 and d.x <= ex - 16 and (d.y >= ey - 16 - 4 and d.y <= ey - 16 + 1)
      result(ok, string.format("%s %s: slot %d icon 32x32 x1 at pret center (%d,%d) (got %s)", version, label, i, ex, ey,
        d and string.format("%dx%d x%s/%s xf %s at %s,%s", d.w, d.h, d.sx, d.sy, d.tsx, d.x, d.y) or "none"))
    end
  end

  local function pixelAt(x, y)
    local canvas = Display._canvas
    if not canvas then return nil end
    local r, g, b = canvas:newImageData():getPixel(x, y)
    return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
  end
  local function rgbEq(label, x, y, want)
    U.wait(2)
    local r, g, b = pixelAt(x, y)
    result(r == want[1] and g == want[2] and b == want[3],
      string.format("%s %s: pixel (%d,%d) = %d,%d,%d (got %s,%s,%s)", version, label, x, y, want[1], want[2], want[3],
        tostring(r), tostring(g), tostring(b)))
  end

  local fullHp = session.party[1].hp
  session.party[2].hp = math.floor(session.party[2].maxHp * 0.4)
  session.party[3].hp = math.max(1, math.floor(session.party[3].maxHp * 0.1))
  session.party[2].status = "PSN"
  PartyMenu.show(session.party, nil, { session = session })
  U.wait(60)
  record(4)
  local SINGLE = { { 16, 40 }, { 104, 18 }, { 104, 42 }, { 104, 66 }, { 104, 90 }, { 104, 114 } }
  iconChecks("field party menu", function(i) return SINGLE[i][1], SINGLE[i][2] end)
  local GREEN_TOP, GREEN_LOW = { 90, 214, 132 }, { 115, 255, 173 }
  local YELLOW_TOP, YELLOW_LOW = { 206, 173, 8 }, { 255, 230, 58 }
  local RED_TOP, RED_LOW = { 197, 58, 0 }, { 255, 115, 49 }
  local EMPTY_TOP, EMPTY_LOW = { 82, 82, 82 }, { 115, 115, 115 }
  rgbEq("party hp bar slot 1 full top row", 8 + 24, 24 + 35, GREEN_TOP)
  rgbEq("party hp bar slot 1 full lower rows", 8 + 24, 24 + 37, GREEN_LOW)
  rgbEq("party hp bar slot 1 full right end", 8 + 24 + 47, 24 + 36, GREEN_LOW)
  rgbEq("party hp bar slot 2 yellow top row", 96 + 88, 8 + 10, YELLOW_TOP)
  rgbEq("party hp bar slot 2 yellow lower rows", 96 + 88, 8 + 12, YELLOW_LOW)
  rgbEq("party hp bar slot 2 empty top row", 96 + 88 + 47, 8 + 10, EMPTY_TOP)
  rgbEq("party hp bar slot 2 empty lower rows", 96 + 88 + 47, 8 + 11, EMPTY_LOW)
  rgbEq("party hp bar slot 3 red top row", 96 + 88, 32 + 10, RED_TOP)
  rgbEq("party hp bar slot 3 red lower rows", 96 + 88, 32 + 11, RED_LOW)
  U.wait(2)
  local textData = Display._canvas and Display._canvas:newImageData()
  local std = require("src.ui.game3.frlg_font").STDPAL[2]
  local stdR, stdG, stdB = math.floor(std[1] * 255 + 0.5), math.floor(std[2] * 255 + 0.5), math.floor(std[3] * 255 + 0.5)
  for _, box in ipairs({ { "slot 1", 0, 16, 96, 80 }, { "slot 2", 96, 0, 240, 32 } }) do
    local shadow, white, stdGray = 0, 0, 0
    for y = box[3], box[5] - 1 do
      for x = box[2], box[4] - 1 do
        local r, g, b = textData:getPixel(x, y)
        r, g, b = math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
        if r == 115 and g == 115 and b == 115 then shadow = shadow + 1 end
        if r == 255 and g == 255 and b == 255 then white = white + 1 end
        if r == stdR and g == stdG and b == stdB and stdR ~= 115 then stdGray = stdGray + 1 end
      end
    end
    result(shadow > 200 and white > 200 and stdGray == 0,
      string.format("%s party %s text: shadow 115,115,115 x%d, fg white x%d, standard gray %d,%d,%d x%d",
        version, box[1], shadow, white, stdR, stdG, stdB, stdGray))
  end
  local st = PartyMenu._oam and PartyMenu._oam[2] and Oam.get(PartyMenu._oam[2].status)
  local wantX = version == "emerald" and 136 or 144
  result(st ~= nil and st.x == wantX and st.y == 27,
    string.format("%s party status icon slot 2 at pret (%d,27) (got %s)", version, wantX,
      st and (st.x .. "," .. st.y) or "none"))
  native("2756p_" .. version .. "_party_menu")
  PartyMenu.close()
  session.party[2].status = nil
  session.party[2].hp = session.party[2].maxHp
  session.party[3].hp = session.party[3].maxHp
  session.party[1].hp = fullHp
  U.wait(30)

  SummaryMenu.openMenu(session.party, 1, { session = session })
  U.wait(90)
  record(4)
  local pic = Pokemon.monFrontPic(session.party[1])
  local pd = pic and findDraws(pic.image)[1]
  local pcx, pcy = 60, 65
  if version == "emerald" then pcx, pcy = 40, 64 end
  local left = pd and (pd.sx < 0 and pd.x - 64 or pd.x)
  result(pd and pd.w == 64 and pd.h == 64 and math.abs(pd.sx) == 1 and pd.sy == 1 and pd.tsx == 1
      and left == pcx - 32 and pd.y == pcy - 32,
    string.format("%s summary: front pic 64x64 x1 at pret center (%d,%d) (got %s)", version, pcx, pcy,
      pd and string.format("%dx%d x%s/%s xf %s at %s,%s", pd.w, pd.h, pd.sx, pd.sy, pd.tsx, pd.x, pd.y) or "none"))
  if version == "emerald" then
    local Kit = require("src.ui.game3.rse.scene_kit")
    local m = Kit.manifest("rse/summary")
    local btnImg = m and m.buttons and Kit.image(m.buttons.png)
    local bd = btnImg and findDraws(btnImg)[1]
    local w = m and m.windows[5]
    local ex = w and (w.left * 8 + 62 - require("src.ui.game3.frlg_font").measure("CANCEL") - 16)
    result(bd ~= nil and bd.w == 16 and bd.h == 16 and bd.y == w.top * 8,
      string.format("%s summary: A button glyph 16x16 from sButtons_Gfx at window top (got %s)", version,
        bd and string.format("%dx%d at %s,%s (cancel text x %s)", bd.w, bd.h, bd.x, bd.y, tostring(ex)) or "none"))
    if bd then
      U.wait(2)
      local canvasData = Display._canvas:newImageData()
      local src = love.image.newImageData(m.buttons.png)
      local same, opaque = true, 0
      for y = 0, 15 do
        for x = 0, 15 do
          local r, g, b, a = src:getPixel(x, y)
          if a > 0 then
            opaque = opaque + 1
            local cr, cg, cb = canvasData:getPixel(bd.x + x, bd.y + y)
            if math.abs(cr - r) > 0.01 or math.abs(cg - g) > 0.01 or math.abs(cb - b) > 0.01 then same = false end
          end
        end
      end
      result(same and opaque > 64, string.format("%s summary: A button pixels on screen match the ROM glyph (%d opaque)", version, opaque))
    end
  end
  native("2756p_" .. version .. "_summary")
  if SummaryMenu.close then SummaryMenu.close() end
  U.wait(30)

  BoxStorageUI.show({ session = session, subMode = "deposit" })
  U.wait(90)
  record(4)
  iconChecks("pc party drawer", function(i)
    if i == 1 then return 104, 64 end
    return 152, 16 + 24 * (i - 2)
  end)
  native("2756p_" .. version .. "_pc_drawer")
  BoxStorageUI.close()
  U.wait(30)

  BoxStorageUI.show({ session = session, subMode = "move" })
  U.wait(60)
  BoxStorageUI.holdingMon = session.party[3]
  BoxStorageUI.holdingSource = { loc = "party", slot = 3 }
  BoxStorageUI.cursorSlot = 8
  U.wait(10)
  record(4)
  local held = Pokemon.monIcon(session.party[3])
  local hd = held and findDraws(held.image)
  local hdl = hd and hd[#hd]
  result(hdl and hdl.w == 32 and hdl.h == 32 and hdl.sx == 1 and hdl.tsx == 1,
    string.format("%s pc held mon: icon 32x32 x1 (got %s)", version,
      hdl and string.format("%dx%d x%s xf %s at %s,%s", hdl.w, hdl.h, hdl.sx, hdl.tsx, hdl.x, hdl.y) or "none"))
  native("2756p_" .. version .. "_pc_held")
  BoxStorageUI.holdingMon = nil
  BoxStorageUI.holdingSource = nil
  BoxStorageUI.close()
  U.wait(30)

  local wx, wy = love.window.getPosition()
  love.window.updateMode(540, 1170, { x = wx, y = wy })
  U.wait(30)
  PartyMenu.show(session.party, nil, { session = session })
  U.wait(60)
  record(4)
  iconChecks("portrait party menu", function(i) return SINGLE[i][1], SINGLE[i][2] end)
  native("2756p_" .. version .. "_party_menu_portrait")
  PartyMenu.close()
  U.wait(30)
  BoxStorageUI.show({ session = session, subMode = "deposit" })
  U.wait(90)
  record(4)
  iconChecks("portrait pc party drawer", function(i)
    if i == 1 then return 104, 64 end
    return 152, 16 + 24 * (i - 2)
  end)
  native("2756p_" .. version .. "_pc_drawer_portrait")
  BoxStorageUI.close()
  U.wait(20)

  love.graphics.draw = realDraw
  finish()
end
