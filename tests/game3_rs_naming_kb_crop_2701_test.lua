package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_SAPPHIRE_ROM") or "../pokeruby/pokesapphire.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("[skip] game3_rs_naming_kb_crop_2701_test: no ROM at " .. ROM_PATH)
  os.exit(0)
end
local data = f:read("*a")
f:close()

local rom = { id = "sapphire", size = #data }
function rom:get(o) return data:byte(o + 1) end
function rom:u16(o) local a, b = data:byte(o + 1, o + 2); return a + b * 256 end
function rom:u32(o)
  local a, b, c, d = data:byte(o + 1, o + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
function rom:readString(o, n) return data:sub(o + 1, o + n) end

local files = {}
local cache = {}
function cache:write(rel, bytes) files[rel] = bytes; return true end
function cache:read(rel) return files[rel] end
function cache:exists(rel) return files[rel] ~= nil end

local ROOT = "data/generated/gba"
require("src.core.GameVersion").set("sapphire")
require("src.import.gba.versions").select("sapphire")

local Naming = require("src.import.gba.rs.extract_naming")
Naming.run(rom, cache, { cacheRoot = ROOT })
local man = assert(load(assert(files[ROOT .. "/naming/manifest.lua"], "naming manifest written"), "@naming", "t", {}))()

-- pokeruby/src/naming_screen.c:1677
eq(man.kb_x, 16, "keyboard panel x")
eq(man.kb_y, 64, "keyboard panel starts at tile row 8")
eq(man.kb_w, 176, "keyboard panel width")
eq(man.kb_h, 80, "keyboard panel height")

local IndexedPng = require("src.core.game3.indexed_png")
local CacheBlob = require("src.import.CacheBlob")
for _, page in ipairs({ "kb_upper", "kb_lower", "kb_symbols" }) do
  local png = IndexedPng.decode(assert(files[ROOT .. "/naming/" .. page .. ".png"], page .. " written"), CacheBlob.inflate)
  local top, bottom
  for y = 0, png.h - 1 do
    for x = 1, png.w do
      if png.index[y * png.w + x] ~= 0 then
        top = top or y
        bottom = y
        break
      end
    end
  end
  check(top ~= nil and top >= 1, page .. " keeps an empty row above the panel rim")
  eq(top and (top + man.kb_y), 67, page .. " rim sits at screen y 67")
  eq(bottom and (bottom + man.kb_y), 142, page .. " panel bottom sits at screen y 142")
end

T.finish()
