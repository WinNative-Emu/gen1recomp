local Store = require("src.box.Store")
local Catalog = require("src.box.Catalog")
local Serializer = require("src.core.SaveSerializer")
local Pack = require("src.save_convert.gen3_port.imagepack")
local Gen3 = require("src.save_convert.Gen3Save")
local GCI = { SIZE = 0x76000, BLOCK = 0x2000, BODY = 0x1FF0 }
local function be32(s, off)
  local a,b,c,d = s:byte(off+1,off+4)
  return a*16777216+b*65536+c*256+d
end
local function word(value)
  return string.char(math.floor(value/16777216)%256,math.floor(value/65536)%256,math.floor(value/256)%256,value%256)
end
local function le32(s, off)
  local a,b,c,d = s:byte(off+1,off+4)
  return a+b*256+c*65536+d*16777216
end
local function little(value)
  return word(value):reverse()
end
function GCI.checksum(block)
  local sum = 0
  for i = 5, 0x1FFC, 2 do sum = (sum + block:byte(i)*256 + block:byte(i+1)) % 65536 end
  return sum*65536 + (0xF004-sum)%65536
end

function GCI.decode(bytes)
  if type(bytes) ~= "string" then return nil, "Choose a Pokémon Box GCI file." end
  local header, raw = "", bytes
  if #bytes == GCI.SIZE + 64 then
    local code = bytes:sub(1,4)
    if code ~= "GPXE" and code ~= "GPXP" and code ~= "GPXJ" then return nil, "This GCI belongs to another game." end
    if bytes:sub(5,6) ~= "01" or bytes:byte(57)*256+bytes:byte(58) ~= 59 then
      return nil, "The GCI header does not describe a 59-block Nintendo Pokémon Box save."
    end
    header, raw = bytes:sub(1,64), bytes:sub(65)
  elseif #bytes ~= GCI.SIZE then return nil, "A Pokémon Box save has 0x76000 data bytes plus an optional 64-byte GCI header." end
  local banks, extra = {}, {}
  for bank = 0, 1 do
    local rows, count, valid = {}, nil, true
    for i = 0, 22 do
      local at = (1+bank*23+i)*GCI.BLOCK
      local block = raw:sub(at+1,at+GCI.BLOCK)
      local id, counter = be32(block,4), be32(block,8)
      if id >= 23 or rows[id] or GCI.checksum(block) ~= be32(block,0)
          or count ~= nil and counter ~= count then valid = false end
      rows[id], count = { offset = at, block = block }, counter
    end
    if valid then banks[#banks+1] = { rows = rows, count = count, bank = bank } end
  end
  if #banks == 0 then return nil, "Both Pokémon Box save banks are damaged." end
  table.sort(banks, function(a,b)
    local distance=(a.count-b.count)%4294967296
    return distance>0 and distance<2147483648
  end)
  local active = banks[1]
  for i = 0, 11 do
    local at = (47+i)*GCI.BLOCK
    local block = raw:sub(at+1,at+GCI.BLOCK)
    local id = be32(block,4)
    if id >= 12 or extra[id] or GCI.checksum(block) ~= be32(block,0) then
      return nil, "Pokémon Box's showcase/photo blocks are damaged."
    end
    extra[id] = { offset = at, block = block }
  end
  local pieces = {}
  for i = 0, 22 do pieces[#pieces+1] = active.rows[i].block:sub(13,12+GCI.BODY) end
  pieces[#pieces+1] = string.rep("\0",23*(GCI.BLOCK-GCI.BODY))
  for i = 0, 11 do pieces[#pieces+1] = extra[i].block:sub(13,12+GCI.BODY) end
  pieces[#pieces+1] = string.rep("\0",12*(GCI.BLOCK-GCI.BODY))
  return { header = header, raw = raw, logical = table.concat(pieces), active = active, extra = extra,
    recovered = #banks == 1, japanese = header:sub(1,4) == "GPXJ" or raw:byte(1) == 0x83 }
end

function GCI.import(state, bytes)
  if Store.count(state) ~= 0 then return nil, "Import a native Box save into an empty warehouse to preserve every existing Pokémon." end
  local data, why = GCI.decode(bytes)
  if not data then return nil, why end
  if data.japanese then return nil, "Japanese Box saves use a different name character set; import an English or European Box save." end
  local nextState, codec = Store.copy(state), Gen3.forVersion("ruby")
  local versions = { [1] = "sapphire", [2] = "ruby", [3] = "emerald", [4] = "firered", [5] = "leafgreen" }
  for b = 1, Store.BOXES do
    local box = nextState.boxes[b]
    local rawName = data.logical:sub(0x1EC38+(b-1)*9+1,0x1EC38+b*9)
    local first = rawName:byte(1)
    box.name = (first == 0 or first == 0xFF) and "BOX "..b or codec.decodeString(rawName,0,9)
    box.gciNameRaw, box.gciNameOriginal = rawName, box.name
    box.gciWallpaper = data.logical:byte(0x1ED19+b)
    for slot = 1, Store.SLOTS do
      local at = 8+((b-1)*60+slot-1)*84
      local raw = data.logical:sub(at+1,at+80)
      local mon = math.floor(raw:byte(20)/2)%2 == 1 and codec.decodeBoxMon(raw) or nil
      if mon then
        if not mon.checksumOk or mon.isBadEgg then return nil, "A native Pokémon record is damaged at Box "..b..", slot "..slot.."." end
        local version = versions[mon.metGame] or "ruby"
        local port = codec.toPortMon(mon,false)
        box.mons[slot] = { id = nextState.nextId, version = version, generation = 3, mon = port,
          depositorId = le32(data.logical,at+80), display = Catalog.describe(version,port),
          gciRaw = raw, gciOriginal = Serializer.encode(port) }
        nextState.nextId = nextState.nextId+1
      end
    end
  end
  nextState.gciTemplate = Pack.pack(bytes)
  nextState.revision = state.revision+1
  return nextState, data.recovered and "Imported using the complete surviving save bank." or nil
end

function GCI.export(state)
  local template = Pack.unpack(state.gciTemplate)
  if not template then return nil, "Import an original Pokémon Box save once to supply its native file template." end
  local data, why = GCI.decode(template)
  if not data then return nil, why end
  local codec = Gen3.forVersion("ruby")
  local edits = {}
  local function put(off, bytes) edits[#edits+1] = { off, bytes } end
  for b = 1, Store.BOXES do
    local box = state.boxes[b]
    local name
    if box.name == box.gciNameOriginal then name = box.gciNameRaw
    else
      name = codec.encodeString(box.name,8)..string.char(0xFF)
      if codec.decodeString(name,0,9) ~= box.name then return nil, "A Box name uses characters the native file cannot represent." end
    end
    put(0x1EC38+(b-1)*9,name)
    put(0x1ED19+b-1,string.char(box.gciWallpaper or 0))
    for slot = 1, Store.SLOTS do
      local entry = box.mons[slot]
      local raw, depositor = string.rep("\0",80), 0
      if entry then
        if entry.generation ~= 3 then return nil, "Native Pokémon Box files accept Gen 3 records. Convert or withdraw earlier-generation Pokémon first." end
        if entry.gciRaw and entry.gciOriginal == Serializer.encode(entry.mon) then raw = entry.gciRaw
        else
          local compatible, err = Catalog.compatible(entry, entry.version)
          if not compatible then return nil, err end
          local native = codec.fromPortMon(entry.mon, {}, false)
          if native.species <= 0 or native.species > 412 then return nil, "A species cannot be represented by native Pokémon Box." end
          if native.heldItem > 346 then return nil, "This held item is outside original Pokémon Box's Ruby/Sapphire item range." end
          for _, move in ipairs(native.moves) do
            if move < 0 or move > 354 then return nil, "A move is outside the native Gen 3 move range." end
          end
          if entry.mon.nickname and native.nickname ~= entry.mon.nickname
              or (entry.mon.otName or entry.mon.ot) and native.otName ~= (entry.mon.otName or entry.mon.ot) then
            return nil, "A Pokémon name would be truncated by native export."
          end
          local rawNick = native.nicknameRaw and codec.decodeString(native.nicknameRaw,0,10,native.language) == native.nickname
          local rawOt = native.otNameRaw and codec.decodeString(native.otNameRaw,0,7,native.language) == native.otName
          if not native.nicknameBytes and not rawNick
              and codec.decodeString(codec.encodeString(native.nickname,10,0xFF,native.language),0,10,native.language) ~= native.nickname
              or not rawOt and codec.decodeString(codec.encodeString(native.otName,7,0xFF,native.language),0,7,native.language) ~= native.otName then
            return nil, "A Pokémon name uses characters the native format cannot represent."
          end
          raw = codec.encodeBoxMon(native)
        end
        depositor = entry.depositorId or 0
      end
      put(8+((b-1)*60+slot-1)*84,raw..little(depositor))
    end
  end
  table.sort(edits, function(a,b) return a[1] < b[1] end)
  local pieces, at = {}, 0
  local source = data.logical
  for _, edit in ipairs(edits) do
    pieces[#pieces+1] = source:sub(at+1, edit[1])
    pieces[#pieces+1] = edit[2]
    at = edit[1] + #edit[2]
  end
  pieces[#pieces+1] = source:sub(at+1)
  local logical = table.concat(pieces)
  local raw, bank = {}, 1-data.active.bank
  local count = (data.active.count+1)%4294967296
  local first = (1+bank*23)*GCI.BLOCK
  raw[1] = data.raw:sub(1,first)
  for id = 0, 22 do
    local at = first+id*GCI.BLOCK
    local old = data.raw:sub(at+1,at+GCI.BLOCK)
    local block = string.rep("\0",4)..word(id)..word(count)
      ..logical:sub(id*GCI.BODY+1,(id+1)*GCI.BODY)..old:sub(0x1FFD)
    raw[#raw+1] = word(GCI.checksum(block))..block:sub(5)
  end
  raw[#raw+1] = data.raw:sub(first+23*GCI.BLOCK+1)
  return data.header..table.concat(raw)
end

return GCI
