package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local GenSave = require("src.save_convert.GenSave")
local Gen2Save = require("src.save_convert.Gen2Save")
local SaveConvert = require("src.save_convert.SaveConvert")
local SaveData = require("src.core.SaveData")
local Origin = require("src.online.union.Origin")

local function versionRoot(version)
  local home = os.getenv("HOME")
  if not home or home == "" then return nil end
  local ids = {}
  local env = os.getenv("POKEPORT_IDENTITY")
  if env and env ~= "" then ids[#ids + 1] = env end
  ids[#ids + 1] = "g1r-" .. version
  ids[#ids + 1] = "pokeport-test-caches"
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE", home .. "/.local/share/love" }) do
    for _, id in ipairs(ids) do
      local root = base .. "/" .. id .. "/" .. version
      local f = io.open(root .. "/data/generated/maps.lua", "rb")
      if f then f:close() return root end
    end
  end
  return nil
end

local function loadTable(root, name)
  local chunk = loadfile(root .. "/data/generated/" .. name .. ".lua")
  local ok, mod = pcall(chunk or error)
  return ok and type(mod) == "table" and mod or nil
end

local function captured(module, fn)
  local seen
  local real = module.encode
  module.encode = function(save, ...)
    seen = save
    return real(save, ...)
  end
  local bytes, err = fn()
  module.encode = real
  return seen, bytes, err
end

local ran = 0

do
  local root = versionRoot("red")
  local stub = root and SaveConvert.gen1DataFromDir(root)
  if stub and stub.maps.MT_MOON_POKECENTER then
    ran = ran + 1
    SaveConvert.setGen1DataStub(stub, "red")
    local function onMap(map, x, y, origin)
      local s = SaveData.newGame({ playerName = "RED", rivalName = "BLUE" })
      s.player.map, s.player.x, s.player.y, s.player.facing = map, x, y, "left"
      s.lastOutdoor = { id = "PALLET_TOWN", x = 5, y = 6 }
      if origin then Origin.record(s, origin) end
      return s
    end
    local mtMoon = { gen = 1, version = "red", map = "MT_MOON_POKECENTER", warp = 3, x = 13, y = 1 }
    local cases = {
      { "2F", onMap("POKECENTER_2F", 13, 2, mtMoon), "MT_MOON_POKECENTER", "ROUTE_4" },
      { "Union Room", onMap("UNION_ROOM", 12, 20, mtMoon), "MT_MOON_POKECENTER", "ROUTE_4" },
      { "1F stairs alcove", onMap("VIRIDIAN_POKECENTER", 12, 1), "VIRIDIAN_POKECENTER", "VIRIDIAN_CITY" },
    }
    for _, c in ipairs(cases) do
      local label, live, center, town = c[1], c[2], c[3], c[4]
      local livePlayer = live.player
      local seen, bytes, err = captured(GenSave, function() return SaveConvert.exportSav(live, "red") end)
      check(seen ~= nil, "red " .. label .. ": the encoder ran")
      eq(seen and seen.player.map, center, "red " .. label .. ": the cart save stands in the origin center")
      eq(seen and seen.player.facing, "up", "red " .. label .. ": facing the nurse")
      eq(seen and seen.lastOutdoor and seen.lastOutdoor.id, town, "red " .. label .. ": LAST_MAP is the center's town")
      check(live.player == livePlayer, "red " .. label .. ": the live save is not moved")
      check(bytes ~= nil, "red " .. label .. ": exported -- " .. tostring(err))
      if bytes then
        local back = SaveConvert.importSav(bytes, "red", "red")
        eq(back and back.player.map, center, "red " .. label .. ": the .sav reads back in the center")
      end
    end
    local plain = onMap("VIRIDIAN_POKECENTER", 11, 3)
    local seen = captured(GenSave, function() return SaveConvert.exportSav(plain, "red") end)
    check(seen == plain, "red: a vanilla cell encodes the save untouched")
    SaveConvert.setGen1DataStub(nil)
  end
end

do
  local root = versionRoot("gold")
  local stub = {}
  for _, name in ipairs({ "pokemon", "moves", "items", "maps", "scripts", "sprites", "constants" }) do
    stub[name] = root and loadTable(root, name)
  end
  local center = "CHERRYGROVE_POKECENTER_1F"
  if stub.maps and stub.maps.POKECENTER_2F and stub.maps[center] then
    ran = ran + 1
    stub.tilesets, stub.landmarks = loadTable(root, "tilesets"), loadTable(root, "landmarks")
    SaveConvert.setGen2DataStub(stub)
    local width = stub.maps.POKECENTER_2F.width * 2
    local function at(map, x, y)
      local s = {
        generation = 2,
        player = { name = "GOLD", id = 12345, money = 3000, gender = "male" },
        rival = { name = "SILVER" }, mom = { name = "MOM" },
        position = { map = map, x = x, y = y, facing = "left" },
        party = {}, boxes = {}, boxNames = {}, currentBox = 1, spawn = 2,
      }
      Origin.record(s, { gen = 2, version = "gold", map = center, warp = 3, x = 0, y = 7, facing = "left" })
      return s
    end
    for _, c in ipairs({ { "Union Room", at("UNION_ROOM", 4, 4) },
                         { "2F added column", at("POKECENTER_2F", width + 1, 3) } }) do
      local label, live = c[1], c[2]
      local livePos = live.position
      local seen, bytes, err = captured(Gen2Save, function() return SaveConvert.exportSav(live, "gold") end)
      check(seen ~= nil, "gold " .. label .. ": the encoder ran")
      eq(seen and seen.position.map, center, "gold " .. label .. ": the cart save stands in the origin 1F")
      eq(seen and seen.position.facing, "up", "gold " .. label .. ": facing the nurse")
      eq(seen and seen.backupWarp and seen.backupWarp.map, center, "gold " .. label .. ": the backup warp is the 1F")
      check(live.position == livePos, "gold " .. label .. ": the live save is not moved")
      check(bytes ~= nil, "gold " .. label .. ": exported -- " .. tostring(err))
    end
    local plain = at("POKECENTER_2F", 2, 3)
    local seen = captured(Gen2Save, function() return SaveConvert.exportSav(plain, "gold") end)
    check(seen == plain, "gold: a vanilla 2F cell encodes the save untouched")
    SaveConvert.setGen2DataStub(nil)
  end
end

do
  SaveConvert.setGen1DataStub({ pokemon = {}, moves = {}, items = {}, maps = {}, encounters = {} }, "red")
  local s = { player = { map = "UNION_ROOM", x = 4, y = 4, facing = "up" } }
  local seen, bytes, why = captured(GenSave, function() return SaveConvert.exportSav(s, "red") end)
  check(seen == nil and bytes == nil, "red: a Union Room save is never encoded without the text pointer table")
  check(type(why) == "string" and why:find("text_pointers", 1, true) ~= nil, "and the refusal names it: " .. tostring(why))
  SaveConvert.setGen1DataStub(nil)
  ran = ran + 1
end

if ran == 0 then
  print("[skip] union_export_safety: no red or gold cache")
  os.exit(0)
end

T.finish("union_export_safety")
