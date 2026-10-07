local Store = require("src.box.Store")
local Catalog = require("src.box.Catalog")
local GameVersion = require("src.core.GameVersion")
local Serializer = require("src.core.SaveSerializer")
local Mon = require("src.battle.gen2.Mon")
local Pokemon = require("src.core.game3.pokemon")
local Unown = require("src.core.gen2.Unown")
local bit = require("bit")
local Migration = {}
local KEYS = { {"hp","hp"},{"atk","attack"},{"def","defense"},{"spe","speed"},{"spa","special"},{"spd","special"} }
local MET_GAME = { sapphire=1,ruby=2,emerald=3,firered=4,leafgreen=5 }
local function clamp(n,lo,hi) return math.max(lo,math.min(hi,math.floor(tonumber(n) or lo))) end
local function normalized(name) return tostring(name):upper():gsub("[%s_%p]","") end
local function label(value,key) return type(value)=="table" and (value.name or key) or value or key end
local function mapped(records,name)
  local want,found=normalized(name),nil
  for key,value in pairs(records) do
    if normalized(label(value,key))==want then
      if found~=nil and found~=key then return nil end
      found=key
    end
  end
  return found
end
local function nameFits(text,generation,limit)
  if type(text)~="string" or text:find("%c") then return false end
  if generation==3 then
    local codec=require("src.save_convert.Gen3Save").forVersion("emerald")
    return codec.decodeString(codec.encodeString(text,limit,0xFF),0,limit)==text
  end
  local chars=generation==1 and require("src.save_convert.data.charmap").byToken
    or require("src.save_convert.Gen2Layout").charmap
  local tokens={}
  for key,value in pairs(chars) do
    local glyph=generation==1 and key or value
    local code=generation==1 and value or key
    if type(glyph)=="string" and not glyph:find("[<>@{}]") and code~=0x50 then tokens[#tokens+1]=glyph end
  end
  table.sort(tokens,function(a,b) return #a>#b end)
  local at,count=1,0
  while at<=#text do
    local found
    for _,token in ipairs(tokens) do
      if #token>0 and text:sub(at,at+#token-1)==token then found=token;break end
    end
    if not found then return false end
    at,count=at+#found,count+1
    if count>limit then return false end
  end
  return true
end
local function gender3(ratio,pid)
  return ratio==255 and "Genderless" or ratio==0 and "Male" or ratio==254 and "Female"
    or pid%256<ratio and "Female" or "Male"
end
local function gender2(def,dvs)
  local gender=Mon.vanillaGender(def,dvs)
  return gender=="unknown" and "Genderless" or gender=="male" and "Male" or "Female"
end
local pidCache={}
local function pidFor(mon,def,national,dvs,shiny)
  local tid=clamp(mon.otId,0,65535)
  local wantedGender=gender2({genderRatio=def.genderRatio},dvs)
  local letter=national==201 and Unown.letterFromDVs(dvs)-1
  local key=table.concat({tid,tostring(def.genderRatio),wantedGender,tostring(letter),tostring(shiny)},"|")
  local hit=pidCache[key]
  if hit~=nil then return hit or nil end
  local found=false
  for highVariant=0,31 do
    local first,step=0,1
    if not shiny then first,step=(-(0x4000+highVariant)*65536)%25,25 end
    for low=first,65535,step do
      local high=shiny and bit.bxor(low,tid,highVariant%8) or (0x4000+highVariant)
      local pid=high*65536+low
      if pid%25==0 and gender3(def.genderRatio,pid)==wantedGender
          and (bit.bxor(tid,high,low)<8)==shiny
          and (not letter or Pokemon.unownLetter(pid)==letter) then found=pid;break end
    end
    if found or shiny and highVariant==7 then break end
  end
  pidCache[key]=found
  return found or nil
end
local function dvsFor(mon,def,national,generation)
  local iv=mon.ivs or {}
  local target={attack=math.floor((iv.atk or 0)/2),defense=math.floor((iv.def or 0)/2),
    speed=math.floor((iv.spe or 0)/2),special=math.floor(((iv.spa or 0)+(iv.spd or 0))/4)}
  local shiny=Pokemon.isShiny({personality=mon.personality,otId=mon.otId,otSecretId=mon.otSecretId})
  local source=Catalog.get(mon._boxVersion)
  local ratio=source.meta[mon.species] and source.meta[mon.species].genderRatio
  if ratio==nil then return nil,"The source gender data is missing." end
  local gender=gender3(ratio,mon.personality)
  local letter=national==201 and Pokemon.unownLetter(mon.personality)+1
  if letter and letter>26 then return nil,"Gen 2 cannot represent Unown ! or ?." end
  local best,score
  for n=0,65535 do
    local d={attack=math.floor(n/4096),defense=math.floor(n/256)%16,speed=math.floor(n/16)%16,special=n%16}
    if Mon.vanillaShiny(d)==shiny and (generation==1 or gender2(def,d)==gender)
        and (not letter or Unown.letterFromDVs(d)==letter) then
      local distance=0
      for key,value in pairs(target) do distance=distance+math.abs(d[key]-value) end
      if score==nil or distance<score then best,score=d,distance;if distance==0 then break end end
    end
  end
  if not best then return nil,"Gen 2 cannot preserve this combination of gender, shininess and form." end
  best.hp=Mon.hpDV(best)
  return best
end
local function expAt(data,species,level)
  if data.generation==3 then
    return require("src.core.game3.summary_data").expForLevel(data.meta[species].growthRate,level)
  end
  return require("src.pokemon.Growth").expForLevel(data.pokemon[species].growthRate,level)
end
function Migration.convert(entry,version)
  local from,to=Catalog.get(entry.version),Catalog.get(version)
  local g1,g2=entry.generation,GameVersion.generation(version)
  if not g2 or g1==g2 then return nil,"Choose a different generation; same-generation Pokémon can be withdrawn directly." end
  if not from.ready or not to.ready then return nil,"Import both games' ROMs before converting." end
  local mon=entry.mon
  if mon.isBadEgg then return nil,"A Bad Egg cannot be migrated." end
  if mon.isEgg and g2==1 then return nil,"Gen 1 cannot represent eggs." end
  if mon.mail~=nil and mon.mail~=255 then return nil,"Remove held mail before converting." end
  local d=Catalog.describe(entry.version,mon)
  if type(mon.otId)~="number" or mon.otId%1~=0 or mon.otId<0 or mon.otId>65535 then return nil,"The original trainer ID is missing or invalid." end
  if d.level<1 or d.level>100 or d.level%1~=0 then return nil,"The source level is invalid." end
  if g1==3 and (not from.meta[mon.species] or from.meta[mon.species].growthRate==nil) then return nil,"Import complete source species data first." end
  local national=d.national
  local species=g2==3 and (to.national.toSpecies or {})[national] or to.byNational[national]
  if not species then return nil,"The destination cannot represent this species." end
  local def=g2==3 and to.meta[species] or to.pokemon[species]
  if not def or def.growthRate==nil or g2==3 and (not to.stats[species] or def.genderRatio==nil)
      or g2<3 and not def.baseStats then return nil,"Import complete destination species data first." end
  local nickname=mon.nickname or d.species
  if g2<3 and normalized(nickname)==normalized(d.species) then nickname=nil end
  local ot=mon.otName or mon.ot or ""
  if nickname~=nil and not nameFits(nickname,g2,10) or not nameFits(ot,g2,7) then
    return nil,"The destination cannot represent this nickname or trainer name without changing it."
  end
  local item=mon.heldItem or mon.item
  local targetItem
  if item and item~=0 then
    if g2==1 then return nil,"Gen 1 cannot represent held items. Remove this item in its game first." end
    if not from.items[item] then return nil,"The held item is unknown in the source game." end
    targetItem=mapped(to.items,label(from.items[item],item))
    if not targetItem then return nil,"The destination cannot represent this held item." end
  end
  local moves,pps,ups={},{},{}
  for _,move in ipairs(mon.moves or {}) do
    local key=type(move)=="table" and (move.moveId or move.id or move.move or move.name) or move
    if key and key~=0 then
      if not from.moves[key] then return nil,"A move is unknown in the source game." end
      local id=mapped(to.moves,label(from.moves[key],key))
      local row=id and (g2==3 and to.battleMoves[id] or to.moves[id])
      if not row or not row.pp then return nil,"The destination cannot represent move "..label(from.moves[key],key).."." end
      local detail=d.moveDetails[#pps+1]
      local bonus=detail and detail.ppUps or 0
      local max=row.pp+bonus*(g2==3 and math.floor(row.pp/5) or math.min(7,math.floor(row.pp/5)))
      local pp=clamp(detail and detail.pp or max,0,max)
      moves[#moves+1]=g2==3 and id or {id=id,pp=pp,ppUps=bonus,maxPp=max}
      pps[#pps+1],ups[#ups+1]=pp,bonus
    end
  end
  if #moves>4 then return nil,"The destination can represent at most four moves." end
  local out={species=species,nickname=nickname,ot=ot,otName=ot,otId=clamp(mon.otId,0,65535),
    level=clamp(d.level,1,100),moves=moves,isEgg=mon.isEgg or nil,item=targetItem,traded=mon.traded,
    pokerus=g2>=2 and clamp(mon.pokerus,0,255) or nil}
  local lines={"Original native record will be archived. Restore replaces this converted record; it does not create a duplicate."}
  local function note(value) lines[#lines+1]=value end
  if g1<3 then
    if type(mon.dvs)~="table" then return nil,"The source DVs are missing." end
    for _,key in ipairs({"attack","defense","speed","special"}) do
      if type(mon.dvs[key])~="number" or mon.dvs[key]%1~=0 or mon.dvs[key]<0 or mon.dvs[key]>15 then return nil,"The source DVs are invalid." end
    end
  elseif type(mon.personality)~="number" or type(mon.ivs)~="table" then return nil,"The native personality or IVs are missing." end
  if g2==3 then
    local pid=pidFor(mon,def,national,mon.dvs,Mon.vanillaShiny(mon.dvs))
    if not pid then return nil,"No personality can preserve this Pokémon's gender, shininess and form." end
    out.personality,out.otSecretId,out.nature=pid,0,0
    out.ivs,out.evs={},{}
    for _,pair in ipairs(KEYS) do out.ivs[pair[1]]=clamp(mon.dvs[pair[2]],0,15)*2+1 end
    out.ivs.hp=Mon.hpDV(mon.dvs)*2+1
    local raw,total={},0
    for _,pair in ipairs(KEYS) do
      local value=math.min(252,math.floor(math.sqrt(clamp((mon.statExp or {})[pair[2]],0,65535))/4)*4)
      raw[pair[1]],total=value,total+value
    end
    local used=0
    for _,pair in ipairs(KEYS) do
      local value=total>510 and math.floor(raw[pair[1]]*510/total/4)*4 or raw[pair[1]]
      out.evs[pair[1]],used=value,used+value
    end
    out.friendship=mon.isEgg and clamp(mon.happiness or mon.eggCycles,0,255) or clamp(mon.happiness or 70,0,255)
    out.eggCycles=mon.isEgg and out.friendship or nil
    out.heldItem,out.pp=targetItem or 0,pps
    out.ppBonusesPacked=0;for i,value in ipairs(ups) do out.ppBonusesPacked=out.ppBonusesPacked+value*4^(i-1) end
    out.markings=entry.markings or 0
    out.abilityNum,out.language,out.otGender=0,2,mon.caughtGender or 0
    out.metLocation,out.metLevel,out.metGame,out.pokeball=255,out.level,MET_GAME[version],4
    out.modernFatefulEncounter=false
    note("DVs → odd IVs (2 × DV + 1); HP uses the derived HP DV.")
    note("Stat Exp → EVs with the same effort contribution, proportionally capped: "..used.." / 510 EVs.")
    note("New personality: Hardy nature, first ability, Secret ID 0. DV shininess, gender and Unown letter are preserved.")
    note("Origin: destination game, Poké Ball, met level "..out.level..", location 255. Earlier met data remains in the archive.")
  elseif g1==3 then
    local input=Store.copy(mon);input._boxVersion=entry.version
    local dvs,why=dvsFor(input,def,national,g2)
    if not dvs then return nil,why end
    out.dvs,out.statExp=dvs,{}
    for _,pair in ipairs(KEYS) do
      local effort=math.floor(clamp((mon.evs or {})[pair[1]],0,255)/4)*4
      out.statExp[pair[2]]=math.max(out.statExp[pair[2]] or 0,effort^2)
    end
    out.happiness=g2==2 and clamp(mon.friendship or mon.happiness or 70,0,255) or nil
    out.caughtLevel,out.caughtLocation,out.caughtGender=g2==2 and out.level or nil,g2==2 and 0 or nil,g2==2 and (mon.otGender or 0) or nil
    note("IVs → nearest DVs preserving shininess"..(g2==2 and ", gender and Unown letter." or " as a latent DV pattern."))
    note(("DVs: Attack %d · Defense %d · Speed %d · Special %d · HP %d"):format(dvs.attack,dvs.defense,dvs.speed,dvs.special,dvs.hp))
    note("EVs → Stat Exp; Special uses the greater Special Attack/Defense effort. HP DV is derived.")
    note("Nature, ability, Secret ID, ball, ribbons, contests and Gen 3 origin data remain only in the archive.")
  else
    local prepared=Store.copy(mon);prepared.species=mon.species
    local Convert=require("src.online.Convert")
    local native,why=(g2==2 and Convert.toGen2 or Convert.toGen1)(prepared,from,to)
    if not native then return nil,"Time Capsule conversion refused: "..tostring(why) end
    out.dvs,out.statExp=Store.copy(native.dvs),Store.copy(native.statExp)
    out.happiness=g2==2 and 70 or nil
    out.caughtLevel=g2==2 and out.level or nil
    note("DVs and Stat Exp are preserved; stats are recalculated using the destination's base stats.")
    if g2==2 then note("Friendship starts at 70; caught level is the current level.") end
  end
  local oldExp=tonumber(mon.exp or mon.experience)
  local oldBase=expAt(from,mon.species,out.level)
  local newBase=expAt(to,species,out.level)
  local experience=newBase
  if oldExp and out.level<100 then
    local oldNext,newNext=expAt(from,mon.species,out.level+1),expAt(to,species,out.level+1)
    local fraction=math.max(0,math.min(1,(oldExp-oldBase)/math.max(1,oldNext-oldBase)))
    experience=newBase+math.floor(fraction*(newNext-newBase))
  end
  if g2==2 then out.experience=experience else out.exp=experience end
  note("Level "..out.level.." retained; experience "..tostring(oldExp or "unrecorded").." → "..experience.." (same progress within the level).")
  local statuses={SLP="sleep",PSN="poison",BRN="burn",PAR="paralyze",FRZ="freeze"}
  local reverse={sleep="SLP",poison="PSN",toxic="PSN",burn="BRN",paralyze="PAR",freeze="FRZ"}
  out.status=g2==2 and (statuses[mon.status] or mon.status) or (reverse[mon.status] or mon.status)
  out.sleep=mon.sleep or mon.sleepTurns
  if g2==2 then
    out.gender=Mon.vanillaGender(def,out.dvs);out.shiny=Mon.vanillaShiny(out.dvs)
    if national==201 then out.unownLetter=Unown.letterFromDVs(out.dvs) end
  elseif g2==1 then out.catchRate=def.catchRate end
  local display=Catalog.describe(version,out)
  out.stats=g2<3 and Store.copy(display.stats) or nil
  out.maxHp,out.hp=display.hp,display.hp
  if g2==3 then for _,key in ipairs({"attack","defense","speed","spAtk","spDef"}) do out[key]=display[key] end end
  note("Stats recalculated; boxed HP restored to full. Status: "..tostring(mon.status or "healthy").." → "..tostring(out.status or "healthy")..".")
  note("Moves and held item mapped by exact name; current PP is capped to destination maximum, PP Ups retained.")
  if g2==1 then note("Friendship, Pokérus, gender and met data remain only in the archive.") end
  return out,lines
end
function Migration.preview(state,refs,version)
  local preview={revision=state.revision,destination=version,rows={},allowed=true}
  local seen={}
  if type(refs)~="table" or #refs==0 then return nil,"Select warehouse Pokémon to preview." end
  for _,ref in ipairs(refs) do
    local entry=Store.at(state,ref.box,ref.slot)
    if not entry or seen[entry.id] then return nil,"A selected Pokémon is missing or repeated." end
    seen[entry.id]=true
    local converted,lines=Migration.convert(entry,version)
    preview.rows[#preview.rows+1]={id=entry.id,name=entry.display.name,original=Serializer.encode(entry),
      converted=converted,lines=converted and lines or {lines}}
    if not converted then preview.allowed=false end
  end
  return preview
end
function Migration.apply(state,refs,version,preview)
  if type(preview)~="table" or preview.revision~=state.revision or preview.destination~=version then
    return nil,"Storage changed. Preview the migration again."
  end
  local fresh,why=Migration.preview(state,refs,version)
  if not fresh then return nil,why end
  if not fresh.allowed then return nil,"The destination cannot represent every selected Pokémon." end
  if Serializer.encode(preview)~=Serializer.encode(fresh) then return nil,"The preview changed. Review it again." end
  local nextState=Store.copy(state)
  for i,ref in ipairs(refs) do
    local entry=Store.at(nextState,ref.box,ref.slot)
    local snapshot=Store.copy(entry);snapshot.archives=nil
    entry.archives=entry.archives or {};entry.archives[#entry.archives+1]=snapshot
    entry.version,entry.generation,entry.mon=version,GameVersion.generation(version),fresh.rows[i].converted
    entry.display=Catalog.describe(version,entry.mon)
    entry.gciRaw,entry.gciOriginal=nil,nil
  end
  nextState.revision=state.revision+1
  return nextState
end
function Migration.restore(state,ref,index)
  local entry=Store.at(state,ref.box,ref.slot)
  local original=entry and entry.archives and entry.archives[index]
  if not original then return nil,"Choose an archived original that is still in Box." end
  local nextState=Store.copy(state)
  local archives=Store.copy(entry.archives);table.remove(archives,index)
  local current=Store.copy(entry);current.archives=nil;archives[#archives+1]=current
  local restored=Store.copy(original);restored.archives=archives
  restored.display=Catalog.describe(restored.version,restored.mon)
  nextState.boxes[ref.box].mons[ref.slot]=restored
  nextState.revision=state.revision+1
  return nextState
end
return Migration
