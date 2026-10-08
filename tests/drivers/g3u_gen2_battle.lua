local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")
local Datasets = require("src.online.xgen.Datasets")
local Project = require("src.online.xgen.Project")
local Table = require("src.battle.g3u.Table")
local BattleSession = require("src.online.union.BattleSession")
local L = require("tests.support.g3u_loopback")
local GameVersion = require("src.core.GameVersion")

local function deepCopy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local out = {}
  seen[v] = out
  for k, x in pairs(v) do out[deepCopy(k, seen)] = deepCopy(x, seen) end
  return out
end

local function deepEq(a, b, seen)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  seen = seen or {}
  if seen[a] == b then return true end
  seen[a] = b
  for k, v in pairs(a) do
    if not deepEq(v, b[k], seen) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function snapshotFiles(dir, out)
  out = out or {}
  local fs = love.filesystem
  for _, name in ipairs(fs.getDirectoryItems(dir)) do
    local path = dir == "" and name or (dir .. "/" .. name)
    local info = fs.getInfo(path)
    if info and info.type == "directory" and (dir ~= "" or name:find("save")) then
      snapshotFiles(path, out)
    elseif info and info.type == "file" then
      out[path] = fs.read(path)
    end
  end
  return out
end

local function botRecord(t, n, level, moveId)
  local b = Table.baseStats(t, n)
  local function st(base) return math.floor(2 * base * level / 100) + 5 end
  local hp = math.floor(2 * b.hp * level / 100) + level + 10
  return {
    species = n, level = level, hp = hp, maxHp = hp, atk = st(b.atk), def = st(b.def), speed = st(b.spe),
    spAtk = st(b.spa), spDef = st(b.spd), moves = { { id = moveId, pp = t.moves[moveId][4], ppUps = 0 } },
    gender = 2, friendship = 70,
  }
end

return function(game)
  local fails = 0
  local version = GameVersion.current
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3u-gen2"
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. line)
    return cond
  end
  local function quit()
    print(("RESULT %s fails=%d"):format(fails == 0 and "PASS" or "FAIL", fails))
    love.event.quit(fails == 0 and 0 or 1)
  end

  U.wait(60)
  local world = game.world
  if not ok(world and world.map, "world booted") then return quit() end
  local save = game.save
  save.party = { Mon.new(game.data, "CYNDAQUIL", 30), Mon.new(game.data, "TOTODILE", 30),
    Mon.new(game.data, "PIDGEY", 25) }
  local mapId = "CHERRYGROVE_POKECENTER_1F"
  local nurse
  for _, o in ipairs(world.maps[mapId].objects or {}) do
    if o.sprite == "SPRITE_NURSE" then nurse = o end
  end
  world:warpToMapId(mapId, nurse.x, nurse.y + 2, "up")
  U.wait(100)
  local base = game.stack:top()
  local at0 = { world.map.id, world.player.cellX, world.player.cellY }
  ok(at0[1] == mapId, "standing in " .. tostring(mapId))
  game:writeSave()
  U.wait(2)
  local files0 = snapshotFiles("")
  local party0 = deepCopy(save.party)

  local data = Datasets.get(version)
  if not ok(data ~= nil, "gold dataset loads") then return quit() end
  local records = {}
  for i, mon in ipairs(save.party) do
    local r, why = Project.mon(mon, data)
    ok(r ~= nil, "record " .. i .. " projects " .. tostring(why or ""))
    records[#records + 1] = r
  end
  local t = assert(Table.build(data, 2))
  local botParty = { botRecord(t, 143, 100, 153), botRecord(t, 19, 5, 33), botRecord(t, 19, 5, 33) }

  local netA, netB = L.pair()
  local go = { seed = 4242, size = 3 }
  local gens = { [0] = 2, [1] = 3 }
  local names = { [0] = save.player.name or "GOLD", [1] = "MAY" }
  local bot = BattleSession.new({ net = netB, seat = 1, go = go, gens = gens, records = botParty, names = names })
  local bstep = L.bot(bot, { seed = 9 })

  local result, doneCount = nil, 0
  local Launch = require("src.ui.g3u.Launch")
  local handle, why = Launch.start(game, 2, { ruleset = "g3u", net = netA, seat = 0, go = go, gens = gens,
    names = names, records = records, onDone = function(r) result = r doneCount = doneCount + 1 end })
  if not ok(handle ~= nil, "Launch.start returns a handle " .. tostring(why or "")) then return quit() end
  local host = handle.screen

  local shots = {}
  local function still(name)
    if shots[name] then return end
    shots[name] = true
    ok(U.still(game, dir .. "/" .. name), "shot " .. name)
  end

  local seen = { menu = 0, banner = false, hit = false, faint = false, replace = false, endText = false }
  local turnsChosen = 0
  for n = 1, 20000 do
    bstep()
    if result then break end
    if n % 300 == 1 then
      local bs = handle.bs
      U.log("tick", n, host.stage, bs.phase, bs.result and bs.result.why, bs.result and bs.result.detail,
        bot.phase, host.screen and host.screen.phase, tostring(game.stack:top()))
    end
    local top = game.stack:top()
    local screen = host and host.screen
    if screen and top == screen then
      local msg = tostring(screen.message or "")
      if msg:find("UNION RULES") and not seen.banner then
        seen.banner = true
        U.wait(100)
        still("g3u2_01_banner.png")
      end
      if msg:find("GEN 3") and not seen.rules then
        seen.rules = true
        U.wait(100)
        still("g3u2_01b_banner_rules.png")
      end
      if screen.hpAnim and not seen.hit then
        seen.hit = true
        still("g3u2_03_hit.png")
      end
      if msg:find("fainted") and not seen.faint then
        seen.faint = true
        U.wait(100)
        still("g3u2_04_faint.png")
      end
      if msg:find("defeated") or msg:find("no more") or msg:find("draw") then
        if not seen.endText then
          seen.endText = true
          U.wait(100)
          still("g3u2_06_end.png")
        end
      end
      if screen.phase == "menu" then
        seen.menu = seen.menu + 1
        U.tap(game, "a")
      elseif screen.phase == "moves" then
        U.wait(2)
        still("g3u2_02_move_menu.png")
        turnsChosen = turnsChosen + 1
        U.tap(game, "a")
      elseif screen.phase == "intro" or screen.phase == "resolving" or screen.phase:find("^refuse")
          or screen.phase == "stats-box" then
        U.tap(game, "a")
      else
        U.wait(1)
      end
    elseif top and top.party and top.onChoose and screen then
      seen.replace = true
      local pick
      for i, m in ipairs(top.party) do
        if not pick and (m.hp or 0) > 0 then pick = i end
      end
      top.index = pick or 1
      U.wait(2)
      still("g3u2_05_replacement.png")
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end
  for _ = 1, 600 do
    if game.stack:top() == base and not world.mapSetup then break end
    U.wait(1)
  end
  U.wait(30)
  still("g3u2_07_back_in_room.png")

  ok(result ~= nil, "onDone fired with " .. tostring(result and result.outcome) .. "/" .. tostring(result and result.why))
  ok(doneCount == 1, "onDone fired exactly once")
  ok(result and result.outcome == "win" and result.why == "faint", "battle ended in a win by faint")
  ok(bot.result and bot.result.outcome == "lose", "bot saw the loss")
  ok(seen.banner, "union rules banner shown")
  ok(turnsChosen >= 2, ("several turns chosen (%d)"):format(turnsChosen))
  ok(seen.hit and seen.faint, "a hit and a faint played")
  ok(seen.replace, "my replacement went through the party menu")
  ok(seen.endText, "end line shown")
  ok(game.stack:top() == base, "overworld is back on top")
  ok(world.map.id == at0[1] and world.player.cellX == at0[2] and world.player.cellY == at0[3],
    ("same cell %s %d,%d"):format(tostring(world.map.id), world.player.cellX, world.player.cellY))
  ok(deepEq(party0, save.party), "save party untouched")
  local files1 = snapshotFiles("")
  local same, count = true, 0
  for path, bytes in pairs(files0) do
    count = count + 1
    if files1[path] ~= bytes then same = false print("changed " .. path) end
  end
  for path in pairs(files1) do if files0[path] == nil then same = false print("new " .. path) end end
  ok(same and count > 0, ("save files unchanged (%d)"):format(count))
  ok(next(host.wrapped) == nil, "state update wrappers removed")
  quit()
end
