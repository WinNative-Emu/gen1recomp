local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_pc_box_text_2756"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS pc_box_text_2756")
    love.event.quit(0)
  else
    print("FAIL pc_box_text_2756 failures=" .. failures)
    love.event.quit(1)
  end
end

local GRID = {
  [1] = "SPECIES_KADABRA", [3] = "SPECIES_BLISSEY", [5] = "SPECIES_MILTANK", [6] = "SPECIES_GENGAR",
  [11] = "SPECIES_SNORLAX", [12] = "SPECIES_NIDOKING", [17] = "SPECIES_GOLEM", [18] = "SPECIES_CHARIZARD",
  [23] = "SPECIES_DUGTRIO", [24] = "SPECIES_MACHAMP", [27] = "SPECIES_GLALIE", [29] = "SPECIES_STEELIX",
}

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Storage = require("src.core.game3.storage")
  local Pokemon = require("src.core.game3.pokemon")
  local FrlgFont = require("src.ui.game3.frlg_font")
  local BoxStorageUI = require("src.ui.game3.box_storage_ui")
  local version = require("src.core.GameVersion").get()
  local C = require("src.core.game3.constants").of(version)

  local session = Runtime.getSession()
  if not result(session ~= nil, version .. ": new game reached the game3 field") then return finish() end

  local function newMon(name, level)
    session.party = {}
    local _, _, mon = Party.giveMon(session, C:require("species", name), level)
    session.party = {}
    return mon
  end

  local storage = Storage.ensure(session)
  storage.currentBox = 1
  local box = storage.boxes[1]
  box.name = "BOX 1"
  for s = 1, 30 do box.mons[s] = newMon(GRID[s] or "SPECIES_PIDGEY", 50) end
  local lead = newMon("SPECIES_ARMALDO", 100)
  lead.gender, lead.heldItem, lead.markings = "M", C:require("items", "ITEM_SCOPE_LENS"), 5
  box.mons[1].heldItem = C:require("items", "ITEM_SCOPE_LENS")
  session.party = { lead, newMon("SPECIES_PIKACHU", 5) }

  local texts, draws, rects = {}, {}, {}
  local realText, realDraw, realRect = FrlgFont.draw, love.graphics.draw, love.graphics.rectangle
  local recording = false
  FrlgFont.draw = function(text, x, y, opts)
    if recording then
      texts[#texts + 1] = { text = tostring(text), x = x, y = y, font = opts and opts.font, colors = opts and opts.colors }
    end
    return realText(text, x, y, opts)
  end
  love.graphics.rectangle = function(mode, x, y, w, h, ...)
    if recording then rects[#rects + 1] = { mode = mode, x = x, y = y, w = w, h = h } end
    return realRect(mode, x, y, w, h, ...)
  end
  love.graphics.draw = function(img, a, b, c, d, e, ...)
    if recording then
      local quad = type(a) == "userdata" and a.typeOf and a:typeOf("Quad")
      if quad then draws[#draws + 1] = { img = img, quad = a, x = b, y = c, sx = e or 1 }
      else draws[#draws + 1] = { img = img, x = a, y = b, sx = d or 1 } end
    end
    return realDraw(img, a, b, c, d, e, ...)
  end
  local function record()
    texts, draws, rects = {}, {}, {}
    recording = true
    for _ = 1, 4000 do
      if #texts > 0 then break end
      U.wait(1)
    end
    recording = false
  end
  local function findText(pred)
    for _, t in ipairs(texts) do if pred(t) then return t end end
  end
  local function findDraw(img)
    for _, d in ipairs(draws) do if d.img == img then return d end end
  end

  local em = version == "emerald"
  local speciesName = Pokemon.name(lead.species)

  BoxStorageUI.show({ session = session, subMode = "deposit" })
  U.wait(60)
  record()
  if version == "ruby" or version == "sapphire" then
    local PcChrome = require("src.ui.game3.pc_chrome")
    local md = PcChrome._markingsImg and findDraw(PcChrome._markingsImg)
    local mqy = md and md.quad and select(2, md.quad:getViewport())
    result(md and md.x == 24 and md.y == 145 and mqy == 40,
      version .. ": markings combo 5 drawn at pret (40,149) center (got " .. (md and (md.x .. "," .. md.y .. " row " .. tostring(mqy)) or "none") .. ")")
    U.still(game, DIR .. "/2756_box_" .. version .. "_pkmn_data.png")
    BoxStorageUI.close()
    U.wait(20)
    FrlgFont.draw, love.graphics.draw, love.graphics.rectangle = realText, realDraw, realRect
    return finish()
  end
  local pic = Pokemon.monFrontPic(lead)
  local pd = pic and findDraw(pic.image)
  local pw, ph = 0, 0
  if pic then pw, ph = pic.image:getDimensions() end
  result(pd and pw == 64 and ph == 64 and pd.x == 8 and pd.y == 16 and pd.sx == 1,
    version .. ": PKMN DATA pic 64x64 at (8,16) scale 1 (got " .. (pd and (pd.x .. "," .. pd.y .. " x" .. pd.sx) or "none") .. ")")
  local mark = findText(function(t) return t.text == "♂" end)
  result(mark and mark.x == 10, version .. ": gender glyph x=10 (got " .. tostring(mark and mark.x) .. ")")
  local sp = findText(function(t) return t.text == "/" .. speciesName end)
  result(sp and sp.y == (em and 103 or 102) and sp.font == (em and "short" or nil),
    version .. ": species line y/font (got " .. tostring(sp and sp.y) .. " " .. tostring(sp and sp.font) .. ")")
  local lv = findText(function(t) return t.text:find("{LV_2}", 1, true) end)
  result(lv and lv.y == (em and 117 or 116) and lv.x > 10, version .. ": level line follows the gender glyph")
  local title = findText(function(t) return t.y == 20 end)
  result(title and title.text == "BOX1", version .. ": default box title is BOX1 (got " .. tostring(title and title.text) .. ")")
  local partyIcon = Pokemon.monIcon(lead)
  local pi = partyIcon and findDraw(partyIcon.image)
  result(pi and pi.x == 88 and (pi.y == 48 or pi.y == 46) and pi.sx == 1,
    version .. ": lead party icon at pret (104,64) center (got " .. (pi and (pi.x .. "," .. pi.y) or "none") .. ")")
  local function rgbIs(c, r, g, b)
    return type(c) == "table" and math.floor(c[1] * 255 + 0.5) == r and math.floor(c[2] * 255 + 0.5) == g
      and math.floor(c[3] * 255 + 0.5) == b
  end
  local function rgbStr(c)
    if type(c) ~= "table" then return "none" end
    return string.format("%d,%d,%d", c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5)
  end
  local nick = findText(function(t) return t.y == 88 end)
  local nc = nick and nick.colors or {}
  result(rgbIs(nc.fg, 255, 255, 255) and rgbIs(nc.shadow, 0, 0, 0),
    version .. ": PKMN DATA text white with black shadow (got fg " .. rgbStr(nc.fg) .. " shadow " .. rgbStr(nc.shadow) .. ")")
  local lc = lv and lv.colors or {}
  result(rgbIs(lc.shadow, 0, 0, 0), version .. ": level line shadow black (got " .. rgbStr(lc.shadow) .. ")")
  local mc = mark and mark.colors or {}
  result(rgbIs(mc.fg, 123, 189, 255) and rgbIs(mc.shadow, 0, 123, 255),
    version .. ": male glyph sScrollingBg_Pal idx4/5 (got " .. rgbStr(mc.fg) .. " / " .. rgbStr(mc.shadow) .. ")")
  local PcChrome = require("src.ui.game3.pc_chrome")
  local md = PcChrome._markingsImg and findDraw(PcChrome._markingsImg)
  local mqy = md and md.quad and select(2, md.quad:getViewport())
  result(md and md.x == 24 and md.y == 146 and mqy == 40,
    version .. ": markings combo 5 drawn at pret (40,150) center (got " .. (md and (md.x .. "," .. md.y .. " row " .. tostring(mqy)) or "none") .. ")")
  U.still(game, DIR .. "/2756_box_" .. version .. "_pkmn_data.png")
  lead.gender = "F"
  record()
  local fem = findText(function(t) return t.text == "♀" end)
  local fc = fem and fem.colors or {}
  result(rgbIs(fc.fg, 255, 132, 132) and rgbIs(fc.shadow, 173, 25, 25),
    version .. ": female glyph sScrollingBg_Pal idx6/7 (got " .. rgbStr(fc.fg) .. " / " .. rgbStr(fc.shadow) .. ")")
  lead.gender = "M"
  BoxStorageUI.close()
  U.wait(30)

  BoxStorageUI.show({ session = session, subMode = "move" })
  U.wait(60)
  BoxStorageUI.cursorSlot = 30
  U.wait(10)
  record()
  local okGrid, bad = true, nil
  for s = 1, 30 do
    local icon = Pokemon.monIcon(box.mons[s])
    local col, row = (s - 1) % 6, math.floor((s - 1) / 6)
    local ex, ey = 84 + col * 24, 28 + row * 24
    local hit = false
    for _, d in ipairs(draws) do
      if icon and d.img == icon.image and d.quad and d.sx == 1 and d.x == ex and (d.y == ey or d.y == ey - 2) then
        local _, _, qw, qh = d.quad:getViewport()
        if qw == 32 and qh == 32 then hit = true end
      end
    end
    if not hit then
      okGrid, bad = false, s
      break
    end
  end
  result(okGrid, version .. ": 30 box icons are 32x32 at 1:1, pret centers (100+24c, 44+24r)"
    .. (bad and (" (slot " .. bad .. " off)") or ""))
  local square
  for _, r in ipairs(rects) do
    if r.w == 3 and r.h == 3 then square = r end
  end
  result(square == nil, version .. ": no held-item square on box icons outside MOVE ITEMS"
    .. (square and (" (got " .. square.x .. "," .. square.y .. ")") or ""))
  U.still(game, DIR .. "/2756_box_" .. version .. "_full_grid.png")
  BoxStorageUI.close()
  U.wait(20)

  FrlgFont.draw, love.graphics.draw, love.graphics.rectangle = realText, realDraw, realRect
  finish()
end
