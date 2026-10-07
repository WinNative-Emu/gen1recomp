package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Serializer = require("src.core.SaveSerializer")
local Store = require("src.box.Store")
local Service = require("src.box.Service")
local Transaction = require("src.box.Transaction")
local Box = require("src.sync.SyncBox")
local Engine = require("src.sync.SyncEngine")
local State = require("src.sync.SyncState")
local Json = require("src.link.Json")
local Base64 = require("src.core.Base64")
require("src.import.CacheFs").readAt = function(path)
  if path:match("data/generated/pokemon.lua$") then
    return Serializer.encode({ PIKACHU = { dex = 25, name = "PIKACHU" } })
  elseif path:match("data/generated/moves.lua$") then
    return Serializer.encode({ THUNDERSHOCK = { name = "THUNDERSHOCK" } })
  end
end
require("src.box.Catalog").reset()

local function filesystem()
  local files, mode = {}, { writes = 0 }
  local fs = {
    read = function(p) return files[p] end,
    getInfo = function(p) return files[p] and { type = "file" } end,
    createDirectory = function() return true end,
    getDirectoryItems = function(dir)
      local out = {}; for p in pairs(files) do
        if p:sub(1, #dir + 1) == dir .. "/" then out[#out + 1] = p:sub(#dir + 2) end
      end; return out
    end,
    remove = function(p) files[p] = nil; return true end,
    write = function(p, body)
      mode.writes = mode.writes + 1
      if mode.writes == mode.at then
        if mode.kind == "partial" then files[p] = body:sub(1, math.floor(#body / 2)) end
        if mode.kind == "crash" then files[p] = body; error("interrupted") end
        return nil, "disk fault"
      end
      files[p] = body; return true
    end,
  }
  return fs, files, mode
end

local function linked()
  local s = State.defaults(); s.account, s.deviceToken, s.enabled = "test", "token", true; return s
end

local mon = { species = "PIKACHU", nickname = "Sparky", level = 12,
  hp = 31, maxHp = 31, otId = 42, otName = "Player", moves = { "THUNDERSHOCK" } }
local function game(id, boxed)
  return { version = "red", generation = 1, player = { name = "RED" },
    party = {}, boxes = { boxed and { Store.copy(mon) } or {} }, currentBox = 1,
    meta = { playthroughId = id, savedAt = 1700000000 } }
end
local function writeGame(files, id, slot, boxed)
  files["saves/red/" .. slot .. ".lua"] = Serializer.encode(game(id, boxed))
end
local function savesFor(files)
  local adapter = { ordinaryWrites = 0 }
  function adapter.list()
    local out = {}
    for path, body in pairs(files) do
      local scope, slot = path:match("^saves/([%w_%-]+)/(slot%d+)%.lua$")
      if scope then
        local save = Serializer.decode(body)
        if save and save.meta and save.meta.playthroughId then
          out[#out + 1] = { version = save.version, slot = slot,
            cart = scope:match("^cart_(.+)$"), playthroughId = save.meta.playthroughId,
            blob = body, meta = Store.copy(save.meta) }
        end
      end
    end
    table.sort(out, function(a, b) return a.playthroughId < b.playthroughId end)
    return out
  end
  function adapter.write() adapter.ordinaryWrites = adapter.ordinaryWrites + 1; return "slot99" end
  function adapter.remove() error("linked deletion must use compound transaction") end
  return adapter
end
local function warehouse(files)
  local s = Store.new(); s.savedAt, s.nextId = 1700000000, 2
  s.boxes[1].mons[1] = { id = 1, version = "red", generation = 1, slotId = "slot1",
    mon = Store.copy(mon), display = { name = "PIKACHU" }, tags = "favorite", markings = 3 }
  s.syncMembers = { ["red/source"] = { version = "red", playthroughId = "source",
    slotId = "slot1", path = "saves/red/slot1.lua" } }
  files[Store.PATH] = Serializer.encode(s); writeGame(files, "source", "slot1", false)
  return s
end

local function cloud()
  local c = { rev = 0, saves = {}, requests = {} }
  function c:transport()
    local transport = {}
    function transport:begin(req)
      c.requests[#c.requests + 1] = req
      local method, path = req.method, req.url:match("http://sync%.test([^?]*)")
      local data, code = {}, 200
      if method == "GET" and path == "/sync/state" then
        data = { capabilities = { box = 1 }, saves = {}, deleted = {} }
        if c.legacy then data.capabilities = nil end
        for key, row in pairs(c.saves) do
          data[row.deleted and "deleted" or "saves"][key] = { rev = row.rev, meta = row.meta }
        end
        if c.box then data.box = { rev = c.rev, meta = c.box.meta, members = c.box.members } end
      elseif method == "GET" and path == "/sync/box" then
        data = Store.copy(c.box or { format = 1, blob = Serializer.encode(Store.new()), assets = {}, meta = { count = 0 }, members = {} })
        data.rev, data.saves = c.rev, Store.copy(c.saves)
        for version, id in req.url:gmatch("([%w_]+)/([%w%-]+)") do
          local key = version .. "/" .. id
          if version == "red" and not data.saves[key] then data.saves[key] = { version = version, deleted = true, rev = 0 } end
        end
        if c.onGet then c.onGet(); c.onGet = nil end
      elseif method == "PUT" and path == "/sync/box" then
        local body = assert(Json.decode(req.body))
        if body.baseRev ~= c.rev then code = 409 end
        for key, row in pairs(body.saves) do if row.baseRev ~= (c.saves[key] and c.saves[key].rev or 0) then code = 409 end end
        if code == 200 then
          c.rev = c.rev + 1; c.box = body; c.box.members = {}; data = { rev = c.rev, revs = {} }
          for key, row in pairs(body.saves) do
            row.rev = row.baseRev + 1; c.saves[key] = Store.copy(row)
            data.revs[key] = row.rev; c.box.members[#c.box.members + 1] = key
          end
        else data = { error = "conflict", rev = c.rev } end
      elseif method == "PUT" and path == "/sync/save" then
        local body = assert(Json.decode(req.body)); data.rev = 1
        c.saves[body.version .. "/" .. body.meta.playthroughId] = { rev = 1, meta = body.meta, blob = body.blob }
      elseif method == "GET" and path == "/sync/save" then
        data = Store.copy(c.saves["red/source"])
        if c.onGetSave then c.onGetSave(); c.onGetSave = nil end
      else code, data = 404, { error = "missing route" } end
      return { status = "ok", code = code, body = Json.encode(data) }
    end
    function transport:poll(handle) return handle end
    function transport:release() end
    return transport
  end
  return c
end

local function engine(fs, files, c, state)
  local saves = savesFor(files)
  local e = Engine.new({ fs = fs, box = Box.new(fs), saves = saves,
    state = state or linked(), persist = false, baseUrl = "http://sync.test", transport = c:transport() })
  return e, saves
end
local function pump(e)
  for _ = 1, 40 do e:update(0.01) end
  T.check(not e:busy(), "sync settles")
end
local function run(e) assert(e:syncNow()); pump(e) end
local function count(files)
  local s = assert(Serializer.decode(files[Store.PATH])); local n = Store.count(s)
  for _, e in ipairs(savesFor(files).list()) do
    local save = assert(Serializer.decode(e.blob))
    for _, b in ipairs(save.boxes or {}) do n = n + #b end
  end
  return n
end

do
  local fs, files = filesystem(); writeGame(files, "source", "slot1", true)
  files[Store.PATH] = Serializer.encode(Store.new())
  local c = cloud(); c.saves["red/source"] = { version = "red", rev = 1, blob = files["saves/red/slot1.lua"], meta = game("source").meta }
  local state = linked(); State.setRev(state, "red/source", 1, 1700000000)
  local e, adapter = engine(fs, files, c, state)
  e._boxKeys = {}
  c.onGetSave = function() warehouse(files) end
  e:_queueDownload("red/source", "red", "source", "replace", 1)
  pump(e)
  T.eq(adapter.ordinaryWrites, 0, "deposit during standalone fetch blocks stale game replacement")
  T.eq(count(files), 1, "concurrent deposit keeps one Pokémon")
  T.eq(c.rev, 1, "standalone fetch restarts as compound Box sync")
  T.eq(#Serializer.decode(c.saves["red/source"].blob).boxes[1], 0, "cloud receives transferred game state with warehouse")
end

do
  local fs, files = filesystem(); writeGame(files, "source", "slot1", true)
  local c = cloud(); local e = engine(fs, files, c)
  local entry = savesFor(files).list()[1]; e._boxKeys = {}
  e:_queueUpload(entry, "red/source", false)
  warehouse(files)
  pump(e)
  for _, req in ipairs(c.requests) do
    T.check(not req.url:find("/sync/save", 1, true), "queued independent write yields to new Box membership")
  end
  T.eq(c.rev, 1, "new Box member uploads as complete collection")
end

do
  local fs, files = filesystem(); warehouse(files)
  local c = cloud(); local e = engine(fs, files, c)
  run(e)
  T.eq(e.phase, "idle", "first upload succeeds")
  T.eq(c.rev, 1, "warehouse revision advances")
  T.eq(c.saves["red/source"].rev, 1, "source save advances in same request")
  T.eq(#c.requests, 2, "state plus one compound upload")
  T.eq(c.requests[2].url, "http://sync.test/sync/box", "no standalone linked save upload")
  run(e); T.eq(c.rev, 1, "unchanged collection does not upload again")
  local fs2, files2 = filesystem()
  writeGame(files2, "unrelated", "slot1", true)
  files2["options.lua"] = Serializer.encode({ saveSlots = { red = { list = { "slot1" }, active = "slot1" } }, custom = "local setting" })
  local e2, adapter = engine(fs2, files2, c); run(e2)
  T.eq(e2.phase, "idle", "new device receives collection")
  T.eq(adapter.ordinaryWrites, 0, "linked save bypasses ordinary download")
  local state2 = Serializer.decode(files2[Store.PATH])
  T.eq(state2.syncMembers["red/source"].slotId, "slot2", "destination slot can differ")
  T.eq(state2.boxes[1].mons[1].slotId, "slot2", "Pokémon origin remapped")
  T.eq(Serializer.decode(files2["options.lua"]).custom, "local setting", "device settings preserved")
  T.eq(count(files2), 2, "local unrelated Pokémon and one synced Pokémon retained")
  T.eq(c.saves["red/unrelated"].rev, 1, "independent saves still sync individually")
  local before = c.rev; run(e2); T.eq(c.rev, before, "remapped slots do not cause ping-pong")
end

do
  local fs, files = filesystem(); local s = warehouse(files)
  local entry = s.boxes[1].mons[1]
  entry.archives = { { id = 1, version = "red", generation = 1, slotId = "slot1", mon = { species = "PIKACHU", opaque = "\0\255" }, display = {} } }
  s.presets = { { name = "Team", ids = { 1 } } }
  s.stages = { require("src.box.Showcase").new() }; s.progress = { trainer = 7 }; s.gciTemplate = "native\0banner"
  s.boxes[1].theme, s.boxes[1].wallpaper = "Showcase", "box/showcase/1.png"
  s.boxes[1].showcaseMusic = "Night"
  local png = "\137PNG\r\n\26\n" .. string.rep("\0", 8) .. "\0\0\4\112\0\0\1\176" .. "fixture"
  files[s.boxes[1].wallpaper] = png; files[Store.PATH] = Serializer.encode(s)
  local payload = assert(Box.new(fs):snapshot(savesFor(files).list(), linked())).payload
  T.check(Box.validate(payload), "full snapshot validates")
  local fs2, files2 = filesystem(); local box2 = Box.new(fs2)
  T.check(box2:apply(payload, {}, linked()), "full snapshot applies")
  local copy = Serializer.decode(files2[Store.PATH])
  T.same(copy.presets, s.presets, "teams survive")
  T.same(copy.stages, s.stages, "stages survive")
  T.eq(copy.boxes[1].showcaseMusic,"Night","applied theme music survives device sync")
  T.same(copy.progress, s.progress, "gift progress survives")
  T.same(copy.boxes[1].mons[1].archives, entry.archives, "archived native records survive")
  T.eq(copy.gciTemplate, s.gciTemplate, "native template survives")
  T.eq(files2["box/showcase/1.png"], png, "wallpaper pixels survive")
  local before = Store.copy(files2)
  for _, mutate in ipairs({
    function(p) p.saves["red/source"].meta.playthroughId = "other" end,
    function(p) p.saves["red/source"].blob = "return { player={},version='gold' }" end,
    function(p) p.assets["box/showcase/1.png"] = nil end,
    function(p) p.assets["../../escape"] = Base64.encode(png) end,
    function(p) p.blob = "return os.execute('bad')" end,
    function(p) p.saves["red/source"].blob = "return {}" end,
  }) do
    local bad = Store.copy(payload); mutate(bad)
    T.check(not box2:apply(bad, savesFor(files2).list(), linked()), "malformed snapshot rejected")
    T.same(files2, before, "invalid snapshot changes no file")
  end
  local cart = Store.copy(payload)
  local save = Serializer.decode(cart.saves["red/source"].blob); save.meta.cartId = "missing-cart"
  cart.saves["red/source"].blob = Serializer.encode(save)
  local cartState = Serializer.decode(cart.blob)
  cartState.syncMembers["red/source"].cartId, cartState.syncMembers["red/source"].path = "missing-cart", "saves/cart_missing-cart/slot1.lua"
  cart.blob = Serializer.encode(cartState)
  local cleanFs, cleanFiles = filesystem()
  local result, why = Box.new(cleanFs):apply(cart, {}, linked())
  T.eq(result, false, "missing cart defers entire collection")
  T.check(why:find("Install", 1, true), "cart instruction given")
  T.eq(next(cleanFiles), nil, "no partial warehouse or save installed")
end

do
  local fs, files = filesystem(); warehouse(files); local c = cloud(); local e = engine(fs, files, c)
  files["saves/red/slot1.lua"] = nil
  T.eq(e:noteSaveDeleted("red/source"), false, "never uploaded deletion stays local")
  run(e)
  T.eq(e.phase, "idle", "unsynced deleted source does not block first Box sync")
  T.eq(c.saves["red/source"].deleted, true, "first snapshot records departed source tomb")
end

do
  local fsA, a = filesystem(); warehouse(a); local c = cloud(); local A = engine(fsA, a, c); run(A)
  local fsB, b = filesystem(); local B = engine(fsB, b, c); run(B)
  assert(assert(Service.open(fsA)):rename(1, "remote edit")); run(A)
  assert(assert(Service.open(fsB)):rename(1, "local edit")); run(B)
  local before = b[Store.PATH]
  c.rev = c.rev + 1
  local remote = Serializer.decode(c.box.blob); remote.boxes[1].name = "remote changed again"; c.box.blob = Serializer.encode(remote)
  c.saves["red/source"].rev = c.saves["red/source"].rev + 1
  assert(B:resolveConflict(Box.KEY, "remote")); pump(B)
  T.eq(#B.conflicts, 1, "remote changing after prompt requires new choice")
  T.eq(b[Store.PATH], before, "stale prompt does not overwrite local state")
  assert(assert(Service.open(fsB)):rename(1, "local changed again"))
  T.eq(B:resolveConflict(Box.KEY, "local"), false, "local changing after prompt requires review")
  T.eq(#B.conflicts, 1, "new local content keeps conflict open")
  T.check(B.conflicts[1].reviewMessage ~= nil, "prompt explains updated local state")
  assert(B:resolveConflict(Box.KEY, "local")); pump(B)
  T.eq(Serializer.decode(c.box.blob).boxes[1].name, "local changed again", "local choice uploads complete state")
  T.eq(assert(B.box:readBackup(B.box:latestBackup())).blob, Serializer.encode(remote), "remote losing state preserved")
end

for _, version in ipairs(require("src.core.GameVersion").ORDER) do
  local generation = require("src.core.GameVersion").generation(version)
  local fs, files = filesystem(); local s = Store.new()
  local id, key, path = "edition-test", version .. "/edition-test", "saves/" .. version .. "/slot7.lua"
  local save = { version = version, generation = generation, player = { name = "TEST" }, meta = { playthroughId = id }, opaque = "\0\255" }
  if generation == 3 then save.player, save.engine, save.name, save.party, save.bag = nil, "game3", "TEST", {}, {} end
  s.syncMembers = { [key] = { version = version, playthroughId = id, slotId = "slot7", path = path } }
  files[Store.PATH], files[path] = Serializer.encode(s), Serializer.encode(save)
  local payload = assert(Box.new(fs):snapshot(savesFor(files).list(), linked())).payload
  T.check(Box.validate(payload), version .. " native shape validates")
  local fs2, files2 = filesystem(); local box = Box.new(fs2)
  T.check(box:apply(payload, {}, linked()), version .. " applies")
  local target = "saves/" .. version .. "/slot1.lua"
  T.eq(Serializer.decode(files2[target]).opaque, save.opaque, version .. " native bytes preserved")
  T.eq(Serializer.decode(files2[Store.PATH]).syncMembers[key].path, target, version .. " routing persisted")
  files2[target .. ".bak"], files2[target .. ".tmp"] = files2[target], files2[target]
  payload.saves[key] = { version = version, deleted = true }
  T.check(box:apply(payload, savesFor(files2).list(), linked()), version .. " linked deletion applies")
  T.eq(files2[target], nil, version .. " primary removed")
  T.eq(files2[target .. ".bak"], nil, version .. " backup cannot resurrect deletion")
  T.eq(files2[target .. ".tmp"], nil, version .. " staged copy cannot resurrect deletion")
end

for _, kind in ipairs({ "fail", "partial", "crash" }) do
  for at = 1, 18 do
    local fs, files, mode = filesystem(); warehouse(files)
    local source = "saves/red/slot1.lua"
    files[source .. ".tmp"] = files[source]
    files["options.lua"] = Serializer.encode({ custom = "before", saveSlots = { red = { list = { "slot1" }, active = "slot1" } } })
    local oldBox = files[Store.PATH]; local newBox = Serializer.decode(oldBox); newBox.boxes[1].name = "wallpaper synced"
    newBox.boxes[1].theme, newBox.boxes[1].wallpaper = "Showcase", "box/showcase/1.png"
    local png = "\137PNG\r\n\26\n" .. string.rep("\0", 8) .. "\0\0\4\112\0\0\1\176" .. "bytes"
    local save = Serializer.decode(files[source]); save.boxes[1] = { Store.copy(mon) }; newBox.boxes[1].mons = {}
    mode.at, mode.kind = at, kind
    pcall(Transaction.commitSync, fs, {
      { path = source, before = files[source], after = Serializer.encode(save) },
      { kind = "asset", path = "box/showcase/1.png", after = png },
      { path = "options.lua", before = files["options.lua"], after = Serializer.encode({ custom = "after" }) },
      { path = Store.PATH, before = oldBox, after = Serializer.encode(newBox) },
    })
    mode.at = nil
    T.check(Transaction.recover(fs), "batch " .. kind .. " " .. at .. " recovers")
    T.eq(count(files), 1, "batch keeps one Pokémon")
    local changed = Serializer.decode(files[Store.PATH]).boxes[1].name == "wallpaper synced"
    if changed then
      T.eq(files["box/showcase/1.png"], png, "committed PNG intact")
      T.eq(Serializer.decode(files["options.lua"]).custom, "after", "options and Box commit together")
      T.eq(files[source .. ".tmp"], nil, "old staged save cleared")
    else T.eq(files["box/showcase/1.png"], nil, "failed initial journal leaves no wallpaper") end
  end
end

do
  local fsA, a = filesystem(); warehouse(a)
  local c = cloud(); local A = engine(fsA, a, c); run(A)
  local fsB, b = filesystem(); local B = engine(fsB, b, c); run(B)
  local source = { version = "red", slotId = "slot1", path = "saves/red/slot1.lua" }
  assert(assert(Service.open(fsA)):withdraw(source, { { box = 1, slot = 1 } }, 1))
  assert(assert(Service.open(fsB)):rename(1, "B chose this"))
  run(A); run(B)
  T.eq(#B.conflicts, 1, "two changed collections conflict")
  T.eq(B.conflicts[1].box, true, "one conflict covers collection and saves")
  T.eq(count(a), 1, "withdraw leaves exactly one Pokémon")
  T.eq(count(b), 1, "conflict leaves local Pokémon intact")
  T.eq(B:resolveConflict(Box.KEY, "both"), false, "cannot duplicate collection with keep-both")
  T.eq(#B.conflicts, 1, "invalid choice retains conflict")
  T.check(B:resolveConflict(Box.KEY, "remote"), "whole remote choice accepted"); pump(B)
  T.eq(count(b), 1, "remote choice preserves exactly one Pokémon")
  T.eq(Store.count(Serializer.decode(b[Store.PATH])), 0, "remote withdrawal applied")
  local current = Serializer.decode(b[Store.PATH])
  T.eq(current.departures[1].path, source.path, "departed destination remapped")
  local backup = B.box:latestBackup(); T.check(backup ~= nil, "losing copy has reachable backup")
  T.eq(assert(B.box:readBackup(backup)).meta.count, 1, "backup holds losing warehouse")
  T.check(B:restoreBoxBackup(backup), "whole snapshot can be restored")
  T.eq(count(b), 1, "restore keeps exactly one Pokémon")
  T.eq(Store.count(Serializer.decode(b[Store.PATH])), 1, "restore includes warehouse")
  run(B); T.eq(Serializer.decode(c.box.blob).boxes[1].mons[1].mon.species, "PIKACHU", "restored collection uploads")
  local extra = Serializer.decode(b[Store.PATH]); extra.syncMembers["red/new"] = { version = "red", playthroughId = "new", path = "saves/red/slot2.lua", slotId = "slot2" }
  b[Store.PATH] = Serializer.encode(extra); writeGame(b, "new", "slot2", false)
  local original = b[Store.PATH]
  T.check(not B:restoreBoxBackup(backup), "backup missing newly linked save cannot restore")
  T.eq(b[Store.PATH], original, "incomplete restore leaves collection unchanged")
  local ghost = { format = 1, blob = Serializer.encode(Store.new()), assets = {},
    saves = { ["red/source"] = { version = "red", deleted = true, rev = 0 }, ["red/new"] = { version = "red", deleted = true, rev = 0 } } }
  local ghostPath = assert(B.box:archive(ghost))
  T.check(not B:restoreBoxBackup(ghostPath), "never-seen cloud source is not a complete deletion backup")
  T.eq(b[Store.PATH], original, "placeholder backup cannot remove new linked saves")
end

do
  local fs, files = filesystem(); warehouse(files); local c = cloud(); local e = engine(fs, files, c)
  e:protectPlaythrough("red", "source"); run(e)
  T.eq(c.rev, 0, "active member defers entire upload")
  T.check(e.status:find("launcher", 1, true), "deferred status explains next step")
  e:protectPlaythrough(nil); T.eq(e.uploadAt, e.clock, "return schedules immediate retry")
  pump(e); T.eq(c.rev, 1, "return uploads collection")
  local s = Serializer.decode(files[Store.PATH]); s.boxes[1].name = "same second"; files[Store.PATH] = Serializer.encode(s)
  run(e); T.eq(c.rev, 2, "same timestamp content changes still upload")
  local state = Serializer.decode(files[Store.PATH]); state.boxes[1].mons = {}; state.departures = nil
  files[Store.PATH] = Serializer.encode(state); run(e)
  T.check(c.saves["red/source"] ~= nil, "empty collection retains save membership")
  files["saves/red/slot1.lua.bak"], files["saves/red/slot1.lua.tmp"] = "old", "old"
  files["saves/red/slot1.lua"] = nil; assert(e:noteSaveDeleted("red/source")); run(e)
  T.eq(c.saves["red/source"].deleted, true, "linked deletion uploads in compound snapshot")
  local fs2, files2 = filesystem(); local e2 = engine(fs2, files2, c); run(e2)
  T.eq(#savesFor(files2).list(), 0, "deleted member is not resurrected")
end

do
  local fs, files = filesystem(); warehouse(files); local c = cloud(); c.legacy = true
  local e = engine(fs, files, c); run(e)
  T.eq(e.phase, "error", "old server blocks Box upload")
  T.eq(#c.requests, 1, "old server receives no half-transfer")
end

do
  local fs, files = filesystem(); warehouse(files); local c = cloud(); local e = engine(fs, files, c); run(e)
  local fs2, files2 = filesystem(); local e2 = engine(fs2, files2, c)
  c.onGet = function() warehouse(files2); local s = Serializer.decode(files2[Store.PATH]); s.boxes[1].name = "edited during fetch"; files2[Store.PATH] = Serializer.encode(s) end
  run(e2); T.eq(e2.phase, "error", "edit during download blocks apply")
  T.eq(Serializer.decode(files2[Store.PATH]).boxes[1].name, "edited during fetch", "new local edits preserved")
end

for _, kind in ipairs({ "fail", "partial", "crash" }) do
  for at = 1, 13 do
    local fs, files, mode = filesystem(); warehouse(files)
    local box = Box.new(fs); local s = Serializer.decode(files[Store.PATH]); s.boxes[1].mons = {}
    local payload = assert(box:snapshot(savesFor(files).list(), linked())).payload
    payload.blob = Serializer.encode(s); local save = Serializer.decode(payload.saves["red/source"].blob)
    save.boxes[1] = { Store.copy(mon) }; payload.saves["red/source"].blob = Serializer.encode(save)
    mode.at, mode.kind = at, kind
    pcall(box.apply, box, payload, savesFor(files).list(), linked())
    mode.at = nil
    T.check(box:recover(), kind .. " " .. at .. " recovers interrupted group")
    T.eq(count(files), 1, kind .. " " .. at .. " retains exactly one Pokémon")
    T.eq(files[Transaction.PATH], nil, "recovery journal cleared")
  end
end

do
  local fs, files, mode = filesystem(); warehouse(files)
  local before = files[Store.PATH]; local nextState = Serializer.decode(before); nextState.boxes[1].name = "cloud"
  mode.at = 2
  Transaction.commitSync(fs, { { path = Store.PATH, before = before, after = Serializer.encode(nextState) } })
  mode.at = nil; local other = Serializer.decode(before); other.boxes[1].name = "external edit"; files[Store.PATH] = Serializer.encode(other)
  local ok, applied, notice = Transaction.recover(fs)
  T.check(ok and not applied and notice, "external edit sets the pending transfer aside")
  T.eq(Serializer.decode(files[Store.PATH]).boxes[1].name, "external edit", "external edit not overwritten")
  T.eq(files[Transaction.PATH], nil, "conflicting journal no longer blocks boot")
  local kept = notice and notice:match("(box/conflicts/[^ ]+%.lua)")
  T.check(kept and files[kept] ~= nil, "conflicting journal is kept for inspection")
end

local function link(files, id, slot)
  writeGame(files, id, slot, false)
  local s = Serializer.decode(files[Store.PATH])
  s.syncMembers["red/" .. id] = { version = "red", playthroughId = id, path = "saves/red/" .. slot .. ".lua", slotId = slot }
  files[Store.PATH] = Serializer.encode(s)
end

do
  local fsA, a = filesystem(); warehouse(a); local c = cloud(); local A = engine(fsA, a, c); run(A)
  local fsB, b = filesystem(); local B = engine(fsB, b, c); run(B)
  link(b, "added", "slot5"); run(B)
  T.eq(B.phase, "idle", "device B uploads a newly linked save")
  local rev = c.rev
  run(A)
  T.eq(#A.conflicts, 0, "save linked on another device is not a local Box change")
  T.eq(A.phase, "idle", "receiving the new member settles")
  local got = false
  for _, entry in ipairs(savesFor(a).list()) do if entry.playthroughId == "added" then got = true end end
  T.check(got, "newly linked save downloads with the collection")
  T.eq(c.rev, rev, "receiving the collection uploads nothing")
  run(A); T.eq(c.rev, rev, "no ping-pong after receiving a new member")
end

do
  local fsA, a = filesystem(); warehouse(a); local c = cloud(); local A = engine(fsA, a, c); run(A)
  local fsB, b = filesystem(); local B = engine(fsB, b, c); run(B)
  link(b, "added", "slot5"); assert(assert(Service.open(fsB)):rename(1, "B edit")); run(B)
  assert(assert(Service.open(fsA)):rename(1, "A edit")); run(A)
  T.eq(#A.conflicts, 1, "real edits on both devices still conflict")
  T.check(A:resolveConflict(Box.KEY, "local"), "local choice accepted with a remote-only member"); pump(A)
  T.eq(A.phase, "idle", "local choice uploads despite a member it never had")
  T.eq(Serializer.decode(c.box.blob).boxes[1].name, "A edit", "local collection wins")
  T.check(c.saves["red/added"] and not c.saves["red/added"].deleted, "remote-only member is carried, not dropped")
  run(A)
  local got = false
  for _, entry in ipairs(savesFor(a).list()) do if entry.playthroughId == "added" then got = true end end
  T.check(got, "carried member downloads on the next sync")
  T.eq(Serializer.decode(a[Store.PATH]).boxes[1].name, "A edit", "local collection kept after receiving the member")
end

do
  local fs, files = filesystem(); warehouse(files); local c = cloud(); local e = engine(fs, files, c)
  c.saves["red/source"] = { version = "red", rev = 3, blob = files["saves/red/slot1.lua"], meta = game("source").meta }
  run(e)
  T.eq(e.phase, "conflict", "server without a Box but a changed linked save asks once")
  T.check(e:resolveConflict(Box.KEY, "local"), "local choice accepted"); pump(e)
  T.eq(e.phase, "idle", "first Box upload initializes the server")
  T.eq(c.rev, 1, "server now has the Box")
end

do
  local fs, files = filesystem(); warehouse(files)
  local payload = assert(Box.new(fs):snapshot(savesFor(files).list(), linked())).payload
  local fs2, files2 = filesystem(); files2["options.lua"] = "return {"
  local box = Box.new(fs2)
  T.check(not box:apply(payload, {}, linked()), "unreadable options refuse the Box apply")
  T.eq(files2["options.lua"], "return {", "unreadable options are not replaced")
  T.eq(files2[Store.PATH], nil, "no Box written when options are unreadable")
end

do
  local fs, files = filesystem(); warehouse(files); local c = cloud(); local e = engine(fs, files, c); run(e)
  files["saves/red/slot1.lua"] = nil
  e.box.markDeleted = function() return nil, "disk fault" end
  local ok = e:noteSaveDeleted("red/source")
  T.eq(ok, nil, "failed Box mark is reported")
  T.check(e.state.pendingDeletes["red/source"] ~= nil, "deletion is still recorded")
  T.eq(State.rev(e.state, "red/source"), nil, "deleted save is forgotten")
  e.box.markDeleted = nil
  run(e)
  T.eq(c.saves["red/source"].deleted, true, "deletion reaches the cloud without resurrecting")
end

T.finish("sync_box")
