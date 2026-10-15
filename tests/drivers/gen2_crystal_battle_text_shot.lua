local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")

return function(game)
  local ok, err = xpcall(function()
    local identity = os.getenv("POKEPORT_IDENTITY") or ""
    assert(identity ~= "" and identity ~= "pokemon-love2d", "isolated identity required")
    local version = game.save.version
    local out = os.getenv("POKEPORT_SHOT_DIR") or "."
    game.writeSave = function() end
    for _ = 1, 1200 do
      if game.world and game.world.map and not game.stack:top() then break end
      U.wait(1)
    end
    local world = assert(game.world)
    local function new(species, ids)
      local moves = {}
      for _, id in ipairs(ids) do
        local d = assert(game.data.moves[id], id)
        moves[#moves + 1] = { id = id, pp = d.pp, maxPp = d.pp, ppUps = 0 }
      end
      return assert(Mon.new(game.data, species, 50, { moves = moves,
        dvs = { attack = 15, defense = 15, speed = 15, special = 15 } }))
    end
    local player, enemy = new("MEW", { "MIMIC", "HAZE" }), new("SNORLAX", { "SPLASH" })
    game.save.party = { player }
    assert(world:startBattle({ wild = enemy }), "wild battle failed")
    local screen
    for _ = 1, 1200 do
      screen = game.stack:top()
      if screen and screen.screenId == "Gen2BattleState" and screen.battle then break end
      U.wait(1)
    end
    assert(screen and screen.battle, "BattleState required")
    local function menu()
      for _ = 1, 5000 do
        if screen.phase == "menu" and #screen.queue == 0 and not screen.anim then return end
        U.tap(game, "a"); U.wait(1)
      end
      error("menu did not settle")
    end
    local function shown(needle, name)
      for _ = 1, 5000 do
        if screen.message and screen.message:find(needle, 1, true) then
          for _ = 1, 2000 do
            if not screen:syncTyper() and screen:messageArrowVisible() then
              U.still(game, out .. "/crystal_text_" .. version .. "_" .. name .. ".png")
              return screen.message
            end
            U.wait(1)
          end
          error("dialog did not finish typing " .. needle)
        end
        U.tap(game, "a"); U.wait(1)
      end
      error("dialog missing " .. needle)
    end
    menu()
    local battle = screen.battle
    battle.random = function(n) if n == 256 then return 0 end return 0 end
    battle:volatile(enemy).lastMove = "SPLASH"
    assert(screen:chooseMenu("fight")); assert(screen:chooseMove(1))
    local learned = shown("learned", "01_mimic_learned")
    local mimic = shown("SPLASH", "02_mimic_move_name")
    local mimicOk = not learned:find("{", 1, true) and not mimic:find("{", 1, true)
    print((mimicOk and "PASS" or "FAIL") .. " Mimic line has the move name and no tokens: " .. mimic:gsub("\n", " / "))
    menu()
    assert(screen:chooseMenu("fight")); assert(screen:chooseMove(2))
    local haze = shown("eliminated", "03_haze_eliminated")
    local hazeOk = not haze:find("{", 1, true)
    print((hazeOk and "PASS" or "FAIL") .. " Haze line has no tokens: " .. haze:gsub("\n", " / "))
    assert(mimicOk and hazeOk, "token leaked into battle text")
  end, debug.traceback)
  if not ok then print("FAIL " .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
