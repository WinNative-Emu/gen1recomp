package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Serializer = require("src.core.SaveSerializer")
local GameVersion = require("src.core.GameVersion")
local CacheFs = require("src.import.CacheFs")
local Store = require("src.box.Store")
local Service = require("src.box.Service")
local Transaction = require("src.box.Transaction")
local Records = require("src.box.Records")
local Catalog = require("src.box.Catalog")

local tables = {}
local function put(version, path, value)
  tables[GameVersion.cachePrefix(version) .. path] = Serializer.encode(value)
end
for _, version in ipairs(GameVersion.ORDER) do
  if GameVersion.generation(version) == 3 then
    put(version, "data/generated/gba/pokemon/names.lua", { [25] = "PIKACHU" })
    put(version, "data/generated/gba/pokemon/national.lua", { toNational = { [25] = 25 }, toSpecies = { [25] = 25 } })
    put(version, "data/generated/gba/pokemon/move_names.lua", { [84] = "THUNDERSHOCK" })
    put(version, "data/generated/gba/items/pack.lua", { items = { [139] = { name = "ORAN BERRY" } } })
  else
    put(version, "data/generated/pokemon.lua", { PIKACHU = { dex = 25, name = "PIKACHU", types = { "ELECTRIC" } } })
    put(version, "data/generated/moves.lua", { THUNDERSHOCK = { name = "THUNDERSHOCK" } })
    put(version, "data/generated/items.lua", {})
  end
end
local readAt = CacheFs.readAt
CacheFs.readAt = function(path) return tables[path] end
Catalog.reset()

local function filesystem()
  local files, writes, mode = {}, 0, {}
  local fs = {
    read = function(path) return files[path] end,
    getInfo = function(path) return files[path] and { type = "file" } or nil end,
    createDirectory = function() return true end,
    remove = function(path)
      if mode.remove == path then return nil, "remove fault" end
      files[path] = nil; return true
    end,
    write = function(path, body)
      writes = writes + 1
      if writes == mode.at then
        if mode.kind == "partial" then files[path] = body:sub(1, math.floor(#body / 2)) end
        if mode.kind == "crash" then files[path] = body; error("simulated interruption") end
        return nil, "write fault"
      end
      files[path] = body
      return true
    end,
  }
  return fs, files, mode
end

local function fixture(version)
  local generation = GameVersion.generation(version)
  local mon = { species = generation == 3 and 25 or "PIKACHU", nickname = "Sparky", level = 12,
    hp = 31, maxHp = 31, otId = 42, otName = "Player", personality = 987654,
    otSecretId = 92, moves = { generation == 3 and { move = 84, pp = 17 } or "THUNDERSHOCK" },
    dvs = { attack = 7, defense = 3, speed = 9, special = 4 },
    opaque = { raw = "\000\255\127", unknown = { [7] = "keep" } } }
  if generation == 3 then mon.heldItem = 139 end
  local save = { version = version, generation = generation, party = { Store.copy(mon) },
    money = 19374, unknown = { keep = true }, rawImport = "original-template" }
  if generation == 3 then
    save.storage = { currentBox = 1, boxes = { { name = "First", wallpaper = 3, mons = { [4] = mon } } } }
  else save.boxes = { { mon } }; save.currentBox = 1 end
  return save, mon, { where = "box", box = 1, index = generation == 3 and 4 or 1 }
end

for _, version in ipairs(GameVersion.ORDER) do
  local fs, files = filesystem()
  local save, mon, ref = fixture(version)
  local source = { version = version, slotId = "slot1", path = "saves/" .. version .. "/slot1.lua" }
  local original = Serializer.encode(save)
  files[source.path] = original
  local service = assert(Service.open(fs))
  T.eq(Store.count(service.state), 0, version .. " begins with empty Box")
  T.check(service:deposit(source, { ref }, 1, original), version .. " deposits")
  T.eq(Store.count(service.state), 1, version .. " stored exactly once")
  T.same(Store.at(service.state, 1, 1).mon, mon, version .. " preserves the entire native record")
  T.same(Serializer.decode(files[source.path]).unknown, save.unknown, version .. " retains unrelated save fields")
  T.check(service:withdraw(source, { { box = 1, slot = 1 } }, 1), version .. " withdraws")
  T.eq(Store.count(service.state), 0, version .. " leaves no duplicate in Box")
  local after = Serializer.decode(files[source.path])
  local returned = Records.list(after, GameVersion.generation(version), 1)
  returned = returned[1]
  T.same(returned, mon, version .. " returned record is unchanged")
  T.eq(after.money, save.money, version .. " keeps money")
  T.eq(after.rawImport, save.rawImport, version .. " keeps cartridge template")
  T.eq(files[Transaction.PATH], nil, version .. " journal is cleared")
end

for _, kind in ipairs({ "fail", "partial", "crash" }) do
  for at = 1, 6 do
    local fs, files, mode = filesystem()
    local save, mon, ref = fixture("ruby")
    local source = { version = "ruby", slotId = "slot1", path = "saves/ruby/slot1.lua" }
    files[source.path] = Serializer.encode(save)
    local original = files[source.path]
    local service = assert(Service.open(fs))
    mode.at, mode.kind = at, kind
    pcall(service.deposit, service, source, { ref }, 1, original)
    mode.at = nil
    local reopened = Service.open(fs)
    if kind == "crash" and at == 1 then
      T.check(reopened ~= nil, "journal interruption recovers")
    else T.check(reopened ~= nil, kind .. " at " .. at .. " can reopen") end
    if reopened then
      local count = Store.count(reopened.state)
      local native = Serializer.decode(files[source.path])
      local inPC = Records.at(native, 3, ref) ~= nil
      T.check((count == 1 and not inPC) or (count == 0 and inPC), kind .. " at " .. at .. " retains exactly one copy")
      T.eq(files[Transaction.PATH], nil, kind .. " at " .. at .. " completes recovery")
      if count == 1 then
        T.eq(files[source.path .. ".bak"], files[source.path], kind .. " at " .. at .. " keeps game recovery consistent")
        T.eq(files[Store.PATH .. ".bak"], files[Store.PATH], kind .. " at " .. at .. " keeps Box recovery consistent")
      end
    end
  end
end

do
  local fs, files = filesystem()
  local save, _, ref = fixture("gold")
  local source = { version = "gold", slotId = "slot1", path = "saves/gold/slot1.lua" }
  local body = Serializer.encode(save); files[source.path] = body
  local service = assert(Service.open(fs))
  files[source.path] = Serializer.encode({ version = "gold", generation = 2, party = {}, boxes = {} })
  T.check(not service:deposit(source, { ref }, 1, body), "stale selection is refused")
  T.eq(Store.count(service.state), 0, "stale selection cannot put a different mon in Box")
  files[source.path] = body
  T.check(not service:deposit(source, { { where = "party", index = 1 } }, 1, body), "last healthy party mon stays")
  T.eq(files[source.path], body, "party refusal is nonmutating")
  T.check(service:deposit(source, { ref }, 1, body), "valid box deposit still succeeds")
  local red = { version = "red", slotId = "slot1", path = "saves/red/slot1.lua" }
  local redSave = fixture("red"); files[red.path] = Serializer.encode(redSave)
  local original = files[red.path]
  T.check(not service:withdraw(red, { { box = 1, slot = 1 } }, 1), "generation conversion is refused")
  T.eq(files[red.path], original, "generation refusal preserves destination")
  T.eq(Store.count(service.state), 1, "generation refusal preserves stored record")
  T.check(service:move(1, 1, 25, 60), "last storage slot is reachable")
  T.check(Store.at(service.state, 25, 60) ~= nil, "move retains entry")
  T.check(service:rename(25, "Rare Pokémon"), "Box can be renamed")
  T.eq(#Store.search(service.state, "THUNDERSHOCK"), 1, "move names are searchable")
  T.eq(#Store.search(service.state, "Rare Pokémon"), 1, "Box names are searchable")
  T.eq(#Store.search(service.state, "type:electric level<50 move:thundershock -egg"), 1,
    "type, level, move and egg filters combine")
  T.eq(#Store.search(service.state, "level>=50"), 0, "numeric level filter excludes lower levels")
  T.eq(#Store.search(service.state, "game:gold species:pikachu"), 1, "game and species filters work")
  T.eq(#Store.search(service.state, "shiny"), 0, "shiny filter respects native metadata")
end

do
  local save = fixture("gold")
  save.party[2] = { species = "PIKACHU", hp = 40, item = "FLOWER_MAIL" }
  save.mail = { party = { [2] = { message = "hello" } }, box = { { message = "keep" } } }
  local after = assert(Records.remove(save, 2, { { where = "party", index = 1 } }))
  T.eq(after.mail.party[1].message, "hello", "remaining party mail shifts with its Pokémon")
  T.same(after.mail.box, save.mail.box, "mailbox stays intact")
  T.eq(save.mail.party[2].message, "hello", "source save is not modified during planning")
end

do
  local fs, files = filesystem()
  files[Store.PATH] = "return { broken = true }"
  T.check(not Service.open(fs), "corrupt Box storage is refused")
  T.eq(files[Store.PATH], "return { broken = true }", "corrupt storage is not overwritten with an empty Box")
end

do
  local fs, files = filesystem()
  local save, _, ref = fixture("emerald")
  local source = { version = "emerald", slotId = "slot1", path = "saves/emerald/slot1.lua" }
  local body = Serializer.encode(save); files[source.path] = body
  local service = assert(Service.open(fs))
  local Trade = require("src.online.Trade")
  local previous = Trade.pendingSentAt
  Trade.pendingSentAt = function() return { { species = 25 } } end
  T.check(not service:deposit(source, { ref }, 1, body), "pending outgoing trade blocks deposit")
  T.eq(files[source.path], body, "pending trade refusal preserves the game save")
  T.eq(Store.count(service.state), 0, "pending trade refusal preserves Box")
  Trade.pendingSentAt = previous
  T.check(service:deposit(source, { ref }, 1, body), "deposit succeeds after pending trade finishes")
  local full = Serializer.decode(files[source.path])
  for i = 1, 30 do full.storage.boxes[1].mons[i] = Store.copy(save.party[1]) end
  local fullBody = Serializer.encode(full); files[source.path] = fullBody
  local boxBody = files[Store.PATH]
  T.check(not service:withdraw(source, { { box = 1, slot = 1 } }, 1), "full destination PC box blocks withdrawal")
  T.eq(files[source.path], fullBody, "full PC refusal preserves every destination record")
  T.eq(files[Store.PATH], boxBody, "full PC refusal preserves the stored record")
end

do
  local fs, files, mode = filesystem()
  local save, _, ref = fixture("ruby")
  local source = { version = "ruby", slotId = "slot1", path = "saves/cart_ruby.v1-hack/slot1.lua" }
  local body = Serializer.encode(save); files[source.path] = body
  local service = assert(Service.open(fs))
  mode.at, mode.kind = 2, "fail"
  T.check(not service:deposit(source, { ref }, 1, body), "target write fault leaves a recoverable journal")
  T.check(files[Transaction.PATH] ~= nil, "journal remains durable before target recovery")
  mode.at = nil
  local changed = Store.copy(save); changed.money = 1
  local changedBody = Serializer.encode(changed); files[source.path] = changedBody
  local boxBody = files[Store.PATH]
  local recovered = Service.open(fs)
  T.check(recovered and recovered.recoveryNotice, "externally changed save undoes the pending transfer")
  T.eq(files[source.path], changedBody, "undone transfer leaves the changed game intact")
  T.eq(files[Store.PATH], boxBody, "undone transfer restores the Box before image")
  T.eq(Store.count(recovered.state), 0, "undone transfer does not duplicate the Pokémon")
  T.eq(files[Transaction.PATH], nil, "undone transfer no longer blocks boot")
end

do
  local fs, files = filesystem()
  local save, _, ref = fixture("ruby")
  local source = { version = "ruby", slotId = "slot1", path = "saves/cart_ruby.v1-hack/slot1.lua" }
  local body = Serializer.encode(save); files[source.path] = body
  local service = assert(Service.open(fs))
  T.check(service:deposit(source, { ref }, 1, body), "cart ID with dots and hyphens deposits")
  local boxBody, gameBody = files[Store.PATH], files[source.path]
  local nextState = Serializer.decode(boxBody); nextState.boxes[1].name = "next"; nextState.revision = nextState.revision + 1
  local nextSave = Serializer.decode(gameBody); nextSave.money = 5
  local journal = Serializer.encode({ format = 1, jobs = {
    { path = Store.PATH, before = boxBody, after = Serializer.encode(nextState) },
    { path = source.path, before = gameBody, after = Serializer.encode(nextSave) } } })
  files[Store.PATH] = Serializer.encode(nextState)
  files[Store.PATH .. ".bak"] = files[Store.PATH]
  files[source.path] = Serializer.encode({ version = "ruby", generation = 3, party = {}, money = 1 })
  files[Transaction.PATH] = journal
  assert(Service.open(fs))
  T.eq(files[Store.PATH], boxBody, "conflict rolls an already written Box back to its before image")
  T.eq(files[Store.PATH .. ".bak"], boxBody, "conflict rolls the Box recovery copy back too")
  files[Transaction.PATH] = journal:sub(1, math.floor(#journal / 2))
  local reopened = Service.open(fs)
  T.check(reopened and reopened.recoveryNotice, "truncated journal is set aside instead of blocking boot")
  T.eq(files[Transaction.PATH], nil, "truncated journal is cleared")
  T.eq(files[Store.PATH], boxBody, "truncated journal leaves targets untouched")
end

do
  local fs, files = filesystem()
  local save, _, ref = fixture("emerald")
  local source = { version = "emerald", slotId = "slot1", path = "saves/emerald/slot1.lua" }
  local body = Serializer.encode(save); files[source.path] = body
  local service = assert(Service.open(fs))
  T.check(service:deposit(source, { ref }, 1, body), "deposit before storage loss")
  local boxBody = files[Store.PATH]
  files[Store.PATH] = nil
  local reopened = assert(Service.open(fs))
  T.eq(Store.count(reopened.state), 1, "missing storage recovers from its backup")
  T.eq(files[Store.PATH], boxBody, "backup is promoted back to storage")
  files[Store.PATH], files[Store.PATH .. ".bak"] = nil, "return {"
  T.check(not Service.open(fs), "missing storage with an unreadable backup is refused")
  T.eq(files[Store.PATH .. ".bak"], "return {", "unreadable backup is not overwritten")
end

CacheFs.readAt = readAt
Catalog.reset()
T.finish()
