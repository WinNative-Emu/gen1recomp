package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local GameVersion = require("src.core.GameVersion")
local Txn = require("src.online.union.TradeTxn")

local realFS = love.filesystem

local function fresh(version)
  local files = {}
  love.filesystem = {
    files = files,
    write = function(path, content) files[path] = content return true end,
    read = function(path) return files[path] end,
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
  }
  SaveData.resetSlotState()
  GameVersion.set(version)
  return files
end

for _, version in ipairs({ "red", "firered" }) do
  local files = fresh(version)
  local flat = SaveData.saveFilename(version)
  local base = flat:gsub("%.lua$", "")
  files[flat] = SaveSerializer.encode({ version = version, engine = version == "firered" and "game3" or nil,
    player = { name = "RED" }, party = {} })
  files[base .. "_xtrade.lua"] = SaveSerializer.encode({ v = 1, entries = { { key = "r1:1:abcd", state = "committed" } } })
  files[base .. "_trade.lua"] = SaveSerializer.encode({ v = 1, entries = { { room = "r2", digest = "ff" } } })
  SaveData.resetSlotState()
  local main = SaveData.saveFilename(version)
  T.check(main ~= flat, version .. ": the flat save moved into a slot (" .. tostring(main) .. ")")
  local pending = Txn.readJournal(version)
  T.eq(#pending, 1, version .. ": the committed cross-gen trade journal follows the save")
  T.eq(pending[1] and pending[1].key, "r1:1:abcd", version .. ": with its entry")
  T.eq(files[base .. "_xtrade.lua"], nil, version .. ": no orphan journal stays at the old path")
  local nbase = main:gsub("%.lua$", "")
  T.check(files[nbase .. "_trade.lua"] ~= nil, version .. ": the link trade journal follows too")
  T.eq(files[base .. "_trade.lua"], nil, version .. ": and leaves the old path")
end

love.filesystem = realFS
T.finish()
