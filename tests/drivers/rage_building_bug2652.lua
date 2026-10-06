-- engine/battle/core.asm:3227
-- engine/battle/core.asm:4913
local U = require("tests.drivers.util")
local Battle = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Version = require("src.core.GameVersion")

return function(game)
  local deadline = love.timer.getTime() + 25
  local old = {}
  for _, k in ipairs({ "writeSave", "writeOptions", "persistOptions" }) do old[k] = rawget(game, k) end
  local keys = { "save", "saveOptions", "saveLiveOptions", "writeSlot", "writeCartSlot" }
  local writers = {}
  for _, k in ipairs(keys) do writers[k] = SaveData[k] end
  local volume = love.audio.getVolume()
  local fails = 0
  local function check(label, ok)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end

  local ok, err = xpcall(function()
    assert(Version.generation() == 1, "Gen1 required")
    local out = assert(os.getenv("POKEPORT_SHOT_DIR"), "shot directory required")
    local function forbidden() error("#2652 unexpected persistent write") end
    for _, k in ipairs({ "writeSave", "writeOptions", "persistOptions" }) do game[k] = forbidden end
    for _, k in ipairs(keys) do SaveData[k] = forbidden end
    love.audio.setVolume(0)

    local function wait(n)
      for _ = 1, n do
        assert(love.timer.getTime() < deadline, "#2652 deadline")
        U.wait(1)
      end
    end
    local function fullyTyped(b)
      local row = b.shown and b.shown[#b.shown]
      return b.current and row and b.codes and #row == #b.codes and b.lineIndex == #b.lines
        and b.total and b.total > 0 and b.charIndex >= b.total and not b.scrollPx and not b.msgWaiting
    end
    local function move(id)
      local def = assert(game.data.moves[id], "required imported move " .. id)
      return { id = id, pp = def.pp, maxPp = def.pp }
    end

    game:startNewGame({ intro = false })
    game.save.options.animations = false
    game.save.options.textSpeed = 1
    U.teleport(game, "PALLET_TOWN", 9, 7, "down")
    local player = Pokemon.new(game.data, "WARTORTLE", 30)
    player.moves = { move("SURF") }
    game.save.party = { player }
    local battle = Battle.newWild(game, "CHARMELEON", 50)
    battle.enemy.mon.moves = { move("RAGE") }
    battle.enemy.curMoves = battle.enemy.mon.moves
    battle.enemy.rageMove = battle.enemy.curMoves[1]
    battle.rng = function(a) return a or 0 end

    local seen = {}
    local seenRows = {}
    local update = battle.update
    battle.update = function(self, ...)
      update(self, ...)
      local row = self.current
      if row and row.text and not seenRows[row] then
        seenRows[row] = true
        seen[#seen + 1] = row.text
      end
    end
    game.stack:push(battle)

    local function advanceUntil(fn, label)
      for _ = 1, 3000 do
        if fn() then return true end
        if battle.current and not battle.current.auto and fullyTyped(battle) then U.tap(game, "a") end
        wait(1)
      end
      error(label)
    end
    local function settledOn(fragment)
      return function()
        return battle.current and battle.current.text
          and battle.current.text:find(fragment, 1, true) and fullyTyped(battle)
      end
    end
    local function pickSurf()
      advanceUntil(function() return battle.phase == "menu" end, "menu did not settle")
      U.tap(game, "a")
      advanceUntil(function() return battle.phase == "moveSelect" end, "move list missing")
      U.tap(game, "a")
    end
    local function find(needle, from)
      for i = from or 1, #seen do
        if seen[i]:find(needle, 1, true) then return i end
      end
    end

    pickSurf()
    local surfAt = #seen + 1
    advanceUntil(settledOn("RAGE is building!"), "rage page never settled")
    assert(U.still(game, out .. "/2654_01_rage_after_super_effective.png"), "capture failed")
    U.tap(game, "a")
    advanceUntil(settledOn("ATTACK rose!"), "rose page never settled")
    assert(U.still(game, out .. "/2654_02_attack_rose.png"), "capture failed")

    local used = find("used SURF", surfAt)
    local super = find("super", used)
    local rage = find("RAGE is building!", used)
    local rose = find("ATTACK rose!", used)
    check("#2654 Surf, super effective, rage and rose pages all shown", used and super and rage and rose)
    check("#2654 super effective prints before RAGE is building", super and rage and super < rage)
    check("#2654 ATTACK rose prints after RAGE is building", rage and rose and rage < rose)
    check("#2654 rage raised the enemy attack stage", (battle.enemy.stages.attack or 0) >= 1)

    advanceUntil(function() return battle.phase == "menu" end, "turn 1 did not finish")
    battle.enemy.mon.hp, battle.enemy.shownHP = 1, 1
    local koFrom = #seen + 1
    pickSurf()
    advanceUntil(settledOn("fainted!"), "faint page never settled")
    assert(U.still(game, out .. "/2652_03_ko_faint_no_rage.png"), "capture failed")
    local koUsed = find("used SURF", koFrom)
    check("#2652 the KO turn reached Surf and the faint page", koUsed ~= nil)
    check("#2652 no RAGE is building page on the fainting hit", koUsed and find("RAGE is building!", koUsed) == nil)
    check("#2652 no ATTACK rose page on the fainting hit", koUsed and find("rose!", koUsed) == nil)

    U.teleport(game, "PALLET_TOWN", 9, 7, "down")
  end, debug.traceback)
  for _, k in ipairs({ "writeSave", "writeOptions", "persistOptions" }) do game[k] = old[k] end
  for _, k in ipairs(keys) do SaveData[k] = writers[k] end
  love.audio.setVolume(volume)
  if not ok then print("FAIL #2652 " .. tostring(err)) end
  love.event.quit((ok and fails == 0) and 0 or 1)
end
