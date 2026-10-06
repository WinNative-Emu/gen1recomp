package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")
local Version = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local Prize = require("src.core.game3.battle.prize")
local Ai = require("src.core.game3.battle.ai")
local Sample = require("src.core.game3.m4a_sample")
local Audio = require("src.core.game3.audio")
local Policy = require("src.core.game3.audio_policy_rs")
local Songs = require("src.core.game3.song_ids")

-- battle_script_commands.c:1005
local expected = {}
for r=0,99 do
  expected[r] = r<30 and 22 or r<40 and 23 or r<50 and 2 or r<60 and 68
    or r<70 and 19 or r<80 and 24 or r<90 and 110 or r<95 and 64
    or r<99 and 69 or 187
end
for _,game in ipairs({"ruby","sapphire"}) do
  Version.set(game)
  local p=Profile.of(game)
  for _,level in ipairs({1,100}) do
    for roll=0,99 do
      local mon={species=263,speciesNumbering="internal",abilityId=53,level=level}
      local calls=0
      local got=Prize.pickup({mon},function() calls=calls+1; return calls==1 and 0 or roll end,p.battle.rules)
      T.eq(mon.heldItem,expected[roll],game.." native Pickup roll "..roll.." level "..level)
      T.eq(#got,1,"Pickup acquisition reaches party")
      T.eq(calls,2,"Pickup consumes chance then item roll")
    end
  end
  local calls=0
  local party={{species=263,abilityId=53,item=1},{species=263,abilityId=53,isEgg=true},
    {species=263,abilityId=1},{species=0,abilityId=53},{species=263,abilityId=53}}
  for _,mon in ipairs(party) do mon.speciesNumbering="internal" end
  T.eq(#Prize.pickup(party,function() calls=calls+1;return 1 end,p.battle.rules),0,"ineligible party and failed chance")
  T.eq(calls,1,"ineligible slots do not consume RNG")
  T.eq(Prize.rewardRse(nil,{secretBaseLevel=42,moneyMultiplier=2}),1680,"native secret-base prize bypasses trainer class/double")

  -- battle_ai_script_commands.c:440
  local st={session={version=game},battlers={[0]={mon={},lastMoveId=33},[2]={mon={},lastMoveId=45}}}
  for i=1,8 do Ai.recordLastUsedMove(st,0) end
  st.battlers[0]={mon={},lastMoveId=99}
  Ai.recordLastUsedMove(st,0)
  T.same(Ai.usedMoves(st,0),{33,33,33,33,33,33,33,33},"full native position history keeps duplicates across switch")
  Ai.recordLastUsedMove(st,2)
  T.same(Ai.usedMoves(st,2),{45,0,0,0,0,0,0,0},"second native position has separate history")

  -- sound.c:347
  local native={{140,0,15360,0,125},{20,225,15360,0,125},{30,225,15600,20,80},
    {50,200,14800,0,125},{20,220,15800,0,125},{140,200,14500,0,125}}
  local cfg=Audio.config()
  for mode=0,5 do
    local c=Sample.cryParams(mode,cfg.cryDefaultVolume,cfg.cryModeOverrides)
    T.same({c.length,c.release,c.pitch,c.chorus,c.volume},native[mode+1],"native cry mode "..mode)
    T.eq(Sample.cryParams(mode,70,cfg.cryModeOverrides).volume,mode==2 and 80 or 70,"explicit cry volume")
  end

  local S=Songs.forVersion(game)
  local weatherSong=game=="ruby" and "MUS_WEATHER_GROUDON" or "MUS_WEATHER_KYOGRE"
  local function ctx(map,o)
    o=o or {}
    return {songs=S,legendaryWeatherSong=weatherSong,location={map=map,x=o.x or 0},
      flag=function(n) return n=="FLAG_SYS_WEATHER_CTRL" and o.legendary or n=="FLAG_DONT_TRANSITION_MUSIC" and o.block or false end,
      var=function(n) return n=="VAR_WEATHER_INSTITUTE_STATE" and (o.institute or 0) or 1 end,
      headerMusic=function(loc) return loc.map=="ROUTE118" and 0x7FFF or S.MUS_ROUTE101 end,
      weather=function() return 8 end,savedWeather=function() return o.weather or 0 end,
      savedMusic=o.saved,currentMusic=o.current or 0,surfing=o.surfing,biking=o.biking,underwater=o.underwater,
      isIndoor=function(loc) return loc.map=="INDOOR" end}
  end
  for _,map in ipairs({"LILYCOVE_CITY","MOSSDEEP_CITY","SOOTOPOLIS_CITY","EVER_GRANDE_CITY","ROUTE124","ROUTE125","ROUTE126","ROUTE127","ROUTE128"}) do
    local c=ctx(map,{legendary=true,saved=S.MUS_CYCLING,surfing=true})
    T.eq(Policy.specialMapMusic(c),S[weatherSong],"native weather beats saved/surf "..map)
    T.eq(Policy.shouldLegendaryMusicPlayAtLocation(ctx(map),{map=map}),false,"weather requires native flag")
  end
  for _,map in ipairs({"ROUTE129","ROUTE130","ROUTE131","MOSSDEEP_CITY_SPACE_CENTER_1F","SOOTOPOLIS_CITY_GYM_1F"}) do
    T.eq(Policy.locationMusic(ctx(map,{legendary=true}),{map=map}),S.MUS_ROUTE101,"no Emerald music exception "..map)
  end
  T.eq(Policy.currLocationDefaultMusic(ctx("ROUTE111",{weather=8})),S.MUS_ROUTE111,"native RS sandstorm music")
  T.eq(Policy.currLocationDefaultMusic(ctx("ROUTE118",{x=23})),S.MUS_ROUTE110,"native sentinel west boundary")
  T.eq(Policy.currLocationDefaultMusic(ctx("ROUTE118",{x=24})),S.MUS_ROUTE119,"native sentinel east boundary")
  T.eq(Policy.locationMusic(ctx("ROUTE119_WEATHER_INSTITUTE_1F"),{map="ROUTE119_WEATHER_INSTITUTE_1F"}),S.MUS_MT_CHIMNEY,"native institute infiltration")
  T.eq(Policy.locationMusic(ctx("ROUTE119_WEATHER_INSTITUTE_1F",{institute=1}),{map="ROUTE119_WEATHER_INSTITUTE_1F"}),S.MUS_ROUTE101,"cleared institute")
  T.eq(Policy.transitionMapMusic(ctx("ROUTE101",{current=S.MUS_SURF,surfing=true}),{map="ROUTE102"}),nil,"surf song persists across connection")
  T.same(Policy.transitionMapMusic(ctx("ROUTE101",{biking=true}),{map="ROUTE102"}),{song=S.MUS_ROUTE101,fadeOut=4,fadeIn=4},"native bike transition fades")
  T.eq(Policy.tryFadeOutOldMapMusic(ctx("ROUTE101"),{map="INDOOR"}),2,"native indoor warp fade")
end

local st={session={version="emerald"},battlers={[0]={mon={},lastMoveId=33}}}
Ai.recordLastUsedMove(st,0);Ai.recordLastUsedMove(st,0)
local used=Ai.usedMoves(st,0)
T.same({used[1],used[2],used[3],used[4]},{33,0,0,0},"Emerald history stays deduplicated")
st.battlers[0]={mon={},lastMoveId=99}
T.same(Ai.usedMoves(st,0),{0,0,0,0},"Emerald history resets for new occupant")
T.finish("game3_rs_battle_audio")
