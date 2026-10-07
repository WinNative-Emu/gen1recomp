--   luajit tests/engine/options_size_budget_2694.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local ModIndex = require("src.mods.ModIndex")
local ModUpdate = require("src.mods.ModUpdate")

local OPTIONS = "options.lua"
local BUDGET = 32 * 1024

local function memfs()
  local files = {}
  return {
    files = files,
    write = function(path, content) files[path] = content return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] ~= nil then return { type = "file", size = #files[path] } end
      return nil
    end,
  }
end

local realLoad, realSave, realFs = SaveData.loadOptions, SaveData.saveOptions, SaveData.persistenceFs
local fs

local function resetCaches()
  if ModIndex._resetCacheForTests then ModIndex._resetCacheForTests() end
  if ModUpdate._resetCacheForTests then ModUpdate._resetCacheForTests() end
end

local function useFs(f)
  fs = f
  resetCaches()
end

SaveData.persistenceFs = function(f) return f or fs end
SaveData.loadOptions = function(f) return realLoad(f or fs) end
SaveData.saveOptions = function(o, f) return realSave(o, f or fs) end

local function bigIndex(n)
  local mods = {}
  for i = 1, n do
    mods[i] = { id = ("author%d@mod%d"):format(i, i), name = ("Mod number %d"):format(i),
      description = ("A fairly long description for mod %d that pads the entry out"):format(i),
      github = ("author%d/mod%d"):format(i, i), tags = { "GAMEPLAY", "ART" },
      versions = { "red", "blue", "yellow" } }
  end
  return { generatedAt = "2026-10-06T00:00:00Z", categories = { "GAMEPLAY", "ART" },
    baseGames = { "red" }, mods = mods, carts = {} }
end

local feed = ModIndex.resolveSource("bryanthaboi/gen1recomp-mod-index").feed

do
  useFs(memfs())
  realSave({ battleLayout = "wide" }, fs)
  check(ModIndex.writeCache(feed, bigIndex(2000)), "writeCache reports success")
  local opts = SaveData.loadOptions()
  opts.speedOverworld = 2
  check(SaveData.saveOptions(opts) ~= nil, "a hotkey-style full options write lands")
  local size = #(fs.files[OPTIONS] or "")
  check(size > 0 and size < BUDGET,
    ("options.lua stays under budget after an index fetch (%d bytes)"):format(size))
  local entry = ModIndex.readCache(feed)
  eq(entry and #entry.mods, 2000, "the index cache still reads back every mod")
  eq(SaveData.loadOptions().battleLayout, "wide", "unrelated options survive")
  resetCaches()
  entry = ModIndex.readCache(feed)
  eq(entry and #entry.mods, 2000, "the index cache survives a fresh session")
end

do
  useFs(memfs())
  check(ModUpdate.writeCache("someone/somemod",
    { { version = "1.0.0", tag = "v1.0.0", body = string.rep("notes ", 2000), downloads = 3 } }),
    "ModUpdate.writeCache reports success")
  local size = #(fs.files[OPTIONS] or "")
  check(size < 1024, ("release notes do not land in options.lua (%d bytes)"):format(size))
  local entry = ModUpdate.readCache("someone/somemod")
  eq(entry and entry.releases[1].version, "1.0.0", "the release cache reads back")
end

do
  useFs(memfs())
  local legacy = bigIndex(2000)
  legacy.checkedAt, legacy.version = os.time(), ModIndex.CACHE_VERSION
  fs.write(OPTIONS, SaveSerializer.encode({ battleLayout = "wide",
    modIndexCache = { [feed] = legacy },
    modUpdateCache = { ["someone/somemod"] = { checkedAt = os.time(),
      releases = { { version = "2.0.0", body = string.rep("x", 4000) } } } } }))
  check(#fs.files[OPTIONS] > BUDGET, "the legacy fixture is over budget")
  local direct = SaveData.loadOptions()
  eq(direct.modIndexCache, nil, "a direct boot never loads the legacy index listing")
  eq(direct.modUpdateCache, nil, "nor the legacy release cache")
  direct.speedOverworld = 2
  SaveData.saveOptions(direct)
  check(#fs.files[OPTIONS] < BUDGET,
    ("a direct-boot options write drops the legacy blob (%d bytes)"):format(#fs.files[OPTIONS]))
  fs.write(OPTIONS, SaveSerializer.encode({ battleLayout = "wide",
    modIndexCache = { [feed] = legacy },
    modUpdateCache = { ["someone/somemod"] = { checkedAt = os.time(),
      releases = { { version = "2.0.0", body = string.rep("x", 4000) } } } } }))
  useFs(fs)
  resetCaches()
  local entry = ModIndex.readCache(feed)
  eq(entry and #entry.mods, 2000, "a legacy options cache migrates into the cache file")
  check(fs.files[ModUpdate.CACHE_FILE] ~= nil,
    "the index migration moves the release cache before stripping options")
  local upd = ModUpdate.readCache("someone/somemod")
  eq(upd and upd.releases[1].version, "2.0.0", "a legacy release cache migrates")
  local size = #(fs.files[OPTIONS] or "")
  check(size < BUDGET, ("the legacy key leaves options.lua (%d bytes)"):format(size))
  local opts = SaveData.loadOptions()
  check(type(opts.modIndexCache) ~= "table" or next(opts.modIndexCache) == nil,
    "options no longer carry the index listing")
  eq(opts.battleLayout, "wide", "migration keeps the player's settings")
  check(fs.files[ModIndex.CACHE_FILE] ~= nil, "the index cache file exists")
  check(fs.files[ModUpdate.CACHE_FILE] ~= nil, "the release cache file exists")
end

SaveData.loadOptions, SaveData.saveOptions, SaveData.persistenceFs = realLoad, realSave, realFs
T.finish()
