local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")
local BattleState = require("src.ui.gen2.BattleState")
local NamingScreen = require("src.ui.gen2.NamingScreen")

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
    local version = (game.save and game.save.version) or "gen2"
    for _ = 1, 1200 do
      if game.world and game.world.map and not game.stack:top() then break end
      U.wait(1)
    end
    local world = assert(game.world, "no world")
    assert(world.map and not game.stack:top(), "world did not settle")

    local function new(species, attack)
      return assert(Mon.new(game.data, species, 5,
        { dvs = { attack = attack, defense = 10, speed = 10, special = 10 } }))
    end
    local function glyphFor(gender)
      if gender == "male" then return "\xe2\x99\x82" end
      if gender == "female" then return "\xe2\x99\x80" end
      return nil
    end

    local starter = new("CHIKORITA", 15)
    local named
    world:renameMon(starter, function(name) named = name end, { blank = true })
    U.wait(6)
    local screen = game.stack:top()
    check(screen and screen.screenId == "Gen2NamingScreen", "2708 starter keyboard open")
    check(screen and screen.iconImage ~= nil and screen.monIcon, "2708 starter icon present")
    check(starter.gender == "male", "2708 starter is male")
    check(screen and screen:genderGlyph() == glyphFor(starter.gender), "2708 starter gender drawn")
    local x, y = screen:iconOrigin()
    check(x == 16 and y == 12, "2708 icon at (16,12)")
    local f0 = screen:iconFrame()
    U.still(game, out .. "/2708_01_starter_nickname_icon_gender.png")
    local flipped = false
    for _ = 1, NamingScreen.ICON_FRAME_STEPS + 2 do
      U.wait(1)
      if screen:iconFrame() ~= f0 then flipped = true break end
    end
    check(flipped, "2708 icon frame toggles")
    U.still(game, out .. "/2708_01b_starter_nickname_other_frame.png")
    U.tap(game, "start") U.wait(3)
    U.tap(game, "a") U.wait(6)
    check(named ~= nil and game.stack:top() ~= screen, "2708 starter keyboard closes on END")

    local caught = new("SENTRET", 0)
    local advanced = false
    local fake = setmetatable({
      game = game,
      nicknameMon = caught,
      advanceQueue = function() advanced = true end,
    }, { __index = BattleState })
    BattleState.answerNickname(fake, true)
    U.wait(6)
    screen = game.stack:top()
    check(screen and screen.screenId == "Gen2NamingScreen", "2708 catch keyboard open")
    check(screen and screen.iconImage ~= nil and screen.monIcon, "2708 catch icon present")
    check(caught.gender == "female", "2708 catch is female")
    check(screen and screen:genderGlyph() == glyphFor(caught.gender), "2708 catch gender drawn")
    check(screen and screen.iconColors ~= nil, "2708 catch icon paletted")
    U.still(game, out .. "/2708_02_catch_nickname.png")
    U.tap(game, "start") U.wait(3)
    U.tap(game, "a") U.wait(6)
    check(advanced, "2708 catch keyboard hands back to the battle")
    print("2708 version " .. tostring(version))
  end, debug.traceback)
  if not ok then
    print("FAIL 2708 driver error: " .. tostring(err))
    fails = fails + 1
  end
  love.event.quit(fails == 0 and 0 or 1)
end
