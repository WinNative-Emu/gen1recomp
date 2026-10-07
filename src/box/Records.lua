local Store = require("src.box.Store")
local Records = {}

function Records.boxes(save, generation)
  if generation == 3 then
    return save.storage and save.storage.boxes or {}
  end
  return save.boxes or (save.box and { save.box }) or {}
end

function Records.list(save, generation, box)
  local row = Records.boxes(save, generation)[box]
  if type(row) ~= "table" then return {} end
  return generation == 3 and (row.mons or {}) or row
end

function Records.at(save, generation, ref)
  if type(ref) ~= "table" then return nil end
  local list = ref.where == "party" and (save.party or {})
    or Records.list(save, generation, ref.box)
  return list[ref.index] or list[tostring(ref.index)]
end

function Records.candidates(save, generation)
  local out = {}
  for i, mon in ipairs(save.party or {}) do
    out[#out + 1] = { where = "party", index = i, mon = mon, source = "Party" }
  end
  local count, size = generation == 1 and 12 or 14, generation == 3 and 30 or 20
  for b = 1, count do
    local row = Records.boxes(save, generation)[b]
    local name = generation == 3 and row and row.name
      or save.boxNames and save.boxNames[b] or "BOX " .. b
    for i = 1, size do
      local mon = Records.list(save, generation, b)[i]
        or Records.list(save, generation, b)[tostring(i)]
      if type(mon) == "table" then
        out[#out + 1] = { where = "box", box = b, index = i, mon = mon, source = name }
      end
    end
  end
  return out
end

function Records.key(ref)
  return table.concat({ ref.where or "box", ref.box or 0, ref.index or ref.slot or 0 }, ":")
end

function Records.identity(generation, mon)
  if generation == 3 then
    if type(mon.personality) ~= "number" then return nil end
    return "3|" .. mon.personality .. "|" .. tostring(mon.otId or 0) .. "|" .. tostring(mon.otSecretId or 0)
  end
  if type(mon.dvs) ~= "table" or mon.otId == nil then return nil end
  local dvs = mon.dvs
  local ot = mon.otName or mon.ot
  if ot == nil then ot = require("src.core.TrainerIdentity").monName(mon) end
  return table.concat({ generation, mon.otId, ot or "",
    dvs.attack or 0, dvs.defense or 0, dvs.speed or 0, dvs.special or 0 }, "|")
end

local function catalog(version)
  return require("src.box.Catalog").get(version)
end

function Records.enterBox(version, generation, mon)
  if type(mon) ~= "table" then return mon end
  if generation == 2 then
    require("src.core.gen2.Boxes").enterBox(mon, catalog(version))
  elseif generation == 3 then
    pcall(require("src.core.game3.storage").fullHealMon, mon, { version = version })
  end
  return mon
end

function Records.leaveBox(version, generation, mon)
  if type(mon) ~= "table" then return mon end
  if generation == 1 then
    local data = catalog(version)
    require("src.pokemon.Stats").ensure(data.pokemon and data.pokemon[mon.species], mon)
  elseif generation == 2 then
    mon.status, mon.statusTurns = nil, nil
    if mon.isEgg then mon.hp = 0 else mon.hp = mon.maxHp or mon.hp end
  end
  return mon
end

function Records.registerReceived(save, generation, mon)
  if mon.isEgg then return end
  if generation == 3 then
    save.dex = save.dex or {}
    require("src.core.game3.dex").handleSetPokedexFlag(save.dex, mon.species, true, mon.personality)
  else
    save.pokedex = save.pokedex or {}
    local dex = save.pokedex
    dex.seen = dex.seen or {}
    local key = generation == 2 and "caught" or "owned"
    dex[key] = dex[key] or {}
    dex.seen[mon.species], dex[key][mon.species] = true, true
    if generation == 2 and mon.species == "UNOWN" then
      local Unown = require("src.core.gen2.Unown")
      local letter = Unown.monLetter(mon)
      save.unownDex = save.unownDex or {}
      local found = false
      for _, value in ipairs(save.unownDex) do if value == letter then found = true end end
      if letter and not found then save.unownDex[#save.unownDex + 1] = letter end
    end
  end
end

function Records.remove(save, generation, refs)
  local nextSave = Store.copy(save)
  local seen, party = {}, false
  for _, ref in ipairs(refs) do
    local key = Records.key(ref)
    if seen[key] or not Records.at(nextSave, generation, ref) then return nil, "A selected Pokémon is missing." end
    seen[key] = true
    local mon = Records.at(nextSave, generation, ref)
    local mail = tonumber(mon.mail)
    if generation == 3 and mail and mail ~= 255 then return nil, "Remove held mail before depositing." end
    if generation == 2 and (require("src.core.gen2.Mail").monHoldsMail(mon)
        or ref.where == "party" and nextSave.mail and nextSave.mail.party
          and nextSave.mail.party[ref.index]) then return nil, "Remove held mail before depositing." end
    local list
    if ref.where == "party" then list, party = nextSave.party, true
    else
      if generation ~= 3 and not nextSave.boxes then
        nextSave.boxes = { nextSave.box or {} }; nextSave.box = nil
      end
      list = Records.list(nextSave, generation, ref.box)
    end
    list[ref.index], list[tostring(ref.index)] = nil, nil
  end
  local function compact(list)
    local keys, values = {}, {}
    for key, value in pairs(list) do
      if type(value) == "table" then keys[#keys + 1] = tonumber(key) end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do values[#values + 1] = list[key] or list[tostring(key)] end
    for key in pairs(list) do list[key] = nil end
    for i, value in ipairs(values) do list[i] = value end
    return keys
  end
  if party then
    local oldSlots = compact(nextSave.party)
    if generation == 2 and nextSave.mail and type(nextSave.mail.party) == "table" then
      local oldMail, nextMail = nextSave.mail.party, {}
      for index, oldIndex in ipairs(oldSlots) do nextMail[index] = oldMail[oldIndex] end
      nextSave.mail.party = nextMail
    end
    local healthy = 0
    for _, mon in ipairs(nextSave.party) do
      if not mon.isEgg and (tonumber(mon.hp) or 0) > 0 then healthy = healthy + 1 end
    end
    if healthy == 0 then return nil, "Keep at least one Pokémon able to battle in the party." end
  end
  if generation < 3 then
    for _, list in pairs(nextSave.boxes or {}) do compact(list) end
  end
  return nextSave
end

function Records.insert(save, generation, box, entries)
  local count, capacity = generation == 1 and 12 or 14, generation == 3 and 30 or 20
  if type(box) ~= "number" or box < 1 or box > count or box ~= math.floor(box) then
    return nil, "Choose a valid destination PC box."
  end
  local nextSave = Store.copy(save)
  local boxes
  if generation == 3 then
    nextSave.storage = nextSave.storage or { currentBox = 1, boxes = {} }
    nextSave.storage.boxes = nextSave.storage.boxes or {}
    boxes = nextSave.storage.boxes
    boxes[box] = boxes[box] or { name = "BOX " .. box, mons = {} }
    boxes[box].mons = boxes[box].mons or {}
  else
    nextSave.boxes = nextSave.boxes or { nextSave.box or {} }
    nextSave.box = nil
    boxes = nextSave.boxes
    boxes[box] = boxes[box] or {}
  end
  local list = generation == 3 and boxes[box].mons or boxes[box]
  for _, entry in ipairs(entries) do
    local free
    for i = 1, capacity do if not (list[i] or list[tostring(i)]) then free = i; break end end
    if not free then return nil, "That PC box does not have enough room." end
    list[free] = Store.copy(entry.mon)
    Records.registerReceived(nextSave, generation, list[free])
  end
  return nextSave
end

return Records
