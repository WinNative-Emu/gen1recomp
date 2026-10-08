local U = require("tests.drivers.util")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Project = require("src.online.xgen.Project")
local Datasets = require("src.online.xgen.Datasets")
local BattleSession = require("src.online.union.BattleSession")
local L = require("tests.support.g3u_loopback")
local GameVersion = require("src.core.GameVersion")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

local function ser(v)
  if type(v) ~= "table" then return type(v) .. ":" .. tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. ser(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

return function(game)
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. line)
  end
  local v = GameVersion.get()
  U.wait(10)

  local function mon(species, level, moves)
    local m = Pokemon.new(game.data, species, level)
    m.moves = {}
    for i, id in ipairs(moves) do m.moves[i] = { id = id, pp = game.data.moves[id].pp } end
    return m
  end
  game.save.party = { mon("CHANSEY", 50, { "POUND" }), mon("MEWTWO", 70, { "PSYCHIC_M", "SWIFT" }) }
  local room = game.data.maps.UNION_ROOM and "UNION_ROOM" or "VIRIDIAN_POKECENTER"
  game.save.lastOutdoor = { id = "VIRIDIAN_CITY", x = 10, y = 10 }
  if room == "UNION_ROOM" then
    U.teleport(game, room, 12, 20, "up")
  else
    U.teleport(game, room, 3, 4, "up")
  end
  game.overworld.lastOutdoor = game.save.lastOutdoor
  U.wait(10)
  ok(game.overworld.map.id == room, "standing in " .. room)
  SaveData.save(game.save)
  U.wait(2)

  local saveName = SaveData.saveFilename(v)
  local saveBefore = love.filesystem.read(saveName)
  local partyBefore = ser(game.save.party)
  local p = game.overworld.player
  local mapBefore, xBefore, yBefore = game.overworld.map.id, p.cellX, p.cellY

  local ds = assert(Datasets.get(v))
  local mine = {}
  for i, m in ipairs(game.save.party) do mine[i] = assert(Project.mon(m, ds)) end
  local theirs = {
    assert(Project.mon(mon("GEODUDE", 45, { "ROCK_THROW" }), ds)),
    assert(Project.mon(mon("MAGIKARP", 10, { "SPLASH" }), ds)),
  }

  local netA, netB = L.pair()
  local go = { seed = 4242, size = 3 }
  local gens = { [0] = 1, [1] = 3 }
  local names = { [0] = game.save.player.name, [1] = "BOT" }
  local bot = BattleSession.new({ net = netB, seat = 1, go = go, gens = gens, records = theirs, names = names })
  local allow = false
  local function stepBot()
    bot:update()
    if not allow then return end
    if bot.phase == "choose" then
      for _, act in ipairs(bot:legal()) do
        if act.kind == "move" then bot:choose(act) break end
      end
    elseif bot.phase == "replace" then
      local list = bot:legal()
      if list[1] then bot:pickReplacement(list[1].index) end
    end
  end

  local doneCount, doneResult = 0, nil
  local launched, how
  local okLaunch, Launch = pcall(require, "src.ui.g3u.Launch")
  if okLaunch then
    launched = Launch.start(game, 1, { ruleset = "g3u", net = netA, seat = 0, go = go, gens = gens, names = names,
      records = mine, onDone = function(r) doneCount = doneCount + 1 doneResult = r end })
    how = "Launch"
  end
  if not launched then
    local G = require("src.ui.g3u.Gen1Screen")
    local bs = BattleSession.new({ net = netA, seat = 0, go = go, gens = gens, data = ds, records = mine,
      names = names })
    launched = G.start(game, bs, { names = { me = names[0], foe = names[1] },
      onDone = function(r) doneCount = doneCount + 1 doneResult = r end })
    how = "Gen1Screen"
  end
  ok(launched ~= nil, "battle started via " .. tostring(how))

  local G = require("src.ui.g3u.Gen1Screen")
  local PartyMenu = require("src.ui.PartyMenu")
  local shots = {}
  local function shot(name)
    if shots[name] then return end
    shots[name] = true
    U.still(game, ("%s/%s_g3u_%s.png"):format(SHOT_DIR, v, name))
  end
  local function battle()
    for _, s in ipairs(game.stack.states) do
      if s.g3u then return s end
    end
    return nil
  end
  local function curText(b)
    return b and b.current and b.current.text or ""
  end

  local seenMenu, seenFaint, seenReplace, seenHit, seenBanner, seenEnd, seenWaiting = false, false, false, false,
    false, false, false
  local turns, myFaint = 0, false
  local lastPhase
  local held = 0
  for f = 1, 60000 do
    local bw = battle()
    if bw and bw.phase == "g3u" and bw.g3uWaiting then held = held + 1 else held = 0 end
    allow = held > 40
    stepBot()
    U.wait(1)
    if doneCount > 0 and game.stack:top() == game.overworld then break end
    local b = battle()
    local top = game.stack:top()
    if b and top == b then
      local t = curText(b)
      if t:find("UNION RULES", 1, true) and b.charIndex and b.total and b.charIndex >= b.total then
        seenBanner = true
        shot("01_banner")
      end
      if b.phase == "g3u" and b.g3uWaiting and not b.g3uEnding then
        seenWaiting = true
        shot("02b_waiting")
      end
      if b.phase == "moveSelect" and not shots["02_move_menu"] then
        seenMenu = true
        shot("02_move_menu")
      end
      if b.fx and b.fx.blink and b.enemy and b:fxHidden(b.enemy) and not shots["03_hit"] then
        seenHit = true
        shot("03_hit")
      end
      if b.fx and b.fx.faint and not shots["04_faint"] then
        seenFaint = true
        if b.fx.faint.battler and b.fx.faint.battler.isPlayer then myFaint = true end
        shot("04_faint")
      end
      if (t:find("defeated", 1, true) or t:find("lost to", 1, true)) and b.charIndex >= b.total then
        seenEnd = true
        shot("06_end_text")
      end
      if b.phase ~= lastPhase and b.phase == "menu" then turns = turns + 1 end
      lastPhase = b.phase
      if b.phase == "menu" then
        if b.menuIndex ~= 1 then U.tap(game, "up") U.tap(game, "left") else U.tap(game, "a") end
      elseif b.phase == "moveSelect" then
        if b.moveIndex ~= 1 then U.tap(game, "up") else U.tap(game, "a") end
      elseif b.phase == "messages" and f % 6 == 0 then
        U.tap(game, "a")
      end
    elseif getmetatable(top) == PartyMenu and b then
      seenReplace = true
      local party = top.party or {}
      if not top.submenu then
        local m = party[top.index]
        if m and m.hp <= 0 then
          U.tap(game, "down")
        else
          shot("05_replacement")
          U.tap(game, "a")
        end
      else
        U.tap(game, "a")
      end
      U.wait(4)
    elseif f % 6 == 0 then
      U.tap(game, "a")
    end
  end

  U.wait(30)
  shot("07_back_in_room")
  local after = game.overworld
  ok(doneCount == 1, "onDone called once (" .. doneCount .. ")")
  ok(doneResult ~= nil, "result " .. tostring(doneResult and doneResult.outcome) .. "/" ..
    tostring(doneResult and doneResult.why))
  ok(doneResult and doneResult.outcome == "win" and doneResult.why == "faint", "the strong side wins by faint")
  ok(seenBanner, "union rules banner shown")
  ok(seenMenu, "move menu opened")
  ok(seenHit, "a hit animation played")
  ok(seenFaint and myFaint, "a faint played (mine " .. tostring(myFaint) .. ")")
  ok(seenReplace, "replacement party menu opened")
  ok(seenEnd, "winner line shown")
  ok(seenWaiting, "waiting box shown between turns")
  ok(turns >= 3, "played several turns (" .. turns .. ")")
  ok(game.stack:top() == after, "back on the overworld")
  ok(after.map.id == mapBefore and after.player.cellX == xBefore and after.player.cellY == yBefore,
    ("same cell %s %d,%d -> %s %d,%d"):format(mapBefore, xBefore, yBefore, after.map.id, after.player.cellX,
      after.player.cellY))
  ok(ser(game.save.party) == partyBefore, "save party untouched")
  ok(love.filesystem.read(saveName) == saveBefore, "save file bytes unchanged")
  ok(battle() == nil, "battle state gone from the stack")
  ok(G ~= nil, "presenter module loaded")
  print(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  love.event.quit(fails == 0 and 0 or 1)
end
