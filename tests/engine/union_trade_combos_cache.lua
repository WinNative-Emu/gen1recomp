package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._xgen_fixture")
local Model = require("src.online.union.TradePrepModel")
local Txn = require("src.online.union.TradeTxn")
local TradeConvert = require("src.online.xgen.TradeConvert")
local Project = require("src.online.xgen.Project")
local Protocol = require("src.link.Protocol")
local GameVersion = require("src.core.GameVersion")
local SaveData = require("src.core.SaveData")
local Save2 = require("src.core.gen2.Save")

local PICK = { [1] = { "red", "blue", "yellow" }, [2] = { "gold", "silver", "crystal" }, [3] = { "firered", "leafgreen" } }

local real = {}
local chosen = {}
for gen, list in pairs(PICK) do
  for _, v in ipairs(list) do
    if not chosen[gen] then
      local d = F.real(v)
      if d then real[v], chosen[gen] = d, v end
    end
  end
end

local gen3root
if chosen[3] then
  local base = F.cacheRoot(chosen[3])
  gen3root = base and (base .. "/" .. GameVersion.cachePrefix(chosen[3]) .. "data/generated/gba")
  local Dataset = require("src.core.game3.dataset")
  Dataset.cacheRootOverride = gen3root
  Dataset.mountExtractRoots()
  require("src.core.game3.pokemon").install(nil)
  if not require("src.core.game3.pokemon")._names then chosen[3] = nil end
end

if not (chosen[1] or chosen[2] or chosen[3]) then
  print("[skip] union_trade_combos: no imported caches")
  os.exit(0)
end

Model.datasetSource = function(v) return real[v] end

local function gameData(d)
  return { pokemon = d.raw.pokemon, moves = d.raw.moves, items = d.raw.items or {} }
end

local function sample(data, otId, nick)
  local sp = data.species[25]
  local moves = {}
  for _, row in ipairs(sp.levelMoves) do
    if row.level <= 20 and #moves < 2 and row.move <= 165 then
      local dup = false
      for _, m in ipairs(moves) do if m == row.move then dup = true end end
      if not dup then moves[#moves + 1] = row.move end
    end
  end
  if data.generation == 3 then
    local list = {}
    for _, m in ipairs(moves) do list[#list + 1] = { id = m, pp = data.moves[m].pp, ppUps = 0 } end
    local Pokemon = require("src.core.game3.pokemon")
    local pid = 0x00C0FFEE
    return { species = sp.localKey, level = 20, exp = sp.exp[20], personality = pid, otId = otId, otSecretId = 654,
      otName = "ASH", nickname = nick, ivs = { hp = 10, atk = 11, def = 12, spe = 13, spa = 14, spd = 15 },
      evs = { hp = 1, atk = 2, def = 3, spe = 4, spa = 5, spd = 6 }, moves = list, friendship = 90, item = 0,
      nature = pid % 25, gender = Pokemon.gender(sp.localKey, pid), ability = Pokemon.abilityId(sp.localKey, pid),
      abilityNum = 0, metLocation = 1, metLevel = 3, metGame = 4, pokeball = 4, otGender = 0, language = 2, ribbons = 0,
      markings = 0, contest = { cool = 0, beauty = 0, cute = 0, smart = 0, tough = 0, sheen = 0 }, isEgg = false,
      hp = 40, status = "", pokerus = 0, eggCycles = 0, fatefulEncounter = false, modernFatefulEncounter = false }
  end
  local list = {}
  for _, m in ipairs(moves) do list[#list + 1] = { id = data.moves[m].localKey, pp = data.moves[m].pp, ppUps = 0 } end
  local rec = { species = sp.localKey, level = 20, nickname = nick, ot = "ASH", otId = otId,
    dvs = { attack = 9, defense = 8, speed = 7, special = 6 }, statExp = { hp = 1, attack = 4, defense = 9, speed = 16, special = 25 },
    moves = list }
  if data.generation == 2 then rec.experience = sp.exp[20]; rec.happiness = 80 else rec.exp = sp.exp[20] end
  return rec
end

local function nativeOf(gen, d, rec)
  if gen == 3 then return assert(Protocol.unpackMon3(nil, rec, { strict = true })) end
  if gen == 2 then return assert(Protocol.unpackMon2(gameData(d), rec, { strict = true })) end
  local m = assert(Protocol.unpackMon(gameData(d), rec, { strict = true }))
  m.catchRate = rec.catchRate
  return m
end

local function destGame(gen, version, d, existing)
  if gen == 3 then
    return { session = { version = version, party = { existing }, dex = { seen = {}, owned = {}, caught = {} }, flags = {}, vars = {} } }
  end
  if gen == 2 then
    local was = GameVersion.get()
    GameVersion.set(version)
    local save = Save2.newGame({ playerName = "GOLD" })
    GameVersion.set(was)
    save.version = version
    save.party = { existing }
    return { save = save, data = gameData(d) }
  end
  return { save = { version = version, party = { existing }, pokedex = { seen = {}, owned = {} } }, data = gameData(d) }
end

local combos = 0
for gs = 1, 3 do
  for gd = 1, 3 do
    local sv, dv = chosen[gs], chosen[gd]
    if sv and dv then
      local src, dst = real[sv], real[dv]
      local label = sv .. " -> " .. dv
      local offered = sample(src, 321, "PIKA")
      local existing = nativeOf(gd, dst, sample(dst, 999, "KEEP"))
      local game = destGame(gd, dv, dst, existing)
      local adapter = Txn.newAdapter(game, dv)
      adapter.writer = function() return true end
      local sender = Model.new({ version = sv, peerVersion = dv, owned = { { ref = { where = "party", index = 1 }, rec = offered } } })
      local rep = sender:choose(1)
      T.check(rep.ok, label .. ": offer converts (" .. tostring(rep.blocks[1] and rep.blocks[1].code) .. ")")
      if rep.ok then
        local payload, digest = sender:payload()
        local receiver = Model.new({ version = dv, peerVersion = sv, owned = adapter:owned() })
        local ok, why = receiver:receive(payload, function(final) return adapter:validate(final) end)
        T.check(ok, label .. ": receiver re-converts and validates in its own game (" .. tostring(why) .. ")")
        if ok then
          local packedExisting = adapter:pack(existing)
          local entry = { key = "room:1:" .. digest, out = { ref = { where = "party", index = 1 },
              canonical = TradeConvert.canonical(packedExisting), identity = Txn.identityOf(gd, packedExisting) },
            incoming = receiver.peer.final, incomingIdentity = Txn.identityOf(gd, receiver.peer.final) }
          local status = Txn.applyEntry(adapter, entry)
          T.eq(status, "applied", label .. ": applies into the destination save structure")
          local s = adapter:save()
          local got = s.party[1]
          local repacked = adapter:pack(got)
          local view = Project.read(repacked, dst)
          T.check(view ~= nil and view.national == 25, label .. ": the result reads back as Pikachu in " .. dv)
          local again = gd == 3 and Protocol.unpackMon3(nil, repacked, { strict = true })
            or gd == 2 and Protocol.unpackMon2(gameData(dst), repacked, { strict = true })
            or Protocol.unpackMon(gameData(dst), repacked, { strict = true })
          T.check(again ~= nil, label .. ": the stored mon decodes strictly as a valid " .. dv .. " mon")
          if gd == 1 then
            local report = SaveData.validate(s, gameData(dst))
            T.eq(#report.lostMons, 0, label .. ": Gen 1 save validation keeps it")
            T.check(s.pokedex.owned[got.species], label .. ": dex owned")
          elseif gd == 2 then
            local report = Save2.validate(s)
            T.check(Save2.emptyReport(report), label .. ": Gen 2 save validation is clean")
            T.check(s.pokedex.caught[got.species], label .. ": dex caught")
          else
            T.eq(got.friendship, 70, label .. ": Gen 3 traded friendship")
            T.check(s.dex.seen[got.species], label .. ": dex seen")
          end
          T.eq(Txn.applyEntry(adapter, entry), "already", label .. ": a second apply is refused")
          combos = combos + 1
        end
      end
    end
  end
end

T.check(combos > 0, "at least one combination ran")
print(("[info] union_trade_combos: %d combinations"):format(combos))
T.finish("union_trade_combos")
