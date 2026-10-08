package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
love = love or require("tests.love_stub")

local noop = function() end
local family = "rse"
local mapType = 1
local forced = false

package.loaded["src.core.game3.pokemon"] = {
  FRIENDSHIP_EVENT_WALKING = 0,
  FRIENDSHIP_EVENT_FAINT_OUTSIDE_BATTLE = 1,
  adjustFriendship = noop,
  currentMapSec = function() return 0 end,
  displayMonName = function(mon) return mon.name or "MON" end,
}
package.loaded["src.core.game3.rom_text"] = { box = function(key) return key end }
package.loaded["src.core.game3.field_semantics"] = {
  var = function(_, name) return name end,
  getVar = function() return 0 end,
  setVar = noop,
}
package.loaded["src.core.game3.field_modules"] = { enabled = function() return false end }
package.loaded["src.core.game3.profile"] = {
  family = function() return family end,
  forSession = function() return { field = {} } end,
}
package.loaded["src.core.game3.capabilities"] = { gate = function() return false end }
package.loaded["src.core.game3.rs.rematch"] = { enabled = function() return false end }
package.loaded["src.core.game3.faraway_island"] = { updateStepCounter = noop }
package.loaded["src.core.game3.mystery_gift"] = { incrementNewsStepCounter = noop }
package.loaded["src.core.game3.rse.init"] = { call = noop, isRse = function() return family == "rse" end }
package.loaded["src.core.game3.player"] = { cellX = 0, cellY = 0 }
package.loaded["src.core.game3.forced_movement"] = {
  isForced = function() return forced end,
  isForcedMovementTile = function() return false end,
}
package.loaded["src.core.game3.map"] = {
  currentDef = function() return { mapType = mapType } end,
}
package.loaded["src.core.game3.se_ids"] = { SE_FIELD_POISON = 1 }
package.loaded["src.core.game3.audio"] = { playSe = noop, fadeOutBgm = noop }
package.loaded["src.core.game3.special_scene_rse"] = { countSSTidalStep = function() return false end }
package.loaded["src.core.game3.safari"] = { takeStep = function() return false end }
package.loaded["src.core.game3.daycare"] = { step = function() return nil end }

local StepEvents = require("src.core.game3.step_events")

local function session(steps)
  return {
    vars = { poisonSteps = steps },
    party = { { name = "TORCHIC", hp = 30, status = "PSN" } },
  }
end

local function walk(s, n)
  for _ = 1, n do
    StepEvents.onStepTaken(s, {})
    StepEvents.flush()
  end
end

family, mapType, forced = "rse", 9, false
local s = session(3)
walk(s, 12)
eq(s.party[1].hp, 30, "rse secret base: poison never bites")
eq(s.vars.poisonSteps, 3, "rse secret base: counter is not advanced")

mapType = 8
s = session(3)
walk(s, 1)
eq(s.party[1].hp, 29, "rse indoor: poison bites on the step the counter wraps")
s = session(0)
walk(s, 4)
eq(s.party[1].hp, 29, "rse: one bite per 4 steps")
walk(s, 4)
eq(s.party[1].hp, 28, "rse: next bite 4 steps later")

forced = true
s = session(3)
walk(s, 6)
eq(s.party[1].hp, 30, "rse forced step: poison skipped")
eq(s.vars.poisonSteps, 3, "rse forced step: counter is not advanced")
forced = false

family, mapType = "frlg", 1
s = session(0)
walk(s, 4)
eq(s.party[1].hp, 30, "frlg: no bite after 4 steps")
eq(s.vars.poisonSteps, 4, "frlg: counter at 4")
walk(s, 1)
eq(s.party[1].hp, 29, "frlg: bite on the 5th step")
walk(s, 5)
eq(s.party[1].hp, 28, "frlg: next bite 5 steps later")

StepEvents.flush()
T.finish("game3_field_poison_step_gate")
