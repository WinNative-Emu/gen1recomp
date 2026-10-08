local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local ROLE = os.getenv("UE_ROLE") or "host"
local MODE = os.getenv("UE_MODE") or "battle"
local CASE = os.getenv("UE_CASE") or "normal"
local NAME = os.getenv("UE_NAME") or (ROLE == "host" and "HOST" or "GUEST")
local PEER = os.getenv("UE_PEER") or (ROLE == "host" and "GUEST" or "HOST")
local STATE = os.getenv("UE_STATE") or "/tmp/ue"
local LIMIT = tonumber(os.getenv("UE_SECONDS") or "") or 300
local PARTY = os.getenv("UE_PARTY") or ""
local WANT = tonumber(os.getenv("UE_WANT") or "")
local TAG = os.getenv("UE_TAG") or "run"

local function now() return love.timer.getTime() end

return function(game)
  io.stdout:setvbuf("line")
  local version = GameVersion.get()
  local gen = GameVersion.generation(version)
  local SHOTS = os.getenv("POKEPORT_SHOT_DIR") or STATE
  local fails = 0
  local t0 = now()
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. "[" .. ROLE .. "/" .. version .. "] " .. line)
    return cond
  end
  local function note(line) print("[ue] [" .. ROLE .. "/" .. version .. "] " .. line) end
  local function mark(name)
    print("[ue] MARK " .. ROLE .. " " .. name)
    local f = io.open(STATE .. "/" .. ROLE .. ".marks", "a")
    if f then f:write(name .. "\n") f:close() end
  end
  local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
  end
  local function shot(name)
    U.still(game, ("%s/%s_%s_%s_%s.png"):format(SHOTS, TAG, ROLE, version, name))
  end
  local Client = require("src.online.Client")
  local function finish()
    print((fails == 0 and "PASS" or "FAIL") .. " union_e2e role=" .. ROLE .. " case=" .. CASE .. " mode=" .. MODE
      .. " fails=" .. fails)
    love.event.quit(fails == 0 and 0 or 1)
    coroutine.yield()
  end
  local function waitFor(cond, seconds, onFrame)
    local stop = now() + seconds
    while now() < stop do
      if cond() then return true end
      if onFrame then onFrame() else U.wait(1) end
    end
    return cond()
  end

  do
    local okF, ffi = pcall(require, "ffi")
    if okF then
      pcall(ffi.cdef, "int getpid(void);")
      local f = io.open(STATE .. "/" .. ROLE .. ".pid", "w")
      if f then f:write(tostring(ffi.C.getpid())) f:close() end
    end
  end

  local Datasets = require("src.online.xgen.Datasets")
  local Project = require("src.online.xgen.Project")
  local Txn = require("src.online.union.TradeTxn")

  local G = {}

  if gen == 1 then
    local Presence = require("src.world.gen1.UnionRoomPresence")
    local UnionRoomMap = require("src.world.gen1.UnionRoomMap")
    local Pokemon = require("src.pokemon.Pokemon")
    local SaveData = require("src.core.SaveData")
    function G.boot()
      U.wait(10)
      if CASE == "resume" then
        local loaded, recovered = SaveData.load()
        if not loaded then return false end
        G.preDisk = SaveData.load().party
        game:restoreSave(loaded, recovered, { freshBoot = true, continued = true })
        U.wait(30)
        return true
      end
      game.save.flags.EVENT_GOT_POKEDEX = true
      game.save.player.name = NAME
      local list = {}
      for sp, lv in PARTY:gmatch("(%u[%u_]*):(%d+)") do list[#list + 1] = Pokemon.new(game.data, sp, tonumber(lv)) end
      game.save.party = list
      local stamp = require("src.battle.BattleState").stampOT
      for _, mon in ipairs(list) do stamp(game.save, mon) end
      local cx, cy = UnionRoomMap.cellFor(ROLE == "host" and 20 or 21)
      U.teleport(game, UnionRoomMap.MAP_ID, cx, cy + 1, "up")
      return true
    end
    function G.save() return game:writeSave() ~= false end
    function G.presence() return Presence.active() end
    function G.joined() local s = G.presence() return s and s.state == "joined" end
    function G.peer()
      local s = G.presence()
      for _, m in ipairs(s and s:entities() or {}) do
        if m.p.name == PEER then return m end
      end
      return nil
    end
    function G.player() return game.overworld and game.overworld.player end
    function G.peerCell(m) return m.cellX, m.cellY end
    function G.activity() local s = G.presence() return s and s.activity end
    function G.idle()
      local s = G.presence()
      return s and s.state == "joined" and not s.busy and s.activity == nil and game.stack:top() == game.overworld
    end
    function G.party() return game.save.party end
    function G.diskParty()
      local loaded = SaveData.load()
      return loaded and loaded.party
    end
  elseif gen == 2 then
    local Presence = require("src.world.gen2.UnionRoomPresence")
    local RoomMap = require("src.world.gen2.UnionRoomMap")
    local Mon = require("src.battle.gen2.Mon")
    local Save2 = require("src.core.gen2.Save")
    function G.boot()
      U.wait(60)
      if CASE == "resume" then
        local loaded = Save2.load(version)
        if not loaded then return false end
        G.preDisk = Save2.load(version).party
        game:continueGame(loaded)
        U.wait(60)
        return true
      end
      local save = game.save
      save.player.name = NAME
      local list = {}
      for sp, lv in PARTY:gmatch("(%u[%u_]*):(%d+)") do
        list[#list + 1] = Mon.stampOT(save, Mon.new(game.data, sp, tonumber(lv)))
      end
      save.party = list
      game.world:warpToMapId(RoomMap.ID, 12, 22, "up")
      return true
    end
    function G.save() return game:writeSave() ~= false end
    function G.presence() return Presence.active() end
    function G.joined() local s = G.presence() return s and s.state == "joined" end
    function G.peer()
      local s = G.presence()
      for _, e in ipairs(s and s:entities() or {}) do
        if e.participant.name == PEER then return e end
      end
      return nil
    end
    function G.player() return game.world and game.world.player end
    function G.peerCell(e) return e.cellX, e.cellY end
    function G.activity() local s = G.presence() return s and s.activity end
    function G.idle()
      local s = G.presence()
      return s and s.state == "joined" and s.activity == nil and s.ui == nil and game.stack:top() == nil
    end
    function G.party() return game.save.party end
    function G.diskParty()
      local loaded = Save2.load(version)
      return loaded and loaded.party
    end
  else
    local GU = require("tests.drivers.union_gen3_util")
    local Map = require("src.core.game3.map")
    local Union = require("src.core.game3.link.union_room")
    local Plaza = require("src.core.game3.link.union_plaza_map")
    local Family = require("src.core.game3.link.family")
    local Flags = require("src.core.game3.scripting.flags")
    local Space = require("src.core.game3.scripting.space")
    local Warp = require("src.core.game3.warp")
    local Player = require("src.core.game3.player")
    local Message = require("src.ui.game3.message")
    local Choice = require("src.ui.game3.choice")
    local SaveMenu = require("src.ui.game3.save_menu")
    local Link = require("src.core.game3.link")
    local CENTER = {
      firered = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F", leafgreen = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F",
      emerald = "EM_OLDALE_TOWN_POKEMON_CENTER_2F", ruby = "RU_OLDALE_TOWN_POKEMON_CENTER_2F",
      sapphire = "SA_OLDALE_TOWN_POKEMON_CENTER_2F",
    }
    local function session() return require("src.core.game3.runtime").getSession() end
    G.Union = Union
    function G.boot()
      for _ = 1, 900 do
        if game.phase == "boot" and game.boot then break end
        U.wait(1)
      end
      if CASE == "resume" then
        game:_handleBootAction({ action = "continue" })
        waitFor(function() return session() ~= nil and game.phase ~= "quest_log" end, 60, function()
          if game.phase == "quest_log" then U.tap(game, "b") end
          U.wait(10)
        end)
        U.wait(60)
        require("src.core.game3.link.trade").resumePending()
        Txn.resumePending(nil)
        U.wait(30)
        return session() ~= nil
      end
      game:_handleBootAction({ action = "new_game", name = NAME })
      U.wait(240)
      local s = session()
      if not s then return false end
      s.name = NAME
      local Party = require("src.core.game3.party")
      local C = require("src.core.game3.constants").of(version)
      s.party = {}
      for sp, lv in PARTY:gmatch("(%u[%u_]*):(%d+)") do
        Party.giveMon(s, C.species.byName["SPECIES_" .. sp], tonumber(lv), "")
      end
      local flags = require("src.ui.game3.screens").flags(s).IDS
      if flags.SYS_POKEDEX_GET then Flags.setFlag(Space.store, nil, flags.SYS_POKEDEX_GET, true) end
      if flags.SYS_POKEMON_GET then Flags.setFlag(Space.store, nil, flags.SYS_POKEMON_GET, true) end
      Link.connect()
      if not waitFor(function() return Client.state() == "online" end, 20) then return false end
      if version == "emerald" then
        -- pokeemerald/data/scripts/cable_club.inc:103
        Flags.setVar(Space.store, nil, Family.var("emerald", "VAR_CABLE_CLUB_TUTORIAL_STATE"), 2)
      end
      local rs = Family.isRubySapphire(version)
      GU.loadMap(game, CENTER[version], rs and 1 or 6, rs and 3 or 4, "up")
      U.wait(30)
      U.tap(game, "a")
      return waitFor(function()
        return Map.current == Plaza.MAP_ID and Union.state == "main" and not Warp.isBusy()
      end, 60, function()
        if Choice.active or SaveMenu.isOpen() or Message.isOpen() then U.tap(game, "a") end
        U.wait(6)
      end)
    end
    function G.save()
      local ok, wrote = pcall(game.saveGame, game)
      return ok and wrote ~= false
    end
    function G.joined() return Map.current == Plaza.MAP_ID and Union.state == "main" and Client.plaza() ~= nil end
    function G.peer()
      for slot = 1, Plaza.CAP do
        local p = Union.players[slot]
        if p and not p.gone and p.name == PEER then return { slot = slot, p = p } end
      end
      return nil
    end
    function G.peerCell(m) return Plaza.cellFor(m.slot) end
    function G.place(x, y, facing)
      Player.cellX, Player.cellY = x, y
      Player.px, Player.py = x * 16, y * 16
      Player.targetX, Player.targetY = x, y
      Player.facing = facing
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
    function G.activity() return Union._xgSession end
    function G.idle()
      return Union.state == "main" and Union._xgSession == nil and not Message.isOpen() and not Choice.active
    end
    function G.busyUi() return Message.isOpen() or Choice.active end
    function G.party()
      local s = session()
      local PartyView = require("src.core.game3.battle.party_view")
      return PartyView.fromSession(s.party, s.move_overlay)
    end
  end

  local data = Datasets.get(version)
  local function nationals(list)
    local out = {}
    for i, rec in ipairs(list or {}) do
      local v = data and Project.read(rec, data)
      out[i] = v and v.national or -1
    end
    return out
  end
  local function natList(list) return table.concat(nationals(list), ",") end

  if not ok(G.boot(), "booted into the game") then return finish() end
  if CASE == "resume" then
    if G.preDisk then note("disk party before resume " .. natList(G.preDisk)) end
    local before = natList(G.party())
    note("resumed party " .. before)
    ok(waitFor(function() return #Txn.pending(version) == 0 end, 30), "journal settled after resume")
    local after = nationals(G.party())
    note("party after resume " .. table.concat(after, ","))
    if WANT then ok(after[1] == WANT, "slot 1 holds the received mon " .. WANT .. " (" .. tostring(after[1]) .. ")") end
    local again = Txn.resumePending(game)
    ok(again == nil, "a second resume finds nothing to apply")
    ok(natList(G.party()) == table.concat(after, ","), "the party is unchanged by the second resume")
    if G.diskParty then
      local disk = nationals(G.diskParty())
      note("disk party " .. table.concat(disk, ","))
      if WANT then ok(disk[1] == WANT, "the saved slot 1 holds the received mon") end
    end
    return finish()
  end

  ok(G.save(), "saved before entering the activity")

  local Flow = require("src.ui.union.Flow")
  local Launch = require("src.ui.g3u.Launch")
  local launchResult
  Flow.seams.launch = {
    start = function(g, gn, session, a)
      session.onDone = function(r) launchResult = r end
      return Launch.start(g, gn, session, a)
    end,
  }
  local Open = require("src.ui.union.prep.Open")
  local OpenTrade = require("src.ui.union.prep.OpenTrade")
  local E = {}
  local origBattle = Open.battle
  Open.battle = function(...)
    local screen, model = origBattle(...)
    E.model = model
    return screen, model
  end
  local origCtl = OpenTrade.controller
  OpenTrade.controller = function(...)
    local ctl = origCtl(...)
    E.ctl = ctl
    return ctl
  end

  if gen ~= 3 then
    if not ok(waitFor(G.joined, 30), "joined the union room on the live relay") then return finish() end
  else
    if not ok(waitFor(G.joined, 20), "in the Gen 3 union room plaza") then return finish() end
  end
  local peer
  if not ok(waitFor(function() peer = G.peer() return peer ~= nil end, 90), "peer " .. PEER .. " shows in the room") then
    return finish()
  end
  U.wait(30)
  local px, py = G.peerCell(peer)
  if gen == 3 then
    G.place(px, py + 1, "up")
  else
    local pl = G.player()
    pl.cellX, pl.cellY = px, py + 1
    pl.px, pl.py = pl.cellX * 16, pl.cellY * 16
    pl.targetX, pl.targetY = pl.cellX, pl.cellY
    pl.facing = "up"
  end
  U.wait(20)
  shot("01_room")
  mark("in_room")

  local function top() return game.stack and game.stack:top() end
  local MenuClass = gen == 2 and require("src.ui.gen2.ScriptMenu") or require("src.ui.Menu")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local function gbMenuUp()
    local t = top()
    if gen == 2 then return t ~= nil and getmetatable(t) == MenuClass end
    return t ~= nil and t ~= game.overworld and t.index ~= nil and getmetatable(t) ~= ChoiceBox
  end

  local shots = {}
  local index = MODE == "trade" and 2 or 1
  if ROLE == "host" then
    if gen == 3 then
      local Union = G.Union
      U.tap(game, "a")
      ok(waitFor(function() return Union.state == "handle_do_something_prompt_input" end, 20, function()
        if Union.state ~= shots.ustate then
          shots.ustate = Union.state
          note("talk union state=" .. tostring(Union.state))
        end
        shots.utap = (shots.utap or 0) + 1
        if shots.utap % 30 == 0 then U.tap(game, "a") else U.wait(1) end
      end), "the talk menu opens")
      U.wait(20)
      shot("02_talk_menu")
      for _ = 2, index do U.tap(game, "down") U.wait(6) end
      U.tap(game, "a")
    else
      U.tap(game, "a")
      local n = 0
      ok(waitFor(gbMenuUp, 20, function()
        n = n + 1
        if n % 30 == 0 then
          local t = top()
          note("talk top=" .. tostring(t and (t.screenId or t.kind or t.phase)) .. " items=" .. tostring(t and t.items ~= nil)
            .. " index=" .. tostring(t and t.index) .. " mt=" .. tostring(t and getmetatable(t) == MenuClass))
          U.tap(game, "a")
        else U.wait(1) end
      end), "the talk menu opens")
      U.wait(10)
      shot("02_talk_menu")
      for _ = 2, index do U.tap(game, "down") U.wait(4) end
      U.tap(game, "a")
    end
  else
    if gen == 3 then
      local Union = G.Union
      ok(waitFor(function() return Union._xgSession ~= nil end, 90, function()
        if G.busyUi() then U.tap(game, "a") end
        U.wait(10)
      end), "accepted the request")
    else
      ok(waitFor(function() local t = top() return t and getmetatable(t) == ChoiceBox end, 90, function()
        local t = top()
        if t and t ~= game.overworld and getmetatable(t) ~= ChoiceBox then
          shots.ask = (shots.ask or 0) + 1
          if shots.ask % 30 == 0 then U.tap(game, "a") end
        end
        U.wait(1)
      end), "the request asks yes or no")
      U.wait(10)
      shot("02_prompt")
      U.tap(game, "a")
    end
  end
  local act
  if not ok(waitFor(function() act = G.activity() return act ~= nil end, 40), "the activity opened") then
    return finish()
  end

  local function pick(items, id, pred)
    for i, it in ipairs(items) do
      if it.id == id and not it.disabled and (pred == nil or pred(it)) then return i end
    end
    return nil
  end
  local function moveTo(holder, idx)
    for _ = 1, 40 do
      if holder.cursor == idx then break end
      U.tap(game, "down")
      U.wait(3)
    end
    U.tap(game, "a")
    U.wait(6)
  end

  if MODE == "battle" then
    local isCancel = CASE == "cancel_host" or CASE == "cancel_guest"
    local opened = waitFor(function() return E.model ~= nil or act.done or act.state == "done" end, 40)
    if isCancel and (act.done or act.state == "done") and not E.model then
      note("the peer cancelled before this side's prep screen opened (" .. tostring(act.why) .. ")")
    elseif not ok(opened and E.model ~= nil, "battle prep screen opened") then
      return finish()
    end
    local m = E.model
    local seen = {}
    local cancelled = false
    local ok2 = waitFor(function() return m == nil or m.done or act.launched or act.done end, 120, function()
      local step = m.step
      if not seen[step] then
        seen[step] = true
        U.wait(10)
        shot("03_prep_" .. step)
        note("prep step " .. step)
      end
      if m.view then U.tap(game, "b") U.wait(4) return end
      local pg = m:page()
      local items = pg.items
      local idx
      if (CASE == "cancel_host" and ROLE == "host") or (CASE == "cancel_guest" and ROLE == "guest") then
        if step == "rules" and not cancelled and m.prep and m.prep.rules then
          cancelled = true
          idx = pick(items, "cancel")
        elseif step == "closed" then
          idx = pick(items, "ok")
        end
      elseif step == "rules" or step == "problems" then
        if step == "rules" and not (m.prep and m.prep.rules) then U.wait(4) return end
        idx = pick(items, "continue")
      elseif step == "substitute" then
        idx = pick(items, "swap_owned") or pick(items, "swap_rental")
      elseif step == "moves" then
        idx = pick(items, "move") or pick(items, "empty")
      elseif step == "size" then
        idx = pick(items, "continue")
        if not idx and m:needSitOut() > m:sitOutCount() then
          for i = #items, 1, -1 do
            if items[i].id == "toggle" and not items[i].chosen then idx = i break end
          end
        end
      elseif step == "confirm" then
        idx = pick(items, "ready")
      elseif step == "closed" then
        idx = pick(items, "ok")
      end
      if idx then moveTo(m, idx) else U.wait(4) end
    end)
    ok(ok2, "prep finished (step " .. tostring(m and m.step) .. ")")
    if isCancel then
      ok(not act.launched, "no battle after a cancel")
      waitFor(function() return act.done and G.idle() end, 30, function()
        if (gen == 3 and G.busyUi()) or (gen ~= 3 and top() and top() ~= game.overworld) then U.tap(game, "a") end
        U.wait(8)
      end)
      U.wait(30)
      shot("07_back_in_room")
      ok(G.idle(), "back in the room after the cancel (" .. tostring(act.why) .. ")")
      ok(Client.room() == nil, "the xg room was left")
      return finish()
    end
    if not ok(waitFor(function() return act.launched or act.done end, 30), "the battle launched (" .. tostring(act.why) .. ")") then
      return finish()
    end
    local bp = act.battlePrep or {}
    note(("battle ruleset=%s size=%s team=%s records=%d"):format(tostring(bp.ruleset and bp.ruleset.id),
      tostring(bp.size), table.concat(bp.team or {}, ","), #(bp.records or {})))
    for i, rec in ipairs(bp.records or {}) do
      local mv = {}
      for j, m in ipairs(rec.moves or {}) do
        if type(m) == "table" then mv[#mv + 1] = tostring(m.id) .. "/" .. tostring(m.pp)
        else mv[#mv + 1] = tostring(m) .. "/" .. tostring(rec.pp and rec.pp[j]) end
      end
      note(("record %d species=%s level=%s moves=%s"):format(i, tostring(rec.species), tostring(rec.level),
        table.concat(mv, " ")))
    end
    local h = act.battle or {}
    local bs = h.bs
    local marked, k = false, 0
    local stop = now() + LIMIT
    local LB = gen == 3 and require("src.core.game3.link.battle") or nil
    local nextLog = now() + 10
    while not act.done and now() < stop do
      k = k + 1
      if now() > nextLog then
        nextLog = now() + 10
        note(("battle phase=%s turn=%s state=%s top=%s"):format(tostring(bs and bs.phase),
          tostring(bs and bs.match and bs.match.turn), tostring(act.state),
          tostring(gen ~= 3 and top() and (top().screenId or top().phase) or "")))
        if gen == 3 and not bs then
          local L3 = require("src.core.game3.link")
          local lk = L3.link
          note(("native3 stage=%s LB=%s why=%s link=%s ready=%s"):format(tostring(h.stage), tostring(LB.state),
            tostring(h.why), tostring(lk and lk:isOpen()), tostring(lk and lk:isReady())))
        end
        shots.slow = (shots.slow or 0) + 1
        if shots.slow <= 3 then shot("08_battle_t" .. shots.slow) end
      end
      if not shots.start and k == 90 then shots.start = true shot("05_battle_start") end
      if not shots.mid and ((bs and bs.match and bs.match.turn >= 2) or k == 600) then
        shots.mid = true
        shot("06_battle_mid")
      end
      if CASE == "kill_battle" and ROLE == "guest" and not marked and ((bs and bs.match and bs.match.turn >= 2) or k > 20000) then
        marked = true
        mark("in_battle")
      end
      if h.state and h.state.packed and not shots.native then
        shots.native = true
        note("native party sent " .. #h.state.packed .. " mons")
      end
      if gen == 3 and LB and LB._myPacked and not shots.lb then
        shots.lb = true
        note("gen3 native party sent " .. #LB._myPacked .. " mons")
      end
      local turn = bs and bs.match and bs.match.turn
      if turn ~= shots.turn or (bs and bs.phase ~= "choose") then
        shots.turn, shots.turnAt = turn, now()
      end
      if gen == 3 and bs and not shots.menu and require("src.core.game3.battle.ui")._mode == "menu" then
        U.tap(game, "a")
        U.wait(20)
        if require("src.core.game3.battle.ui")._mode == "moves" then
          shots.menu = true
          U.tap(game, "down")
          U.wait(10)
          shot("05b_move_menu")
        end
      end
      if bs and bs.phase == "choose" and now() - (shots.turnAt or now()) > 3 then
        shots.unstick = (shots.unstick or 0) + 1
        local seqs = gen == 3 and { { "right" }, { "down" }, { "right", "down" } }
          or { { "down" }, { "down", "down" }, { "down", "down", "down" } }
        local seq = seqs[(shots.unstick - 1) % 3 + 1]
        for _ = 1, 3 do U.tap(game, "b") U.wait(8) end
        U.tap(game, "a")
        U.wait(12)
        for _, b in ipairs(seq) do U.tap(game, b) U.wait(6) end
        U.tap(game, "a")
        U.wait(6)
        shots.turnAt = now()
      elseif bs and bs.phase == "replace" and k % 18 == 6 then
        U.tap(game, gen == 3 and "right" or "down")
      elseif not bs and gen == 3 then
        local mode = require("src.core.game3.battle.ui")._mode
        if mode ~= shots.nphase then shots.nphase, shots.nphaseAt = mode, now() end
        local partyOpen = require("src.ui.game3.party_menu").isOpen()
        if mode == "none" or partyOpen or not shots.g3progress then shots.g3progress = now() end
        if (mode == "party" or partyOpen) and k % 24 == 6 then
          U.tap(game, (math.floor(k / 24) % 2 == 0) and "right" or "down")
        elseif mode == "bag" and k % 12 == 6 then
          U.tap(game, "b")
        elseif (mode == "moves" or mode == "selmsg" or mode == "menu") and now() - (shots.g3progress or now()) > 4 then
          shots.unstick = (shots.unstick or 0) + 1
          local seqs = { { "right" }, { "down" }, { "right", "down" } }
          for _ = 1, 3 do U.tap(game, "b") U.wait(8) end
          U.tap(game, "a")
          U.wait(12)
          for _, b in ipairs(seqs[(shots.unstick - 1) % 3 + 1]) do U.tap(game, b) U.wait(6) end
          U.tap(game, "a")
          shots.g3progress = now()
        elseif k % 6 == 0 then
          U.tap(game, "a")
        else
          U.wait(1)
        end
      elseif not bs and gen ~= 3 then
        local t = top()
        local phase = t and t.phase
        if phase ~= shots.nphase then shots.nphase, shots.nphaseAt = phase, now() end
        if (phase == "moveSelect" or phase == "moves") and now() - shots.nphaseAt > 3 then
          U.tap(game, "down")
          U.wait(4)
          U.tap(game, "a")
          shots.nphaseAt = now()
        elseif type(phase) == "string" and phase:find("^refuse") and k % 12 == 6 then
          U.tap(game, "b")
        elseif (phase == nil or phase == "forced-switch") and t and k % 18 == 6 then
          U.tap(game, "down")
        elseif k % 6 == 0 then
          U.tap(game, "a")
        else
          U.wait(1)
        end
      elseif k % 6 == 0 then
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    ok(act.done or act.state == "done", "the battle ended inside the limit")
    local r = bs and bs.result
    if not r and launchResult ~= nil then
      r = type(launchResult) == "table" and launchResult or { outcome = launchResult, why = "native" }
    end
    note(("RESULT outcome=%s why=%s why_act=%s"):format(tostring(r and r.outcome), tostring(r and r.why), tostring(act.why)))
    if CASE == "kill_battle" and ROLE == "host" then
      ok(r == nil or r.why == "disconnect", "the survivor ends as a disconnect")
    end
  else
    if not ok(waitFor(function() return E.ctl ~= nil or act.done end, 40), "trade prep screen opened") then
      return finish()
    end
    local c = E.ctl
    local mine0 = nationals(G.party())
    note("party before " .. table.concat(mine0, ","))
    if CASE == "kill_confirm" and ROLE == "host" then
      local orig = Txn.send
      Txn.send = function(self, msg)
        if type(msg) == "table" and msg.type == "trade_confirm" then
          mark("confirm_held")
          return true
        end
        return orig(self, msg)
      end
    end
    if CASE == "crash_commit" and ROLE == "guest" then
      Txn.Adapter.write = function()
        mark("commit_logged")
        while true do love.timer.sleep(0.2) end
      end
    end
    local seen, sentMark = {}, false
    local done = waitFor(function() return c.done or c.step == "done" or act.done end, LIMIT, function()
      local step = c.step
      if not seen[step] then
        seen[step] = true
        U.wait(10)
        shot("04_trade_" .. step)
        note("trade step " .. step)
      end
      if CASE == "kill_confirm" and ROLE == "guest" and not sentMark and c.txn and c.txn.state == "commit_wait" then
        sentMark = true
        mark("confirm_sent")
      end
      local pg = c:page()
      local items = pg.items
      local idx
      if step == "pick" then
        idx = pick(items, "mon")
      elseif step == "offer" then
        idx = pick(items, "offer") or pick(items, "moves")
      elseif step == "moves" then
        idx = pick(items, "remove") or pick(items, "move")
      elseif step == "confirm" then
        idx = pick(items, "trade")
      elseif step == "closed" or (step == "trading" and c.txn and c.txn.state == "unresolved") then
        if not seen["closed_hold"] then
          seen["closed_hold"] = true
          U.wait(20)
          shot("04_trade_closed")
          note("closed: " .. tostring(c.closedText) .. " txn=" .. tostring(c.txn and c.txn.state))
        end
        if c.txn and c.txn.state == "unresolved" and #Txn.pending(version) > 0 then U.wait(10) return end
        idx = pick(items, "leave")
      end
      if idx then moveTo(c, idx) else U.wait(4) end
    end)
    note("trade end step=" .. tostring(c.step) .. " txn=" .. tostring(c.txn and c.txn.state) .. " closed=" .. tostring(c.closedText))
    local after = nationals(G.party())
    note("party after " .. table.concat(after, ","))
    if CASE == "kill_confirm" then
      ok(waitFor(function() return #Txn.pending(version) == 0 end, 60), "the open journal resolves")
      local now2 = nationals(G.party())
      local same = table.concat(now2, ",") == table.concat(mine0, ",")
      note("party after resolve " .. table.concat(now2, ",") .. (same and " (unchanged)" or " (changed)"))
      if WANT and not same then ok(now2[1] == WANT, "a committed trade applied the received mon") end
      ok(same or (WANT and now2[1] == WANT), "the party is consistent with the relay outcome")
    else
      ok(done and c.step == "done", "the trade completed (" .. tostring(c.step) .. ")")
      if WANT then ok(after[1] == WANT, "slot 1 now holds the received mon " .. WANT .. " (" .. tostring(after[1]) .. ")") end
      ok(after[1] ~= mine0[1], "the offered mon is gone from slot 1")
      ok(#Txn.pending(version) == 0, "the journal is dropped")
      if G.diskParty then
        local disk = nationals(G.diskParty())
        note("disk party " .. table.concat(disk, ","))
        if WANT then ok(disk[1] == WANT, "the save on disk holds the received mon") end
      end
      shot("06_trade_done")
      local stopIdx = pick(c:page().items, "stop")
      if stopIdx then moveTo(c, stopIdx) end
    end
  end

  waitFor(function() return (act.done or act.state == "done") and G.idle() end, 40, function()
    if gen == 3 then
      if G.busyUi() then U.tap(game, "a") end
    elseif top() and top() ~= game.overworld then
      U.tap(game, "a")
    end
    U.wait(8)
  end)
  U.wait(60)
  shot("07_back_in_room")
  ok(G.idle(), "back in the room with the presence restored (" .. tostring(act.why) .. ")")
  ok(Client.room() == nil, "the xg room was left")
  local plaza = Client.plaza()
  local me = Client.you() and Client.you().id
  local status
  for _, row in ipairs(plaza and plaza.members or {}) do
    if row.id == me then status = row.status end
  end
  ok(waitFor(function()
    for _, row in ipairs((Client.plaza() or {}).members or {}) do
      if row.id == me then status = row.status end
    end
    return status == "idle"
  end, 10), "my room status is idle (" .. tostring(status) .. ")")
  if CASE ~= "kill_battle" and CASE ~= "kill_confirm" then
    ok(waitFor(function() return G.peer() ~= nil end, 15), "the peer is still in the member list")
  end
  note("elapsed " .. math.floor(now() - t0) .. "s")
  return finish()
end
