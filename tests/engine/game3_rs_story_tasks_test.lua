package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
local T=require("tests.harness")
local Version=require("src.core.GameVersion")
local Task=require("src.core.game3.task")
local sess={version="ruby",options={}}
local keys={}
local input={wasPressed=function(_,key) return keys[key]==true end,isDown=function() return true end}
local rt={getSession=function() return sess end,_game={input=input}}
package.loaded["src.core.game3.runtime"]=rt
local pans,writes,se,closed,unfrozen,unlocked={}, {}, {},0,0,0
package.loaded["src.core.game3.field_view"]={setCameraPanning=function(x,y) pans[#pans+1]={x,y} end}
package.loaded["src.core.game3.field"]={setMetatile=function(x,y,id,solid) writes[#writes+1]={x,y,id,solid} end,unlock=function() unlocked=unlocked+1 end}
package.loaded["src.core.game3.audio"]={playSe=function(id) se[#se+1]=id end}
package.loaded["src.ui.game3.braille"]={hide=function() end}
local ready=false
package.loaded["src.core.game3.weather"]={rseEngine=function() return {isWeatherChangeComplete=function() return ready end} end}
local Space={store={flags={},vars={}},scriptKey=function(name) assert(name=="S_OpenRegiceChamber");return "native_open_regice" end}
package.loaded["src.core.game3.scripting.space"]=Space
local Story=require("src.core.game3.rse.story_specials_rs")
local Braille=require("src.core.game3.braille_field_rs")
local Orb=require("src.core.game3.rse.orb_effect_rs")
local Rse=require("src.core.game3.rse.init")
local adapters={closeMessage=function() closed=closed+1 end,unfreezeLocal=function() unfrozen=unfrozen+1 end}
local function step(n) for _=1,n do Task.update(1/60) end end
local function waitContext()
  local ctx={lockSnapshots={[1]={}},frozen=true,messageOpen=true,lockKind="all"}
  Space.vm={ctx=ctx,start=function(_,key) ctx.started=key;return true end,halt=function() ctx.halted=true end}
  return ctx
end
for _,game in ipairs({"ruby","sapphire"}) do
  Version.set(game);sess.version=game
  local C=require("src.core.game3.constants").of(game)
  Task.clear();ready=false
  local ctx={}
  Story.waitWeather(ctx)
  T.eq(ctx.stateWait(),false,"weather waits until task boundary")
  step(10);T.eq(ctx.stateWait(),false,"weather incomplete remains suspended")
  ready=true;step(1);T.eq(ctx.stateWait(),true,"weather completion resumes script")
  ctx={};Story.waitWeather(ctx);T.eq(ctx.stateWait(),false,"already-ready weather still schedules task")
  step(1);T.eq(ctx.stateWait(),true,"already-ready weather resumes next update")
  for _,long in ipairs({true,false}) do
    Task.clear();pans={};ctx={}
    Story.sealedChamberShake(ctx,long)
    local duration=long and 250 or 10
    step(duration-1);T.eq(ctx.stateWait(),false,"shake blocks through penultimate frame")
    step(1);T.eq(ctx.stateWait(),true,"native shake task boundary")
    T.eq(#pans,(long and 50 or 2)+1,"native five-frame oscillations and reset")
    T.same(pans[1],{0,long and -2 or -3},"native first pan")
    T.same(pans[#pans],{0,0},"restore pan-ahead")
  end
  for mode=0,2 do
    for _,key in ipairs({"a","b","start","select","up","down","left","right","l","r"}) do
      keys={[key]=true}
      T.eq(Story.brailleButtonPressed(input,mode),key~="l" and key~="r" or key=="l" and mode~=0 or key=="r" and mode==1,"native new-key mask")
    end
  end
  keys={};T.eq(Story.brailleButtonPressed(input,1),false,"held input alone cannot cancel")
  Task.clear();Space.store={flags={},vars={}};ctx=waitContext();closed=0;unfrozen=0
  Story.brailleWait(ctx,adapters);step(7200)
  T.eq(closed,0,"native wait has init plus7200 countdown")
  step(1);T.eq(closed,1,"erase on countdown expiry")
  step(30);T.eq(ctx.started,nil,"30-frame erased pause does not yet replace caller")
  step(1);T.eq(ctx.started,"native_open_regice","native continuation on update7232")
  T.eq(unfrozen,1,"object snapshots released once")
  T.eq(ctx.stateWait,nil,"old waitstate removed")
  Task.clear();ctx=waitContext();keys={};Story.brailleWait(ctx,adapters);step(1)
  keys={a=true};step(1);keys={};step(7199);T.eq(ctx.started,nil,"first key retains remaining countdown")
  step(1);T.eq(ctx.started,nil,"phase4 selected before continuation")
  step(1);T.eq(ctx.started,"native_open_regice","first-key path resumes after preserved countdown")
  Task.clear();ctx=waitContext();keys={};Story.brailleWait(ctx,adapters);step(1)
  local unlockedBefore=unlocked
  keys={a=true};step(1);keys={b=true};step(1);keys={}
  T.eq(unlocked,unlockedBefore,"cancel press frame keeps field locked")
  T.eq(ctx.halted,true,"second new key aborts caller")
  T.eq(ctx.started,nil,"cancel never opens chamber")
  local unlockedAtPress=unlocked
  step(1);T.check(unlocked>unlockedAtPress and not Task.busy(),"cancel unlocks field on the next task frame and drops task")
  Rse.setFlag("FLAG_SYS_BRAILLE_WAIT",true)
  ctx=waitContext();Story.brailleWait(ctx,adapters);T.eq(Task.busy(),false,"completed puzzle does not wait again")
  Rse.setFlag("FLAG_SYS_BRAILLE_WAIT",false)
  local prefix=game=="ruby" and "RU_" or "SA_"
  for _,spec in ipairs({{"SEALED_CHAMBER_OUTER_ROOM",3,9,"Dig","FLAG_SYS_BRAILLE_DIG",9,1},{"DESERT_RUINS",23,9,"Strength","FLAG_SYS_BRAILLE_STRENGTH",7,19},{"ANCIENT_TOMB",25,8,"Fly","FLAG_SYS_BRAILLE_FLY",7,19}}) do
    sess.map=prefix..spec[1];sess.x=spec[3];sess.y=spec[2]
    T.eq(Braille["shouldDo"..spec[4]](sess),true,"RS puzzle correct saved position")
    sess.y=sess.y+1;T.eq(Braille["shouldDo"..spec[4]](sess),false,"adjacent row rejects puzzle")
    sess.y=spec[2];writes={};Braille["do"..spec[4]](sess)
    T.eq(#writes,6,"native entrance six tiles")
    T.same({writes[1][1],writes[1][2]},{spec[6],spec[7]},"native coordinates subtract seven-tile border")
    T.eq(writes[4][4],true,"left lower entrance stays solid")
    T.eq(writes[5][4],false,"center lower entrance walkable")
    T.eq(writes[6][4],true,"right lower entrance stays solid")
    T.eq(Rse.flag(spec[5]),true,"native flag persists completion")
    T.eq(Braille["shouldDo"..spec[4]](sess),false,"completed entrance bypasses puzzle")
  end
  for result=0,3 do
    Task.clear();Orb.reset();local readyAt,doneAt
    local tick=0
    local o=Orb.start(result,function() readyAt=tick end)
    T.eq(o.cx,result<2 and 104 or 120,"native orb center")
    T.eq(o.blue,result%2==1,"native orb palette")
    for i=1,163 do tick=i;step(1) end
    T.eq(readyAt,163,"native parent/child task ordering")
    T.eq(o.radius,159,"native last scanline radius")
    tick=164;step(1);T.eq(o.phase,4,"shake setup on following frame")
    step(4);T.eq(o.shakeDir,1,"native first shake four frames")
    Orb.fade(function() doneAt=tick end)
    for i=1,194 do tick=i;step(1) end
    T.eq(doneAt,194,"retained shake direction requires24 fade coefficient updates plus init/cleanup")
    T.eq(Orb.isActive(),false,"orb cleanup completes")
    T.eq(Task.busy(),false,"orb parent and child removed")
    local color=Orb.blendColor({31,20,9},result%2==1,12,7)
    T.same(color,result%2==1 and {13,8,27} or {31,8,3},"native RGB5 truncation/saturation")
  end
end
Version.set("emerald");sess.version="emerald";sess.map="EM_ANCIENT_TOMB";sess.x=8;sess.y=25
T.eq(Braille.shouldDoFly(sess),false,"Emerald keeps its own puzzle rules")
T.finish("game3_rs_story_tasks")
