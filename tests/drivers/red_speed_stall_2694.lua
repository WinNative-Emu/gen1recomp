local U = require("tests.drivers.util")
local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local ModIndex = require("src.mods.ModIndex")

local failed = false
local function expect(cond, label)
  print((cond and "PASS " or "FAIL ") .. label)
  if not cond then failed = true end
end

local function key(k)
  love.keypressed(k, k, false)
  love.keyreleased(k, k)
end

local function timePresses(n)
  local t = love.timer.getTime()
  for _ = 1, n do key("1") end
  return (love.timer.getTime() - t) / n * 1000
end

local function bigIndex(n)
  local mods = {}
  for i = 1, n do
    mods[i] = { id = ("author%d@mod%d"):format(i, i), name = ("Mod number %d"):format(i),
      description = ("A fairly long description for mod %d that pads the entry out"):format(i),
      github = ("author%d/mod%d"):format(i, i), tags = { "GAMEPLAY", "ART" } }
  end
  return { checkedAt = os.time(), version = ModIndex.CACHE_VERSION,
    generatedAt = "2026-10-06T00:00:00Z", categories = { "GAMEPLAY" },
    baseGames = { "red" }, mods = mods, carts = {} }
end

return function(game)
  U.newGame(game)
  game.speedOverride = nil
  local feed = ModIndex.resolveSource("bryanthaboi/gen1recomp-mod-index").feed
  game.save.options.speedOverworld = 1
  game:writeOptions()
  local small = timePresses(10)
  print(("INFO per-press ms, no index cached: %.2f"):format(small))

  expect(small < 10, "red_speed_press_under_10ms")

  local fs = SaveData.persistenceFs()
  local legacy = SaveData.loadOptions()
  legacy.modIndexCache = { [feed] = bigIndex(1500) }
  SaveData.saveOptions(legacy)
  fs.write("options.lua", SaveSerializer.encode(legacy))
  local seeded = fs.getInfo("options.lua")
  print(("INFO options.lua bytes with the legacy blob: %d"):format(seeded and seeded.size or 0))
  expect(seeded and seeded.size > 32 * 1024, "red_legacy_blob_seeded")
  if ModIndex._resetCacheForTests then ModIndex._resetCacheForTests() end
  local entry = ModIndex.readCache(feed)
  expect(entry and #entry.mods == 1500, "red_index_cache_still_reads")
  game.save.options = SaveData.loadOptions()
  expect(game.save.options.modIndexCache == nil, "red_live_options_never_carry_the_index")
  game.save.options.speedOverworld = 1
  local heavy = timePresses(10)
  print(("INFO per-press ms, 1500-mod index cached: %.2f"):format(heavy))
  expect(heavy < small * 3 + 2, "red_speed_press_cost_independent_of_index")
  expect(heavy < 10, "red_speed_press_with_index_under_10ms")
  local info = fs.getInfo("options.lua")
  local size = info and info.size or 0
  print(("INFO options.lua bytes: %d"):format(size))
  expect(size > 0 and size < 32 * 1024, "red_options_lua_stays_small")
  game.speedOverride = 1
  love.event.quit(failed and 1 or 0)
end
