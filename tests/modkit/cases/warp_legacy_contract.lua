package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Version = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Profile = require("src.core.game3.profile")

local function noop() end

do
  local WorldAPI = require("src.world.gen2.WorldAPI")
  local seen
  local world = { map = { id = "A" }, maps = { A = true, B = true }, player = { facing = "up" },
    warpToMapId = function(_, _, _, _, _, opts) seen = { opts = opts } return true end }
  local api = WorldAPI.new({ world = world }, "legacy")
  T.eq(api:warpTo("B", 1, 2, "down", { arrive = "fly", onDone = noop }), true, "gen2 warpTo accepted")
  T.eq(seen.opts, nil, "gen2 warpTo hands warpToMapId no opts for API 1 and 2 mods")
  api:_warpToWith("B", 1, 2, "down", { arrive = "fly", onDone = noop })
  T.eq(seen.opts and seen.opts.arrive, "fly", "gen2 API 3 path forwards opts")
end

Version.set("firered")
Versions.select("firered")
Profile.reset()
local savedField, savedRuntime, savedWarp = package.loaded["src.core.game3.field"],
  package.loaded["src.core.game3.runtime"], package.loaded["src.core.game3.warp"]
local requests = {}
package.loaded["src.core.game3.field"] = { running = true }
package.loaded["src.core.game3.runtime"] = { getSession = function() return { version = "firered" } end }
package.loaded["src.core.game3.warp"] = { request = function(_, _, raw, x, y, facing, opts)
  requests[#requests + 1] = { raw = raw, opts = opts }
  return true
end }
do
  local WorldAPI = require("src.world.game3.WorldAPI")
  local api = WorldAPI.new({}, "legacy")
  local function lastOpts() return requests[#requests].opts end
  T.eq(api:warpTo("FR_OAKS_LAB", 1, 2, "down", { arrive = "teleport", onDone = noop, keepMusic = true }), true,
    "gen3 warpTo accepted")
  local opts = lastOpts()
  T.eq(opts.teleport, true, "gen3 legacy warpTo keeps the native teleport sequence")
  T.eq(opts.onDone, nil, "gen3 legacy warpTo does not forward onDone")
  T.eq(opts.keepMusic, nil, "gen3 legacy warpTo does not forward keepMusic")
  T.eq(opts.arrive, nil, "gen3 legacy warpTo does not route through the portable path")
  api:_warpToWith("FR_OAKS_LAB", 1, 2, "down", { arrive = "teleport", onDone = noop })
  opts = lastOpts()
  T.eq(opts.arrive, "teleport", "gen3 API 3 path forwards arrive")
  T.eq(opts.onDone, noop, "gen3 API 3 path forwards onDone")
  local Compat = require("src.mods.Gen3Compat")
  Compat.bind(function() return {} end)
  local ow = Compat.resolve("src.world.OverworldController", "old_mod", 2)
  ow.startWarpTo("FR_OAKS_LAB", 1, 2, "down", noop, { arrive = "teleport", keepMusic = true })
  local legacy = lastOpts()
  T.eq(legacy.onDone, nil, "OverworldState.startWarpTo drops onDone for API 2 claimants")
  T.eq(legacy.teleport, true, "OverworldState.startWarpTo keeps the teleport sequence for API 2 claimants")
  Compat.resolve("src.world.OverworldController", "new_mod", 3)
  ow.startWarpTo("FR_OAKS_LAB", 1, 2, "down", noop, { arrive = "teleport", keepMusic = true })
  local modern = lastOpts()
  T.eq(modern.onDone, noop, "OverworldState.startWarpTo forwards onDone once an API 3 mod claims it")
  Compat.bind(nil)
end
package.loaded["src.core.game3.field"], package.loaded["src.core.game3.runtime"],
  package.loaded["src.core.game3.warp"] = savedField, savedRuntime, savedWarp
T.finish("warp legacy contract")
