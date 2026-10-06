package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local Version=require('src.core.GameVersion')
local Rng=require('src.core.game3.rng')
local Pokemon=require('src.core.game3.pokemon')
local E=require('src.core.game3.encounters')
local session={party={},flags={},vars={}}
package.loaded['src.core.game3.runtime']={getSession=function() return session end}
Pokemon._types={[81]={13,8},[16]={0,2}}
Pokemon._speciesMeta={[1]={genderRatio=127},[81]={genderRatio=255},[16]={genderRatio=127,itemCommon=139,itemRare=142}}
Pokemon._abilities={[1]={0,0}}
Pokemon._names={[1]='X'}
local queue,calls
local function script(values)
  queue,calls=values,0
  Rng.Random=function() calls=calls+1;return assert(table.remove(queue,1),'native RS RNG queue exhausted') end
end
local function done(n) T.eq(calls,n,'exact native main-RNG calls');T.eq(#queue,0,'native RNG queue exhausted exactly') end
Rng.WildRandom=function() error('native RS must not use Emerald wild RNG stream') end
for _,game in ipairs({'ruby','sapphire'}) do
  Version.set(game);session.version=game
  local C=require('src.core.game3.constants').of(game)
  local function lead(name,extra)
    local mon={species=1,abilityId=name and C:require('abilities',name) or 0,level=100,hp=100,personality=13}
    for k,v in pairs(extra or {}) do mon[k]=v end
    session.party={mon}
  end
  local r=E.rules()
  T.check(r.everyStep,'native RS profile selects the every-step RSE policy')
  for _,ab in ipairs({'ABILITY_HUSTLE','ABILITY_PRESSURE','ABILITY_VITAL_SPIRIT'}) do
    lead(ab);script({3});T.eq(r.chooseLevel({minLevel=20,maxLevel=25}),23,'RS has no Emerald max-level ability '..ab);done(1)
  end
  lead('ABILITY_STENCH');T.eq(E.encounterRate(20),160,'native Stench')
  lead('ABILITY_ILLUMINATE');T.eq(E.encounterRate(20),640,'native Illuminate')
  for _,ab in ipairs({'ABILITY_ARENA_TRAP','ABILITY_WHITE_SMOKE','ABILITY_SAND_VEIL'}) do
    lead(ab);T.eq(E.encounterRate(20),320,'RS has no Emerald rate effect '..ab)
  end
  lead('ABILITY_ILLUMINATE',{isEgg=true});T.eq(E.encounterRate(20),320,'native egg ignores ability')
  lead(nil,{item=C:require('items','ITEM_CLEANSE_TAG')});T.eq(E.encounterRate(20),213,'native Cleanse Tag integer rate')
  for _,ab in ipairs({'ABILITY_SYNCHRONIZE','ABILITY_CUTE_CHARM'}) do
    lead(ab);script({7,7,0,3137,6308})
    local mon=r.createWild(16,3)
    T.eq(mon.personality,7,'RS ignores Emerald personality ability '..ab)
    T.same(mon.ivs,{hp=1,atk=2,def=3,spe=4,spa=5,spd=6},'native IVs exist before transition');done(5)
  end
  local slots={}
  for i=1,12 do slots[i]={species=i==1 and 81 or 16,minLevel=20,maxLevel=25} end
  for _,ab in ipairs({'ABILITY_MAGNET_PULL','ABILITY_STATIC','ABILITY_KEEN_EYE','ABILITY_INTIMIDATE'}) do
    lead(ab);script({20,3,7,7,0,3137,6308})
    local mon=r.tryGenerate({slots=slots},'land',true,true)
    T.eq(mon.species,16,'native slot survives without Emerald ability '..ab)
    T.eq(mon.level,23,'native level survives');done(7)
  end
  lead('ABILITY_COMPOUND_EYES')
  for _,case in ipairs({{20,false},{44,false},{45,139},{94,139},{95,142},{99,142}}) do
    script({case[1]});T.eq(r.wildHeldItem(16),case[2] or nil,'native held-item45/95 thresholds');done(1)
  end
  E._loaded=true;E._tables={NATIVE_RS_MAP={land={rate=20,slots=slots}}}
  E.resetRateModifiers();script({})
  for i=1,4 do T.eq(E.onStep('NATIVE_RS_MAP','land',{behavior=1}),nil,'native four immunity steps') end
  done(0)
  E._rsePrevBehavior=1;lead('ABILITY_INTIMIDATE');script({0,20,3,7,7,0,3137,6308})
  local mon=E.onStep('NATIVE_RS_MAP','land',{behavior=1})
  T.eq(mon.species,16,'real onStep reaches native generation');T.eq(E._immunitySteps,0,'native immunity resets');done(8)
end
T.finish('game3_rs_encounters')
