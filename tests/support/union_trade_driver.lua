local U = require("tests.drivers.util")
local FakeRelay = require("tests.support.fake_relay")
local Participant = require("src.online.union.Participant")
local Room = require("src.online.union.Room")
local Datasets = require("src.online.xgen.Datasets")
local GameVersion = require("src.core.GameVersion")
local Model = require("src.online.union.TradePrepModel")
local Txn = require("src.online.union.TradeTxn")
local Open = require("src.ui.union.prep.OpenTrade")
local SaveData = require("src.core.SaveData")

local D = {}

local FP = "1234123412341234"

local function identityRoot(version)
  local home = os.getenv("HOME") or ""
  local prefix = GameVersion.cachePrefix(version)
  local probe = GameVersion.generation(version) == 3 and "data/generated/gba/pokemon/names.lua" or "data/generated/pokemon.lua"
  local ids = { os.getenv("POKEPORT_IDENTITY") or "", "g1r-" .. version, "pokeport-test-caches" }
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE", home .. "/.local/share/love" }) do
    for _, id in ipairs(ids) do
      if id ~= "" then
        local f = io.open(base .. "/" .. id .. "/" .. prefix .. probe, "rb")
        if f then f:close() return base .. "/" .. id end
      end
    end
  end
  return nil
end
D.identityRoot = identityRoot

function D.installDatasets()
  local roots = {}
  Datasets.setReader(function(v, rel)
    if roots[v] == nil then roots[v] = identityRoot(v) or false end
    if not roots[v] then return nil end
    return Datasets.directoryReader(roots[v])(v, rel)
  end)
  Model.datasetSource = nil
end

function D.installGen3(version)
  local root = identityRoot(version)
  if not root then return false end
  local Dataset = require("src.core.game3.dataset")
  Dataset.cacheRootOverride = root .. "/" .. GameVersion.cachePrefix(version) .. "data/generated/gba"
  Dataset.mountExtractRoots()
  require("src.core.game3.pokemon").install(nil)
  return require("src.core.game3.pokemon")._names ~= nil
end

function D.gameData(version)
  local d = Datasets.get(version)
  return d and { pokemon = d.raw.pokemon, moves = d.raw.moves, items = d.raw.items or {} }
end

function D.peerGame(version, species, level, moves)
  local P = require("src.link.Protocol")
  local gen = GameVersion.generation(version)
  if gen == 3 then
    local Pokemon = require("src.core.game3.pokemon")
    local sp = Pokemon.speciesFromNational(species)
    local list = {}
    for _, m in ipairs(moves) do list[#list + 1] = { id = m, pp = Pokemon.movePp(m), ppUps = 0 } end
    local pid = 0x12345678
    local exp = require("src.core.game3.summary_data").expForLevel(Pokemon.growthRate(sp), level)
    local mon = assert(P.unpackMon3(nil, { species = sp, level = level, exp = exp, personality = pid, otId = 4321,
      otSecretId = 0, otGender = 1, otName = "LEAF", nickname = "", ivs = { hp = 10, atk = 10, def = 10, spe = 10, spa = 10, spd = 10 },
      evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }, moves = list, item = 0, nature = pid % 25, gender = Pokemon.gender(sp, pid),
      ability = Pokemon.abilityId(sp, pid), friendship = 70, metLocation = 1, metLevel = level, metGame = 4,
      pokeball = 4, language = 2 }, { strict = true }))
    return { session = { version = version, party = { mon }, dex = { seen = {}, owned = {}, caught = {} }, flags = {}, vars = {} } }
  end
  local data = D.gameData(version)
  local d = Datasets.get(version)
  local key = d.species[species].localKey
  local list = {}
  for _, m in ipairs(moves) do list[#list + 1] = { id = d.moves[m].localKey, pp = d.moves[m].pp } end
  local packed = { species = key, level = level, ot = "PEER", otId = 4321,
    dvs = { attack = 9, defense = 9, speed = 9, special = 9 }, statExp = {}, moves = list }
  if gen == 2 then
    packed.experience = d.species[species].exp[level]
    packed.happiness = 70
    local mon = assert(P.unpackMon2(data, packed, { strict = true }))
    local Save2 = require("src.core.gen2.Save")
    local was = GameVersion.get()
    GameVersion.set(version)
    local save = Save2.newGame({ playerName = "PEER" })
    GameVersion.set(was)
    save.version = version
    save.party = { mon }
    return { save = save, data = data }
  end
  packed.exp = d.species[species].exp[level]
  local mon = assert(P.unpackMon(data, packed, { strict = true }))
  mon.catchRate = 45
  return { save = { version = version, party = { mon }, pokedex = { seen = {}, owned = {} } }, data = data }
end

local function ctxFor(version, name, tid)
  local gen = Participant.genOf(version)
  return { version = version, name = name, trainerId = tid, gender = 0,
    profile = { engine = gen, version = version, engineVersion = "0.0.0-dev", apiVersion = 2, fingerprint = FP,
      rulesetId = gen == 3 and "g3_single" or "union", kind = "vanilla" },
    vanillaFingerprint = FP, gameplayMods = false }
end

function D.world(myVersion, peerVersion)
  local clock = 0
  local w = { relay = FakeRelay.new({ clock = function() return clock end }), clients = {} }
  local saved = package.loaded["src.online.Client"]
  function w:add(n, name)
    local seat = self.relay:seat(("%08x"):format(n), name)
    package.loaded["src.online.Client"] = nil
    local C = require("src.online.Client")
    C.reset()
    C.configure({ relayAddress = "fake:3", connect = function() return seat.transport end })
    C.connect({ name = name, profiles = {} })
    self.clients[#self.clients + 1] = C
    return Room.new({ client = C })
  end
  function w:pump(rounds)
    for _ = 1, rounds or 1 do
      clock = clock + 16
      self.relay:pump()
      for _, C in ipairs(self.clients) do C.update(0) end
    end
  end
  local ra = w:add(1, "ME")
  local rb = w:add(2, "PEER")
  package.loaded["src.online.Client"] = saved
  w:pump(4)
  ra:join(ctxFor(myVersion, "ME", 1))
  rb:join(ctxFor(peerVersion, "PEER", 2))
  w:pump(4)
  ra:poll(); rb:poll()
  ra:invite(("%08x"):format(2), "xg_trade")
  w:pump(4)
  rb:reply(rb:incoming()[1].id, true)
  w:pump(4)
  w.mine, w.peer = ra, rb
  return w
end

function D.run(game, cfg)
  local fails = 0
  local version = GameVersion.get()
  local dir = os.getenv("POKEPORT_SHOT_DIR") or ("/tmp/union-trade-" .. version)
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. version .. " " .. line)
    return cond
  end
  local function finish()
    print((fails == 0 and "PASS" or "FAIL") .. " union_trade " .. version .. "<->" .. cfg.peerVersion .. " failures=" .. fails)
    love.event.quit(fails == 0 and 0 or 1)
    U.wait(10)
  end
  D.installDatasets()
  local w = D.world(version, cfg.peerVersion)
  local peerGame = cfg.peerGame()
  local peerAdapter = Txn.newAdapter(peerGame, cfg.peerVersion)
  peerAdapter.writer = function() return true end
  local peer = Open.controller(peerGame, w.peer, w.peer:prep(), { version = cfg.peerVersion, adapter = peerAdapter,
    opponent = { name = "ME", version = version } })
  local called = false
  local screen, ctl = Open.trade(game, w.mine, w.mine:prep(), function() called = true end,
    { version = version, opponent = { name = "PEER", version = cfg.peerVersion } })
  ok(screen ~= nil and ctl ~= nil, "the trade screen opens")

  local function step(n)
    for _ = 1, n or 1 do
      w:pump(1)
      peer:poll(0)
      U.wait(1)
    end
  end
  local function shot(name)
    step(6)
    U.still(game, ("%s/%s_%s.png"):format(dir, version, name))
  end
  local function lines() return table.concat(ctl:page().lines or {}, " ") end
  local function find(c, id)
    for i, it in ipairs(c:page().items) do if it.id == id then return i end end
    return nil
  end
  local function choose(id)
    local idx = find(ctl, id)
    if not ok(idx ~= nil, ctl.step .. " has " .. id) then return false end
    for _ = 1, 40 do
      if ctl.cursor == idx then break end
      U.tap(game, "down")
      step(2)
    end
    for _ = 1, 12 do
      local was, scroll = ctl.step, ctl.scroll
      U.tap(game, "a")
      step(4)
      if ctl.step ~= was or ctl.scroll == scroll then break end
    end
    return true
  end
  local function peerChoose(id)
    local idx = find(peer, id)
    if idx then peer.cursor = idx; peer:input("a") end
    step(4)
  end
  local function waitStep(want, frames)
    for _ = 1, frames or 240 do
      if ctl.step == want then return true end
      step(1)
    end
    return ctl.step == want
  end

  step(20)
  ok(ctl.step == "pick", "starts on the pick page")
  ok(lines():find(GameVersion.VERSIONS[cfg.peerVersion].label, 1, true) ~= nil, "names the other player's game")
  shot("01_pick")
  choose("mon")
  ok(ctl.step == "offer", "the offer preview opens")
  if cfg.expectMoveFix then
    ok(find(ctl, "moves") ~= nil, "a move the other game lacks offers a fix")
    shot("02_offer_blocked")
    choose("moves")
    ok(ctl.step == "moves", "legal replacements are listed")
    shot("03_moves")
    choose("remove")
  end
  ok(find(ctl, "offer") ~= nil, "the converted offer can be sent: " .. lines())
  shot("04_offer")
  choose("offer")
  ok(ctl.step == "wait", "waiting for the peer's offer")
  shot("05_wait")
  peerChoose("mon")
  if find(peer, "moves") then peerChoose("moves") peerChoose("remove") end
  peerChoose("offer")
  ok(waitStep("confirm", 240), "both offers reach the final check (" .. ctl.step .. ")")
  ok(lines():find("feature of this app", 1, true) ~= nil, "the final page says this is an app feature")
  shot("06_confirm")
  local scrolled = ctl.scroll
  U.tap(game, "a")
  step(2)
  ok(ctl.step == "confirm" and ctl.scroll > scrolled, "A turns the page of a long final check")
  shot("07_confirm_more")
  local before = cfg.mine()
  choose("trade")
  ok(ctl.step == "ready", "waiting for the peer to agree")
  shot("08_ready")
  peerChoose("trade")
  ok(waitStep("done", 300), "the trade completes (" .. ctl.step .. " txn=" .. tostring(ctl.txn.state) .. " saveFailed=" .. tostring(ctl.txn.saveFailed) .. " " .. tostring(ctl.closedText) .. ")")
  shot("09_done")
  local after = cfg.mine()
  ok(after ~= before, "the outgoing slot now holds the received mon (" .. tostring(before) .. " -> " .. tostring(after) .. ")")
  ok(cfg.expectReceived == nil or after == cfg.expectReceived, "received " .. tostring(cfg.expectReceived))
  ok(#Txn.pending(version) == 0, "no journal remains")
  local main = SaveData.saveFilename(version)
  ok(love.filesystem.getInfo(main) ~= nil, "the trade was saved")
  choose("stop")
  step(20)
  ok(called, "the screen closes and reports back")
  return finish()
end

return D
