package.path="./?.lua;./?/init.lua;"..package.path
love=love or require("tests.love_stub")
local T=require("tests.harness")
local Store=require("src.box.Store")
local Search=require("src.box.Search")
local Showcase=require("src.box.Showcase")
local Editor=require("src.import.ShowcaseEditor")
local Organizer=require("src.box.Organizer")
local Kit=require("src.ui.kit.Kit")
local s={stageDraft=Showcase.new(),stagePiece=1,toolsPage="Showcase",stageRect={x=10,y=20,w=400,h=200}}
s.stageDraft.pieces={{kind="Arch",x=.5,y=.5,scale=1,rotation=0},
  {kind="Tree",x=.5,y=.5,scale=1,rotation=0}}
T.eq(Showcase.hit(s.stageDraft,10,20,400,200,210,120),2,"frontmost visible layer is picked")
T.eq(Showcase.reorder(s.stageDraft,2,1),1,"send behind updates array layer")
T.eq(Showcase.hit(s.stageDraft,10,20,400,200,210,120),2,"new frontmost layer is picked")
T.eq(s.stageDraft.pieces[2].kind,"Arch","arch is now in front")
local imp={tab="box",_boxState=s}
Kit.blockClicks=false
T.check(Editor.pointerPressed(imp,"finger",210,120),"touch starts a direct scene drag")
T.check(Editor.pointerMoved(imp,"finger",250,140),"touch move stays in scene")
T.eq(s.stageDraft.pieces[2].x,.6,"scene drag uses normalized X")
T.eq(s.stageDraft.pieces[2].y,.6,"scene drag uses normalized Y")
T.check(Editor.pointerReleased(imp,"finger"),"touch release ends drag")
T.eq(s.stageGesture,nil,"gesture cleared")
T.eq(#s.stageUndo,1,"one undo snapshot for entire drag")
Editor.begin(s,"resize",210,120,s.stageRect)
Editor.move(s,350,80,s.stageRect)
T.check(s.stageDraft.pieces[2].scale>1,"hold resize uses pointer movement")
Editor.move(s,9999,-9999,s.stageRect)
T.eq(s.stageDraft.pieces[2].scale,4,"resize respects maximum")
Editor.finish(s)
Editor.begin(s,"rotate",290,140,s.stageRect)
Editor.move(s,250,180,s.stageRect)
T.check(math.abs(s.stageDraft.pieces[2].rotation)>0,"hold rotation uses angle around piece")
Editor.finish(s)
s.stageDraft.pieces[2].flipY=true
T.check(Showcase.validate(s.stageDraft,1),"vertical flip survives stage validation")
local state=Store.new()
local saved=assert(Showcase.save(state,1,s.stageDraft))
T.eq(saved.stages[1].pieces[2].flipY,true,"vertical flip persists")
T.eq(saved.stages[1].pieces[2].kind,"Arch","layer order persists")
for _,query in ipairs({"bulba","BULBA","BuLbA","Pokémon","POKÉMON","pokemon"}) do
  local entry={version="red",display={name="Bulbasaur Pokémon",species="BULBASAUR"},mon={}}
  T.check(Search.compile(query)(entry,"BOX 1"),"lookup folds case/accents: "..query)
end
local entry={id=1,version="red",generation=1,mon={},display={name="Bulbasaur",species="BULBASAUR",types="Grass",national=1,level=10}}
local layout={count=14,capacity=30,names={},rows={{box=1,slot=1,entry=entry}}}
for b=1,14 do layout.names[b]="BOX "..b end
local config={mode="rules",sort="species",descending=false,fallback="sort",
  rules={{firstBox=1,lastBox=14,match="all",conditions={{field="species",value="buLBAsaur"}}}}}
local analysis=assert(Organizer.analyze(layout,config))
T.eq(analysis.ruleCounts[1],1,"live count shares actual case-insensitive rule matcher")
T.eq(analysis.freeBoxes,0,"all reserved boxes are reported")
T.eq(analysis.remaining,0,"remaining count excludes first matching rule")
config.rules[1].conditions[1].value="PIKACHU"
analysis=assert(Organizer.analyze(layout,config))
T.eq(analysis.remaining,1,"unmatched group is visible before preview")
T.check(Organizer.plan(layout,config)==nil,"full reserved range prevents fallback placement")
T.finish("box_studio_interaction")
