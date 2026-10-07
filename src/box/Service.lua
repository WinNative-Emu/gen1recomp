local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")
local Serializer = require("src.core.SaveSerializer")
local Store = require("src.box.Store")
local Transaction = require("src.box.Transaction")
local Records = require("src.box.Records")
local Catalog = require("src.box.Catalog")

local Service = {}
Service.__index = Service

local function sourceCart(source)
  return source.cartId or type(source.path) == "string" and source.path:match("^saves/cart_([%w%._%-]+)/slot%d+%.lua$") or nil
end

function Service.open(fs)
  fs = fs or SaveData.persistenceFs()
  if not fs then return nil, "Save storage is unavailable." end
  local ok, why, notice = Transaction.recover(fs)
  if not ok then return nil, why end
  local state, err, body = Store.load(fs)
  if not state then return nil, err end
  local repaired, changed = pcall(require("src.save_convert.Gen3Save").repairJapaneseNames, state)
  if body and repaired and changed then
    local after = Serializer.encode(state)
    if Transaction.commit(fs, { { path = Store.PATH, before = body, after = after } }) then body = after end
  end
  for _, box in ipairs(state.boxes) do
    for _, entry in pairs(box.mons) do entry.display = Catalog.describe(entry.version, entry.mon) end
  end
  return setmetatable({ fs = fs, state = state, body = body, recoveryNotice = notice }, Service)
end

function Service.sources()
  local out = {}
  for _, version in ipairs(GameVersion.ORDER) do
    for _, slot in ipairs(SaveData.listSlots(version)) do
      if slot.exists then
        out[#out + 1] = { version = version, slotId = slot.id,
          path = "saves/" .. version .. "/" .. slot.id .. ".lua",
          label = GameVersion.info(version).label .. " · " .. tostring(slot.name or slot.id) }
      end
    end
  end
  for _, cartId in ipairs(SaveData.cartsWithSlots()) do
    for _, slot in ipairs(SaveData.listCartSlots(cartId)) do
      if slot.exists and not SaveData.slotSealBroken(cartId, slot.id) then
        local body = SaveData.readCartSlotSource(cartId, slot.id)
        local save = body and Serializer.decode(body)
        if type(save) == "table" and GameVersion.VERSIONS[save.version] then
          out[#out + 1] = { version = save.version, slotId = slot.id, cartId = cartId,
            path = "saves/cart_" .. cartId .. "/" .. slot.id .. ".lua",
            label = cartId .. " · " .. tostring(slot.name or slot.id) }
        end
      end
    end
  end
  return out
end

function Service:read(source)
  if type(source) ~= "table" or not GameVersion.VERSIONS[source.version] then return nil, "Choose a save." end
  if source.cartId and SaveData.slotSealBroken(source.cartId, source.slotId) then
    return nil, "This save's seal is broken."
  end
  local checked, pending = pcall(require("src.online.Trade").pendingSentAt, source.path)
  if not checked then return nil, "Online trade status could not be read." end
  if #pending > 0 then return nil, "Finish this save's pending online trade before using Box." end
  local body = self.fs.read(source.path)
  local save, why
  if body then save, why = Serializer.decode(body) end
  if type(save) ~= "table" then return nil, why or "That save could not be read." end
  if save.version and save.version ~= source.version then return nil, "The save's game does not match." end
  if save.generation and save.generation ~= GameVersion.generation(source.version) then
    return nil, "The save's generation does not match."
  end
  if GameVersion.generation(source.version) == 3 then pcall(require("src.save_convert.Gen3Save").repairJapaneseNames, save) end
  return save, nil, body
end

function Service:commit(nextState, source, before, nextSave)
  if source then
    nextSave.meta = type(nextSave.meta) == "table" and nextSave.meta or {}
    local options = SaveData.loadOptions(self.fs)
    local cart = sourceCart(source)
    local scope = cart and "cart_" .. cart or source.version
    local mapped = options.playthroughIds and options.playthroughIds[scope]
    local id = nextSave.meta.playthroughId or mapped and mapped[source.slotId] or SaveData.newPlaythroughId()
    nextSave.meta.playthroughId = id
    if cart then nextSave.meta.cartId = cart end
    nextSave.meta.savedAt = os.time()
    nextState.syncMembers = nextState.syncMembers or {}
    nextState.syncMembers[source.version .. "/" .. id] = { version = source.version,
      playthroughId = id, path = source.path, cartId = cart, slotId = source.slotId }
  end
  nextState.savedAt = os.time()
  local valid, why = Store.validate(nextState)
  if not valid then return nil, why end
  local after = Serializer.encode(nextState)
  local jobs = { { path = Store.PATH, before = self.body, after = after } }
  if source then
    jobs[#jobs + 1] = { path = source.path, before = before, after = Serializer.encode(nextSave) }
  end
  local ok, err = Transaction.commit(self.fs, jobs)
  if not ok then return nil, err end
  self.state, self.body = nextState, after
  return true
end

function Service:audit(source, refs, kind)
  if type(refs) ~= "table" or type(source) ~= "table" then return {} end
  local save = kind == "pc" and self:read(source) or nil
  if kind == "pc" and not save then return {} end
  local generation = GameVersion.generation(source.version)
  local out = {}
  for _, ref in ipairs(refs) do
    local mon, version
    if kind == "pc" then
      mon, version = Records.at(save, generation, ref), source.version
    else
      local entry = Store.at(self.state, ref.box, ref.slot)
      if entry and entry.generation == generation then mon, version = entry.mon, source.version end
    end
    if mon then
      local fatal, fixes = Catalog.check(version, mon)
      if fatal then return {} end
      if #fixes > 0 then out[#out + 1] = { name = Catalog.describe(version, mon).name, fixes = fixes } end
    end
  end
  return out
end

function Service:deposit(source, refs, box, expectedBody, repair)
  if type(refs) ~= "table" or #refs == 0 then return nil, "Select Pokémon to deposit." end
  local save, why, body = self:read(source)
  if not save then return nil, why end
  if expectedBody and body ~= expectedBody then return nil, "That save changed. Reload before transferring." end
  local generation = GameVersion.generation(source.version)
  local nextSave, err = Records.remove(save, generation, refs)
  if not nextSave then return nil, err end
  local nextState = Store.copy(self.state)
  for _, ref in ipairs(refs) do
    local slot = Store.free(nextState, box)
    if not slot then return nil, "That Box does not have enough room." end
    local mon = Records.at(save, generation, ref)
    if not mon then return nil, "A selected Pokémon is missing." end
    if repair then
      local fixed, fixWhy = Catalog.repair(source.version, mon)
      if not fixed then return nil, fixWhy end
      mon = fixed
    end
    if ref.where == "party" then mon = Records.enterBox(source.version, generation, Store.copy(mon)) end
    local legal, why = Catalog.compatible({ generation = generation, mon = mon }, source.version)
    if not legal then return nil, why end
    local identity, returned = Records.identity(generation, mon), nil
    if identity then
      local matches = {}
      for id, departure in pairs(nextState.departures or {}) do
        if departure.identity == identity and departure.entry.generation == generation then matches[#matches + 1] = id end
      end
      if #matches == 1 then returned = matches[1] end
    end
    local entry = returned and Store.copy(nextState.departures[returned].entry) or { id = nextState.nextId }
    entry.version, entry.generation, entry.slotId, entry.cartId = source.version, generation, source.slotId, sourceCart(source)
    entry.mon, entry.display = Store.copy(mon), Catalog.describe(source.version, mon)
    if returned then nextState.departures[returned] = nil else nextState.nextId = nextState.nextId + 1 end
    if generation == 3 then entry.depositorId = require("src.box.Gifts").trainerId(save) end
    nextState.boxes[box].mons[slot] = entry
  end
  nextState.revision = nextState.revision + 1
  require("src.box.Gifts").recordProgress(nextState, source, nextSave)
  return self:commit(nextState, source, body, nextSave)
end

function Service:withdraw(source, refs, pcBox, repair)
  if type(refs) ~= "table" or #refs == 0 then return nil, "Select Pokémon to withdraw." end
  local save, why, body = self:read(source)
  if not save then return nil, why end
  local nextState, entries, ids = Store.copy(self.state), {}, {}
  for _, ref in ipairs(refs) do
    local entry = Store.at(nextState, ref.box, ref.slot)
    if not entry or ids[entry.id] then return nil, "A selected Box Pokémon is missing." end
    if entry.generation ~= GameVersion.generation(source.version) then
      local converted, convertWhy = require("src.box.Migration").convert(entry, source.version)
      if not converted then return nil, tostring(entry.display and entry.display.name or "This Pokémon") .. ": " .. tostring(convertWhy) end
      local snapshot = Store.copy(entry); snapshot.archives = nil
      entry.archives = entry.archives or {}; entry.archives[#entry.archives + 1] = snapshot
      entry.version, entry.generation, entry.mon = source.version, GameVersion.generation(source.version), converted
      entry.display, entry.gciRaw, entry.gciOriginal = Catalog.describe(source.version, converted), nil, nil
    end
    if repair and entry.generation == GameVersion.generation(source.version) then
      local fixed, fixWhy = Catalog.repair(source.version, entry.mon)
      if not fixed then return nil, fixWhy end
      entry.mon, entry.display = fixed, Catalog.describe(entry.version, fixed)
    end
    local ok, err = Catalog.compatible(entry, source.version)
    if not ok then return nil, err end
    ids[entry.id] = true
    entries[#entries + 1] = entry
    nextState.departures = nextState.departures or {}
    nextState.departures[entry.id] = { entry = Store.copy(entry), identity = Records.identity(entry.generation, entry.mon), path = source.path }
    nextState.boxes[ref.box].mons[ref.slot] = nil
  end
  local nextSave, err = Records.insert(save, GameVersion.generation(source.version), pcBox, entries)
  if not nextSave then return nil, err end
  nextState.revision = nextState.revision + 1
  return self:commit(nextState, source, body, nextSave)
end

function Service:movePC(source, refs, target, expectedBody)
  if type(refs) ~= "table" or #refs == 0 then return nil, "Select Pokémon to move." end
  local save, why, body = self:read(source)
  if not save then return nil, why end
  if expectedBody and body ~= expectedBody then return nil, "That save changed. Reload before moving." end
  local generation = GameVersion.generation(source.version)
  local count, capacity = generation == 1 and 12 or 14, generation == 3 and 30 or 20
  local function whole(n, hi) return type(n) == "number" and n == math.floor(n) and n >= 1 and n <= hi end
  if type(target) ~= "table" or target.where ~= "party"
      and not (whole(target.box, count) and whole(target.index, capacity)) then
    return nil, "Choose a valid destination PC box."
  end
  local mons = {}
  for i, ref in ipairs(refs) do
    local mon = Records.at(save, generation, ref)
    if not mon then return nil, "A selected Pokémon is missing." end
    mons[i] = Store.copy(mon)
    if target.where == "party" and ref.where ~= "party" then
      Records.leaveBox(source.version, generation, mons[i])
    elseif target.where ~= "party" and ref.where == "party" then
      Records.enterBox(source.version, generation, mons[i])
    end
  end
  local nextSave, err = Records.remove(save, generation, refs)
  if not nextSave then return nil, err end
  if target.where == "party" then
    nextSave.party = nextSave.party or {}
    if #nextSave.party + #mons > 6 then return nil, "The party is full." end
    for _, mon in ipairs(mons) do
      if generation == 3 and (mon.level == nil or mon.hp == nil or mon.maxHp == nil or mon.attack == nil) then
        local d = Catalog.describe(source.version, mon)
        if not d.hp then return nil, "Import complete species data before moving this Pokémon to the party." end
        mon.level, mon.maxHp, mon.hp = d.level, d.hp, d.hp
        for _, key in ipairs({ "attack", "defense", "speed", "spAtk", "spDef" }) do mon[key] = d[key] end
      end
      nextSave.party[#nextSave.party + 1] = mon
      if generation == 2 and type(nextSave.mail) == "table" and type(nextSave.mail.party) == "table" then
        nextSave.mail.party[#nextSave.party] = nil
      end
    end
  elseif generation == 3 then
    nextSave.storage = nextSave.storage or { currentBox = 1, boxes = {} }
    nextSave.storage.boxes = nextSave.storage.boxes or {}
    local box = nextSave.storage.boxes[target.box] or { name = "BOX " .. target.box, mons = {} }
    nextSave.storage.boxes[target.box] = box
    box.mons = box.mons or {}
    for _, mon in ipairs(mons) do
      local free
      for step = 0, 29 do
        local i = (target.index - 1 + step) % 30 + 1
        if not (box.mons[i] or box.mons[tostring(i)]) then free = i; break end
      end
      if not free then return nil, "That PC box does not have enough room." end
      box.mons[free] = mon
    end
  else
    if not nextSave.boxes then nextSave.boxes = { nextSave.box or {} }; nextSave.box = nil end
    local list = nextSave.boxes[target.box] or {}
    nextSave.boxes[target.box] = list
    if #list + #mons > 20 then return nil, "That PC box does not have enough room." end
    local at = math.min(target.index, #list + 1)
    for i, mon in ipairs(mons) do table.insert(list, at + i - 1, mon) end
  end
  return self:commit(Store.copy(self.state), source, body, nextSave)
end

function Service:move(fromBox, fromSlot, toBox, toSlot)
  local state, why = Store.move(self.state, fromBox, fromSlot, toBox, toSlot)
  if not state then return nil, why end
  return self:commit(state)
end

function Service:rename(box, name)
  local state, why = Store.rename(self.state, box, name)
  if not state then return nil, why end
  return self:commit(state)
end

function Service:previewOrganize(target, source, config)
  if self.fs.read(Store.PATH) ~= self.body then return nil, "Box changed. Reload before organizing." end
  local Organizer = require("src.box.Organizer")
  local result, report, body
  if target == "box" then
    result, report = Organizer.applyWarehouse(self.state, config)
  elseif target == "pc" then
    local save, why
    save, why, body = self:read(source)
    if not save then return nil, why end
    result, report = Organizer.applyGame(save, source.version, config)
  else return nil, "Choose Box storage or Game PC." end
  if not result then return nil, report end
  return { target = target, source = target == "pc" and Store.copy(source) or nil,
    config = Store.copy(config), boxBefore = self.body, gameBefore = body, report = report }
end

function Service:applyOrganize(preview)
  if type(preview) ~= "table" or type(preview.config) ~= "table" then return nil, "Preview the arrangement first." end
  if preview.boxBefore ~= self.body or self.fs.read(Store.PATH) ~= self.body then
    return nil, "Box changed since the preview. Preview it again."
  end
  local Organizer = require("src.box.Organizer")
  local nextState, nextSave, report
  if preview.target == "box" then
    nextState, report = Organizer.applyWarehouse(self.state, preview.config)
    if not nextState then return nil, report end
  elseif preview.target == "pc" then
    local save, why, body = self:read(preview.source)
    if not save then return nil, why end
    if body ~= preview.gameBefore then return nil, "The game save changed since the preview. Preview it again." end
    nextSave, report = Organizer.applyGame(save, preview.source.version, preview.config)
    if not nextSave then return nil, report end
    nextState = Store.copy(self.state); nextState.revision = nextState.revision + 1
  else return nil, "Choose Box storage or Game PC." end
  if report.moved == 0 then return nil, "Everything is already in place." end
  return self:commit(nextState, preview.target == "pc" and preview.source or nil, preview.gameBefore, nextSave)
end

function Service:saveOrganizer(name, target, config, index)
  if type(name) ~= "string" or #name == 0 or #name > 64 or name:find("%c") then
    return nil, "Name this preset with 1 to 64 bytes."
  end
  local valid, why = require("src.box.Organizer").validate(config)
  if not valid then return nil, why end
  if target ~= "box" and target ~= "pc" then return nil, "Choose Box storage or Game PC." end
  local nextState = Store.copy(self.state)
  nextState.organizerProfiles = nextState.organizerProfiles or {}
  if index == nil then index = #nextState.organizerProfiles + 1 end
  if type(index) ~= "number" or index ~= math.floor(index) or index < 1
      or index > 20 or index > #nextState.organizerProfiles + 1 then return nil, "All 20 preset slots are full." end
  nextState.organizerProfiles[index] = { name = name, target = target, config = Store.copy(config) }
  nextState.revision = nextState.revision + 1
  return self:commit(nextState)
end

function Service:deleteOrganizer(index)
  local profiles = self.state.organizerProfiles or {}
  if type(index) ~= "number" or index ~= math.floor(index) or not profiles[index] then return nil, "Choose a saved preset." end
  local nextState = Store.copy(self.state)
  table.remove(nextState.organizerProfiles, index)
  nextState.revision = nextState.revision + 1
  return self:commit(nextState)
end

function Service:giftProgress(source)
  local save, why = self:read(source)
  if not save then return nil, why end
  return require("src.box.Gifts").progress(self.state, source, save)
end

function Service:claimEgg(source, seed)
  local save, why, body = self:read(source)
  if not save then return nil, why end
  local Gifts = require("src.box.Gifts")
  local progress, err = Gifts.progress(self.state, source, save)
  if not progress then return nil, err end
  if not progress.eligible then return nil, "The next gift egg has not been unlocked." end
  local box, slot
  for b = 1, Store.BOXES do
    local free = Store.free(self.state, b)
    if free then box, slot = b, free; break end
  end
  if not box then return nil, "Make room in Box storage before claiming this egg." end
  local mon, createErr = Gifts.create(source.version, progress.nextAward, seed)
  if not mon then return nil, createErr end
  local nextState, nextSave = Store.copy(self.state), Store.copy(save)
  nextState.boxes[box].mons[slot] = { id = nextState.nextId, version = source.version, generation = 3,
    slotId = source.slotId, cartId = source.cartId, depositorId = Gifts.trainerId(save),
    mon = mon, display = Catalog.describe(source.version, mon), gift = progress.nextAward }
  nextState.nextId, nextState.revision = nextState.nextId + 1, nextState.revision + 1
  Gifts.setFlags(nextSave, progress.flags - progress.flags % 8 + 1 + (progress.nextAward - 1) * 2)
  Gifts.recordProgress(nextState, source, nextSave)
  return self:commit(nextState, source, body, nextSave)
end

function Service:importGCI(bytes)
  local state, why = require("src.box.GCI").import(self.state, bytes)
  if not state then return nil, why end
  local ok, err = self:commit(state)
  return ok, err or why
end

function Service:exportGCI()
  local bytes, why = require("src.box.GCI").export(self.state)
  if not bytes then return nil, why end
  local path = "box/exports/pokemon-box-" .. self.state.revision .. (#bytes == 0x76040 and ".gci" or ".sav")
  if not self.fs.createDirectory("box/exports") then return nil, "Could not create the export folder." end
  local ok, err = self.fs.write(path, bytes)
  if not ok or self.fs.read(path) ~= bytes then return nil, err or "The exported file could not be verified." end
  return true, path
end

function Service:saveStage(index, stage)
  local state, why = require("src.box.Showcase").save(self.state, index, stage)
  if not state then return nil, why end
  return self:commit(state)
end

function Service:exportStage(index, box)
  local path, why = require("src.box.Showcase").export(self.state, index, self.fs)
  if not path then return nil, why end
  if box then return self:theme(box, "Showcase", path, self.state.stages[index].music) end
  return true, path
end

function Service:event(source, id, collect)
  local save, why, body = self:read(source)
  if not save then return nil, why end
  local Events = require("src.box.Events")
  local nextSave, err = (collect and Events.collect or Events.receive)(save, id, 2)
  if not nextSave then return nil, err end
  local nextState = Store.copy(self.state)
  nextState.revision = nextState.revision + 1
  return self:commit(nextState, source, body, nextSave)
end

function Service:migrate(refs, version, preview)
  local state, why = require("src.box.Migration").apply(self.state, refs, version, preview)
  if not state then return nil, why end
  return self:commit(state)
end

function Service:restoreOriginal(ref, index)
  local state, why = require("src.box.Migration").restore(self.state, ref, index)
  if not state then return nil, why end
  return self:commit(state)
end

for _, operation in ipairs({ "moveGroup", "arrange", "theme", "mark", "preset" }) do
  Service[operation] = function(self, ...)
    local state, why = Store[operation](self.state, ...)
    if not state then return nil, why end
    return self:commit(state)
  end
end

function Service:deployPreset(source, index)
  local preset = self.state.presets and self.state.presets[index]
  if not preset then return nil, "Choose a saved team." end
  local save, why, body = self:read(source)
  if not save then return nil, why end
  if #(save.party or {}) + #preset.ids > 6 then return nil, "The party needs room for the entire team." end
  local nextSave, nextState = Store.copy(save), Store.copy(self.state)
  nextSave.party = nextSave.party or {}
  for _, id in ipairs(preset.ids) do
    local row = Store.find(nextState, id)
    if not row then return nil, "A preset member is currently outside Box storage." end
    local ok, err = Catalog.compatible(row.entry, source.version)
    if not ok then return nil, err end
    if row.entry.mon.isEgg then return nil, "Hatch eggs before deploying a team." end
    local mon = Store.copy(row.entry.mon)
    local d = Catalog.describe(source.version, mon)
    if row.entry.generation == 3 then
      if not d.hp then return nil, "Import complete species data before deploying this team." end
      mon.level, mon.maxHp, mon.hp = d.level, d.hp, d.hp
      for _, key in ipairs({ "attack", "defense", "speed", "spAtk", "spDef" }) do mon[key] = d[key] end
    elseif next(d.stats) then
      mon.stats, mon.maxHp = Store.copy(d.stats), d.hp
      mon.hp = math.min(tonumber(mon.hp) or d.hp, d.hp)
      if row.entry.generation == 2 then Records.leaveBox(source.version, 2, mon) end
    else return nil, "Import complete species data before deploying this team." end
    nextSave.party[#nextSave.party + 1] = mon
    Records.registerReceived(nextSave, row.entry.generation, mon)
    nextState.departures = nextState.departures or {}
    nextState.departures[row.entry.id] = { entry = Store.copy(row.entry),
      identity = Records.identity(row.entry.generation, mon), path = source.path }
    nextState.boxes[row.box].mons[row.slot] = nil
  end
  nextState.revision = nextState.revision + 1
  return self:commit(nextState, source, body, nextSave)
end

return Service
