package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local SaveSerializer = require("src.core.SaveSerializer")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")

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

local function fresh(version, scope, extra)
  local files = {}
  local reg = { list = { "slot1" }, active = "slot1", names = { slot1 = "MAIN" } }
  local opts = { playthroughIds = { [scope] = { slot1 = "aaaa" } } }
  if scope:sub(1, 5) == "cart_" then
    reg.hashes = { slot1 = "cafe" }
    reg.broken = { slot1 = true }
    opts.cartSlots = { [scope:sub(6)] = reg }
  else
    opts.saveSlots = { [scope] = reg }
  end
  files["options.lua"] = SaveSerializer.encode(opts)
  local save = {
    version = version,
    player = { name = "ASH", map = "PALLET_TOWN", x = 1, y = 1 },
    party = {},
    pokedex = { seen = {}, owned = {} },
    inventory = {},
    meta = { playthroughId = "aaaa" },
  }
  for k, v in pairs(extra or {}) do save[k] = v end
  files["saves/" .. scope .. "/slot1.lua"] = SaveSerializer.encode(save)
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set(version)
  return files
end

local function decode(files, path)
  return files[path] and SaveSerializer.decode(files[path]) or nil
end

do
  local files = fresh("red", "red")
  files["mod_storage/red/aaaa/m/data.lua"] = "return { n = 1 }"
  local before = files["saves/red/slot1.lua"]
  local id, err = SaveData.duplicateSlot("red", "slot1", "MAIN copy")
  T.eq(id, "slot2", "red: duplicateSlot returns the next slot id (" .. tostring(err) .. ")")
  local copy = decode(files, "saves/red/slot2.lua")
  T.check(type(copy) == "table", "red: the copy decodes")
  T.eq(copy and copy.player.name, "ASH", "red: the copy holds the same progress")
  local newId = copy and copy.meta.playthroughId
  T.check(type(newId) == "string" and newId ~= "" and newId ~= "aaaa",
    "red: the copy gets its own playthroughId")
  T.eq(files["saves/red/slot1.lua"], before, "red: the original file is untouched")
  local opts = SaveData.loadOptions()
  T.eq(opts.playthroughIds.red.slot2, newId, "red: options map slot2 to the new id")
  T.eq(opts.playthroughIds.red.slot1, "aaaa", "red: and slot1 keeps its id")
  T.eq(files["mod_storage/red/" .. tostring(newId) .. "/m/data.lua"], "return { n = 1 }",
    "red: mod storage is copied under the new id")
  T.eq(files["mod_storage/red/aaaa/m/data.lua"], "return { n = 1 }",
    "red: and the original mod storage stays")
  local label
  for _, s in ipairs(SaveData.listSlots("red")) do
    if s.id == "slot2" then label = s.label end
  end
  T.eq(label, "MAIN copy", "red: listSlots shows the copy's label")
  T.eq(files["saves/red/slot2.lua.bak"], nil, "red: the copy starts with no .bak")

  copy.player.name = "GARY"
  T.check(SaveData.writeSlot("red", "slot2", copy), "red: the copy can be written")
  T.eq(decode(files, "saves/red/slot1.lua").player.name, "ASH",
    "red: writing the copy leaves the original alone")

  T.check(SaveData.deleteSlot("red", "slot2"), "red: the copy can be deleted")
  opts = SaveData.loadOptions()
  T.eq(opts.playthroughIds.red.slot1, "aaaa", "red: deleting the copy keeps slot1's id")
  T.check(files["saves/red/slot1.lua"] ~= nil, "red: and slot1's file")
end

do
  local files = fresh("crystal", "crystal", {
    generation = 2, rtc = { day = 3, hour = 7 }, rawImport = "RAWCART" })
  files["saves/crystal/slot1.cart"] = "LEGACYCART"
  local id = SaveData.duplicateSlot("crystal", "slot1", "MAIN copy")
  T.eq(id, "slot2", "crystal: duplicate works for Gen 2")
  local copy = decode(files, "saves/crystal/slot2.lua")
  T.eq(copy and copy.rtc and copy.rtc.hour, 7, "crystal: RTC bookkeeping survives")
  T.eq(copy and copy.rawImport, "RAWCART", "crystal: the raw cart image survives")
  T.eq(files["saves/crystal/slot2.cart"], "LEGACYCART", "crystal: the legacy .cart sidecar is copied")
end

do
  local files = fresh("firered", "firered", {
    engine = "game3", generation = 3, modData = { cartImage = "FRCART", cartKey = 1234 } })
  local id = SaveData.duplicateSlot("firered", "slot1", "MAIN copy")
  T.eq(id, "slot2", "firered: duplicate works for Gen 3")
  local copy = decode(files, "saves/firered/slot2.lua")
  T.eq(copy and copy.modData and copy.modData.cartImage, "FRCART", "firered: the cart template survives")
  T.eq(copy and copy.modData and copy.modData.cartKey, 1234, "firered: the stored key survives")
end

do
  local files = fresh("red", "cart_x")
  local id = SaveData.duplicateCartSlot("x", "slot1", "MAIN copy")
  T.eq(id, "slot2", "cart: duplicateCartSlot works for a cart scope")
  T.check(files["saves/cart_x/slot2.lua"] ~= nil, "cart: the copy lands in the cart scope")
  T.eq(SaveData.slotCartHash("x", "slot2"), "cafe", "cart: the cart hash is copied")
  T.eq(SaveData.slotSealBroken("x", "slot2"), true, "cart: the broken seal is copied")
end

do
  local files = fresh("red", "red")
  files["saves/red/slot1_trade.lua"] = SaveSerializer.encode({
    entries = { { sent = { species = "PIKACHU" } } } })
  local optsBefore = files["options.lua"]
  local id, err = SaveData.duplicateSlot("red", "slot1", "MAIN copy")
  T.eq(id, nil, "trade: a pending trade blocks the copy")
  T.check(type(err) == "string" and err:find("trade", 1, true) ~= nil, "trade: and says why")
  T.eq(files["options.lua"], optsBefore, "trade: the registry is untouched")
  T.eq(files["saves/red/slot2.lua"], nil, "trade: no copy is written")
  T.eq(files["saves/red/slot2_trade.lua"], nil, "trade: the journal is never copied")

  files["saves/red/slot1_trade.lua"] = SaveSerializer.encode({ entries = {} })
  id = SaveData.duplicateSlot("red", "slot1", "MAIN copy")
  T.eq(id, "slot2", "trade: a settled journal does not block the copy")
  T.eq(files["saves/red/slot2_trade.lua"], nil, "trade: and the journal stays behind")
end

do
  fresh("red", "red")
  local id, err = SaveData.duplicateSlot("red", "slot9", "x")
  T.eq(id, nil, "missing: an unregistered slot is refused")
  T.check(type(err) == "string", "missing: with a reason")
end

do
  local files = fresh("red", "red")
  local RomImporter = require("src.import.RomImporter")
  local imp = RomImporter.new(function() end, { launcher = true })
  imp._sync = false
  imp:_refreshSlots("red")
  imp:_duplicateSlot("red", "slot1")
  T.eq(imp.activeSlot.red, "slot2", "launcher: Duplicate selects the copy")
  T.eq(imp.saveNotice.red and imp.saveNotice.red.ok, true, "launcher: and reports success")
  local label
  for _, s in ipairs(imp.slots.red or {}) do
    if s.id == "slot2" then label = s.label end
  end
  T.eq(label, "MAIN copy", "launcher: the copy is labelled after the original")
  T.check(files["saves/red/slot2.lua"] ~= nil, "launcher: and written to disk")
end

do
  local src = assert(io.open("src/import/LauncherView.lua")):read("*a")
  local body = src:match("local function saveActions%(.-\nend\n")
  T.check(body and body:find("_duplicateSlot(scope, slot.id)", 1, true) ~= nil,
    "launcher: the save card offers a Duplicate action")
end

love.filesystem = realFS

T.finish("save_slot_duplicate_2484")
