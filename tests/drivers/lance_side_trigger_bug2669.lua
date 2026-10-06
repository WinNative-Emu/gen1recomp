-- scripts/LancesRoom.asm:54
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

  local function findLance(ow)
    for _, npc in ipairs(ow.npcs or {}) do
      if npc.def and npc.def.name == "LANCESROOM_LANCE" then return npc end
    end
  end

  local function approach(fromX, fromY, dir, label, shotName)
    U.teleport(game, "LANCES_ROOM", fromX, fromY, dir)
    local ow = game.overworld
    if not check(label .. " overworld up in LANCES_ROOM", ow and ow.map.id == "LANCES_ROOM") then
      return false
    end
    local lance = findLance(ow)
    if not check(label .. " Lance present", lance ~= nil) then return false end
    check(label .. " Lance starts facing down", lance.facing == "down")
    U.hold(game, dir, 4)
    local opened = false
    for _ = 1, 600 do
      if game.stack:top() ~= ow then opened = true break end
      U.wait(1)
    end
    check(label .. " pre-battle text opens", opened)
    U.wait(40)
    check(label .. " Lance still faces down during his text", lance.facing == "down")
    if lance.facing ~= "down" then U.log(label, "lance facing", lance.facing) end
    U.still(game, DIR .. "/" .. shotName)
    return true
  end

  game.save.party = { Pokemon.new(game.data, "MEWTWO", 100) }
  game.save.flags.EVENT_BEAT_LANCE = nil
  game.save.flags.EVENT_LANCES_ROOM_LOCK_DOOR = true

  approach(5, 2, "up", "2669 side (5,1)", "2669_01_side_tile_lance_faces_down.png")
  approach(6, 3, "up", "2669 front (6,2)", "2669_02_front_tile_lance_faces_down.png")

  finish()
end
