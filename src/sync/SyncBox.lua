local SaveData = require("src.core.SaveData")
local Serializer = require("src.core.SaveSerializer")
local Store = require("src.box.Store")
local Transaction = require("src.box.Transaction")
local Base64 = require("src.core.Base64")
local Version = require("src.core.GameVersion")
local Client = require("src.sync.SyncClient")
local Work = require("src.sync.SyncWork")
local SyncBox = {}
SyncBox.__index = SyncBox
SyncBox.KEY = "box/collection"
SyncBox.MAX_MEMBERS = 240

local function split(key)
  if type(key) ~= "string" then return nil end
  local version, id = key:match("^([^/]+)/([%w%._:%-]+)$")
  if not version or not Version.VERSIONS[version] or #id > 64 then return nil end
  return version, id
end

local function pathOf(entry)
  if type(entry.slot) ~= "string" or not entry.slot:match("^slot%d+$") then return nil end
  local scope = entry.cart and "cart_" .. entry.cart or entry.version
  if type(scope) ~= "string" or not scope:match("^[%w%._%-]+$") then return nil end
  return "saves/" .. scope .. "/" .. entry.slot .. ".lua"
end

local CHANGED = "Box or a linked save changed during sync. Sync again."

local function loadStore(fs)
  if not Work.async() then return Store.load(fs) end
  local body = fs.read(Store.PATH)
  if not body then return Store.load(fs) end
  local state, err = Work.call("decode", body)
  if not state then return nil, "Box storage could not be decoded: " .. tostring(err) end
  local valid, why = Store.validate(state)
  if not valid then return nil, why end
  return valid, nil, body
end

local function same(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local memo

function SyncBox.fingerprint(snapshot)
  local bodies, assets = {}, {}
  for key, row in pairs(snapshot.saves) do
    if row.deleted then bodies[key] = false else bodies[key] = row.blob end
  end
  for name, encoded in pairs(snapshot.assets or {}) do assets[name] = encoded end
  if memo and memo.blob == snapshot.blob and same(memo.bodies, bodies) and same(memo.assets, assets) then
    return memo.value
  end
  local value = Work.call("fingerprint", snapshot.blob, snapshot.assets, bodies)
  memo = { blob = snapshot.blob, bodies = bodies, assets = assets, value = value }
  return value
end

function SyncBox.new(fs)
  return setmetatable({ fs = SaveData.persistenceFs(fs), saveCache = {}, assetCache = {} }, SyncBox)
end

function SyncBox:recover()
  local ok, applied, notice = Transaction.recover(self.fs)
  if notice then self.recoveryNotice = notice end
  return ok, applied, notice
end

function SyncBox:owns(key)
  local body = self.fs.read(Store.PATH)
  if body == nil then
    if self.fs.getInfo(Store.PATH) then return nil, "Box storage could not be read." end
    local state, why, recovered = Store.load(self.fs)
    if not state then return nil, why end
    if not recovered then return false end
    body = recovered
  end
  if body ~= self.membersBody then
    local valid, why = Store.validate(Work.call("decode", body))
    if not valid then return nil, why end
    self.membersBody, self.members = body, valid.syncMembers or {}
  end
  return self.members[key] ~= nil
end

function SyncBox:markDeleted(key)
  local state, why, before = Store.load(self.fs)
  if not state then return nil, why end
  if not before or not (state.syncMembers and state.syncMembers[key]) then return true end
  state.syncMembers[key].deleted = true
  state.revision, state.savedAt = state.revision + 1, os.time()
  return Transaction.commitSync(self.fs, { { path = Store.PATH, before = before, after = Serializer.encode(state) } })
end

function SyncBox:snapshot(entries, syncState, extraKeys)
  local state, why, body = loadStore(self.fs)
  if not state then return nil, why end
  local byPath, byKey = {}, {}
  for _, entry in ipairs(entries or {}) do
    local key = entry.version .. "/" .. entry.playthroughId
    local path = pathOf(entry)
    byKey[key] = entry
    if path then byPath[path] = entry end
  end
  local members, remoteOnly = Store.copy(state.syncMembers or {}), {}
  local pending = syncState and syncState.pendingDeletes or {}
  for key in pairs(extraKeys or {}) do
    if not members[key] then
      local version, id = split(key)
      if not version then return nil, "A cloud Box save identity is invalid." end
      local entry = byKey[key]
      if entry or pending[key] then
        members[key] = { version = version, playthroughId = id, path = entry and pathOf(entry) or "saves/" .. version .. "/slot0.lua",
          slotId = entry and entry.slot or "slot0", cartId = entry and entry.cart }
      else
        remoteOnly[key] = true
      end
    end
  end
  local function legacy(path)
    local entry = byPath[path]
    if entry then
      local key = entry.version .. "/" .. entry.playthroughId
      members[key] = { version = entry.version, playthroughId = entry.playthroughId,
        path = path, slotId = entry.slot, cartId = entry.cart }
    end
  end
  local function origin(entry)
    if entry.slotId then legacy(pathOf({ version = entry.version, cart = entry.cartId, slot = entry.slotId })) end
    for _, original in ipairs(entry.archives or {}) do origin(original) end
  end
  if state.syncMembers == nil then
    for _, box in ipairs(state.boxes) do
      for _, entry in pairs(box.mons) do origin(entry) end
    end
    for _, departure in pairs(state.departures or {}) do legacy(departure.path); origin(departure.entry) end
  end
  local saves, keys, missing = {}, {}, {}
  local todo, jobs = {}, {}
  for key in pairs(members) do
    local entry, cached = byKey[key], self.saveCache[key]
    if entry and not (cached and cached.source == entry.blob and cached.version == entry.version
        and cached.id == entry.playthroughId and cached.cart == entry.cart) then
      todo[#todo + 1] = key
      jobs[#jobs + 1] = { n = 4, entry.blob, entry.version, entry.playthroughId, entry.cart }
    end
  end
  local normalized = Work.batch("normalizeSave", jobs)
  for i, key in ipairs(todo) do
    local entry, blob = byKey[key], normalized[i][1]
    if not blob then return nil, "A save linked to Box could not be read." end
    self.saveCache[key] = { source = entry.blob, version = entry.version, id = entry.playthroughId, cart = entry.cart,
      blob = blob }
  end
  for key in pairs(remoteOnly) do keys[key] = true end
  for key, member in pairs(members) do
    local entry = byKey[key]
    keys[key] = true
    if entry then
      local cached = self.saveCache[key]
      if not (cached and cached.source == entry.blob and cached.version == entry.version
          and cached.id == entry.playthroughId and cached.cart == entry.cart) then
        local save = SaveData.decode(entry.blob)
        if not save then return nil, "A save linked to Box could not be read." end
        save.meta = type(save.meta) == "table" and save.meta or {}
        save.meta.playthroughId = entry.playthroughId
        save.version = save.version or entry.version
        if entry.cart then save.meta.cartId = entry.cart end
        cached = { source = entry.blob, version = entry.version, id = entry.playthroughId, cart = entry.cart,
          blob = Serializer.encode(save) }
        self.saveCache[key] = cached
      end
      member.path, member.slotId, member.cartId, member.deleted = pathOf(entry), entry.slot, entry.cart, nil
      saves[key] = { version = entry.version, blob = cached.blob, meta = Store.copy(entry.meta), slot = entry.slot }
      saves[key].meta.playthroughId = entry.playthroughId
    elseif member.deleted or syncState.pendingDeletes and syncState.pendingDeletes[key] then
      member.deleted = true
      saves[key] = { version = member.version, deleted = true }
    else
      missing[key] = true
      saves[key] = { version = member.version, deleted = true }
    end
  end
  if next(members) then state.syncMembers = members end
  local assets, published = {}, state
  local wallpapers, pending, encodes = {}, {}, {}
  for b, box in ipairs(state.boxes) do
    local bytes = box.wallpaper and self.fs.read(box.wallpaper)
    wallpapers[b] = bytes
    local cached = bytes and self.assetCache[box.wallpaper]
    if bytes and not (cached and cached.bytes == bytes) and not pending[box.wallpaper]
        and Transaction.assetValid(box.wallpaper, bytes) then
      pending[box.wallpaper] = bytes
      encodes[#encodes + 1] = { n = 1, bytes, name = box.wallpaper }
    end
  end
  local encoded = Work.batch("base64Encode", encodes)
  for i, job in ipairs(encodes) do
    self.assetCache[job.name] = { bytes = job[1], encoded = encoded[i][1] }
  end
  for b, box in ipairs(state.boxes) do
    local bytes = wallpapers[b]
    if box.wallpaper and bytes == nil and not self.fs.getInfo(box.wallpaper) then
      if published == state then published = Store.copy(state) end
      published.boxes[b].wallpaper = nil
    elseif box.wallpaper then
      local cached = self.assetCache[box.wallpaper]
      if not (cached and cached.bytes == bytes) then
        if not Transaction.assetValid(box.wallpaper, bytes) then return nil, "A Box wallpaper is missing or unreadable." end
        cached = { bytes = bytes, encoded = Base64.encode(bytes) }
        self.assetCache[box.wallpaper] = cached
      end
      assets[box.wallpaper] = cached.encoded
    end
  end
  local snapshot = { format = 1, blob = Work.call("encode", published), assets = assets, saves = saves,
    meta = { count = Store.count(state), savedAt = state.savedAt or 0 } }
  return { payload = snapshot, fingerprint = SyncBox.fingerprint(snapshot), keys = keys,
    missing = missing, remoteOnly = remoteOnly, exists = body ~= nil, state = state, body = body }
end

function SyncBox:remember(snapshot, entries, syncState)
  local current, why = self:snapshot(entries, syncState, snapshot.saves)
  if not current then return nil, why end
  local before = self.fs.read(Store.PATH)
  if Work.async() and before ~= current.body then return nil, CHANGED end
  local after = Work.call("encode", current.state)
  if before == after then return true, false end
  local ok, err = Transaction.commitSync(self.fs, { { path = Store.PATH, before = before, after = after } })
  return ok, err or true
end

function SyncBox.validate(snapshot)
  if type(snapshot) ~= "table" or snapshot.format ~= 1 or type(snapshot.blob) ~= "string"
      or #snapshot.blob > Client.MAX_BOX_BLOB or type(snapshot.assets) ~= "table"
      or type(snapshot.saves) ~= "table" then return nil, "The cloud Box snapshot is invalid." end
  local state = Work.call("decode", snapshot.blob, { maxBytes = Client.MAX_BOX_BLOB, maxNodes = 2000000 })
  local valid, why = Store.validate(state)
  if not valid then return nil, why end
  local assets, references = {}, {}
  for _, box in ipairs(state.boxes) do if box.wallpaper then references[box.wallpaper] = true end end
  local names, decodes, badAsset = {}, {}, false
  for name, encoded in pairs(snapshot.assets) do
    if type(encoded) ~= "string" or #encoded > 2800000 or not references[name] then badAsset = true; break end
    names[#names + 1] = name
    decodes[#decodes + 1] = { n = 1, encoded }
  end
  local decoded = Work.batch("base64Decode", decodes)
  for i, name in ipairs(names) do
    local bytes = decoded[i][1]
    if not Transaction.assetValid(name, bytes) then return nil, "A cloud Box wallpaper is unreadable." end
    assets[name] = bytes
  end
  if badAsset then return nil, "A cloud Box wallpaper is invalid." end
  for name in pairs(references) do if not assets[name] then return nil, "The cloud snapshot is missing a Box wallpaper." end end
  local saves, count, rows, blobs, rowError = {}, 0, {}, {}, nil
  for key, row in pairs(snapshot.saves) do
    count = count + 1
    local version, id = split(key)
    if not version or count > SyncBox.MAX_MEMBERS or type(row) ~= "table" or row.version ~= version then
      rowError = "A cloud Box save link is invalid."; break
    end
    if row.deleted then
      if row.blob ~= nil then rowError = "A deleted cloud save has conflicting data."; break end
      rows[#rows + 1] = { key = key, version = version, id = id, deleted = true }
    else
      if type(row.blob) ~= "string" or #row.blob > Client.MAX_BLOB or type(row.meta) ~= "table"
          or row.meta.playthroughId ~= id then rowError = "A cloud Box game save is invalid."; break end
      rows[#rows + 1] = { key = key, version = version, id = id }
      blobs[#blobs + 1] = { n = 1, row.blob, row = #rows }
    end
  end
  local decodedSaves = Work.batch("decode", blobs)
  for i, job in ipairs(blobs) do rows[job.row].save = decodedSaves[i][1] end
  for _, entry in ipairs(rows) do
    local key, version, id = entry.key, entry.version, entry.id
    if entry.deleted then
      saves[key] = { version = version, id = id, deleted = true }
    else
      local save = entry.save
      local native = save and save.engine == "game3" and type(save.name) == "string"
        and type(save.party) == "table" and type(save.bag) == "table"
      if type(save) ~= "table" or (type(save.player) ~= "table" and not native)
          or save.version and save.version ~= version or save.generation and save.generation ~= Version.generation(version)
          or save.meta and type(save.meta) ~= "table"
          or save.meta and save.meta.playthroughId and save.meta.playthroughId ~= id then
        return nil, "A cloud Box game save does not match its playthrough."
      end
      save.version = version
      save.meta = save.meta or {}; save.meta.playthroughId = id
      local cart = save.meta.cartId
      if cart ~= nil and (type(cart) ~= "string" or #cart > 64 or not cart:match("^[%w%._%-]+$")) then
        return nil, "A cloud Box cart identity is invalid."
      end
      saves[key] = { version = version, id = id, cart = cart, save = save }
    end
  end
  if rowError then return nil, rowError end
  for key, member in pairs(state.syncMembers or {}) do
    if not saves[key] then return nil, "The cloud snapshot is missing a linked save." end
    if not saves[key].deleted and saves[key].cart ~= member.cartId then return nil, "A cloud Box link points to a different cart." end
  end
  for _, key in ipairs(snapshot.members or {}) do if not saves[key] then return nil, "The cloud snapshot is incomplete." end end
  return { state = state, saves = saves, assets = assets }
end

function SyncBox:archive(snapshot)
  local valid, why = SyncBox.validate(snapshot)
  if not valid then return nil, why end
  local path = "box/conflicts/" .. os.time() .. "-" .. SaveData.newPlaythroughId() .. ".lua"
  if not self.fs.createDirectory("box/conflicts") then return nil, "Could not make the Box sync backup directory." end
  local body = Work.call("encode", snapshot)
  local ok, err = self.fs.write(path, body)
  if not ok or self.fs.read(path) ~= body then return nil, err or "The Box sync backup could not be verified." end
  local index = Serializer.encode({ path = path })
  ok, err = self.fs.write("box/last-sync-backup.lua", index)
  if not ok or self.fs.read("box/last-sync-backup.lua") ~= index then return nil, err or "The Box backup index could not be verified." end
  return path
end

function SyncBox:latestBackup()
  local body = self.fs.read("box/last-sync-backup.lua")
  local index = Serializer.decode(body)
  if type(index) == "table" and type(index.path) == "string"
      and index.path:match("^box/conflicts/%d+%-[%w%-]+%.lua$") and self.fs.getInfo(index.path) then return index.path end
  if not self.fs.getDirectoryItems then return nil end
  local latest
  for _, name in ipairs(self.fs.getDirectoryItems("box/conflicts") or {}) do
    if name:match("^%d+%-[%w%-]+%.lua$") and (not latest or name > latest) then latest = name end
  end
  return latest and "box/conflicts/" .. latest
end

function SyncBox:readBackup(path)
  if type(path) ~= "string" or not path:match("^box/conflicts/%d+%-[%w%-]+%.lua$") then
    return nil, "Choose a Box sync recovery backup."
  end
  local body = self.fs.read(path)
  if not body or #body > Client.MAX_BOX_BODY * 2 then return nil, "The Box sync backup could not be read." end
  local snapshot = Work.call("decode", body, { maxBytes = Client.MAX_BOX_BODY * 2, maxNodes = 4000000 })
  local valid, why = SyncBox.validate(snapshot)
  if not valid then return nil, why end
  return snapshot, valid
end

function SyncBox:apply(snapshot, entries, syncState, expected)
  local stamp
  if Work.async() then
    stamp = { [Store.PATH] = self.fs.read(Store.PATH) or false }
    local linked = type(snapshot) == "table" and type(snapshot.saves) == "table" and snapshot.saves or {}
    for _, entry in ipairs(entries) do
      local path = linked[entry.version .. "/" .. entry.playthroughId] ~= nil and pathOf(entry)
      if path then stamp[path] = self.fs.read(path) or false end
    end
  end
  local function before(path)
    if stamp and stamp[path] ~= nil then return stamp[path] or nil end
    return self.fs.read(path)
  end
  local valid, why = SyncBox.validate(snapshot)
  if not valid then return nil, why end
  local current, err = self:snapshot(entries, syncState, snapshot.saves)
  if not current then return nil, err end
  if expected and current.fingerprint ~= expected then return nil, "Box or a linked save changed during sync. Sync again." end
  local optionsBefore = self.fs.read("options.lua")
  if optionsBefore == nil and self.fs.getInfo("options.lua") then return nil, "Local save-slot settings could not be read." end
  local options = {}
  if optionsBefore ~= nil then options = Work.call("decode", optionsBefore) end
  if type(options) ~= "table" then return nil, "Local save-slot settings could not be read." end
  local byKey = {}
  for _, entry in ipairs(entries) do byKey[entry.version .. "/" .. entry.playthroughId] = entry end
  local jobs, downloads, mapping = {}, {}, {}
  local state = Store.copy(valid.state)
  state.syncMembers = {}
  for key, row in pairs(valid.saves) do
    local entry = byKey[key]
    local oldLink = valid.state.syncMembers and valid.state.syncMembers[key]
    if entry and entry.cart ~= row.cart and not row.deleted then return nil, "A cloud save points to a different cart." end
    local cart = row.cart or entry and entry.cart or oldLink and oldLink.cartId
    if cart and not row.deleted then
      local registered = options.carts and options.carts[cart]
      local installed = self.fs.getInfo(require("src.carts.CartStore").fileFor(cart))
      if not registered and not installed then return false, "Install the \"" .. cart .. "\" cart before syncing this Box collection." end
    end
    local scope = cart and "cart_" .. cart or row.version
    local root = cart and "cartSlots" or "saveSlots"
    local regKey = cart or row.version
    options[root] = options[root] or {}
    local reg = Store.copy(options[root][regKey] or { list = {} })
    reg.list = reg.list or {}
    local slot = entry and entry.slot
    local created = false
    if not slot and not row.deleted then
      local max = 0
      for _, id in ipairs(reg.list) do max = math.max(max, tonumber(id:match("^slot(%d+)$")) or 0) end
      repeat max = max + 1; slot = "slot" .. max until not self.fs.getInfo("saves/" .. scope .. "/" .. slot .. ".lua")
      reg.list[#reg.list + 1] = slot; reg.active = reg.active or slot; created = true
    end
    local path = slot and pathOf({ version = row.version, cart = cart, slot = slot })
    if slot and not path then return nil, "A local save slot is invalid. Restart G1R before syncing Box." end
    if oldLink and path then mapping[oldLink.path] = { path = path, slot = slot, cart = cart } end
    options.playthroughIds = options.playthroughIds or {}
    options.playthroughIds[scope] = options.playthroughIds[scope] or {}
    if path then
      jobs[#jobs + 1] = { path = path, before = before(path), save = not row.deleted and row.save or nil, deleted = row.deleted }
      if row.deleted then
        local list = {}; for _, id in ipairs(reg.list) do if id ~= slot then list[#list + 1] = id end end
        reg.list = list
        if reg.active == slot then reg.active = list[1] end
        for _, field in ipairs({ "names", "hashes", "broken" }) do if reg[field] then reg[field][slot] = nil end end
        options.playthroughIds[scope][slot] = nil
      else
        options.playthroughIds[scope][slot] = row.id
        if cart then
          reg.hashes = reg.hashes or {}; reg.hashes[slot] = row.save.meta.cartHash
          reg.broken = reg.broken or {}; reg.broken[slot] = row.save.meta.sealBroken == true or nil
        end
      end
      downloads[#downloads + 1] = { version = row.version, cart = cart, slot = slot,
        created = created, removed = row.deleted, device = snapshot.meta and snapshot.meta.device }
    end
    options[root][regKey] = reg
    state.syncMembers[key] = { version = row.version, playthroughId = row.id, cartId = cart,
      slotId = slot or "slot0", path = path or "saves/" .. scope .. "/slot0.lua", deleted = row.deleted }
  end
  local function remap(entry)
    if entry.slotId then
      local old = pathOf({ version = entry.version, cart = entry.cartId, slot = entry.slotId })
      local target = mapping[old]
      if target then entry.slotId, entry.cartId = target.slot, target.cart end
    end
    for _, original in ipairs(entry.archives or {}) do remap(original) end
  end
  for _, box in ipairs(state.boxes) do for _, entry in pairs(box.mons) do remap(entry) end end
  for _, departure in pairs(state.departures or {}) do
    if mapping[departure.path] then departure.path = mapping[departure.path].path end
    remap(departure.entry)
  end
  local encodes = {}
  for _, job in ipairs(jobs) do if job.save then encodes[#encodes + 1] = { n = 1, job.save, job = job } end end
  local encoded = Work.batch("encode", encodes)
  for i, item in ipairs(encodes) do item.job.after, item.job.save = encoded[i][1], nil end
  for name, bytes in pairs(valid.assets) do jobs[#jobs + 1] = { kind = "asset", path = name, before = self.fs.read(name), after = bytes } end
  jobs[#jobs + 1] = { path = "options.lua", before = optionsBefore, after = Work.call("encode", options) }
  jobs[#jobs + 1] = { path = Store.PATH, before = before(Store.PATH), after = Work.call("encode", state) }
  local backup, backupErr = self:archive(current.payload)
  if not backup then return nil, backupErr end
  for path, body in pairs(stamp or {}) do
    if self.fs.read(path) ~= (body or nil) then return nil, CHANGED end
  end
  local ok, failure = Transaction.commitSync(self.fs, jobs)
  if not ok then return nil, failure end
  for _, row in ipairs(downloads) do SaveData.refreshSlotResolution(row.cart and "cart_" .. row.cart or row.version) end
  local Themes = package.loaded["src.box.Themes"]
  if type(Themes) == "table" and Themes.forget then
    for _, job in ipairs(jobs) do
      if job.kind == "asset" then Themes.forget(job.path) end
    end
  end
  require("src.box.Catalog").reset()
  downloads[#downloads + 1] = { box = true, backup = backup }
  return downloads
end

return SyncBox
