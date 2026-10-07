local U = require("tests.drivers.util")

local failed = false
local function expect(cond, label)
  print((cond and "PASS " or "FAIL ") .. label)
  if not cond then failed = true end
end

local function key(k)
  love.keypressed(k, k, false)
  love.keyreleased(k, k)
end

return function(game)
  U.wait(45)
  expect(game.world and game.world.map ~= nil, "gold_world_booted")
  game.speedOverride = nil
  game.options.speed = 1
  key("1")
  expect(game.options.speed == 2, "gold_1_raises")
  key("1")
  expect(game.options.speed == 3, "gold_1_raises_again")
  key("0")
  expect(game.options.speed == 2, "gold_0_lowers")
  expect(game:logicSpeed() == 2, "gold_logic_follows_0")
  key("kp0")
  expect(game.options.speed == 1, "gold_numpad_0_lowers")
  local saved = require("src.core.SaveData").loadOptions()
  expect(saved.speed == 1 or saved.speedOverworld == 1, "gold_0_persists")
  game.linkNet = { closed = false }
  game.options.speed = 3
  key("0")
  expect(game.options.speed == 3, "gold_0_ignored_in_link")
  game.linkNet = nil
  game.speedOverride = 1
  love.event.quit(failed and 1 or 0)
end
