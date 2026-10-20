local Fixture = {}
local ROOT = "data/generated/gba/"
local versions = { ruby = 1, sapphire = 2, emerald = 3, firered = 4, leafgreen = 5 }
local packs, images = {}, {}

local function lua(value)
  if type(value) == "string" then return string.format("%q", value) end
  if type(value) ~= "table" then return tostring(value) end
  local keys, fields = {}, {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return a < b end
    return type(a) < type(b)
  end)
  for _, key in ipairs(keys) do
    local name = type(key) == "string" and key:match("^[%a_][%w_]*$") and key
      or ("[" .. lua(key) .. "]")
    fields[#fields + 1] = name .. " = " .. lua(value[key])
  end
  return "{ " .. table.concat(fields, ", ") .. " }"
end

local function xor(a, b)
  local out, bit = 0, 1
  while a > 0 or b > 0 do
    if a % 2 ~= b % 2 then out = out + bit end
    a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
  end
  return out
end

local function be32(n)
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
    math.floor(n / 256) % 256, n % 256)
end

local crcTable = {}
for n = 0, 255 do
  local c = n
  for _ = 1, 8 do
    c = c % 2 == 1 and xor(math.floor(c / 2), 0xEDB88320) or math.floor(c / 2)
  end
  crcTable[n] = c
end

local function chunk(kind, body)
  local c, bytes = 0xFFFFFFFF, kind .. body
  for i = 1, #bytes do
    c = xor(math.floor(c / 256), crcTable[xor(c % 256, bytes:byte(i))])
  end
  return be32(#body) .. bytes .. be32(xor(c, 0xFFFFFFFF))
end

local function png(w, h)
  local key = w .. ":" .. h
  if not images[key] then
    local raw = string.rep("\0", (1 + math.ceil(w / 8)) * h)
    local n = #raw
    assert(n < 65536, "fixture PNG exceeds one stored block")
    local inverse = 65535 - n
    local zlib = "\120\1\1" .. string.char(n % 256, math.floor(n / 256),
      inverse % 256, math.floor(inverse / 256)) .. raw .. be32((n % 65521) * 65536 + 1)
    images[key] = "\137PNG\13\10\26\10"
      .. chunk("IHDR", be32(w) .. be32(h) .. "\1\3\0\0\0")
      .. chunk("PLTE", "\160\160\160\224\224\224")
      .. chunk("IDAT", zlib) .. chunk("IEND", "")
  end
  return images[key]
end

local function build(version)
  local files = {}
  local rs = version == "ruby" or version == "sapphire"
  local function manifest(path, data) files[path] = "return " .. lua(data) .. "\n" end
  local function image(path, w, h)
    files[path] = png(w, h)
    return ROOT .. path
  end
  local function rgba(path, w, h)
    files[path] = string.rep("\160\160\160\255", w * h)
  end
  local palette, rgb = {}, {}
  for i = 1, 256 do palette[i] = i % 2 == 0 and 0x4210 or 0x739C end
  for i = 0, 255 do rgb[i] = { 160, 160, 160 } end

  local naming = { version = 3, layout = rs and "rs" or version == "emerald" and "rse" or "frlg",
    screen = "naming", templates = {}, palettes = { menu = palette, sprites = {} },
    kb_x = 16, kb_y = rs and 64 or 72, kb_w = 176, kb_h = 80,
    geometry = { pageFrameX = 184, pageFrameY = 64, pageButtonX = 188, pageButtonY = 67,
      pageTextX = 192, pageTextY = 72, backX = 184, backY = 96, okX = 184, okY = 120,
      titleX = 72, titleY = 16, inputY = 32, inputArrowY = 40, underscoreY = 44 } }
  for tag = 1, 6 do naming.palettes.sprites[tag] = palette end
  for i, title in ipairs({ "PLAYER", "BOX", "CAUGHT_MON", "NICKNAME", "WALDA" }) do
    naming.templates[i] = { title = title, maxChars = 7, initialPage = 0,
      copyExistingString = 1, iconFunction = i - 1, addGenderIcon = 0 }
  end
  local keyboard = { chars = {}, columnX = {}, columnCounts = { 8, 8, 6 },
    pageOrder = { "UPPER", "LOWER", "OTHERS" }, buttonColumn = 8,
    textX = 24, textY = rs and 72 or 80, rowHeight = 16,
    cursorOriginX = 27, cursorOriginY = 80 }
  local rows = {
    { "ABCDEF .", "GHIJKL ,", "MNOPQRS ", "TUVWXYZ " },
    { "abcdef .", "ghijkl ,", "mnopqrs ", "tuvwxyz " },
    { "01234 ", "56789 ", "!?/.- ", "'()   " },
  }
  for p, page in ipairs(rows) do
    keyboard.chars[p], keyboard.columnX[p] = {}, {}
    for c = 1, keyboard.columnCounts[p] do keyboard.columnX[p][c] = (rs and 24 or 0) + (c - 1) * 16 end
    for r, text in ipairs(page) do
      keyboard.chars[p][r] = {}
      for c = 1, keyboard.columnCounts[p] do keyboard.chars[p][r][c] = { char = text:sub(c, c) } end
    end
  end
  naming.keyboard = keyboard
  for _, spec in ipairs({ { "bg", 240, 160 }, { "kb_upper", 176, 80 }, { "kb_lower", 176, 80 },
    { "kb_symbols", 176, 80 }, { "cursor", 48, 16 }, { "cursor_base", 48, 16 },
    { "cursor_glow", 48, 16 }, { "input_arrow", 8, 8 }, { "underscore", 8, 8 },
    { "rival", 16, 32 }, { "pc_icon_off", 16, 24 }, { "pc_icon_on", 16, 24 },
    { "back_button", 40, 24 }, { "ok_button", 40, 24 }, { "page_swap_frame", 40, 32 },
    { "page_swap_button", 32, 16 }, { "page_swap_button_glow", 40, 32 },
    { "back_button_glow", 40, 24 }, { "ok_button_glow", 40, 24 } }) do
    naming[spec[1]] = image("naming/" .. spec[1] .. ".png", spec[2], spec[3])
  end
  for _, name in ipairs({ "upper", "lower", "others" }) do
    naming["page_swap_" .. name] = image("naming/page_swap_" .. name .. ".png", 24, 8)
    naming["page_swap_button_" .. name] = image("naming/page_swap_button_" .. name .. ".png", 32, 16)
  end
  manifest("naming/manifest.lua", naming)

  manifest("pokemon/party/manifest.lua", { formatVersion = 2, width = 240, height = 160,
    ballW = 32, ballSheetH = 64, ballFrames = 2, slotMainW = 80, slotMainH = 56,
    slotWideW = 144, slotWideH = 24, cancelButtonW = 56, cancelButtonH = 16,
    holdIconW = 8, holdIconSheetH = 16, holdIconFrames = 2,
    pokemonVersion = versions[version], palBuffer = rgb })
  rgba("pokemon/icons/16.rgba", 32, 64)
  rgba("pokemon/party/bg.rgba", 240, 160)
  for _, suffix in ipairs({ "", "_selected", "_multi", "_multi_selected" }) do
    rgba("pokemon/party/slot_main" .. suffix .. ".rgba", 80, 56)
    rgba("pokemon/party/slot_wide" .. suffix .. ".rgba", 144, 24)
  end
  rgba("pokemon/party/slot_wide_empty.rgba", 144, 24)
  for _, name in ipairs({ "cancel_button", "confirm_button" }) do
    rgba("pokemon/party/" .. name .. ".rgba", 56, 16)
    rgba("pokemon/party/" .. name .. "_selected.rgba", 56, 16)
  end
  rgba("pokemon/party/status_balls.rgba", 32, 64)
  rgba("pokemon/party/status_icons.rgba", 32, 64)
  rgba("pokemon/party/hold_icons.rgba", 8, 16)

  local option = { title = "OPTION", rows = {}, textPalette = palette, bgColor = 0x4210,
    nativeWindow = { foregroundColor = 1, backgroundColor = 0, shadowColor = 8 },
    selectedStyle = 8, inactiveStyle = 15, titleX = 32, titleY = 8,
    frameLabel = "TYPE", frameLabelX = 120, frameNumberX = 144, frameY = 120, frameCount = 20,
    windows = { { left = 2, top = 1, width = 26, height = 2 },
      { left = 2, top = 5, width = 26, height = 14 } } }
  for i, name in ipairs({ "TEXT SPEED", "BATTLE SCENE", "BATTLE STYLE", "SOUND", "BUTTON MODE", "FRAME", "CANCEL" }) do
    option.rows[i] = { text = name, x = 32, y = 40 + (i - 1) * 16, choices = {} }
    local count = ({ 3, 2, 2, 2, 3, 0, 0 })[i]
    for j = 1, count do option.rows[i].choices[j] = { text = tostring(j - 1), x = 120 + (j - 1) * 32 } end
  end
  if rs or version == "emerald" then
    manifest("rse/menus/manifest.lua", { layout = rs and "rs" or "rse", option = option })
    local arrows = { w = 8, h = 8, png = image("rse/bag/arrows.png", 8, 16) }
    manifest("rse/bag/manifest.lua", { layout = rs and "rs" or "rse",
      sprites = { arrows = arrows, arrows_vertical = arrows } })
  end

  if rs then
    local parts = {}
    for _, name in ipairs({ "left", "middle", "wide", "right" }) do
      parts[name] = { png = image("rse/common_ui/cursor_" .. name .. ".png", name == "wide" and 32 or 8, 16) }
    end
    manifest("rse/common_ui/manifest.lua", { layout = "rs", menuCursor = { parts = parts } })
    local party = { layout = "rs", bg = { png = image("rse/party/bg.png", 240, 160) },
      panels = {}, palettes = { bg = palette }, sprites = {}, windows = {}, buttons = {},
      coordinates = {}, textSettings = {}, monIconAnims = {}, heldItemOffset = { 4, 10 },
      gfx = ROOT .. "rse/party/misc.gfx", orderGfx = ROOT .. "rse/party/order.gfx" }
    files["rse/party/misc.gfx"], files["rse/party/order.gfx"] = string.rep("\17", 16384), string.rep("\17", 4096)
    party.order = { png = image("rse/party/order.png", 256, 32) }
    for _, spec in ipairs({ { "large", 88, 56 }, { "small", 152, 24 }, { "empty", 152, 24 } }) do
      local entry = { w = spec[2], h = spec[3], variants = {}, tiles = {} }
      for i = 1, spec[2] * spec[3] / 64 do entry.tiles[i] = 0 end
      for bank = 3, 10 do entry.variants[bank] = image("rse/party/" .. spec[1] .. "_" .. bank .. ".png", spec[2], spec[3]) end
      party.panels[spec[1]] = entry
    end
    party.hpTiles = { w = 8, h = 8, variants = {} }
    for _, color in ipairs({ "green", "yellow", "red", "caps" }) do
      party.hpTiles.variants[color] = image("rse/party/hp_" .. color .. ".png", 8, 96)
    end
    party.sprites.status = { w = 32, h = 8, png = image("rse/party/status.png", 32, 56) }
    party.sprites.heldItems = { w = 8, h = 8, png = image("rse/party/held_items.png", 8, 16),
      anims = { { { frame = 0 } }, { { frame = 1 } } } }
    for _, key in ipairs({ "bg", "monText", "menu" }) do
      party.windows[key] = { fontNum = 3, foregroundColor = 1, backgroundColor = 0, shadowColor = 8 }
    end
    for i, key in ipairs({ "confirm", "cancel" }) do
      party.buttons[key] = { x = 24, y = 14 + i * 2, tiles = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } }
    end
    for i = 1, 5 do party.monIconAnims[i] = { { op = "frame", tile = 0, duration = 8 }, { op = "jump", target = 0 } } end
    for _, key in ipairs({ "panels", "linkPanels", "monIcons", "text", "hpBars", "descriptors" }) do
      party.coordinates[key] = {}
      for layout = 1, 4 do
        party.coordinates[key][layout] = {}
        for slot = 1, 6 do
          local x, y = (slot - 1) % 2 * 15, math.floor((slot - 1) / 2) * 6
          if key == "monIcons" then x, y = x * 8 + 16, y * 8 + 16
          elseif key ~= "panels" and key ~= "linkPanels" then x, y = x + 4, y + 2 end
          party.coordinates[key][layout][slot] = { x, y }
        end
      end
    end
    for layout = 1, 4 do
      party.textSettings[layout] = {}
      for slot = 1, 6 do
        local pos = party.coordinates.panels[layout][slot]
        party.textSettings[layout][slot] = { x = pos[1] * 8 + 24, y = pos[2] * 8,
          oam = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 16, 0 }, { 24, 0 } } }
      end
    end
    manifest("rse/party/manifest.lua", party)
  end

  for i = 0, 19 do rgba("chrome/user_frame_" .. i .. ".rgba", 24, 24) end
  for _, spec in ipairs({ { "menu_message_rgba", 48, 24 }, { "std_rgba", 24, 24 },
    { "signpost_rgba", 40, 32 }, { "message_box", 56, 16 },
    { "fonts/text_cursor", 16, 16 }, { "fonts/down_arrows_fg", 128, 16 },
    { "fonts/down_arrow", 8, 64 }, { "fonts/keypad_icons", 128, 32 } }) do
    rgba("chrome/" .. spec[1] .. ".rgba", spec[2], spec[3])
  end
  local arrow = { width = 8, height = 64, frameH = 16, yOffsets = { 0, 16, 32, 48 } }
  local dialogue = { width = 56, height = 16, tilesW = 7, tilesH = 2 }
  manifest("chrome/manifest.lua", { frames = { message_box = dialogue }, fonts = { down_arrow = arrow } })
  manifest("chrome/rs_frames.lua", { layout = "rs", dialogue = dialogue, downArrow = arrow })
  manifest("chrome/font_palette.lua", rgb)
  manifest("chrome/palettes.lua", { message_box = rgb, std_menu = rgb })
  local widths, metrics, native = {}, {}, { layout = "rs", fonts = {} }
  for i = 0, 511 do widths[i] = 6 end
  for i, name in ipairs({ "normal", "small", "short", "narrow", "small_narrow" }) do
    metrics[i] = { name = "FONT_" .. name:upper(), maxLetterHeight = 16, lineSpacing = 0, letterSpacing = 0 }
    for _, language in ipairs({ "latin", "japanese" }) do
      local stem = language .. "_" .. name
      rgba("chrome/fonts/" .. stem .. "_fg.rgba", 256, 512)
      rgba("chrome/fonts/" .. stem .. "_shadow.rgba", 256, 512)
      local suffix = name == "normal" and "" or "_" .. name
      manifest("chrome/fonts/" .. language .. suffix .. "_widths.lua", widths)
    end
  end
  manifest("chrome/fonts/metrics.lua", metrics)
  if rs then
    for _, language in ipairs({ "latin", "japanese" }) do
      for id = 0, 6 do
        local stem = "rs_" .. language .. "_" .. id
        native.fonts[stem] = { id = id, language = language, bpp = 4,
          width = 256, height = 512, glyphs = 512 }
        manifest("chrome/fonts/" .. stem .. "_widths.lua", widths)
        rgba("chrome/fonts/" .. stem .. "_fg.rgba", 256, 512)
        rgba("chrome/fonts/" .. stem .. "_shadow.rgba", 256, 512)
        files["chrome/fonts/" .. stem .. ".idx"] = string.rep("\14", 256 * 512)
      end
    end
    manifest("chrome/native_fonts.lua", native)
  end
  return files
end

function Fixture.bytes(version, path)
  if not versions[version] or type(path) ~= "string" then return nil end
  local start = path:find(ROOT, 1, true)
  if start then path = path:sub(start + #ROOT) end
  path = path:gsub("^/+", "")
  if not packs[version] then packs[version] = build(version) end
  return packs[version][path]
end

return Fixture
