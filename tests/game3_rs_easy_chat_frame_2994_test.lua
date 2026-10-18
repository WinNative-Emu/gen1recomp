package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local function romFrom(path, id)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  local rom = { id = id, size = #data }
  function rom:get(o) return data:byte(o + 1) end
  function rom:u16(o) local a, b = data:byte(o + 1, o + 2); return a + b * 256 end
  function rom:u32(o)
    local a, b, c, d = data:byte(o + 1, o + 4)
    return a + b * 256 + c * 65536 + d * 16777216
  end
  function rom:readString(o, n) return data:sub(o + 1, o + n) end
  function rom:ptrOffset(p)
    if not p or p < 0x08000000 or p >= 0x0A000000 then return nil end
    return p - 0x08000000
  end
  return rom
end

local function memCache()
  local files, cache = {}, {}
  function cache:write(rel, bytes) files[rel] = bytes; return true end
  function cache:read(rel) return files[rel] end
  function cache:exists(rel) return files[rel] ~= nil end
  return cache, files
end

local ROOT = "data/generated/gba"
local function loadLua(files, rel)
  return assert(load(assert(files[ROOT .. "/" .. rel], "missing " .. rel), "@" .. rel, "t", {}))()
end

local function plteColor(png, index)
  local at = assert(png:find("PLTE", 1, true), "indexed png has a PLTE chunk")
  local o = at + 4 + index * 3
  return png:byte(o), png:byte(o + 1), png:byte(o + 2)
end

local ran = 0
for _, game in ipairs({ { "ruby", "../pokeruby/pokeruby.gba", "POKEPORT_RUBY_ROM" },
  { "sapphire", "../pokeruby/pokesapphire.gba", "POKEPORT_SAPPHIRE_ROM" } }) do
  local id = game[1]
  local rom = romFrom(os.getenv(game[3]) or game[2], id)
  if rom then
    ran = ran + 1
    require("src.core.GameVersion").set(id)
    require("src.import.gba.versions").select(id)
    local cache, files = memCache()
    require("src.import.gba.rs.extract_easy_chat_ui").run(rom, cache, { cacheRoot = ROOT })
    require("src.import.gba.rs.extract_easy_chat_editor").run(rom, cache, { cacheRoot = ROOT })
    require("src.import.gba.rs.extract_trendy_phrase").run(rom, cache, { cacheRoot = ROOT })
    local ui = loadLua(files, "rse/easy_chat/manifest.lua")
    local editor = loadLua(files, "rse/easy_chat_editor/manifest.lua")
    local trend = loadLua(files, "rse/trendy_phrase/manifest.lua")
    for i = 1, 16 do
      eq(ui.palettes.bg[80 + i], ui.palettes.frameBlue[i], id .. " BG palette 5 color " .. (i - 1) .. " is gMenuWordGroupFrame2_Pal")
    end
    local lit = 0
    for i = 1, 15 do if ui.palettes.bg[81 + i] ~= 0 then lit = lit + 1 end end
    check(lit >= 8, id .. " word group frame palette 5 is not black")
    local png = assert(files[editor.blueFrame.base], "blue frame base png written")
    local r, g, b = plteColor(png, 15)
    check(r + g + b > 0, id .. " blue frame base png palette is not black")
    local atlas = assert(files[ui.tiles.png], "frame atlas png written")
    r, g, b = plteColor(atlas, 95)
    check(r + g + b > 0, id .. " frame atlas palette 5 is not black")
    eq(editor.titlePalette, 1, id .. " editor title prints with palette 1")
    eq(editor.titleFont, nil, id .. " editor title has no font override")
    eq(trend.titlePalette, 1, id .. " trendy phrase title prints with palette 1")
    eq(ui.titlePalette, 1, id .. " mail header cells use palette 1")
  else
    print("[skip] " .. id .. ": no ROM")
  end
end

local Frames = require("src.ui.game3.rs.easy_chat_editor_frames")
local function settle(alpha)
  local t, indicator = Frames.begin("groups", alpha), nil
  local map, man = {}, { maps = { base = {}, picker = {}, shapes = {} } }
  for i = 1, 640 do map[i] = 0; man.maps.base[i] = 0; man.maps.picker[i] = 0 end
  for _ = 1, 200 do
    local done, events = Frames.step(t, map, man)
    if events.indicator then indicator = events.indicator end
    if done then break end
  end
  return indicator
end
eq(settle(false), 3, "group mode opens with the GROUP MODE indicator animation")
eq(settle(true), 4, "alphabet mode opens with the A-Z MODE indicator animation")

if ran == 0 then print("[skip] game3_rs_easy_chat_frame_2994_test: no pret ROMs") end
T.finish()
