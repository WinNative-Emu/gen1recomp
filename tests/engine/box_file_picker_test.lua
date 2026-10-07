package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")
local RomImporter = require("src.import.RomImporter")
local BoxPanel = require("src.import.BoxPanel")
local Files = {}
love.filesystem.getInfo = function(path)
  return Files[path] and { type = "file", size = #Files[path] } or nil
end
love.filesystem.read = function(path) return Files[path] end
love.filesystem.write = function(path, data) Files[path] = data; return true end
love.filesystem.remove = function(path) Files[path] = nil; return true end
love.filesystem.getDirectoryItems = function() return {} end
local imports, gameImports, bytes, problem = 0, 0
BoxPanel.importGCI = function(_, data, why)
  bytes, problem = data, why
  if data then imports = imports + 1; return true end
  return false
end
local function importer()
  local imp = RomImporter.new(function() end, { launcher = true })
  imp.tab, imp._findFetch = "box", nil
  imp._importSave = function() gameImports = gameImports + 1 end
  return imp
end
local native = string.rep("N", 0x76040)
local raw = native:sub(65)
Files["picked_save.sav"] = native
local imp = importer()
imp.android, imp.pickerPendingKind = true, "box"
imp:focus(true)
T.eq(imports, 1, "legacy mobile pick reaches Box instead of game save import")
T.eq(gameImports, 0, "Box pick does not overwrite a game slot")
T.eq(bytes, native, "bridge extension does not alter GCI bytes")
T.eq(Files["picked_save.sav"], nil, "successful staged copy is consumed")
T.eq(imp.pickerPendingKind, nil, "completed pick clears Box routing")

Files["picked_save.sav"] = "bad"
imp.pickerPendingKind = "box"
imp:focus(true)
T.eq(imports, 1, "wrong file size never reaches Box parser")
T.check(problem:find("0x76040", 1, true), "bad-size notice describes accepted formats")
T.eq(gameImports, 0, "bad Box pick never falls through to normal saves")
Files["picked_save.sav"] = nil

Files["pick_error.flag"] = "cancelled: picked_save.sav"
imp.pickerPendingKind, imp.pickPending = "box", true
imp:focus(true)
T.check(problem:find("file manager", 1, true), "legacy cancel is shown on Box")
T.eq(imp.pickPending, nil, "legacy cancel stops polling")

local pickerKind
love.system.pickFile = function(kind) pickerKind = kind; return true end
love.system.getPickedFile = function() return "native.gci" end
imp = importer()
imp.nativePicker, imp.android = true, false
Files["native.gci"] = native
imp:chooseBoxImport()
T.eq(pickerKind, "sav", "existing bridge save picker accepts generic data files")
T.eq(imp.pickerPendingKind, "box", "modern picker records Box destination")
imp:update(0)
T.eq(imports, 2, "modern picker imports a GCI")
T.eq(Files["native.gci"], native, "ordinary selected input is preserved")

love.system.getPickedFile = function() return nil end
love.system.getPickError = function() return "Picker cancelled" end
imp.pickerPendingKind = "box"
imp:update(0)
T.eq(problem, "Picker cancelled", "modern cancel reports to Box")

local closed, readCount = false, 0
local drop = {
  getFilename = function() return "native.sav" end,
  getSize = function() return #raw end,
  open = function() return true end,
  read = function(_, size) readCount = readCount + 1; T.eq(size, #raw, "raw read is bounded"); return raw end,
  close = function() closed = true end,
}
imp:filedropped(drop)
T.eq(imports, 3, "raw native save dropped on Box reaches Box")
T.check(closed, "dropped handle closes after read")
imp.tab = "emerald"
imp:filedropped(drop)
T.eq(gameImports, 1, "game tab retains its ordinary save routing")
T.eq(readCount, 1, "Box reader does not read a game-directed drop")
drop.getFilename = function() return "too-large.gci" end
drop.getSize = function() return 1024 * 1024 * 1024 end
imp:filedropped(drop)
T.eq(readCount, 1, "oversized GCI is refused before allocation")
T.eq(imports, 3, "oversized GCI cannot mutate storage")
T.finish()
