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

local Pokedex = require("src.ui.game3.rse.pokedex")

for t = 1, 15 do check(not Pokedex.caughtFlashOn(t), "timer " .. t .. " keeps the base colors") end
for t = 16, 31 do check(Pokedex.caughtFlashOn(t), "timer " .. t .. " loads the gray colors") end
check(not Pokedex.caughtFlashOn(32), "timer 32 returns to the base colors")

local ran = 0
local sapphire = romFrom(os.getenv("POKEPORT_SAPPHIRE_ROM") or "../pokeruby/pokesapphire.gba", "sapphire")
if sapphire then
  ran = ran + 1
  require("src.core.GameVersion").set("sapphire")
  require("src.import.gba.versions").select("sapphire")
  local cache, files = memCache()
  require("src.import.gba.rs.extract_pokedex").run(sapphire, cache, { cacheRoot = ROOT })
  require("src.import.gba.rs.extract_pokedex_detail").run(sapphire, cache, { cacheRoot = ROOT })
  local hoenn = loadLua(files, "rse/pokedex/manifest.lua").palettes.hoenn
  local flash = loadLua(files, "rse/pokedex_detail/manifest.lua").palettes.registrationFlash
  eq(#hoenn, 96, "RS hoenn dex palette keeps 96 colors")
  local nonzero = 0
  for i = 1, 16 do
    eq(hoenn[48 + i], flash[i], "hoenn color " .. (47 + i) .. " reads through into gPokedexMenu2_Pal")
    if hoenn[48 + i] ~= 0 then nonzero = nonzero + 1 end
  end
  check(nonzero >= 8, "RS caught page palette 5 is not black")
  local base = {}
  for i = 0, 255 do base[i] = 0 end
  local pal, on, off = Pokedex.caughtPalettes(base, { hoenn = hoenn, registrationFlash = flash }, true)
  for i = 1, 7 do
    eq(on[80 + i], hoenn[i + 1], "RS gray phase color " .. i)
    eq(off[80 + i], flash[i + 1], "RS pink phase color " .. i)
    eq(pal[80 + i], off[80 + i], "RS base page already shows the pink phase " .. i)
  end
  eq(on[81], off[81], "RS description panel color 1 stays white in both phases")
  check(on[82] ~= off[82], "RS bars change color between phases")
else
  print("[skip] sapphire: no ROM")
end

local emerald = romFrom(os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba", "emerald")
if emerald then
  ran = ran + 1
  require("src.core.GameVersion").set("emerald")
  require("src.import.gba.versions").select("emerald")
  local cache, files = memCache()
  require("src.import.gba.rse.pokedex_chrome_extract").run(emerald, cache, { cacheRoot = ROOT, game = "emerald" })
  local hoenn = loadLua(files, "rse/pokedex/manifest.lua").palettes.hoenn
  local base = {}
  for i = 0, 255 do base[i] = 0 end
  for i = 1, #hoenn - 1 do base[i] = hoenn[i + 1] end
  local _, on, off = Pokedex.caughtPalettes(base, { hoenn = hoenn }, false)
  local differs = false
  for i = 1, 7 do
    eq(on[48 + i], hoenn[i + 1], "Emerald gray phase color " .. i)
    eq(off[48 + i], hoenn[49 + i], "Emerald orange phase color " .. i)
    if on[48 + i] ~= off[48 + i] then differs = true end
  end
  check(differs, "Emerald caught page bars flash")
else
  print("[skip] emerald: no ROM")
end

if ran == 0 then
  print("[skip] game3_rs_pokedex_palette_2710_test: no pret ROMs")
  os.exit(0)
end
T.finish()
