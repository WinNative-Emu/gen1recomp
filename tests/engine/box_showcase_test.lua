package.path="./?.lua;./?/init.lua;"..package.path
love=love or require("tests.love_stub")
local T=require("tests.harness")
local Store=require("src.box.Store")
local Showcase=require("src.box.Showcase")
local Serializer=require("src.core.SaveSerializer")
local Service=require("src.box.Service")
local state=Store.new();state.nextId=3
for i=1,2 do state.boxes[1].mons[i]={id=i,version="red",generation=1,
  mon={species="PIKACHU",level=50,otId=42,ot="OWNER",nickname="PIKA",hp=10,
    dvs={attack=i,defense=2,speed=3,special=4}},display={name="PIKA",species="PIKACHU",national=25}} end
local stage=assert(Showcase.add(Showcase.new(),{{box=1,slot=1},{box=1,slot=2}},state))
stage.name,stage.pattern,stage.music="My stage","Stars","Gentle"
stage.pieces[1].rotation,stage.pieces[1].scale,stage.pieces[1].flip=math.pi/2,2,true
stage.pieces[#stage.pieces+1]={kind="Arch",x=.5,y=.8,scale=1,rotation=0,flip=false}
local saved=assert(Showcase.save(state,5,stage))
T.eq(state.stages,nil,"stage editing leaves saved collection unchanged")
T.eq(saved.stages[5].name,"My stage","fifth stage slot saves its name")
local round=assert(Store.validate(assert(Serializer.decode(Serializer.encode(saved)))))
T.check(math.abs(round.stages[5].pieces[1].rotation-math.pi/2)<1e-12,"placement rotations survive persistence")
T.eq(round.stages[5].pieces[1].flip,true,"placement mirroring survives persistence")
T.eq(round.stages[5].music,"Gentle","selected music persists")
T.eq(#Showcase.resolve(round,stage),3,"furniture and Pokémon retain stage order")
local moved=assert(Store.moveGroup(round,{{box=1,slot=1}},25,60))
T.eq(Showcase.resolve(moved,stage)[1].entry.id,1,"stage references survive warehouse rearrangement")
T.check(not Showcase.save(state,6,stage),"stage slot outside 1–5 refuses save")
local bad=Store.copy(stage);bad.pieces[1].scale=0
T.check(not Showcase.save(state,1,bad),"invalid placement refuses save")
bad=Store.copy(stage);bad.pieces[1].x=0/0
T.check(not Showcase.save(state,1,bad),"NaN coordinates refuse save")
T.check(not Showcase.export(state,1,{}),"unsaved stage cannot be exported")
local files={[Store.PATH]=Serializer.encode(saved),["saves/red/slot1.lua"]=Serializer.encode({version="red",generation=1,
  party={Store.copy(state.boxes[1].mons[2].mon)},boxes={}})}
local fs={read=function(p)return files[p]end,getInfo=function(p)return files[p] and {type="file"}end,
  createDirectory=function()return true end,write=function(p,b)files[p]=b;return true end,remove=function(p)files[p]=nil;return true end}
local source={version="red",slotId="slot1",path="saves/red/slot1.lua"}
local Catalog=require("src.box.Catalog")
local oldCompatible=Catalog.compatible;Catalog.compatible=function()return true end
local service=assert(Service.open(fs))
T.check(service:withdraw(source,{{box=1,slot=1}},1),"withdrawal moves a staged record into a game")
T.eq(Showcase.resolve(service.state,stage)[1].missing,true,"withdrawn entry becomes a missing placement")
T.check(service:deposit(source,{{where="box",box=1,index=1}},2),"unique native identity can return to Box")
T.eq(Showcase.resolve(service.state,stage)[1].entry.id,1,"return restores the original stage reference")
T.eq(Store.count(service.state),2,"return creates no extra live record")
Catalog.compatible=oldCompatible
do
  local themed=assert(Store.theme(saved,1,"Showcase","box/showcase/125.png","Gentle"))
  local persisted=assert(Store.validate(assert(Serializer.decode(Serializer.encode(themed)))))
  T.eq(Showcase.boxMusic(persisted,persisted.boxes[1]),"Gentle","applied theme keeps its music after reload")
  persisted.stages[5].music="Night"
  T.eq(Showcase.boxMusic(persisted,persisted.boxes[1]),"Gentle","later stage edits do not change the applied music")
  local legacy=assert(Store.theme(saved,1,"Showcase","box/showcase/125.png"))
  T.eq(Showcase.boxMusic(legacy,legacy.boxes[1]),"Gentle","existing stage exports resolve their music")
  local cleared=assert(Store.theme(themed,1,"Forest"))
  T.eq(cleared.boxes[1].showcaseMusic,nil,"changing theme clears associated music")
  T.eq(Showcase.boxMusic(cleared,cleared.boxes[1]),"Silent","ordinary themes stop music")
  T.check(not Store.theme(saved,1,"Showcase","box/showcase/125.png","invalid"),"unknown theme tracks are rejected")
  local music=require("src.box.ShowcaseMusic")
  local oldRequest,oldAudio=music.request,love.audio
  local created,played,stopped,released=0,0,0,0
  local pending=2
  music.request=function()
    if pending>0 then pending=pending-1;return nil,"pending" end
    return {}
  end
  love.audio={newSource=function()
    created=created+1
    return {setLooping=function(_,v) T.eq(v,true,"theme music loops") end,
      setVolume=function() end,play=function() played=played+1 end,stop=function() stopped=stopped+1 end,
      release=function() released=released+1 end}
  end}
  love.sound=love.sound or {};local oldNew=love.sound.newSoundData
  love.sound.newSoundData=love.sound.newSoundData or function() end
  local panel=require("src.import.BoxPanel")
  local imp={_boxState={service={state=themed},box=1}}
  panel.update(imp,.016);panel.update(imp,.016)
  T.eq(created,0,"Box theme renders across frames before creating a source")
  T.eq(Showcase.currentMusic(),"Gentle","pending render keeps the requested track")
  panel.update(imp,.016);panel.update(imp,.016)
  T.eq(created,1,"Box theme creates one source across repeated frames")
  T.eq(played,1,"applied Box music starts automatically")
  imp._boxState.toolsPage="Showcase";panel.update(imp,.016)
  T.eq(stopped,1,"leaving board stops theme music")
  T.eq(released,1,"old source is released")
  Showcase.playMusic({music="Night"});panel.update(imp,.016)
  T.eq(Showcase.currentMusic(),"Night","editor playback survives its update")
  imp._boxState.toolsPage=nil;panel.update(imp,.016)
  T.eq(Showcase.currentMusic(),"Gentle","returning to Boxes resumes its theme")
  imp._boxState.box=2;panel.update(imp,.016)
  T.eq(Showcase.currentMusic(),"Silent","switching to plain Box stops track")
  Showcase.stopMusic();music.request,love.audio,love.sound.newSoundData=oldRequest,oldAudio,oldNew
end
do
  local music=require("src.box.ShowcaseMusic")
  local oldNew=love.sound and love.sound.newSoundData
  love.sound=love.sound or {}
  local samples=0
  love.sound.newSoundData=function(n) return {n=n,setSample=function() samples=samples+1 end} end
  local calls,sound,why=0
  repeat calls=calls+1;sound,why=music.request("Dream",0) until sound or why~="pending" or calls>100000
  T.check(sound~=nil and calls>1,"song rendering yields across calls")
  T.eq(music.request("Dream",0),sound,"rendered song is cached")
  T.eq(samples,sound.n*2,"every sample is written once")
  love.sound.newSoundData=oldNew
end
do
  local files={["box/showcase/11.png"]="a",["box/showcase/12.png"]="b",["box/showcase/21.png"]="c",["box/showcase/note.txt"]="d"}
  local fs={read=function(p)return files[p]end,getInfo=function(p)return files[p] and {type="file"}end,remove=function(p)files[p]=nil;return true end,
    getDirectoryItems=function()local out={} for p in pairs(files) do out[#out+1]=p:match("[^/]+$") end return out end}
  local kept=Store.new();kept.boxes[2].theme,kept.boxes[2].wallpaper="Showcase","box/showcase/12.png"
  T.eq(Showcase.prune(kept,fs,"box/showcase/21.png"),1,"stale exported wallpaper is removed")
  T.eq(files["box/showcase/11.png"],nil,"unreferenced export is gone")
  T.check(files["box/showcase/12.png"] and files["box/showcase/21.png"] and files["box/showcase/note.txt"],"referenced, new and foreign files survive")
  files["box/showcase/31.png"]="e";files[require("src.box.Transaction").PATH]="pending"
  T.eq(Showcase.prune(kept,fs),0,"pending transfer blocks wallpaper cleanup")
end
do
  local g=love.graphics
  local oldRect=g.rectangle
  local count=0
  g.rectangle=function() count=count+1 end
  local empty=Showcase.new();empty.pattern="Checks"
  Showcase.draw(state,empty,0,0,0,100);Showcase.draw(state,empty,0,0,100,-1)
  T.eq(count,0,"zero-sized stage draws nothing")
  g.rectangle=oldRect
end
do
  local g=love.graphics
  local oldColor,oldScissor,oldSetScissor=g.setColor,g.getScissor,g.setScissor
  local colors,clips={},{}
  g.setColor=function(...) colors[#colors+1]={...} end
  g.getScissor=function() return 10,20,100,50 end
  g.setScissor=function(...) clips[#clips+1]={...} end
  for _,background in ipairs(Showcase.BACKGROUNDS) do
    colors,clips={},{}
    local empty=Showcase.new();empty.background=background
    Showcase.draw(state,empty,0,0,568,216)
    T.check(math.max(colors[1][1],colors[1][2],colors[1][3])>.1,
      background.." uses the launcher's 255 RGB color contract")
    T.eq(colors[2][1],1,"pattern white remains white through Theme.col")
    T.same(clips[1],{10,20,100,50},"stage respects the existing launcher clip")
    T.same(clips[#clips],{10,20,100,50},"stage restores the launcher clip")
  end
  g.setColor,g.getScissor,g.setScissor=oldColor,oldScissor,oldSetScissor
end
do
  local g=love.graphics
  local oldLine=g.line
  local calls,patterns={},{}
  g.line=function(...) calls[#calls+1]={...} end
  for _,pattern in ipairs({"Crosses","Bricks","Grid"}) do
    calls={};local empty=Showcase.new();empty.pattern=pattern
    Showcase.draw(state,empty,0,0,400,200)
    patterns[pattern]=Serializer.encode(calls)
  end
  T.check(patterns.Crosses~=patterns.Bricks,"cross motifs differ from staggered bricks")
  T.check(patterns.Crosses~=patterns.Grid,"cross motifs differ from continuous grid")
  T.check(patterns.Bricks~=patterns.Grid,"brick seams alternate instead of square grid")
  g.line=oldLine
end
T.finish("Box showcase")
