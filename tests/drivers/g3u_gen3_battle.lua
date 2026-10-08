local U = require("tests.drivers.util")
local Project = require("src.online.xgen.Project")
local Datasets = require("src.online.xgen.Datasets")
local BattleSession = require("src.online.union.BattleSession")
local Table = require("src.battle.g3u.Table")
local F = require("tests.engine._g3u_fixture")
local L = require("tests.support.g3u_loopback")
local GameVersion = require("src.core.GameVersion")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

local CENTER = {
  firered = { map = "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F", x = 7, y = 8 },
  leafgreen = { map = "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F", x = 7, y = 8 },
  emerald = { map = "EM_OLDALE_TOWN_POKEMON_CENTER_1F", x = 7, y = 8 },
}

local function ser(v, seen)
  if type(v) ~= "table" then return type(v) .. ":" .. tostring(v) end
  seen = seen or {}
  if seen[v] then return "<cycle>" end
  seen[v] = true
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. ser(v[k], seen) end
  seen[v] = nil
  return "{" .. table.concat(out, ",") .. "}"
end

return function(game)
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. line)
    return cond
  end
  local v = GameVersion.get()
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  local spot = CENTER[v] or CENTER.firered
  local okBoot, bootErr = pcall(function()
    game:_handleBootAction({ action = "new_game", name = "LEAF", gender = 0,
      start = { map = spot.map, x = spot.x, y = spot.y, facing = "down" } })
  end)
  if not okBoot then print("[driver] center start failed: " .. tostring(bootErr)) end
  U.wait(90)
  local Runtime = require("src.core.game3.runtime")
  local Player = require("src.core.game3.player")
  local Map = require("src.core.game3.map")
  local Party = require("src.core.game3.party")
  local Stack = require("src.ui.game3.stack")
  local Message = require("src.ui.game3.message")
  local PartyMenu = require("src.ui.game3.party_menu")
  local AnimSeq = require("src.core.game3.battle.anim_seq")
  local Ui = require("src.core.game3.battle.ui")
  local SaveData = require("src.core.SaveData")
  local session = Runtime.getSession()
  if not ok(session ~= nil, "a " .. v .. " session is on the field") then
    love.event.quit(1)
    return
  end
  for _ = 1, 600 do
    if not Message.isOpen() and not Stack.busy() then break end
    if Message.isOpen() then U.tap(game, "a") end
    U.wait(2)
  end
  ok(Map.current ~= nil, "standing in " .. tostring(Map.current))
  local C = require("src.core.game3.constants").of(v)
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_SQUIRTLE"), 14)
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_RATTATA"), 10)
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_PIDGEY"), 9)
  game:saveGame()
  U.wait(2)
  local saveName = SaveData.saveFilename(v)
  local saveBefore = love.filesystem.read(saveName)
  ok(saveBefore ~= nil, "the save is on disk before the battle")
  local partyBefore = ser(session.party)
  local mapBefore, xBefore, yBefore, faceBefore = Map.current, Player.cellX, Player.cellY, Player.facing

  local ds = assert(Datasets.get(v))
  local mine = {}
  for _, m in ipairs(session.party) do
    local r, why = Project.mon(m, ds)
    if r then mine[#mine + 1] = r else print("[driver] skip mon: " .. tostring(why)) end
  end
  ok(#mine == 3, "three projected records from the save party (" .. #mine .. ")")

  local red = F.real("red", "g1r-red")
  ok(red ~= nil, "real red data for the bot (else fixture)")
  red = red or F.gen1()
  local t = assert(Table.build(red, 1))
  local theirs = { F.record(t, 53, { 10, 45 }, 30), F.record(t, 129, { 150 }, 5) }

  local Scope = require("src.battle.g3u.Scope")
  local Mods = Scope.modules()
  local function live()
    local P, Mv = Mods["src.core.game3.pokemon"], Mods["src.core.game3.battle.moves"]
    return { rawget(P, "_names"), rawget(P, "_types"), rawget(P, "_moveNames"), rawget(Mv, "_rom"),
      rawget(Mv, "BY_NUM"), math.random }
  end
  local liveBefore = live()

  local netA, netB = L.pair()
  local go = { seed = 777, size = 3 }
  local gens = { [0] = 1, [1] = 3 }
  local names = { [0] = "BOT", [1] = session.name or "LEAF" }
  local bot = BattleSession.new({ net = netA, seat = 0, go = go, gens = gens, data = red, records = theirs,
    names = names })
  local stepBot = L.bot(bot, { seed = 5, pick = function(_, list)
    for _, a in ipairs(list) do if a.kind == "move" and a.slot == 1 then return a end end
    return list[1]
  end })

  local doneCount, doneResult = 0, nil
  local function onDone(r) doneCount = doneCount + 1 doneResult = r end
  local handle, how
  local okL, Launch = pcall(require, "src.ui.g3u.Launch")
  if okL then
    local h, why = Launch.start(game, 3, { ruleset = "g3u", net = netB, seat = 1, go = go, gens = gens,
      names = names, records = mine, onDone = onDone })
    if h then handle, how = h.screen, "Launch" else print("[driver] Launch.start failed: " .. tostring(why)) end
  end
  if not handle then
    local G = require("src.ui.g3u.Gen3Presenter")
    local bs = BattleSession.new({ net = netB, seat = 1, go = go, gens = gens, records = mine, names = names })
    handle = G.start(game, bs, { names = { me = names[1], foe = names[0] }, onDone = onDone })
    how = "Gen3Presenter.start"
  end
  ok(handle ~= nil and handle.run ~= nil, "battle started via " .. tostring(how))
  local run = handle and handle.run

  local shots = {}
  local function shot(name)
    if shots[name] then return end
    shots[name] = true
    U.still(game, ("%s/%s_%s.png"):format(SHOT_DIR, v, name))
  end
  local function waitingText()
    return Message.isOpen() and Message.isWaiting() and (Message.currentPage() or "") or nil
  end
  local function step()
    local s = AnimSeq._steps and AnimSeq._steps[AnimSeq._i]
    return s and s.kind
  end

  local seen = {}
  local menus, moveMenus = 0, 0
  local lastPhase
  for f = 1, 80000 do
    stepBot()
    U.wait(1)
    if doneCount > 0 and run.phase == "done" and not Stack.has("g3u_battle") then break end
    local phase = run and run.phase
    local text = waitingText()
    if text and text:find("Union rules", 1, true) then
      seen.banner = true
      shot("01_union_rules")
    end
    if step() == "hitfx" and not shots["04_hit"] then
      seen.hit = true
      U.wait(3)
      shot("04_hit")
    end
    if step() == "faint" then seen.faint = true end
    if seen.faint and text and text:find("fainted", 1, true) then shot("05_faint") end
    if phase == "ending" and text and (text:find("against", 1, true) or text:find("defeated", 1, true)
        or text:find("draw", 1, true)) then
      seen.endText = text
      shot("07_end")
    end
    if phase == "menu" then
      if lastPhase ~= "menu" then menus = menus + 1 end
      if menus == 1 then shot("02_action_menu") end
      if Ui._menuIndex ~= 1 then U.tap(game, "up") U.tap(game, "left") else U.tap(game, "a") end
      U.wait(2)
    elseif phase == "moves" then
      if lastPhase ~= "moves" then moveMenus = moveMenus + 1 end
      if moveMenus == 1 then shot("03_move_menu") end
      if Ui._moveIndex ~= 1 then U.tap(game, "up") U.tap(game, "left") else U.tap(game, "a") end
      U.wait(2)
    elseif phase == "party" and PartyMenu.isOpen() then
      seen.replace = seen.replace or run.partyForced
      local party = PartyMenu._party or {}
      if PartyMenu.mode == "battle_faint" or PartyMenu.mode == "battle_switch" then
        local m = party[PartyMenu.cursor]
        if not m or (tonumber(m.hp) or 0) <= 0 then
          U.tap(game, "down")
        else
          shot("06_replacement")
          U.tap(game, "a")
        end
      else
        U.tap(game, "a")
      end
      U.wait(6)
    end
    lastPhase = phase
  end
  U.wait(60)
  shot("08_back_on_field")

  ok(doneCount == 1, "onDone called once (" .. doneCount .. ")")
  ok(doneResult ~= nil, "result " .. tostring(doneResult and doneResult.outcome) .. "/" ..
    tostring(doneResult and doneResult.why))
  ok(doneResult and doneResult.why == "faint", "the battle ended by faint")
  ok(seen.banner, "union rules line shown")
  ok(menus >= 2, "several turns played (" .. menus .. " action menus)")
  ok(moveMenus >= 1, "move menu opened")
  ok(seen.hit, "a hit animation played")
  ok(seen.faint, "a faint played")
  ok(seen.replace, "replacement party menu opened")
  ok(seen.endText ~= nil, "end line shown: " .. tostring(seen.endText))
  ok(not Stack.has("g3u_battle"), "battle layer popped")
  ok(Map.current == mapBefore and Player.cellX == xBefore and Player.cellY == yBefore and Player.facing == faceBefore,
    ("same cell %s %s,%s -> %s %s,%s"):format(tostring(mapBefore), tostring(xBefore), tostring(yBefore),
      tostring(Map.current), tostring(Player.cellX), tostring(Player.cellY)))
  ok(ser(session.party) == partyBefore, "session party untouched")
  ok(love.filesystem.read(saveName) == saveBefore, "save file bytes unchanged")
  local liveAfter = live()
  local same = true
  for i = 1, #liveBefore do if liveBefore[i] ~= liveAfter[i] then same = false end end
  ok(same, "live Gen 3 data intact after the battle")
  ok(#Scope.trips == 0, "no scope guard trips (" .. #Scope.trips .. ")")
  local Battle = require("src.core.game3.battle")
  ok(Battle._st == nil and not Battle.isActive(), "battle singleton left clean")
  print(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  love.event.quit(fails == 0 and 0 or 1)
end
