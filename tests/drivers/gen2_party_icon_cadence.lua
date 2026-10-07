local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")
local PartyMenu = require("src.ui.gen2.PartyMenu")

return function(game)
  local fails = 0
  local function check(cond, label)
    print((cond and "PASS " or "FAIL ") .. label)
    if not cond then fails = fails + 1 end
    return cond
  end
  local ok, err = xpcall(function()
    local identity = os.getenv("POKEPORT_IDENTITY") or ""
    assert(identity ~= "" and identity ~= "pokemon-love2d", "isolated identity required")
    local out = assert(os.getenv("POKEPORT_SHOT_DIR"), "shot dir required")
    for _ = 1, 1200 do
      if game.world and game.world.map and not game.stack:top() then break end
      U.wait(1)
    end
    assert(game.world and game.world.map and not game.stack:top(), "world did not settle")

    local function new(species, fraction)
      local m = assert(Mon.new(game.data, species, 30))
      local maxHp = m.maxHp or (m.stats and m.stats.hp)
      m.hp = math.floor(maxHp * fraction)
      return m
    end
    local save = game.save
    save.party = {
      new("CYNDAQUIL", 1.0),
      new("TOTODILE", 0.3),
      new("CHIKORITA", 0.1),
      new("PIDGEY", 0),
    }
    check(PartyMenu.iconHpBand(save.party[1]) == "green", "S3 slot 1 green")
    check(PartyMenu.iconHpBand(save.party[2]) == "yellow", "S3 slot 2 yellow")
    check(PartyMenu.iconHpBand(save.party[3]) == "red", "S3 slot 3 red")
    check(PartyMenu.iconHpBand(save.party[4]) == "red", "S3 slot 4 fainted is red")

    local menu = PartyMenu.new(game, { party = save.party })
    game.stack:push(menu)
    U.wait(2)
    check(game.stack:top() == menu, "S3 party list open")

    local function frames()
      local t = {}
      for i, m in ipairs(save.party) do t[i] = menu:iconFrame(m) end
      return t
    end
    local function waitClock(target)
      for _ = 1, 400 do
        if menu.clock >= target then return end
        U.wait(1)
      end
    end

    waitClock(4)
    local a = frames()
    U.still(game, out .. "/s3_01_all_frame0.png")
    check(a[1] == 0 and a[2] == 0 and a[3] == 0 and a[4] == 0, "S3 all icons start on frame 0")

    waitClock(10)
    local b = frames()
    U.still(game, out .. "/s3_02_green_flipped_tick10.png")
    check(b[1] == 1 and b[2] == 0 and b[3] == 0, "S3 green flips after 9 ticks, others hold")

    waitClock(74)
    local c = frames()
    U.still(game, out .. "/s3_03_yellow_flipped_tick74.png")
    check(c[2] == 1 and c[3] == 0, "S3 yellow flips after 73 ticks, red holds")

    waitClock(138)
    local d = frames()
    U.still(game, out .. "/s3_04_red_flipped_tick138.png")
    check(d[3] == 1 and d[4] == 1, "S3 red and fainted flip after 137 ticks")

    game.stack:pop()
    U.wait(2)
  end, debug.traceback)
  if not ok then
    print("FAIL S3 driver error: " .. tostring(err))
    fails = fails + 1
  end
  love.event.quit(fails == 0 and 0 or 1)
end
