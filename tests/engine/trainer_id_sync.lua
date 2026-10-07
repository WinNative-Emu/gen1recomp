package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")
local TrainerIdSync = require("src.core.TrainerIdSync")

local realFS = love.filesystem

local function memfs(files)
  return {
    files = files,
    write = function(path, content) files[path] = content return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      return nil
    end,
  }
end

local function fresh()
  local files = {}
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set("red")
  return files
end

do
  local files = fresh()
  local red = SaveData.createSlot("red")
  SaveData.writeSlot("red", red, { version = "red", player = { id = 111, name = "RED" },
    party = { { species = "PIKACHU", otId = 111, ot = "RED" } } })
  local gold = SaveData.createSlot("gold")
  SaveData.writeSlot("gold", gold, { version = "gold", generation = 2, player = { id = 222, name = "GOLD" },
    party = { { species = "CYNDAQUIL", otId = 222, ot = "GOLD" }, { species = "ABRA", otId = 111, ot = "RED", traded = true } } })
  local em = SaveData.createSlot("emerald")
  SaveData.writeSlot("emerald", em, { version = "emerald", engine = "game3", generation = 3,
    trainerId = 333, secretId = 5, name = "MAY", party = { { species = 25, otId = 333, otSecretId = 5, otName = "MAY", personality = 12345 } } })

  local job = TrainerIdSync.newJob({ scope = "gold", slot = gold })
  local steps, last = 0, -1
  while not job:step() do
    steps = steps + 1
    local p = job:progress()
    T.check(p >= last and p <= 1, "progress is monotonic")
    last = p
    if steps > 100 then break end
  end
  T.eq(job.error, nil, "job finishes without error")
  T.eq(job.newId, 222, "source save's id is the target")
  T.eq(job.written, 3, "both other saves plus the source (its traded-in Abra) are written")

  local r = SaveData.decode(SaveData.readSlotSource("red", red))
  T.eq(r.player.id, 222, "red save took gold's id")
  T.eq(r.party[1].otId, 222, "red own mon followed")
  T.check(type(r.meta) == "table" and r.meta.savedAt, "rewritten save is stamped for save sync")
  local g = SaveData.decode(SaveData.readSlotSource("gold", gold))
  T.eq(g.party[2].otId, 222, "mon traded in from the red save is synced into the source save")
  local e = SaveData.decode(SaveData.readSlotSource("emerald", em))
  T.eq(e.trainerId, 222, "emerald save took the id")
  T.eq(e.party[1].otId, 222, "emerald own mon followed")
  T.check(files ~= nil, "memfs used")
end

do
  fresh()
  local job = TrainerIdSync.newJob({ scope = "red", slot = "slot9" })
  while not job:step() do end
  T.check(job.error ~= nil, "a missing source save fails cleanly")
end

do
  fresh()
  local Json = require("src.link.Json")
  local SyncState = require("src.sync.SyncState")
  local SyncEngine = require("src.sync.SyncEngine")
  local RomImporter = require("src.import.RomImporter")

  local red = SaveData.createSlot("red")
  SaveData.writeSlot("red", red, { version = "red", meta = { savedAt = 500 },
    player = { id = 111, name = "RED" }, party = { { species = "PIKACHU", otId = 111, ot = "RED" } } })
  local gold = SaveData.createSlot("gold")
  SaveData.writeSlot("gold", gold, { version = "gold", generation = 2, meta = { savedAt = 500 },
    player = { id = 222, name = "GOLD" }, party = { { species = "CYNDAQUIL", otId = 222, ot = "GOLD" } } })

  local server, puts = {}, {}
  local transport = { sent = {}, handles = {} }
  function transport:begin(req)
    self.sent[#self.sent + 1] = req
    local path = req.url:match("^[^?]*"):gsub("^http://sync%.test", "")
    local reply
    if req.method == "GET" and path == "/sync/state" then
      reply = { saves = server }
    elseif req.method == "PUT" and path == "/sync/save" then
      local body = Json.decode(req.body)
      puts[#puts + 1] = body
      local key = SyncState.key(body.version, body.meta.playthroughId)
      local rev = ((server[key] or {}).rev or 0) + 1
      server[key] = { rev = rev, meta = body.meta }
      reply = { ok = true, rev = rev }
    end
    self.handles[#self.sent] = { status = "ok", code = reply and 200 or 404,
      body = Json.encode(reply or { error = "no route" }) }
    return #self.sent
  end
  function transport:poll(h) return self.handles[h] end
  function transport:release() end

  local state = SyncState.defaults()
  state.account, state.deviceToken, state.enabled = "aa11bb22cc33dd44", "tok", true
  local eng = SyncEngine.new({ baseUrl = "http://sync.test", transport = transport,
    state = state, persist = false })
  local function pump() for _ = 1, 60 do eng:update(0.05) end end

  eng:syncNow()
  pump()
  T.eq(#puts, 2, "both saves reach the server before the ID sync")
  puts = {}
  eng:syncNow()
  pump()
  T.eq(#puts, 0, "an unchanged device uploads nothing")

  local imp = {
    _idSync = TrainerIdSync.newJob({ scope = "gold", slot = gold }),
    _busy = { progress = 0 },
    _clearBusy = function(self) self._busy = nil end,
    _syncEngine = function() return eng end,
  }
  for _ = 1, 50 do
    if not imp._idSync then break end
    RomImporter._pumpIdSync(imp)
  end
  T.eq(imp._idSync, nil, "the launcher pump finishes the job")
  T.check(imp._idSyncResult and imp._idSyncResult.body:find("Save sync is uploading", 1, true),
    "the result says save sync picked it up")
  pump()
  T.eq(#puts, 1, "save sync uploads the rewritten save straight away")
  local up = puts[1] or {}
  T.eq(up.version, "red", "and it is the red save that changed")
  local blob = SaveData.decode(up.blob or "")
  T.eq(blob and blob.player.id, 222, "the uploaded blob carries the synced ID")
  T.eq(blob and blob.party[1].otId, 222, "and the synced OT")
  T.eq(up.baseRev, 1, "as a normal revision on top of the server copy, not a conflict")
  T.eq(eng.phase, "idle", "and the engine settles")
end

do
  local nick = ("50"):rep(11)
  local ot = "91848350" .. ("00"):rep(7)
  local struct = ("A5"):rep(12) .. "006F" .. ("00"):rep(19)
  local save = { version = "red", player = { id = 111, name = "RED" }, party = {},
    daycare = { cartRaw = "01" .. nick .. ot .. struct } }
  local owners = {}
  TrainerIdSync.addOwner(owners, { id = 111, name = "RED" }, 1)
  local changed = TrainerIdSync.rewriteSave(save, 1, { id = 222, name = "BLUE", sid = 0 }, owners)
  T.check(changed, "raw cart day-care block counts as a change")
  local raw = save.daycare.cartRaw
  T.eq(#raw, 112, "raw day-care block keeps its size")
  T.eq(raw:sub(71, 74), "00DE", "raw day-care OT id rewritten")
  T.eq(raw:sub(25, 34), "818B9484" .. "50", "raw day-care OT name rewritten")
  T.eq(raw:sub(1, 24), "01" .. nick, "raw day-care nickname untouched")
end

love.filesystem = realFS

T.finish("trainer_id_sync")
