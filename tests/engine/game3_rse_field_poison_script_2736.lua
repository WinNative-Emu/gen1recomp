package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local noop = function() end
local profileField
local started = {}
local vm = { active = false }

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
  family = function() return profileField and "rse" or "frlg" end,
  forSession = function() return { field = profileField } end,
}
package.loaded["src.core.game3.capabilities"] = { gate = function() return false end }
package.loaded["src.core.game3.rs.rematch"] = { enabled = function() return false end }
package.loaded["src.core.game3.faraway_island"] = { updateStepCounter = noop }
package.loaded["src.core.game3.mystery_gift"] = { incrementNewsStepCounter = noop }
package.loaded["src.core.game3.rse.init"] = { call = noop, isRse = function() return profileField ~= nil end }
package.loaded["src.core.game3.player"] = { cellX = 0, cellY = 0 }
package.loaded["src.core.game3.forced_movement"] = {
  isForced = function() return false end,
  isForcedMovementTile = function() return false end,
}
package.loaded["src.core.game3.se_ids"] = { SE_FIELD_POISON = 1 }
package.loaded["src.core.game3.audio"] = { playSe = noop, fadeOutBgm = noop }
package.loaded["src.core.game3.special_scene_rse"] = { countSSTidalStep = function() return false end }
package.loaded["src.core.game3.safari"] = { takeStep = function() return false end }
package.loaded["src.core.game3.daycare"] = { step = function() return nil end }
package.loaded["src.core.game3.scripting.space"] = {
  vm = vm,
  scriptKey = function(name) return name end,
  startScript = function(key)
    started[#started + 1] = key
    vm.active = true
    return true
  end,
}

local StepEvents = require("src.core.game3.step_events")

local function poisonedSession()
  return {
    vars = { poisonSteps = 3 },
    party = {
      { name = "TORCHIC", hp = 1, status = "PSN" },
      { name = "MUDKIP", hp = 20 },
    },
  }
end

local function types()
  local out = {}
  for i, ev in ipairs(StepEvents._queue) do out[i] = ev.type end
  return table.concat(out, ",")
end

for _, case in ipairs({
  { name = "emerald", field = require("src.core.game3.profiles.emerald.field"), script = "EventScript_FieldPoison" },
  { name = "rs", field = require("src.core.game3.profiles.rs.field"), script = "gUnknown_081A14B8" },
}) do
  StepEvents.flush()
  started = {}
  vm.active = false
  profileField = case.field
  eq(case.field.fieldPoisonScript, case.script, case.name .. " profile names the cart field poison script")
  local session = poisonedSession()
  StepEvents.onStepTaken(session, {})
  local mon = session.party[1]
  eq(mon.hp, 0, case.name .. ": poison step takes the last HP")
  eq(mon.status, "PSN", case.name .. ": status is left for the script's faint check")
  eq(types(), "field_poison_script", case.name .. ": only the field poison script is queued")
  StepEvents.update(1 / 60, {})
  eq(started[1], case.script, case.name .. ": the step starts " .. case.script)
  check(StepEvents.busy(), case.name .. ": step events stay busy while the script runs")
  StepEvents.update(1 / 60, {})
  check(StepEvents.busy(), case.name .. ": still busy on the next frame")
  vm.active = false
  for _ = 1, 8 do StepEvents.update(1 / 60, {}) end
  check(not StepEvents.busy(), case.name .. ": step events release once the script ends")
end

StepEvents.flush()
started = {}
profileField = nil
local session = poisonedSession()
session.vars.poisonSteps = 4
StepEvents.onStepTaken(session, {})
eq(types(), "poison_faint,poison_white_out", "firered keeps the Lua faint + white out events")
eq(session.party[1].status, nil, "firered clears status at faint time")
eq(#started, 0, "firered starts no script")
StepEvents.flush()

T.finish("game3_rse_field_poison_script_2736")
