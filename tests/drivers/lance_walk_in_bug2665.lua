-- scripts/LancesRoom.asm:96
-- scripts/LancesRoom.asm:111
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local ok = true

  local function check(label, cond)
    print((cond and "PASS " or "FAIL ") .. label)
    if not cond then ok = false end
    return cond
  end

  local function finish()
    U.wait(5)
    love.event.quit(ok and 0 or 1)
    while true do coroutine.yield() end
  end

  local mon = Pokemon.new(game.data, "MEWTWO", 100)
  game.save.party = { mon }
  game.save.flags.EVENT_BEAT_LANCE = nil
  game.save.flags.EVENT_LANCES_ROOM_LOCK_DOOR = nil

  U.teleport(game, "LANCES_ROOM", 24, 16, "up")
  local ow = game.overworld
  if not check("2665 overworld up in LANCES_ROOM", ow and ow.map.id == "LANCES_ROOM") then
    return finish()
  end

  local shots = {
    ["21,16"] = "2665_01_left_off_the_stairs.png",
    ["18,20"] = "2665_02_down_the_right_corridor.png",
    ["12,23"] = "2665_03_left_along_the_bottom.png",
    ["6,16"] = "2665_04_up_the_middle_column.png",
  }
  local cells = { "24,16" }
  local lastKey = "24,16"
  for _ = 1, 20000 do
    local p = ow.player
    local key = p.cellX .. "," .. p.cellY
    if key ~= lastKey then
      cells[#cells + 1] = key
      lastKey = key
      if shots[key] then
        U.still(game, DIR .. "/" .. shots[key])
        shots[key] = nil
      end
    end
    if #(ow.scriptMoves or {}) == 0 and #cells > 1 and not p.moving then break end
    U.wait(1)
  end

  local expected = { "24,16" }
  local x, y = 24, 16
  local D = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 } }
  for _, seg in ipairs({ { "left", 6 }, { "down", 7 }, { "left", 12 }, { "up", 12 } }) do
    for _ = 1, seg[2] do
      x, y = x + D[seg[1]][1], y + D[seg[1]][2]
      expected[#expected + 1] = x .. "," .. y
    end
  end
  check("2665 first step leaves the stairs going left", cells[2] == "23,16")
  check("2665 walk-in follows the reversed WalkToLance list cell for cell",
        table.concat(cells, " ") == table.concat(expected, " "))
  if table.concat(cells, " ") ~= table.concat(expected, " ") then
    U.log("got", table.concat(cells, " "))
  end
  check("2665 lands on (6,11)", ow.player.cellX == 6 and ow.player.cellY == 11)
  check("2665 door locks on landing", game.save.flags.EVENT_LANCES_ROOM_LOCK_DOOR == true)
  check("2665 door blocks closed", ow.map:blockAt(2, 6) == 0x72 and ow.map:blockAt(3, 6) == 0x73)
  U.wait(10)
  U.still(game, DIR .. "/2665_05_landed_door_locked.png")

  finish()
end
