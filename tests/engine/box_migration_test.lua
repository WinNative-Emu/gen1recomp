package.path="./?.lua;./?/init.lua;"..package.path
love=love or require("tests.love_stub")
local T=require("tests.harness")
local Migration=require("src.box.Migration")
local Store=require("src.box.Store")
local Catalog=require("src.box.Catalog")
local Serializer=require("src.core.SaveSerializer")
local CacheFs=require("src.import.CacheFs")
local GameVersion=require("src.core.GameVersion")
local oldRead,tables=CacheFs.readAt,{}
local function put(v,p,value) tables[GameVersion.cachePrefix(v)..p]=Serializer.encode(value) end
for _,v in ipairs(GameVersion.ORDER) do
  local gen=GameVersion.generation(v)
  if gen==3 then
    local root="data/generated/gba/pokemon/"
    put(v,root.."names.lua",{[25]="PIKACHU",[201]="UNOWN",[277]="TREECKO"})
    put(v,root.."national.lua",{toNational={[25]=25,[201]=201,[277]=252},toSpecies={[25]=25,[201]=201,[252]=277}})
    put(v,root.."meta.lua",{[25]={genderRatio=127,growthRate=0},[201]={genderRatio=255,growthRate=0},[277]={genderRatio=31,growthRate=0}})
    put(v,root.."stats.lua",{[25]={hp=35,atk=55,def=40,spe=90,spa=50,spd=50},[201]={hp=48,atk=72,def=48,spe=48,spa=72,spd=48},[277]={hp=40,atk=45,def=35,spe=70,spa=65,spd=55}})
    put(v,root.."move_names.lua",{[84]="THUNDERSHOCK",[57]="SURF",[354]="PSYCHO BOOST"})
    put(v,root.."battle_moves.lua",{moves={[84]={pp=30},[57]={pp=15},[354]={pp=5}}})
    put(v,root.."abilities.lua",{[25]={9},[201]={26},[277]={65}})
    put(v,"data/generated/gba/items/pack.lua",{items={[68]={name="RARE CANDY"},[1]={name="MASTER BALL"}}})
  else
    local pokemon={PIKACHU={id="PIKACHU",name="PIKACHU",dex=25,growthRate="MEDIUM_FAST",genderRatio=127,catchRate=190,
      baseStats={hp=35,attack=55,defense=30,speed=90,special=50,specialAttack=50,specialDefense=40}}}
    if gen==2 then pokemon.UNOWN={id="UNOWN",name="UNOWN",dex=201,growthRate="MEDIUM_FAST",genderRatio=255,
      baseStats={hp=48,attack=72,defense=48,speed=48,specialAttack=72,specialDefense=48}} end
    put(v,"data/generated/pokemon.lua",pokemon)
    put(v,"data/generated/moves.lua",{THUNDERSHOCK={name="THUNDERSHOCK",pp=30},SURF={name="SURF",pp=15}})
    put(v,"data/generated/items.lua",{RARE_CANDY={name="RARE CANDY"},MASTER_BALL={name="MASTER BALL"}})
  end
end
CacheFs.readAt=function(path) return tables[path] end;Catalog.reset()
local function entry(v)
  local gen=GameVersion.generation(v)
  local mon={species=gen==3 and 25 or "PIKACHU",nickname="PIKA",ot="ALICE",otName="ALICE",otId=42,level=50,
    exp=125500,experience=125500,happiness=150,friendship=150,
    dvs={attack=15,defense=10,speed=10,special=10},statExp={hp=65535,attack=65535,defense=65535,speed=65535,special=65535},
    moves=gen==3 and {84} or {{id="THUNDERSHOCK",pp=15,ppUps=3,maxPp=48}}}
  if gen==3 then
    mon.dvs,mon.statExp=nil,nil
    mon.personality,mon.otSecretId,mon.pp,mon.ppBonusesPacked=12345,3,{15},3
    mon.ivs={hp=31,atk=31,def=20,spe=20,spa=20,spd=20}
    mon.evs={hp=84,atk=84,def=84,spe=84,spa=84,spd=84}
  end
  return {id=1,version=v,generation=gen,mon=mon,display=Catalog.describe(v,mon),tags="original"}
end
for _,from in ipairs(GameVersion.ORDER) do
  for _,to in ipairs(GameVersion.ORDER) do
    if GameVersion.generation(from)~=GameVersion.generation(to) then
      local original=entry(from)
      local before=Serializer.encode(original)
      local out,why=Migration.convert(original,to)
      T.check(out~=nil,from.." → "..to..": "..tostring(why))
      if out then
        local d=Catalog.describe(to,out)
        T.eq(d.level,50,"migration retains level")
        T.eq(d.experience,125500,"migration retains progress within same growth curve")
        T.eq(d.moveDetails[1].pp,15,"migration retains spent PP")
        T.eq(d.moveDetails[1].ppUps,3,"migration retains PP Ups")
        T.eq(out.otId,42,"migration retains visible trainer ID")
        if GameVersion.generation(to)==3 then
          local total=0;for _,n in pairs(out.evs) do total=total+n end
          T.check(total<=510,"Gen3 effort fits total EV limit")
          if GameVersion.generation(from)<3 then T.eq(out.nature,125500%25,"nature comes from EXP mod 25") end
          local codec=require("src.save_convert.Gen3Save").forVersion(to)
          local round=codec.toPortMon(assert(codec.decodeBoxMon(codec.encodeBoxMon(codec.fromPortMon(out,{},false)))),false)
          T.eq(round.personality,out.personality,"converted PK3 personality survives native encryption")
          T.eq(round.ppBonusesPacked,3,"converted PP Ups survive native encoding")
        end
      end
      T.eq(Serializer.encode(original),before,"preview never alters original")
    end
  end
end
local e=entry("emerald")
e.mon.status="PAR"
T.eq(assert(Migration.convert(e,"gold")).status,"paralyze","Gen3 status converts to native Gen2 status")
local statusEntry=entry("gold");statusEntry.mon.status="paralyze"
T.eq(assert(Migration.convert(statusEntry,"emerald")).status,"PAR","Gen2 status converts to native Gen3 status")
e.mon.heldItem=68
T.check(not Migration.convert(e,"red"),"Gen1 refuses every held item")
T.eq(assert(Migration.convert(e,"gold")).item,"RARE_CANDY","held item maps by exact name")
e.mon.heldItem=999
T.check(not Migration.convert(e,"gold"),"unknown item refuses migration")
e.mon.heldItem=nil;e.mon.moves={354}
T.check(not Migration.convert(e,"gold"),"newer move refuses migration")
e.mon.moves={84};e.mon.species=277
T.check(not Migration.convert(e,"gold"),"newer species refuses migration")
e=entry("gold");e.mon.isEgg=true
T.check(not Migration.convert(e,"red"),"Gen1 refuses eggs")
T.check(Migration.convert(e,"emerald")~=nil,"Gen2 eggs may migrate to Gen3")
e=entry("red");e.mon.ot="TOO LONG";e.mon.otName=e.mon.ot
T.check(not Migration.convert(e,"emerald"),"overlong trainer names refuse silent truncation")
e.mon.otName="🙂";e.mon.ot=e.mon.otName
T.check(not Migration.convert(e,"emerald"),"unrepresentable names refuse replacement glyphs")
e=entry("gold");e.mon.species="UNOWN"
local unown=assert(Migration.convert(e,"emerald"))
T.eq(require("src.core.game3.pokemon").unownLetter(unown.personality)+1,require("src.core.gen2.Unown").letterFromDVs(e.mon.dvs),"forward migration retains Unown letter")
local u={id=1,version="emerald",generation=3,mon=unown,display=Catalog.describe("emerald",unown)}
T.eq(require("src.core.gen2.Unown").letterFromDVs(assert(Migration.convert(u,"gold")).dvs),require("src.core.gen2.Unown").letterFromDVs(e.mon.dvs),"reverse migration retains Unown letter")
u.mon.personality=3+256*2+65536
T.check(not Migration.convert(u,"gold"),"Unown ! is not silently replaced")
do
  local state=Store.new();state.nextId=2;state.boxes[1].mons[1]=entry("red")
  local refs={{box=1,slot=1}}
  local original=Serializer.encode(state.boxes[1].mons[1])
  local preview=assert(Migration.preview(state,refs,"emerald"))
  local converted=assert(Migration.apply(state,refs,"emerald",preview))
  T.eq(Store.count(converted),1,"migration creates no extra warehouse Pokémon")
  T.eq(converted.boxes[1].mons[1].id,1,"migration preserves preset/stage entry ID")
  T.eq(Serializer.encode(converted.boxes[1].mons[1].archives[1]),original,"archive retains full original exactly")
  T.check(Store.validate(assert(Serializer.decode(Serializer.encode(converted))))~=nil,"archives persist through serialization")
  local restored=assert(Migration.restore(converted,refs[1],1))
  local copy=Store.copy(restored.boxes[1].mons[1]);copy.archives=nil
  T.eq(Serializer.encode(copy),original,"restore reproduces native original and local metadata")
  T.eq(restored.boxes[1].mons[1].archives[1].generation,3,"restore archives replaced converted version")
  T.check(not Migration.apply(converted,refs,"emerald",preview),"stale preview cannot apply twice")
  preview.rows[1].converted.otId=999
  T.check(not Migration.apply(state,refs,"emerald",preview),"tampered preview is rejected")
  T.check(not Migration.restore(state,refs[1],1),"missing archive fails safely")
  converted.boxes[1].mons[1].archives[1].id=9
  T.check(not Store.validate(converted),"corrupt archive identity is rejected on load")
end
for fault=1,4 do
 local state=Store.new();state.nextId=2;state.boxes[1].mons[1]=entry("red")
 local files={[Store.PATH]=Serializer.encode(state)}
 local writes,fail=0,true
 local fs={read=function(p)return files[p]end,getInfo=function(p)return files[p] and {type="file"}end,
  createDirectory=function()return true end,remove=function(p)files[p]=nil;return true end,
  write=function(p,b)
   writes=writes+1
   if fail and writes==fault then files[p]=b:sub(1,math.floor(#b/2));return nil,"interruption" end
   files[p]=b;return true
  end}
 local Service=require("src.box.Service")
 local service=assert(Service.open(fs))
 local refs={{box=1,slot=1}};local preview=assert(Migration.preview(service.state,refs,"emerald"))
 service:migrate(refs,"emerald",preview);fail=false
 local recovered=assert(Service.open(fs)).state
 local mon=recovered.boxes[1].mons[1]
 T.eq(Store.count(recovered),1,"interrupted migration retains one live record")
 T.check(mon.generation==1 and not mon.archives or mon.generation==3 and mon.archives and mon.archives[1].generation==1,
  "interrupted migration keeps conversion and original archive consistent")
end
CacheFs.readAt=oldRead;Catalog.reset()
T.finish("Box migration")
