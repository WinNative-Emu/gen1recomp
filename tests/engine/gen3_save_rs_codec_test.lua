package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")
local eq, check = T.eq, T.check
local B = require("tests.fixtures.save.bytes")
local Mon = require("tests.fixtures.save.gen3_build")
local Gen3 = require("src.save_convert.Gen3Save")
local Compat = require("src.save_convert.Compat")

-- src/save.c:110
local chunks = { [0]=0x890,0xF80,0xF80,0xF80,0xC40,0xF80,0xF80,0xF80,0xF80,0xF80,0xF80,0xF80,0xF80,0x7D0 }
local function fixture(game)
  local sb2,sb1,storage = B.new(0x890),B.new(0x3AC0),B.new(0x83D0)
  for i,v in ipairs(Mon.text("BRENDAN",8)) do sb2[i-1]=v end
  B.le(sb2,0xA,0x1234,2);B.le(sb2,0xC,0x5678,2)
  B.put(sb1,4,25,40,255,0);B.le(sb1,8,2,2);B.le(sb1,10,2,2)
  B.le(sb1,0x490,123456,4);B.le(sb1,0x494,4321,2)
  for _, pocket in ipairs({{0x560,13,19},{0x5B0,259,1},{0x600,4,20},{0x640,289,2},{0x740,133,99}}) do
    B.le(sb1,pocket[1],pocket[2],2);B.le(sb1,pocket[1]+2,pocket[3],2)
  end
  B.le(sb1,0x1540+7*4,0x12345678,4)
  local parent = Mon.mon({species=280,nick="TORCHIC",ot="BRENDAN",origins=5+(game=="ruby" and 2 or 1)*128+4*2048})
  for slot=0,1 do
    parent.pid=0x12345678+slot
    for i,v in ipairs(Mon.encodeMon(parent,false)) do sb1[0x2F9C+slot*80+i-1]=v end
    local mail=0x2F9C+0xA0+slot*56
    for i=0,8 do B.le(sb1,mail+i*2,i+slot*10,2) end
    for i,v in ipairs(Mon.text("BRENDAN",8)) do sb1[mail+0x12+i-1]=v end
    B.le(sb1,mail+0x1A,0x56781234,4);B.le(sb1,mail+0x1E,280,2);B.le(sb1,mail+0x20,121,2)
    for i,v in ipairs(Mon.text("OTNAME",8)) do sb1[mail+36+i-1]=v end
    for i,v in ipairs(Mon.text("TORCHIC",11)) do sb1[mail+44+i-1]=v end
  end
  B.le(sb1,0x30AC,0x01020304,4);B.le(sb1,0x30B0,0xA0B0C0D0,4)
  B.le(sb1,0x30B4,0xFECA,2);B.put(sb1,0x30B6,77)
  for _, raw in ipairs({{0x311B,20},{0x312F,21},{0x3160,1328},{0x3690,1004}}) do
    for i=0,raw[2]-1 do sb1[raw[1]+i]=(i*37+11)%256 end
  end
  for i=0,899 do sb1[0x2738+i]=(i*17+23)%256 end
  for i=0,24 do sb1[0x2738+i*36]=255 end
  local flash = B.new(0x20000,255)
  local parts = {[0]={sb2,0}}
  local offset=0
  for id=1,4 do parts[id]={sb1,offset};offset=offset+chunks[id] end
  offset=0
  for id=5,13 do parts[id]={storage,offset};offset=offset+chunks[id] end
  for id=0,13 do
    local at=(14+id)*0x1000
    B.fill(flash,at,0xF80,0)
    local source,start=parts[id][1],parts[id][2]
    for i=0,chunks[id]-1 do flash[at+i]=source[start+i] end
    local sum=0
    for i=0,chunks[id]-4,4 do sum=(sum+B.getLE(flash,at+i,4))%4294967296 end
    B.le(flash,at+0xFF4,id,2);B.le(flash,at+0xFF6,(sum+math.floor(sum/65536))%65536,2)
    B.le(flash,at+0xFF8,0x08012025,4);B.le(flash,at+0xFFC,3,4)
  end
  return B.pack(flash),B.pack(sb1)
end

for _,game in ipairs({"ruby","sapphire"}) do
  local codec=Gen3.forVersion(game)
  eq(codec.L.FAMILY,"rs",game.." own native layout")
  eq(codec.L.GAME,game,game.." edition routing")
  eq(codec.L.BLOCKS[1].size,0x890,"native SaveBlock2 size")
  eq(codec.L.BLOCKS[2].size,0x3AC0,"native SaveBlock1 size")
  local image,raw=fixture(game)
  eq(Gen3.sniff(image),"rs","RS family sniff")
  local cart,blocks=codec.decode(image)
  check(cart~=nil,"native fixture decodes: "..tostring(blocks))
  if cart then
    eq(cart.money,123456,"unencrypted money")
    eq(cart.coins,4321,"unencrypted coins")
    eq(cart.pockets.ITEMS[1].qty,19,"unencrypted item quantity")
    eq(cart.pockets.KEY_ITEMS[1].qty,1,"native key-items offset")
    eq(cart.pockets.POKE_BALLS[1].qty,20,"native balls offset")
    eq(cart.pockets.TM_CASE[1].qty,2,"native TMs offset")
    eq(cart.pockets.BERRY_POUCH[1].qty,99,"native berries offset")
    eq(cart.gameStats[7],0x12345678,"unencrypted stat")
    eq(cart.daycare.mons[1].species,280,"first parent before mails")
    eq(cart.daycare.mons[2].species,280,"second parent before mails")
    eq(cart.daycare.steps[1],0x01020304,"first steps after both mails")
    eq(cart.daycare.steps[2],0xA0B0C0D0,"second steps after both mails")
    eq(cart.daycare.mail[1].otName,"OTNAME","first parent mail")
    eq(cart.daycare.mail[2].message.words[1],10,"second parent mail")
    eq(cart.daycare.offspringPersonality,0xFECA,"RS offspring u16")
    eq(cart.daycare.stepCounter,77,"RS step counter")
    local save,why=codec.importPort(image,game)
    check(save~=nil,"native cart imports into port: "..tostring(why))
    if save then
      eq(save.map,game=="ruby" and "RU_INSIDE_OF_TRUCK" or "SA_INSIDE_OF_TRUCK","own edition map prefix")
      check(save.modData[game.."_daycare"]~=nil,"edition daycare save key")
      eq(save.encryptionKey,nil,"no runtime encryption key")
      local prefix=codec.recordMixTvPrefix(save,save.tvShows)
      eq(prefix,raw:sub(0x2738+1,0x2738+256),"RS record mixing takes native first 256 TV bytes")
      save.tvShows[0].active=false
      local changed=codec.recordMixTvPrefix(save,save.tvShows)
      eq(changed:byte(2),0,"RS record mixing applies active-header mutation")
      eq(changed:sub(3),prefix:sub(3),"RS record mixing preserves opaque remaining native payload")
      save.tvShows[0].active=true
      save.money=654321
      local output,note=codec.exportPort(save,{
        version=game,metGame=game=="ruby" and 2 or 1,
        toNational=function(species) return species==280 and 255 or species end,
        itemId=function(item) return tonumber(item) end,
      })
      check(output~=nil,"native cart exports: "..tostring(note))
      if output then
        local newer,newBlocks=codec.decode(output)
        check(newer~=nil,"export decodes")
        if newer then
          eq(newer.money,654321,"edited money roundtrip")
          eq(newer.daycare.steps[2],0xA0B0C0D0,"daycare steps retained")
          eq(newer.daycare.mail[2].message.words[1],10,"daycare mail retained")
          for _,span in ipairs({{0x2738,900},{0x311B,20},{0x312F,21},{0x3160,1328},{0x3690,1004}}) do
            eq(newBlocks.sb1:sub(span[1]+1,span[1]+span[2]),raw:sub(span[1]+1,span[1]+span[2]),"opaque native span "..span[1])
          end
          local direct=B.fromString(newBlocks.sb1)
          eq(B.getLE(direct,0x490,4),654321,"exported currency bytes are plain")
          eq(Gen3.sniff(output),"rs","export keeps RS family")
        end
      end
    end
  end
  eq(Compat.generationOf(game),3,"compat generation")
end
T.finish("gen3_save_rs_codec")
