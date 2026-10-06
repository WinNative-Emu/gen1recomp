local bit = require("bit")

local TrainerIdSync = {}

local function u16(v)
  local n = tonumber(v)
  if not n or n ~= n or n < 0 or n == math.huge then return nil end
  return math.floor(n) % 65536
end

function TrainerIdSync.generationOf(save, version)
  if type(save) ~= "table" then return nil end
  if save.engine == "game3" or save.generation == 3 then return 3 end
  if save.generation == 2 then return 2 end
  local GameVersion = require("src.core.GameVersion")
  local info = GameVersion.info(type(save.version) == "string" and save.version or version)
  if not info then info = GameVersion.info(version) end
  return info and info.generation or 1
end

function TrainerIdSync.playerIdOf(save, gen)
  if type(save) ~= "table" then return nil end
  if gen == 3 then return u16(save.trainerId) end
  return u16(type(save.player) == "table" and save.player.id or nil)
end

local function reseat(oldId, sid, newId)
  if type(sid) ~= "number" then return sid end
  return bit.band(bit.bxor(sid, oldId, newId), 0xFFFF)
end

local function rawOtId(raw)
  if type(raw) ~= "string" or #raw < 28 then return nil end
  return tonumber(raw:sub(25, 28), 16)
end

local function setRawOtId(raw, id)
  return raw:sub(1, 24) .. ("%04X"):format(id) .. raw:sub(29)
end

local function syncMon(mon, gen, newId, ids)
  if type(mon) ~= "table" then return false end
  if gen == 1 and mon.otId == nil and type(mon.cartRaw) == "string" then
    local id = rawOtId(mon.cartRaw)
    if id and ids[id] and id ~= newId then
      mon.cartRaw = setRawOtId(mon.cartRaw, newId)
      return true
    end
    return false
  end
  local id = u16(mon.otId)
  if not id or not ids[id] then return false end
  local changed = false
  if id ~= newId then
    if gen == 3 then mon.otSecretId = reseat(id, mon.otSecretId, newId) end
    mon.otId = newId
    changed = true
  end
  if gen ~= 3 and mon.traded then
    mon.traded = nil
    changed = true
  end
  return changed
end

local function each(list, fn)
  if type(list) ~= "table" then return end
  for _, v in pairs(list) do fn(v) end
end

local function monsOf(save, gen)
  local out, seen = {}, {}
  local function add(mon)
    if type(mon) == "table" and not seen[mon] then
      seen[mon] = true
      out[#out + 1] = mon
    end
  end
  each(save.party, add)
  if gen == 3 then
    local boxes = type(save.storage) == "table" and save.storage.boxes or nil
    each(boxes, function(box) each(type(box) == "table" and box.mons, add) end)
    each(save.savedPlayerParty, add)
    local tower = type(save.frontier) == "table" and save.frontier.towerPlayer or nil
    each(type(tower) == "table" and tower.party, add)
    for key, mod in pairs(type(save.modData) == "table" and save.modData or {}) do
      if type(key) == "string" and key:match("_daycare$") and type(mod) == "table" then
        local dc = mod.daycare
        if type(dc) == "table" then
          add(dc[1])
          add(dc[2])
          each(dc.mons, add)
        end
        local r5 = mod.route5Daycare
        if type(r5) == "table" then add(r5.mon) end
      end
    end
  else
    each(save.boxes, function(box) each(box, add) end)
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

local function syncExtras(save, gen, oldId, oldSid, newId, newSid, ids)
  local changed = false
  if gen == 2 then
    local hof = type(save.hallOfFame) == "table" and save.hallOfFame.teams or nil
    each(hof, function(team)
      each(type(team) == "table" and team.mons, function(mon)
        local id = type(mon) == "table" and u16(mon.otId)
        if id and ids[id] and id ~= newId then mon.otId = newId; changed = true end
      end)
    end)
    local mail = type(save.mail) == "table" and save.mail or nil
    for _, list in ipairs({ mail and mail.party, mail and mail.box }) do
      each(list, function(m)
        local id = type(m) == "table" and u16(m.authorId)
        if id and ids[id] and id ~= newId then m.authorId = newId; changed = true end
      end)
    end
  elseif gen == 3 then
    each(save.hallOfFameTeams, function(team)
      each(team, function(mon)
        local id = type(mon) == "table" and u16(mon.trainerId)
        if id and ids[id] and id ~= newId then
          mon.otSecretId = reseat(id, mon.otSecretId, newId)
          mon.trainerId = newId
          changed = true
        end
      end)
    end)
    local base = type(save.secretBases) == "table" and save.secretBases[1] or nil
    local tid = type(base) == "table" and base.trainerId or nil
    if type(tid) == "table" and oldId ~= newId
        and tid[1] == oldId % 256 and tid[2] == math.floor(oldId / 256) then
      tid[1], tid[2] = newId % 256, math.floor(newId / 256)
      if type(newSid) == "number" and tid[3] == (oldSid or 0) % 256
          and tid[4] == math.floor((oldSid or 0) / 256) then
        tid[3], tid[4] = newSid % 256, math.floor(newSid / 256)
      end
      changed = true
    end
  end
  return changed
end

function TrainerIdSync.rewriteSave(save, gen, newId, ids)
  if type(save) ~= "table" then return false end
  local changed = false
  local oldId = TrainerIdSync.playerIdOf(save, gen)
  local oldSid, newSid
  if gen == 3 then
    oldSid = save.secretId
    if oldId and oldId ~= newId then
      newSid = reseat(oldId, oldSid, newId)
      save.secretId = newSid
      save.trainerId = newId
      changed = true
    end
  elseif oldId ~= newId then
    save.player = type(save.player) == "table" and save.player or {}
    save.player.id = newId
    changed = true
  end
  for _, mon in ipairs(monsOf(save, gen)) do
    if syncMon(mon, gen, newId, ids) then changed = true end
  end
  if oldId and syncExtras(save, gen, oldId, oldSid, newId, newSid or oldSid, ids) then
    changed = true
  end
  return changed
end

local function scopes(SaveData)
  local GameVersion = require("src.core.GameVersion")
  local out = {}
  for _, version in ipairs(GameVersion.ORDER) do
    out[#out + 1] = { key = version, version = version }
  end
  local ok, ids = pcall(SaveData.cartsWithSlots)
  if ok and type(ids) == "table" then
    local okOpts, options = pcall(SaveData.loadOptions)
    local reg = okOpts and type(options) == "table" and type(options.carts) == "table"
      and options.carts or {}
    for _, id in ipairs(ids) do
      local row = type(reg[id]) == "table" and reg[id] or nil
      out[#out + 1] = { key = "cart_" .. id, cart = id, version = row and row.base or nil }
    end
  end
  return out
end

function TrainerIdSync.newJob(source, SaveData)
  SaveData = SaveData or require("src.core.SaveData")
  local entries = {}
  for _, scope in ipairs(scopes(SaveData)) do
    local okList, slots = pcall(function()
      if scope.cart then return SaveData.listCartSlots(scope.cart) end
      return SaveData.listSlots(scope.version)
    end)
    for _, slot in ipairs(okList and type(slots) == "table" and slots or {}) do
      if slot.exists then
        entries[#entries + 1] = { scope = scope.key, cart = scope.cart,
                                  version = scope.version, slot = slot.id }
      end
    end
  end
  return setmetatable({
    SaveData = SaveData, source = source, entries = entries,
    phase = "read", at = 0, ids = {}, written = 0, failed = {},
  }, { __index = TrainerIdSync })
end

function TrainerIdSync:progress()
  local n = #self.entries
  if n == 0 then return 1 end
  local done = self.phase == "read" and self.at or n + self.at
  if self.phase == "done" then return 1 end
  return math.min(1, done / (2 * n))
end

function TrainerIdSync:_read(e)
  local SaveData = self.SaveData
  local ok, source = pcall(function()
    if e.cart then return SaveData.readCartSlotSource(e.cart, e.slot) end
    return SaveData.readSlotSource(e.version, e.slot)
  end)
  local save = ok and source and SaveData.decode(source) or nil
  if type(save) ~= "table" then return end
  e.save = save
  e.gen = TrainerIdSync.generationOf(save, e.version)
  local id = TrainerIdSync.playerIdOf(save, e.gen)
  if id then self.ids[id] = true end
  if e.scope == self.source.scope and e.slot == self.source.slot then
    self.newId = id
  end
end

function TrainerIdSync:_write(e)
  if type(e.save) ~= "table" then return end
  if not TrainerIdSync.rewriteSave(e.save, e.gen, self.newId, self.ids) then return end
  local meta = type(e.save.meta) == "table" and e.save.meta or {}
  e.save.meta = meta
  meta.savedAt = os.time()
  local SaveData = self.SaveData
  local ok, wrote, err = pcall(function()
    if e.cart then return SaveData.writeCartSlot(e.cart, e.slot, e.save) end
    return SaveData.writeSlot(e.version, e.slot, e.save)
  end)
  if ok and wrote then
    self.written = self.written + 1
  else
    self.failed[#self.failed + 1] = tostring(ok and err or wrote)
  end
end

function TrainerIdSync:step()
  if self.phase == "done" then return true end
  self.at = self.at + 1
  local e = self.entries[self.at]
  if self.phase == "read" then
    if e then self:_read(e) end
    if self.at >= #self.entries then
      if not self.newId then
        self.error = "the selected save has no trainer ID"
        self.phase = "done"
        return true
      end
      self.phase, self.at = "write", 0
    end
    return false
  end
  if e then
    self:_write(e)
    e.save = nil
  end
  if self.at >= #self.entries then
    self.phase = "done"
    return true
  end
  return false
end

return TrainerIdSync
