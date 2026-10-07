local bit = require("bit")
local Identity = require("src.core.TrainerIdentity")
local Store = require("src.box.Store")
local Transaction = require("src.box.Transaction")
local GameVersion = require("src.core.GameVersion")
local TrainerIdSync = {}

function TrainerIdSync.generationOf(save, version)
  if type(save) ~= "table" then return nil end
  if save.engine == "game3" or save.generation == 3 then return 3 end
  if save.generation == 2 then return 2 end
  local info = GameVersion.info(type(save.version) == "string" and save.version or version)
    or GameVersion.info(version)
  return info and info.generation or 1
end

function TrainerIdSync.playerIdOf(save, gen)
  if type(save) ~= "table" then return nil end
  return Identity.u16(gen == 3 and save.trainerId or save.player and save.player.id)
end

function TrainerIdSync.addOwner(owners, profile, gen)
  for g = 1, 2 do owners[Identity.key(g, profile.id, profile.name)] = profile end
  owners[Identity.key(3, profile.id, profile.name, gen == 3 and profile.sid or 0)] = profile
end

local function each(list, fn)
  for _, value in pairs(type(list) == "table" and list or {}) do fn(value) end
end

function TrainerIdSync.monsOf(save, gen)
  local out, seen = {}, {}
  local function add(mon)
    if type(mon) == "table" and not seen[mon] then seen[mon], out[#out + 1] = true, mon end
  end
  each(save.party, add)
  if gen == 3 then
    each(type(save.storage) == "table" and save.storage.boxes,
      function(box) each(type(box) == "table" and box.mons, add) end)
    each(save.savedPlayerParty, add)
    local tower = type(save.frontier) == "table" and save.frontier.towerPlayer
    each(type(tower) == "table" and tower.party, add)
    for key, mod in pairs(type(save.modData) == "table" and save.modData or {}) do
      if type(key) == "string" and key:match("_daycare$") and type(mod) == "table" then
        local dc = mod.daycare
        if type(dc) == "table" then add(dc[1]); add(dc[2]); each(dc.mons, add) end
        if type(mod.route5Daycare) == "table" then add(mod.route5Daycare.mon) end
      end
    end
  else
    each(save.boxes or (save.box and { save.box }),
      function(box) each(box, add) end)
    if type(save.daycare) == "table" then add(save.daycare.mon) end
    if type(save.orphaned) == "table" then each(save.orphaned.mons, add) end
    if gen == 2 and type(save.dayCare) == "table" then
      local dc = save.dayCare
      if type(dc.man) == "table" then add(dc.man.mon) end
      if type(dc.lady) == "table" then add(dc.lady.mon) end
      add(dc.egg)
    end
  end
  return out
end

local function syncMon(mon, gen, target, owners, localOwner, report)
  if not Identity.owner(mon, gen, owners, localOwner) then
    if (mon.otId ~= nil or mon.cartRaw ~= nil) and Identity.monName(mon) == nil then
      report.unknown = report.unknown + 1
    end
    return false
  end
  local changed = false
  if gen == 3 then
    local pid, why = Identity.personality(mon, target)
    if not pid then return nil, why end
    if pid ~= mon.personality then
      mon.personality, changed = pid, true
      report.personalities = report.personalities + 1
      if tonumber(mon.species) == 308 then report.spinda = report.spinda + 1 end
    end
    if mon.otSecretId ~= target.sid then mon.otSecretId, changed = target.sid, true end
  end
  local id = Identity.u16(mon.otId) or Identity.rawId(mon, gen)
  if id ~= target.id or mon.otId ~= nil and mon.otId ~= target.id then
    if gen == 1 and type(mon.cartRaw) == "string" then
      mon.cartRaw = mon.cartRaw:sub(1, 24) .. ("%04X"):format(target.id) .. mon.cartRaw:sub(29)
    elseif gen == 2 and type(mon.cartRaw) == "string" then
      require("src.save_convert.Gen2Save").rewriteCarrierId(mon, target.id)
    end
    if mon.otId ~= nil or gen ~= 1 or not mon.cartRaw then mon.otId = target.id end
    changed = true
  end
  local renamed, why = Identity.rename(mon, target.name, gen)
  if renamed == nil then return nil, why end
  changed = changed or renamed
  if mon.traded then mon.traded, changed = nil, true end
  if changed then report.mons = report.mons + 1 end
  return changed
end

local function syncRawDaycare(save, gen, target, owners, localOwner, report)
  local dc = gen == 1 and type(save.daycare) == "table" and save.daycare or nil
  local raw = dc and dc.mon == nil and type(dc.cartRaw) == "string" and dc.cartRaw or nil
  if not raw or #raw < 112 or raw:find("[^%x]") then return false end
  local view = { cartOt = raw:sub(25, 46), cartRaw = raw:sub(47) }
  local changed, why = syncMon(view, gen, target, owners, localOwner, report)
  if changed == nil then return nil, why end
  if changed then dc.cartRaw = raw:sub(1, 24) .. view.cartOt .. view.cartRaw end
  return changed
end

local function syncMail(mail, gen, target, owners, localOwner)
  if type(mail) ~= "table" then return false end
  local name = gen == 2 and mail.author or mail.playerName
  local id = gen == 2 and mail.authorId or mail.trainerId
  local full = Identity.packed(id)
  if not full or type(name) ~= "string" then return false end
  local sid = math.floor(full / 65536)
  if gen == 3 and full < 65536 and localOwner and localOwner.id == full
      and localOwner.name == name then sid = localOwner.sid end
  if not owners[Identity.key(gen, full % 65536, name, sid)] then return false end
  local nextId = gen == 2 and target.id or target.id + target.sid * 65536
  if id == nextId and name == target.name then return false end
  if gen == 2 then mail.authorId, mail.author = nextId, target.name
  else mail.trainerId, mail.playerName = nextId, target.name end
  return true
end

local function syncExtras(save, gen, target, owners, old)
  local changed = false
  if gen == 2 then
    local mail = type(save.mail) == "table" and save.mail or {}
    for _, key in ipairs({ "party", "box" }) do
      each(mail[key], function(m) changed = syncMail(m, gen, target, owners, old) or changed end)
    end
  elseif gen == 3 then
    each(save.mail, function(m) changed = syncMail(m, gen, target, owners, old) or changed end)
    for key, mod in pairs(save.modData or {}) do
      if type(key) == "string" and key:match("_daycare$") and type(mod) == "table" then
        local dc = type(mod.daycare) == "table" and mod.daycare or {}
        each(dc.mail, function(m)
          if type(m) == "table" then changed = syncMail(m.message, gen, target, owners, old) or changed end
        end)
        local r5 = type(mod.route5Daycare) == "table" and mod.route5Daycare
        if r5 and type(r5.mail) == "table" then
          changed = syncMail(r5.mail.message, gen, target, owners, old) or changed
        end
      end
    end
    local base = type(save.secretBases) == "table" and save.secretBases[1]
    local tid = type(base) == "table" and base.trainerId
    if type(tid) == "table" and tid[1] == old.id % 256 and tid[2] == math.floor(old.id / 256)
        and tid[3] == old.sid % 256 and tid[4] == math.floor(old.sid / 256)
        and (base.trainerName == nil or base.trainerName == old.name) then
      if old.id ~= target.id or old.sid ~= target.sid or old.name ~= target.name then
        base.trainerId = { target.id % 256, math.floor(target.id / 256),
          target.sid % 256, math.floor(target.sid / 256) }
        if base.trainerName ~= nil then base.trainerName = target.name end
        changed = true
      end
    end
  end
  return changed
end

local function reportNew() return { mons = 0, personalities = 0, spinda = 0, unknown = 0 } end

function TrainerIdSync.rewriteSave(save, gen, target, owners, report)
  local old = Identity.profile(save, gen)
  if not old or type(target) ~= "table" then return nil, "The save has no complete trainer identity." end
  report = report or reportNew()
  local changed = old.id ~= target.id or old.name ~= target.name or gen == 3 and old.sid ~= target.sid
  for _, mon in ipairs(TrainerIdSync.monsOf(save, gen)) do
    local updated, why = syncMon(mon, gen, target, owners, old, report)
    if updated == nil then return nil, why end
    changed = updated or changed
  end
  local daycare, why = syncRawDaycare(save, gen, target, owners, old, report)
  if daycare == nil then return nil, why end
  changed = daycare or changed
  changed = syncExtras(save, gen, target, owners, old) or changed
  if gen == 3 then
    save.trainerId, save.secretId, save.name = target.id, target.sid, target.name
    if save.playerName ~= nil then save.playerName = target.name end
  else save.player.id, save.player.name = target.id, target.name end
  return changed
end

local function scopes(SaveData)
  local out = {}
  for _, version in ipairs(GameVersion.ORDER) do out[#out + 1] = { key = version, version = version } end
  local options = SaveData.loadOptions()
  for _, id in ipairs(SaveData.cartsWithSlots()) do
    local row = type(options.carts) == "table" and options.carts[id]
    out[#out + 1] = { key = "cart_" .. id, cart = id, version = type(row) == "table" and row.base }
  end
  return out
end

function TrainerIdSync.newJob(source, SaveData)
  SaveData = SaveData or require("src.core.SaveData")
  local fs = SaveData.persistenceFs()
  local job = setmetatable({ SaveData = SaveData, fs = fs, source = source, entries = {},
    phase = "read", at = 0, owners = {}, written = 0, failed = {}, report = reportNew(), jobs = {} },
    { __index = TrainerIdSync })
  local ok, why = Transaction.recover(fs)
  if not ok then job.error, job.phase = why, "done"; return job end
  job.warehouse, why, job.boxBody = Store.load(fs)
  if not job.warehouse then job.error, job.phase = why, "done"; return job end
  for _, scope in ipairs(scopes(SaveData)) do
    local slots = scope.cart and SaveData.listCartSlots(scope.cart) or SaveData.listSlots(scope.version)
    for _, slot in ipairs(slots) do
      local path = "saves/" .. scope.key .. "/" .. slot.id .. ".lua"
      if slot.exists or fs.getInfo(path) or fs.getInfo(path .. ".bak") or fs.getInfo(path .. ".tmp") then
        job.entries[#job.entries + 1] = { scope = scope.key, cart = scope.cart,
          version = scope.version, slot = slot.id, path = path }
      end
    end
  end
  job.optionsBody = fs.read("options.lua")
  return job
end

function TrainerIdSync:progress()
  if self.phase == "done" then return 1 end
  return math.min(0.99, ((self.phase == "read" and 0 or #self.entries) + self.at) / math.max(1, 2 * #self.entries + 1))
end

function TrainerIdSync:_check(e)
  if e.cart and self.SaveData.slotSealBroken(e.cart, e.slot) then return nil, "A save's seal is broken." end
  local ok, pending = pcall(require("src.online.Trade").pendingSentAt, e.path)
  if not ok or type(pending) ~= "table" then return nil, "Online trade status could not be read." end
  if #pending > 0 then return nil, "Finish the pending online trade before using ID Sync." end
  return true
end

function TrainerIdSync:_read(e)
  local ok, why = self:_check(e)
  if not ok then return nil, why end
  e.before = self.fs.read(e.path)
  e.save = e.before and self.SaveData.decode(e.before)
  if type(e.save) ~= "table" then return nil, "A save could not be read: " .. e.path end
  e.version = e.save.version or e.version
  e.gen = TrainerIdSync.generationOf(e.save, e.version)
  e.profile = Identity.profile(e.save, e.gen)
  if not GameVersion.VERSIONS[e.version] or not e.profile
      or e.gen ~= GameVersion.generation(e.version) then
    return nil, "A save has an incomplete or mismatched trainer profile: " .. e.path
  end
  TrainerIdSync.addOwner(self.owners, e.profile, e.gen)
  if e.scope == self.source.scope and e.slot == self.source.slot then self.target = Store.copy(e.profile) end
  return true
end

function TrainerIdSync:_target()
  if not self.target then return nil, "The selected save has no complete trainer identity." end
  if self.target.sid == nil then
    for _, e in ipairs(self.entries) do
      if e.gen == 3 then self.target.sid = bit.bxor(e.profile.sid, e.profile.id, self.target.id); break end
    end
    self.target.sid = self.target.sid or 0
  end
  local checked = {}
  for _, e in ipairs(self.entries) do checked[e.gen] = true end
  local function checkEntry(entry)
    checked[entry.generation] = true
    for _, original in ipairs(entry.archives or {}) do checked[original.generation] = true end
  end
  if self.boxBody then
    for _, box in ipairs(self.warehouse.boxes) do each(box.mons, checkEntry) end
    each(self.warehouse.departures, function(d) checkEntry(d.entry) end)
  end
  for gen in pairs(checked) do
    local codes, why
    if gen < 3 then codes, why = Identity.nameCodes(self.target.name, gen)
    else
      local Codec = require("src.save_convert.Gen3Save")
      local encoded = Codec.encodeString(self.target.name, 8)
      codes = encoded:find("\255", 1, true) ~= nil
        and Codec.decodeString(encoded, 0, 8) == self.target.name
      if not codes then why = "The trainer name cannot be represented in a Gen 3 save." end
    end
    if not codes then return nil, why end
  end
  self.newId = self.target.id
  return true
end

function TrainerIdSync:_plan(e)
  local changed, why = TrainerIdSync.rewriteSave(e.save, e.gen, self.target, self.owners, self.report)
  if changed == nil then return nil, e.path .. ": " .. why end
  e.changed = changed
  return true
end

function TrainerIdSync:_box()
  if not self.boxBody then return true end
  local Catalog, Records, Gifts = require("src.box.Catalog"), require("src.box.Records"), require("src.box.Gifts")
  local function entrySync(entry)
    local changed, why = syncMon(entry.mon, entry.generation, self.target, self.owners, nil, self.report)
    if changed == nil then return nil, why end
    if changed then entry.display = Catalog.describe(entry.version, entry.mon) end
    for _, original in ipairs(entry.archives or {}) do
      local ok, err = entrySync(original)
      if not ok then return nil, err end
    end
    if entry.generation == 3 and entry.depositorId ~= nil then
      for _, e in ipairs(self.entries) do
        if e.gen == 3 and entry.depositorId == e.profile.id + e.profile.sid * 65536
            and (entry.slotId == nil or entry.slotId == e.slot and entry.version == e.version and entry.cartId == e.cart) then
          entry.depositorId = self.target.id + self.target.sid * 65536
          break
        end
      end
    end
    return true
  end
  for _, box in ipairs(self.warehouse.boxes) do
    for _, entry in pairs(box.mons) do
      local ok, why = entrySync(entry)
      if not ok then return nil, why end
    end
  end
  for _, departure in pairs(self.warehouse.departures or {}) do
    local ok, why = entrySync(departure.entry)
    if not ok then return nil, why end
    departure.identity = Records.identity(departure.entry.generation, departure.entry.mon)
  end
  for _, e in ipairs(self.entries) do
    local source = { version = e.version, path = e.path }
    local original = self.SaveData.decode(e.before)
    local oldKey, newKey = Gifts.identity(source, original), Gifts.identity(source, e.save)
    local progress = self.warehouse.progress
    if progress and progress[oldKey] ~= nil and oldKey ~= newKey then
      progress[newKey] = math.max(progress[newKey] or 0, progress[oldKey])
      progress[oldKey] = nil
    end
  end
  return true
end

function TrainerIdSync:_commit()
  local ok, why
  local changed = false
  for _, e in ipairs(self.entries) do
    if self.boxBody or e.changed then
      local meta = type(e.save.meta) == "table" and e.save.meta or {}
      e.save.meta = meta
      if self.boxBody then
        local opts = self.SaveData.loadOptions()
        local mapped = opts.playthroughIds and opts.playthroughIds[e.scope]
        local id = meta.playthroughId or mapped and mapped[e.slot] or self.SaveData.newPlaythroughId()
        if meta.playthroughId ~= id or e.cart and meta.cartId ~= e.cart then e.changed = true end
        meta.playthroughId = id
        if e.cart then meta.cartId = e.cart end
        self.warehouse.syncMembers = self.warehouse.syncMembers or {}
        self.warehouse.syncMembers[e.version .. "/" .. meta.playthroughId] = {
          version = e.version, playthroughId = meta.playthroughId, path = e.path, cartId = e.cart, slotId = e.slot }
      end
      if e.changed then
        meta.savedAt = os.time()
        self.jobs[#self.jobs + 1] = { path = e.path, before = e.before, after = self.SaveData.encode(e.save) }
        changed = true
      end
    end
  end
  ok, why = self:_box()
  if not ok then return nil, why end
  if self.boxBody and self.SaveData.encode(self.warehouse) ~= self.boxBody then
    local members = 0
    for _ in pairs(self.warehouse.syncMembers or {}) do members = members + 1 end
    if members > 240 then return nil, "ID Sync exceeds the 240-save cloud Box limit." end
    self.warehouse.revision, self.warehouse.savedAt = self.warehouse.revision + 1, os.time()
    self.jobs[#self.jobs + 1] = { path = Store.PATH, before = self.boxBody, after = self.SaveData.encode(self.warehouse) }
    self.boxUpdated, changed = true, true
  end
  if self.fs.read("options.lua") ~= self.optionsBody or self.fs.read(Store.PATH) ~= self.boxBody then
    return nil, "Save settings or Box changed. Run ID Sync again."
  end
  for _, e in ipairs(self.entries) do
    ok, why = self:_check(e)
    if not ok then return nil, why end
    if self.fs.read(e.path) ~= e.before then return nil, "A save changed. Run ID Sync again." end
  end
  if not changed then return true end
  ok, why = Transaction.commitIdentity(self.fs, self.jobs)
  if not ok then return nil, why end
  for _, e in ipairs(self.entries) do if e.changed then self.written = self.written + 1 end end
  return true
end

function TrainerIdSync:step()
  if self.phase == "done" then return true end
  local ok, why
  if self.phase == "read" or self.phase == "plan" then
    self.at = self.at + 1
    local e = self.entries[self.at]
    if e then
      if self.phase == "read" then ok, why = self:_read(e) else ok, why = self:_plan(e) end
    else ok = true end
    if ok and self.at >= #self.entries then
      if self.phase == "read" then
        ok, why = self:_target()
        if ok then self.phase, self.at = "plan", 0 end
      else self.phase = "commit" end
    end
  else
    ok, why = self:_commit()
    if ok then self.phase = "done"; return true end
  end
  if not ok then self.error, self.phase = why, "done"; return true end
  return false
end

return TrainerIdSync
