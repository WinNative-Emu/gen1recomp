package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local function check(ok, label)
  assert(ok, "FAIL walkfaster3017 " .. label)
  print("PASS walkfaster3017 " .. label)
end
local DIRS = { [0x35] = "down", [0x36] = "up", [0x37] = "left", [0x38] = "right" }
-- pokeruby/src/event_object_movement.c:8100
-- pokeemerald/src/event_object_movement.c:5894
for _, case in ipairs({ { "sapphire", 4 }, { "ruby", 4 }, { "emerald", 4 }, { "firered", nil } }) do
  local version, want = case[1], case[2]
  require("src.core.GameVersion").set(version)
  require("src.import.gba.versions").select(version)
  local Movement = require("src.core.game3.scripting.movement")
  for b, dir in pairs(DIRS) do
    local act = Movement.decodeAction(b)
    check(act.kind == "step" and act.dir == dir and act.frames == want,
      string.format("%s 0x%02X %s frames=%s", version, b, dir, tostring(want)))
  end
end
print("PASS walkfaster3017")
