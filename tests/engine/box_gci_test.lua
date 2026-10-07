package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local GCI = require("src.box.GCI")
local Store = require("src.box.Store")
local CacheFs = require("src.import.CacheFs")
local Serializer = require("src.core.SaveSerializer")
local oldRead = CacheFs.readAt
local tables = {
  ["data/generated/gba/pokemon/names.lua"] = Serializer.encode({[25]="PIKACHU"}),
  ["data/generated/gba/pokemon/move_names.lua"] = Serializer.encode({[84]="THUNDERSHOCK"}),
  ["data/generated/gba/pokemon/national.lua"] = Serializer.encode({toNational={[25]=25},toSpecies={[25]=25}}),
  ["data/generated/gba/items/pack.lua"] = Serializer.encode({items={}}),
}
CacheFs.readAt = function(path) return path:match("^ruby/") and tables[path:sub(6)] end
require("src.box.Catalog").reset()
local codec = require("src.save_convert.Gen3Save").forVersion("ruby")
local function word(n) return string.char(math.floor(n/16777216)%256,math.floor(n/65536)%256,math.floor(n/256)%256,n%256) end
local function put(s,off,value) return s:sub(1,off)..value..s:sub(off+#value+1) end
local logical = string.rep("\0",35*0x2000)
local originalMons = {}
for _, slot in ipairs({1,6,7,12,13,60,1500}) do
  local raw = codec.encodeBoxMon(codec.fromPortMon({ species = 25, personality = slot*123,
    nickname = "PIKA"..slot, otName = "Owner", otId = 42, otSecretId = 3,
    exp = 1000, moves = { 84 }, pp = { 15 }, ivs = { hp = 7, atk = 8 }, evs = {},
    friendship = 70, pokeball = 4, metLevel = 5, metGame = 2, language = 2 },{},false))
  originalMons[slot] = raw
  logical = put(logical,8+(slot-1)*84,raw..word(0x01020304):reverse())
end
for b = 1,25 do
  logical = put(logical,0x1EC38+(b-1)*9,codec.encodeString("BOX "..b,9))
  logical = put(logical,0x1ED19+b-1,string.char((b-1)%16))
end
local chunks = { string.rep("B",0x2000) }
for bank = 0,1 do
  for i = 0,22 do
    local id = 22-i
    local block = string.rep("\0",4)..word(id)..word(bank+1)..logical:sub(id*GCI.BODY+1,(id+1)*GCI.BODY).."KEEP"
    block = put(block,0,word(GCI.checksum(block)));chunks[#chunks+1]=block
  end
end
for id = 0,11 do
  local body = string.rep(string.char(id+1),GCI.BODY)
  local block = string.rep("\0",4)..word(id)..word(0)..body.."TAIL"
  block = put(block,0,word(GCI.checksum(block)));chunks[#chunks+1]=block
end
local header = put("GPXE01"..string.rep("\0",58),56,string.char(0,59))
local bytes = header..table.concat(chunks)
T.eq(#bytes,0x76040,"native GCI size includes 64-byte header and 59 physical blocks")
local decoded = assert(GCI.decode(bytes))
T.eq(decoded.active.bank,1,"newest complete bank is selected")
T.eq(decoded.logical:sub(9,88),originalMons[1],"logical mon bytes survive shuffled physical blocks")
local state = assert(GCI.import(Store.new(),bytes))
T.eq(Store.count(state),7,"import retains all occupied slots")
for _, slot in ipairs({1,6,7,12,13,60,1500}) do
  local b,index = math.floor((slot-1)/60)+1,(slot-1)%60+1
  T.eq(state.boxes[b].mons[index].mon.personality,slot*123,"native 12-column slot "..slot.." retains position")
  T.eq(state.boxes[b].mons[index].depositorId,0x01020304,"depositor ID uses little endian")
end
T.eq(state.boxes[25].name,"BOX 25","native Box 25 name is decoded")
T.eq(state.boxes[25].gciWallpaper,8,"native wallpaper ID is preserved")
local exported = assert(GCI.export(state)); local roundTrip = assert(GCI.decode(exported))
T.eq(roundTrip.active.count,3,"export advances save count and writes other bank")
T.eq(roundTrip.header,header,"GCI header stays byte-exact")
T.eq(exported:sub(65,64+0x2000),bytes:sub(65,64+0x2000),"native banner stays byte-exact")
T.eq(exported:sub(64+47*0x2000+1),bytes:sub(64+47*0x2000+1),"photo and showcase blocks stay byte-exact")
for _, slot in ipairs({1,6,7,12,13,60,1500}) do
  local at = 8+(slot-1)*84
  T.eq(roundTrip.logical:sub(at+1,at+80),originalMons[slot],"unchanged PK3 "..slot.." stays byte-exact")
end
state = assert(Store.mark(state,{{box=1,slot=7}},8))
local edited = assert(GCI.decode(assert(GCI.export(state))))
T.eq(assert(codec.decodeBoxMon(edited.logical:sub(8+6*84+1,8+6*84+80))).markings,8,"edited markings export as native PK3")
local brokenNewest = put(bytes,64+(1+23)*0x2000+100,"X")
local recovered = assert(GCI.decode(brokenNewest))
T.eq(recovered.active.bank,0,"corrupt newest bank recovers complete older bank")
T.eq(recovered.recovered,true,"recovery is reported")
local brokenBoth = put(brokenNewest,64+0x2000+100,"X")
T.check(not GCI.decode(brokenBoth),"two corrupt banks are rejected")
T.check(not GCI.decode(bytes:sub(1,-2)),"truncated native file is rejected")
T.check(not GCI.decode("GXXE"..bytes:sub(5)),"another game's GCI is rejected")
T.check(not GCI.decode(put(bytes,56,string.char(0,58))),"incorrect header block count is rejected")
T.check(not GCI.import(Store.new(),"GPXJ"..bytes:sub(5)),"unsupported Japanese names are refused before mutation")
local wrapped=bytes
for bank=0,1 do
  for i=0,22 do
    local at=64+(1+bank*23+i)*GCI.BLOCK
    local block=put(wrapped:sub(at+1,at+GCI.BLOCK),8,word(bank==0 and 4294967295 or 0))
    block=put(block,0,word(GCI.checksum(block)))
    wrapped=put(wrapped,at,block)
  end
end
T.eq(assert(GCI.decode(wrapped)).active.bank,1,"save count rollover selects zero after FFFFFFFF")
T.check(not GCI.import(state,bytes),"native import cannot overwrite occupied warehouse")
state.boxes[1].name="Name too long"
T.check(not GCI.export(state),"overlong native name fails without silent truncation")
state.boxes[1].name="BOX 1"
state.boxes[1].mons[1].generation,state.boxes[1].mons[1].version=2,"gold"
T.check(not GCI.export(state),"earlier-generation records cannot silently become PK3")
CacheFs.readAt=oldRead;require("src.box.Catalog").reset()
T.finish("Box GCI")
