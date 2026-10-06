package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.harness")
local Extract=require("src.import.gba.object_interactions_extract")
local Opcodes=require("src.core.game3.scripting.opcodes")
for _,game in ipairs({"ruby","sapphire"}) do
  for _,build in ipairs(require("src.import.gba.rs_builds")[game]) do
    local S=require("src.import.gba.syms").of(build.build)
    local seeds,aliases,rows=Extract.readScriptsRse(build.build)
    T.eq(#rows,19,"native RS metatile branches")
    T.eq(#seeds,27,"native RS interaction and code roots")
    for _,row in ipairs(rows) do
      T.eq(aliases[row[2]],Opcodes.key(0x08000000+S.off(row[4] or row[2])),"native revision root "..row[2])
      T.check(row[1]~="WIRELESS_BOX_RESULTS" and row[1]~="QUESTIONNAIRE" and row[1]~="TRAINER_HILL_TIMER"
        and row[1]~="SKY_PILLAR_CLOSED_DOOR" and row[1]~="CABLE_BOX_RESULTS_2","Emerald-only interaction absent")
    end
    for _,row in ipairs({{"EventScript_TV","Event_TV"},{"EventScript_UseWaterfall","S_UseWaterfall"},
        {"EventScript_CannotUseWaterfall","S_CannotUseWaterfall"},{"EventScript_UseDive","UseDiveScript"},
        {"EventScript_HiddenItemScript","EventScript_HiddenItem"}}) do
      T.eq(aliases[row[1]],Opcodes.key(0x08000000+S.off(row[2])),"RS field consumer alias")
    end
    T.check(aliases.EventScript_FallDownHoleMtPyre~=nil and aliases.S_UseDiveUnderwater~=nil,"native fall/emerge code roots")
    T.eq(aliases.EventScript_Questionnaire,nil,"no Emerald questionnaire seed")
  end
end
local seeds,_,rows=Extract.readScriptsRse("emerald")
T.eq(rows,Extract.RSE_INTERACTIONS,"Emerald preserves its native interaction branches")
T.eq(#seeds,#Extract.RSE_INTERACTIONS+#Extract.RSE_CODE_ROOTS-1,"Emerald duplicate cable script is seeded once")
T.finish("game3_rs_interaction_roots")
