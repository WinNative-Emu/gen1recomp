package.path="./?.lua;./?/init.lua;"..package.path
love=love or require("tests.love_stub")
local T=require("tests.harness")
local Importer=require("src.import.RomImporter")
local Panel=require("src.import.BoxPanel")
local Transition=require("src.ui.kit.Transition")
local clock=10
local oldTime,oldRefresh=love.timer.getTime,Panel.refresh
love.timer.getTime=function() return clock end
Panel.refresh=function(self) clock=clock+.7;self._boxState={};return self._boxState end
local imp=setmetatable({_disarmTextInput=function() end,_setModScope=function() end,
  _queueReimport=function() end,_ensureSkins=function() clock=clock+.3 end}, {__index=Importer})
Transition.armed,Transition.reduceMotion=true,false
local tabs={"red","box","mods","online","skins"}
for _,from in ipairs(tabs) do
  for _,to in ipairs(tabs) do
    if from~=to then
      imp.tab=from
      imp:_switchTab(to)
      Transition.update()
      local tr=Transition.get("tabs")
      T.check(tr~=nil,from.." → "..to.." starts after loading completes")
      T.eq(tr.from,from,"outgoing page retained")
      T.eq(tr.to,to,"incoming page retained")
      T.eq(tr.p,0,"first frame has whole slide remaining")
      clock=clock+.09;Transition.update()
      T.check(Transition.progress("tabs")>0 and Transition.progress("tabs")<1,"midpoint still slides")
      clock=clock+.1;Transition.update()
      T.eq(Transition.get("tabs"),nil,"slide finishes")
    end
  end
end
Transition.reduceMotion=true;imp.tab="red";imp:_switchTab("box")
T.eq(Transition.get("tabs"),nil,"reduced motion still disables Box slide")
love.timer.getTime,Panel.refresh=oldTime,oldRefresh
Transition.armed,Transition.reduceMotion=false,false;Transition.clear("tabs")
T.finish("launcher_box_transition")
