local probes = require("tests.gen2_crystal_rom_probes")

return function(game)
  local ok, passed = pcall(probes, game.data)
  if not ok then
    print("FAIL Crystal ROM probes: " .. tostring(passed))
    love.event.quit(1)
    return
  end
  love.event.quit(passed and 0 or 1)
end
