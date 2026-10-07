package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local SaveSerializer = require("src.core.SaveSerializer")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")
local SaveFileIO = require("src.import.SaveFileIO")

local realFS = love.filesystem

local function memfs(files)
  return {
    files = files,
    read = function(path) return files[path] end,
    write = function(path, content) files[path] = content return true end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    createDirectory = function() return true end,
    getSaveDirectory = function() return "/fake/save" end,
    getDirectoryItems = function(path)
      local seen, items = {}, {}
      local prefix = path == "" and "" or path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then
          local child = key:sub(#prefix + 1):match("^[^/]+")
          if child and not seen[child] then
            seen[child] = true
            items[#items + 1] = child
          end
        end
      end
      table.sort(items)
      return items
    end,
  }
end

local function fresh()
  local files = {}
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set("red")
  return files
end

local ID = "0123456789abcdef0123456789abcdef"

local function sample(version, id)
  return {
    version = version,
    player = { name = "ASH", map = "PALLET_TOWN", x = 1, y = 1 },
    party = { { species = "BULBASAUR", level = 7 } },
    money = 1234,
    meta = { format = 5, mods = {}, playthroughId = id },
  }
end

local function slotId(version, slot)
  local save = SaveSerializer.decode(SaveData.readSlotSource(version, slot) or "")
  return save and save.meta and save.meta.playthroughId
end

do
  local files = fresh()
  local src = SaveData.createSlot("red")
  SaveData.writeSlot("red", src, sample("red", ID))
  SaveData.setActiveSlot("red", src)
  T.eq(SaveData.slotPlaythroughId("red", src, sample("red", ID)), ID, "red: the source owns the id")
  files["mod_storage/red/" .. ID .. "/m/data.lua"] = "return { n = 1 }"

  local ok, rel = SaveFileIO.exportLuaSlot("red", src)
  T.eq(ok, true, "red: the slot exports as .lua")
  rel = tostring(rel):match("(exports/.+)$")
  local imported, copy = SaveFileIO.importToSlot(rel, "red")
  T.eq(imported, true, "red: the export imports back beside its source")
  local newId = slotId("red", copy)
  T.check(type(newId) == "string" and newId ~= ID, "red: the import gets its own playthroughId")
  T.eq(SaveData.loadOptions().playthroughIds.red[copy], newId, "red: the new slot is mapped to the new id")
  T.eq(SaveData.loadOptions().playthroughIds.red[src], ID, "red: the source keeps its mapping")
  T.eq(slotId("red", src), ID, "red: the source file keeps its id")
  T.eq(files["mod_storage/red/" .. tostring(newId) .. "/m/data.lua"], "return { n = 1 }",
    "red: mod storage is copied under the new id")

  T.eq(SaveData.deleteSlot("red", copy), true, "red: the import deletes")
  T.eq(SaveData.loadOptions().playthroughIds.red[src], ID, "red: deleting the import leaves the source mapping")
  T.eq(files["mod_storage/red/" .. ID .. "/m/data.lua"], "return { n = 1 }",
    "red: and the source's mod storage")
end

do
  fresh()
  local src = SaveData.createSlot("crystal")
  SaveData.writeSlot("crystal", src, { version = "crystal", generation = 2, party = {}, meta = {} })
  local opts = SaveData.loadOptions()
  opts.playthroughIds = { crystal = { [src] = ID } }
  SaveData.saveOptions(opts)
  local slot = SaveData.createSlot("crystal")
  local save = sample("crystal", ID)
  local got = SaveData.claimImportPlaythroughId("crystal", slot, save)
  T.check(got ~= ID and save.meta.playthroughId == got,
    "crystal: an id only the options mapping holds still counts as taken")
end

do
  fresh()
  local slot = SaveData.createSlot("firered")
  local opts = SaveData.loadOptions()
  opts.playthroughIds = { firered = { [slot] = ID } }
  SaveData.saveOptions(opts)
  local save = sample("firered", ID)
  T.eq(SaveData.claimImportPlaythroughId("firered", slot, save), ID,
    "firered: re-importing into the slot that owns the id keeps it")
  T.eq(save.meta.playthroughId, ID, "firered: the save is not re-stamped")
end

do
  fresh()
  local slot = SaveData.createSlot("red")
  local save = sample("red", nil)
  T.eq(SaveData.claimImportPlaythroughId("red", slot, save), nil, "red: an id-less import is left for lazy minting")
  T.eq(save.meta.playthroughId, nil, "red: and is not stamped")
end

if loadfile("data/generated/pokemon.lua") then
  local data = require("tests.save_compat._codec").gen1Data("red")
  local stampMapWindow = loadfile("tests/fixture_data/map_window.lua")()
  for mapId in pairs(data.maps) do stampMapWindow(data, mapId) end
  local files = fresh()
  local slot = SaveData.createSlot("red")
  SaveData.setActiveSlot("red", slot)
  local save = SaveData.newGame({ playerName = "ASH", rivalName = "GARY" })
  save.meta = SaveData.buildMeta({}, save.meta, os.time() - 60)
  T.check(SaveData.save(save), "red .sav: the source saves")
  local ok = SaveFileIO.exportActiveSlot("red")
  T.eq(ok, true, "red .sav: the slot exports")
  local id = SaveData.loadOptions().playthroughIds.red[slot]
  local out = files["exports/red/gen1recomp-red-" .. slot .. ".sav"]
  local imported, copy = SaveFileIO.importToSlot(out, "red")
  T.eq(imported, true, "red .sav: the export imports beside its source")
  local newId = SaveData.loadOptions().playthroughIds.red[copy]
  T.check(type(id) == "string" and type(newId) == "string" and newId ~= id,
    "red .sav: a same-install round trip gets its own playthroughId")
  T.eq(slotId("red", copy), newId, "red .sav: stamped into the imported slot")
else
  print("[skip] red .sav round trip (needs data/generated/ for the Gen1 save codec)")
end

love.filesystem = realFS
SaveData.resetSlotState()
GameVersion.set("red")

T.finish("save_import_playthrough_id_s7")
