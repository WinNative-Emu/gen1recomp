package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROMS = {
  { game = "firered", path = os.getenv("POKEPORT_FIRERED_ROM") or "../pokefirered/pokefirered.gba" },
  { game = "leafgreen", path = os.getenv("POKEPORT_LEAFGREEN_ROM") or "../pokefirered/pokeleafgreen.gba" },
  { game = "emerald", path = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba" },
  { game = "sapphire", path = os.getenv("POKEPORT_SAPPHIRE_ROM") or "../pokeruby/pokesapphire.gba" },
}

local function romFrom(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  local rom = { size = #data }
  function rom:get(o) return data:byte(o + 1) end
  function rom:u16(o) local a, b = data:byte(o + 1, o + 2); return a + b * 256 end
  function rom:u32(o)
    local a, b, c, d = data:byte(o + 1, o + 4)
    return a + b * 256 + c * 65536 + d * 16777216
  end
  function rom:readString(o, n) return data:sub(o + 1, o + n) end
  return rom
end

local function sameCmds(got, want, label)
  eq(#got, #want, label .. " command count")
  for i, w in ipairs(want) do
    eq(got[i] and got[i][1], w[1], label .. " cmd " .. i .. " frame")
    eq(got[i] and got[i][2], w[2], label .. " cmd " .. i .. " duration")
  end
end

-- pokeemerald/src/data/trainer_graphics/back_pic_anims.h:1
local RSE_THROW = { { 0, 24 }, { 1, 9 }, { 2, 24 }, { 0, 9 }, { 3, 50 } }
-- pokefirered/src/data/trainer_graphics/back_pic_anims.h:1
local RED_THROW = { { 1, 20 }, { 2, 6 }, { 3, 6 }, { 4, 24 }, { 0, 1 } }
local OLD_MAN_THROW = { { 1, 24 }, { 2, 9 }, { 3, 24 }, { 0, 9 } }

local EXPECT = {
  firered = { [0] = { 0, RED_THROW }, [1] = { 0, RED_THROW }, [2] = { 3, RSE_THROW }, [5] = { 0, OLD_MAN_THROW } },
  leafgreen = { [0] = { 0, RED_THROW }, [1] = { 0, RED_THROW }, [3] = { 3, RSE_THROW }, [4] = { 0, OLD_MAN_THROW } },
  emerald = { [0] = { 3, RSE_THROW }, [1] = { 3, RSE_THROW }, [2] = { 0, RED_THROW }, [6] = { 3, RSE_THROW },
    [7] = { 3, RSE_THROW } },
  sapphire = { [0] = { 3, RSE_THROW }, [1] = { 3, RSE_THROW }, [2] = { 3, RSE_THROW } },
}

local ran = 0
for _, spec in ipairs(ROMS) do
  local rom = romFrom(spec.path)
  if not rom then
    print("[skip] " .. spec.game .. ": no ROM at " .. spec.path)
  else
    ran = ran + 1
    require("src.core.GameVersion").set(spec.game)
    require("src.import.gba.versions").select(spec.game)
    local files = {}
    local cache = {}
    function cache:write(rel, bytes) files[rel] = bytes; return true end
    function cache:read(rel) return files[rel] end
    function cache:exists(rel) return files[rel] ~= nil end
    local TrainerExtract = require("src.import.gba.trainer_extract")
    TrainerExtract.run(rom, cache, { cacheRoot = "data/generated/gba", scripts = {}, text = {} })
    check(files["data/generated/gba/trainers/back_anims.lua"] ~= nil, spec.game .. " writes trainers/back_anims.lua")
    local required = false
    for _, rel in ipairs(TrainerExtract.REQUIRED) do
      if rel == "trainers/back_anims.lua" then required = true end
    end
    check(required, "back_anims.lua is a required trainer cache file")
    package.loaded["src.core.game3.trainer_pic"] = nil
    local TrainerPic = require("src.core.game3.trainer_pic")
    TrainerPic.install(cache)
    for pic, want in pairs(EXPECT[spec.game]) do
      local label = spec.game .. " back pic " .. pic
      eq(TrainerPic.backIdleFrame(pic), want[1], label .. " idle frame")
      sameCmds(TrainerPic.backAnims(pic).throw, want[2], label .. " throw")
    end
  end
end

if ran == 0 then
  print("[skip] game3_back_pic_anims_2702_test: no pret ROMs")
  os.exit(0)
end
T.finish()
