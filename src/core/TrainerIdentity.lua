local bit = require("bit")
local Identity = {}
local U32 = 4294967296

function Identity.u16(value)
  local n = tonumber(value)
  if not n or n ~= n or n < 0 or n == math.huge or n ~= math.floor(n) then return nil end
  return n % 65536
end
function Identity.packed(id, sid)
  local n = tonumber(id)
  if not n or n ~= n or n < 0 or n >= U32 or n ~= math.floor(n) then return nil end
  return n % 65536 + (Identity.u16(sid) or math.floor(n / 65536)) * 65536
end
function Identity.nameOf(save, gen)
  if type(save) ~= "table" then return nil end
  local player = type(save.player) == "table" and save.player or {}
  local name = gen == 3 and (save.name or save.playerName or player.name) or player.name
  return type(name) == "string" and name ~= "" and name or nil
end
function Identity.monName(mon)
  if type(mon) ~= "table" then return nil end
  local name = mon.otName or mon.ot or mon.originalTrainer
  if type(name) == "string" then return name end
  if type(mon.cartOt) == "string" and not mon.cartOt:find("[^%x]") then
    local map, out = require("src.save_convert.data.charmap").byByte, {}
    for token in mon.cartOt:gmatch("%x%x") do
      local code = tonumber(token, 16)
      if code == 0x50 then break end
      local glyph = map[code]
      if not glyph or glyph:sub(1, 1) == "<" then return nil end
      out[#out + 1] = glyph
    end
    return table.concat(out)
  end
end
function Identity.rawId(mon, gen)
  local raw = type(mon) == "table" and mon.cartRaw
  local at = gen == 1 and 25 or gen == 2 and 13
  if not at or type(raw) ~= "string" or #raw < at + 3 then return nil end
  return tonumber(raw:sub(at, at + 3), 16)
end
function Identity.profile(save, gen)
  if type(save) ~= "table" then return nil end
  local name = Identity.nameOf(save, gen)
  local id = gen == 3 and save.trainerId or save.player and save.player.id
  local packed = Identity.packed(id, gen == 3 and save.secretId or 0)
  if not packed or not name then return nil end
  local sid = math.floor(packed / 65536)
  if gen == 3 and save.secretId == nil and tonumber(id) < 65536 then
    local function scan(list)
      for _, mon in pairs(type(list) == "table" and list or {}) do
        if type(mon) == "table" and Identity.u16(mon.otId) == packed
            and Identity.monName(mon) == name and Identity.u16(mon.otSecretId) ~= nil then
          return Identity.u16(mon.otSecretId)
        end
      end
    end
    sid = scan(save.party)
    if sid == nil then
      local boxes = type(save.storage) == "table" and save.storage.boxes
      for _, box in pairs(type(boxes) == "table" and boxes or {}) do
        if type(box) == "table" then sid = sid or scan(box.mons) end
      end
    end
    sid = sid or 0
  end
  return { id = packed % 65536, sid = gen == 3 and sid or nil, name = name }
end
function Identity.key(gen, id, name, sid)
  return table.concat({ gen, id, #name, name, gen == 3 and (sid or 0) or 0 }, "|")
end
function Identity.owner(mon, gen, owners, localOwner)
  local id = Identity.u16(mon.otId) or Identity.rawId(mon, gen)
  if id == nil then return nil end
  local name = Identity.monName(mon)
  local packed = gen == 3 and Identity.packed(mon.otId, mon.otSecretId)
  local sid = packed and math.floor(packed / 65536) or 0
  if name == nil and localOwner and not mon.traded and id == localOwner.id
      and (gen ~= 3 or sid == (localOwner.sid or 0)) then name = localOwner.name end
  if name == nil then return nil end
  if gen == 3 and mon.otSecretId == nil and localOwner and not mon.traded and id == localOwner.id
      and name == localOwner.name and tonumber(mon.otId) == id then sid = localOwner.sid or 0 end
  return owners[Identity.key(gen, id, name, sid)]
end

local function unown(pid)
  return (bit.band(pid, 3) + bit.band(bit.rshift(pid, 6), 12)
    + bit.band(bit.rshift(pid, 12), 48) + bit.band(bit.rshift(pid, 18), 192)) % 28
end
local function shiny(pid, id, sid)
  return bit.bxor(id, sid, pid % 65536, math.floor(pid / 65536)) < 8
end
-- pokefirered/src/pokemon.c:6062 IsShinyOtIdPersonality
function Identity.personality(mon, target)
  local pid = tonumber(mon.personality)
  if not pid or pid ~= math.floor(pid) or pid < 0 or pid >= U32 then
    return nil, "A Gen 3 Pokémon has no valid personality value."
  end
  local originalId = Identity.packed(mon.otId, mon.otSecretId) or 0
  local old = shiny(pid, originalId % 65536, math.floor(originalId / 65536))
  if mon.isShiny ~= nil then old = not not mon.isShiny end
  if shiny(pid, target.id, target.sid) == old then return pid end
  local low, high = pid % 65536, math.floor(pid / 65536)
  if not old then
    local nextHigh = high + 25600 <= 65535 and high + 25600 or high - 25600
    return nextHigh * 65536 + low
  end
  local isUnown = tonumber(mon.species) == 201
  local isWurmple = tonumber(mon.species) == 290
  local limit = isUnown and 65536 or 256
  for offset = 0, limit - 1 do
    local nextLow = isUnown and (low + offset) % 65536
      or (low % 256 + ((math.floor(low / 256) + offset) % 256) * 256)
    for key = 0, 7 do
      local nextHigh = bit.bxor(target.id, target.sid, nextLow, key)
      local nextPid = nextHigh * 65536 + nextLow
      if nextPid % 25 == pid % 25 and nextPid % 2 == pid % 2
          and (not isUnown or unown(nextPid) == unown(pid))
          and (not isWurmple or (nextHigh % 10 < 5) == (high % 10 < 5)) then return nextPid end
    end
  end
  return nil, "Shininess and this Pokémon's personality traits cannot be preserved together."
end

function Identity.nameCodes(name, gen)
  local map = gen == 2 and require("src.save_convert.Gen2Layout").charmap
    or require("src.save_convert.data.charmap").byByte
  local reverse = {}
  for code, token in pairs(map) do
    if type(token) == "string" and token ~= "" and code ~= 0x50 then reverse[token] = code end
  end
  local codes, pos = {}, 1
  while pos <= #name do
    local best, code
    for token, byte in pairs(reverse) do
      if name:sub(pos, pos + #token - 1) == token and (not best or #token > #best) then
        best, code = token, byte
      end
    end
    if not best then return nil, "The trainer name cannot be represented in a Gen " .. gen .. " save." end
    codes[#codes + 1], pos = code, pos + #best
  end
  if #codes > 7 then return nil, "The trainer name is longer than the game's seven-character limit." end
  return codes
end

function Identity.rename(mon, name, gen)
  local changed, found = false, false
  for _, key in ipairs({ "ot", "otName", "originalTrainer" }) do
    if mon[key] ~= nil then
      found = true
      if mon[key] ~= name then mon[key], changed = name, true end
    end
  end
  if not found then mon[gen == 3 and "otName" or "ot"], changed = name, true end
  if gen == 1 and type(mon.cartOt) == "string" then
    local codes, err = Identity.nameCodes(name, gen)
    if not codes then return nil, err end
    local tokens = {}
    for _, code in ipairs(codes) do tokens[#tokens + 1] = ("%02X"):format(code) end
    local prefix = table.concat(tokens) .. "50"
    local raw = prefix .. mon.cartOt:sub(#prefix + 1)
    if raw ~= mon.cartOt then mon.cartOt, changed = raw, true end
  end
  return changed
end
return Identity
