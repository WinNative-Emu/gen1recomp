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
  local ids = { [100] = true, [200] = true, [300] = true }
  local save = {
    version = "red",
    player = { id = 200, name = "RED" },
    party = {
      { species = "PIKACHU", otId = 200 },
      { species = "ABRA", otId = 100, traded = true },
      { species = "MEW", otId = 4242, traded = true },
      { species = "ODDISH" },
    },
    boxes = { { { species = "ZUBAT", otId = 300 } } },
    daycare = { mon = { species = "EKANS", otId = 200 } },
  }
  T.check(TrainerIdSync.rewriteSave(save, 1, 100, ids), "gen1 save reports a change")
  T.eq(save.player.id, 100, "gen1 player id takes the new id")
  T.eq(save.party[1].otId, 100, "own catch follows the id")
  T.eq(save.party[2].otId, 100, "mon traded from another save follows the id")
  T.eq(save.party[2].traded, nil, "and is no longer flagged traded")
  T.eq(save.party[3].otId, 4242, "a real trade keeps its OT")
  T.eq(save.party[3].traded, true, "and stays traded")
  T.eq(save.party[4].otId, nil, "an unstamped mon is left for load-time stamping")
  T.eq(save.boxes[1][1].otId, 100, "boxed mons follow the id")
  T.eq(save.daycare.mon.otId, 100, "daycare mon follows the id")
  T.check(not TrainerIdSync.rewriteSave(save, 1, 100, ids), "a second pass is a no-op")
end

do
  local raw = ("00"):rep(12) .. "00C8" .. ("00"):rep(30)
  local save = { player = { id = 200 }, party = { { cartRaw = raw } } }
  TrainerIdSync.rewriteSave(save, 1, 100, { [100] = true, [200] = true })
  T.eq(save.party[1].cartRaw:sub(25, 28), "0064", "raw gen1 carrier gets its OT bytes rewritten")
  T.eq(#save.party[1].cartRaw, #raw, "without changing its length")
end

do
  local save = {
    version = "gold", player = { id = 200 },
    party = { { otId = 200, traded = true } },
    dayCare = { man = { mon = { otId = 200 } }, egg = { otId = 200 } },
    hallOfFame = { teams = { { mons = { { otId = 200 } } } } },
    mail = { party = { { authorId = 200 } }, box = { { authorId = 9 } } },
  }
  TrainerIdSync.rewriteSave(save, 2, 100, { [100] = true, [200] = true })
  T.eq(save.player.id, 100, "gen2 player id")
  T.eq(save.dayCare.man.mon.otId, 100, "gen2 daycare parent")
  T.eq(save.dayCare.egg.otId, 100, "gen2 daycare egg")
  T.eq(save.hallOfFame.teams[1].mons[1].otId, 100, "gen2 hall of fame")
  T.eq(save.mail.party[1].authorId, 100, "gen2 own mail")
  T.eq(save.mail.box[1].authorId, 9, "gen2 foreign mail untouched")
end

do
  local bit = require("bit")
  local function shinyKey(tid, sid) return bit.bxor(tid, sid) end
  local save = {
    engine = "game3", version = "emerald", trainerId = 200, secretId = 0x1234,
    party = { { otId = 200, otSecretId = 0x1234 }, { otId = 300, otSecretId = 0x0F0F } },
    storage = { boxes = { [3] = { mons = { [7] = { otId = 200, otSecretId = 0x1234 } } } } },
    modData = { emerald_daycare = { daycare = { { otId = 200, otSecretId = 0x1234 } } } },
    hallOfFameTeams = { { { trainerId = 200, otSecretId = 0x1234 } } },
    secretBases = { { trainerId = { 200, 0, 0x34, 0x12 } } },
  }
  TrainerIdSync.rewriteSave(save, 3, 100, { [100] = true, [200] = true, [300] = true })
  T.eq(save.trainerId, 100, "gen3 trainer id")
  T.eq(shinyKey(save.trainerId, save.secretId), shinyKey(200, 0x1234),
    "gen3 secret id is reseated so own shinies stay shiny")
  T.eq(save.party[1].otId, 100, "gen3 party mon")
  T.eq(save.party[1].otSecretId, save.secretId, "own mon keeps matching the save's secret id")
  T.eq(shinyKey(save.party[2].otId, save.party[2].otSecretId), shinyKey(300, 0x0F0F),
    "mon from another save keeps its shininess")
  T.eq(save.storage.boxes[3].mons[7].otId, 100, "gen3 sparse box mon")
  T.eq(save.modData.emerald_daycare.daycare[1].otId, 100, "gen3 daycare mon")
  T.eq(save.hallOfFameTeams[1][1].trainerId, 100, "gen3 hall of fame")
  local b = save.secretBases[1].trainerId
  T.eq(b[1] + b[2] * 256, 100, "own secret base TID")
  T.eq(b[3] + b[4] * 256, save.secretId, "own secret base SID")
end

do
  local files = fresh()
  local red = SaveData.createSlot("red")
  SaveData.writeSlot("red", red, { version = "red", player = { id = 111, name = "RED" },
    party = { { species = "PIKACHU", otId = 111 } } })
  local gold = SaveData.createSlot("gold")
  SaveData.writeSlot("gold", gold, { version = "gold", generation = 2, player = { id = 222, name = "GOLD" },
    party = { { species = "CYNDAQUIL", otId = 222 }, { species = "ABRA", otId = 111, traded = true } } })
  local em = SaveData.createSlot("emerald")
  SaveData.writeSlot("emerald", em, { version = "emerald", engine = "game3", generation = 3,
    trainerId = 333, secretId = 5, name = "MAY", party = { { otId = 333, otSecretId = 5 } } })

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
    player = { id = 111, name = "RED" }, party = { { species = "PIKACHU", otId = 111 } } })
  local gold = SaveData.createSlot("gold")
  SaveData.writeSlot("gold", gold, { version = "gold", generation = 2, meta = { savedAt = 500 },
    player = { id = 222, name = "GOLD" }, party = { { species = "CYNDAQUIL", otId = 222 } } })

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

love.filesystem = realFS

T.finish("trainer_id_sync")
