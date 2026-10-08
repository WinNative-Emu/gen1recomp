package.path="./?.lua;./?/init.lua;"..package.path
love=love or require("tests.love_stub")
local T=require("tests.harness")
local Migration=require("src.box.Migration")
local Store=require("src.box.Store")
local Catalog=require("src.box.Catalog")
local Serializer=require("src.core.SaveSerializer")
local CacheFs=require("src.import.CacheFs")
local GameVersion=require("src.core.GameVersion")
local Recommend=require("src.recommend.Recommend")
local Tools=require("src.import.BoxTools")
local UI=require("src.import.BoxUI")
local oldRead,tables=CacheFs.readAt,{}
local function put(v,p,value) tables[GameVersion.cachePrefix(v)..p]=Serializer.encode(value) end
for _,v in ipairs(GameVersion.ORDER) do
  local gen=GameVersion.generation(v)
  if gen==3 then
    local root="data/generated/gba/pokemon/"
    put(v,root.."names.lua",{[25]="PIKACHU",[277]="TREECKO"})
    put(v,root.."national.lua",{toNational={[25]=25,[277]=252},toSpecies={[25]=25,[252]=277}})
    put(v,root.."meta.lua",{[25]={genderRatio=127,growthRate=0},[277]={genderRatio=31,growthRate=0}})
    put(v,root.."stats.lua",{[25]={hp=35,atk=55,def=40,spe=90,spa=50,spd=50},[277]={hp=40,atk=45,def=35,spe=70,spa=65,spd=55}})
    put(v,root.."move_names.lua",{[84]="THUNDERSHOCK",[57]="SURF",[354]="PSYCHO BOOST"})
    put(v,root.."battle_moves.lua",{moves={[84]={pp=30},[57]={pp=15},[354]={pp=5}}})
    put(v,root.."abilities.lua",{[25]={9},[277]={65}})
    put(v,"data/generated/gba/items/pack.lua",{items={[68]={name="RARE CANDY"}}})
  else
    put(v,"data/generated/pokemon.lua",{PIKACHU={id="PIKACHU",name="PIKACHU",dex=25,growthRate="MEDIUM_FAST",genderRatio=127,catchRate=190,
      baseStats={hp=35,attack=55,defense=30,speed=90,special=50,specialAttack=50,specialDefense=40}}})
    put(v,"data/generated/moves.lua",{THUNDERSHOCK={name="THUNDERSHOCK",pp=30},SURF={name="SURF",pp=15}})
    put(v,"data/generated/items.lua",{RARE_CANDY={name="RARE CANDY"}})
  end
end
CacheFs.readAt=function(path) return tables[path] end;Catalog.reset()
local function entry(id,species,moves)
  local mon={species=species,nickname="PIKA",ot="ALICE",otName="ALICE",otId=42,level=50,exp=125500,
    personality=12345,otSecretId=3,pp={15,5},ppBonusesPacked=0,moves=moves,
    ivs={hp=31,atk=31,def=20,spe=20,spa=20,spd=20},evs={hp=84,atk=84,def=84,spe=84,spa=84,spd=84}}
  return {id=id,version="emerald",generation=3,mon=mon,display=Catalog.describe("emerald",mon),tags="original"}
end
local state=Store.new();state.nextId=4
state.boxes[1].mons[1]=entry(1,25,{84,354})
state.boxes[1].mons[2]=entry(2,277,{84})
state.boxes[1].mons[3]=entry(3,25,{354})
local refs={{box=1,slot=1},{box=1,slot=2},{box=1,slot=3}}

local out,why,info=Migration.convert(state.boxes[1].mons[1],"gold")
T.eq(out,nil,"a move the destination lacks still blocks plain conversion")
T.check(tostring(why):find("PSYCHO BOOST",1,true)~=nil,"block reason names the missing move")
T.check(type(info)=="table" and info.moveBlock==true,"move-only block is flagged")
T.same(info and info.missing,{"PSYCHO BOOST"},"block lists the missing moves")
T.eq(info and info.species,"PIKACHU","block carries the destination species name")

local preview=assert(Migration.preview(state,refs,"gold"))
T.eq(preview.allowed,false,"blocked rows keep the preview from applying")
T.eq(preview.rows[1].moveBlock,true,"preview row flags the move-only block")
T.eq(preview.rows[2].moveBlock,nil,"species block is not offered a move replacement")
T.eq(preview.rows[3].moveBlock,true,"a mon with no representable move is still a move-only block")
T.eq(#Migration.moveBlocked(preview),2,"moveBlocked lists both move-only rows")

local forced=assert(Migration.convert(state.boxes[1].mons[1],"gold",{moves={"SURF","THUNDERSHOCK"}}))
T.same(forced.moves,{{id="SURF",pp=15,ppUps=0,maxPp=15},{id="THUNDERSHOCK",pp=30,ppUps=0,maxPp=30}},
  "override replaces the moveset at full PP with no PP Ups")
local plain=assert(Migration.convert(entry(9,25,{84}),"gold"))
T.same(forced.dvs,plain.dvs,"override keeps the computed DVs")
T.eq(Migration.convert(state.boxes[1].mons[1],"gold",{moves={"PSYCHO_BOOST"}}),nil,"override must name destination moves")
T.eq(Migration.convert(state.boxes[1].mons[1],"gold",{moves={}}),nil,"empty override refuses")

local sent,serverSets={},{}
local fake={send=function(_,method,path,_,opts) sent[#sent+1]={method=method,path=path,species=opts.params.species};return #sent end,
  poll=function() return {status="ok",data={sets=serverSets}} end,release=function() end}
local offline=false
package.loaded["src.sync.SyncClient"]={new=function()
  if offline then return {send=function() return nil end,poll=function() return {status="error"} end,release=function() end} end
  return fake
end}

local imp={}
local s={service={state=state},migrationPreview=preview}
T.check(Tools.askRecommended(imp,s,refs),"move-only rows open the replace prompt")
T.check(imp._boxPopup and imp._boxPopup.confirm~=nil,"prompt is a yes/cancel confirmation")
T.check(imp._boxPopup and imp._boxPopup.message:find("Gold",1,true)~=nil,"prompt names the destination game")
UI.keypressed(imp,"escape")
T.eq(s.migrationFetch,nil,"cancel fetches nothing")
T.eq(#sent,0,"cancel sends no request")
T.eq(s.migrationPreview.rows[1].converted,nil,"cancel leaves the row blocked")

Recommend.reset()
offline=true
Tools.askRecommended(imp,s,refs);UI.keypressed(imp,"return")
Tools.update(s)
T.eq(s.migrationFetch,nil,"offline fetch finishes")
T.eq(s.noticeKind,"error","offline shows an error notice")
T.eq(s.migrationPreview.rows[1].converted,nil,"offline keeps the row blocked")
T.eq(s.migrationPreview.allowed,false,"offline keeps the preview unappliable")

Recommend.reset()
offline=false
serverSets={pikachu={generation=2,species="pikachu",set={moves={"Surf","Thundershock","Psycho Boost"},ivs={hp=31}}}}
Tools.askRecommended(imp,s,refs);UI.keypressed(imp,"return")
T.eq(#sent,1,"several rows share one batch request")
T.eq(sent[1].path,"/recommend/gen2","request asks for the destination generation")
T.eq(sent[1].species,"pikachu","request names each species once")
Tools.update(s)
local rows=s.migrationPreview.rows
T.check(rows[1].converted~=nil,"recommended moves convert the first move-only row")
T.check(rows[3].converted~=nil,"recommended moves convert the second move-only row")
T.eq(rows[1].recommended,true,"row records that the recommended set was used")
T.same(rows[1].converted.moves,{{id="SURF",pp=15,ppUps=0,maxPp=15},{id="THUNDERSHOCK",pp=30,ppUps=0,maxPp=30}},
  "recommended set resolves to native destination moves")
T.same(rows[1].converted.dvs,plain.dvs,"recommended set does not apply its IVs")
T.eq(rows[2].converted,nil,"unrelated block stays blocked")

local single={{box=1,slot=1}}
local p1=assert(Migration.preview(state,single,"gold",{moves={[1]={"SURF","THUNDERSHOCK"}}}))
T.eq(p1.allowed,true,"override preview is appliable")
local applied=assert(Migration.apply(state,single,"gold",p1))
T.same(applied.boxes[1].mons[1].mon.moves,p1.rows[1].converted.moves,"apply uses the overridden moves")
T.eq(applied.boxes[1].mons[1].archives[1].mon.moves[2],354,"archive keeps the original moveset")
local tampered=Store.copy(p1);tampered.moves[1]={"SURF"}
T.check(not Migration.apply(state,single,"gold",tampered),"edited override invalidates the preview")

Recommend.reset()
serverSets={}
s.migrationPreview=assert(Migration.preview(state,single,"gold"))
s.migrationMoves=nil
Tools.askRecommended(imp,s,single);UI.keypressed(imp,"return")
Tools.update(s)
T.eq(s.noticeKind,"error","missing recommendation shows an error notice")
T.check(tostring(s.notice):find("PIKA",1,true)~=nil,"notice names the Pokémon with no recommendation")
T.eq(s.migrationPreview.rows[1].converted,nil,"missing recommendation keeps the row blocked")

package.loaded["src.sync.SyncClient"]=nil
Recommend.reset()
CacheFs.readAt=oldRead;Catalog.reset()
T.finish("Box migration recommended moves")
