package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
local T=require("tests.harness")
local Version=require("src.core.GameVersion")
local sess={version="ruby",vars={},flags={},weatherCycleStage=0}
package.loaded["src.core.game3.runtime"]={getSession=function() return sess end,_game={data={maps={}}}}
package.loaded["src.core.game3.dataset"]={cache=function() return {read=function()
  return "return {cycles={route119={2,3,5,3},route123={2,2,3,2}}}"
end} end}
local dispatch={}
local E={startAbnormal=function() dispatch[#dispatch+1]="abnormal";return 12 end,
  stopAbnormal=function() dispatch[#dispatch+1]="stop" end,
  setNextWeather=function(id) dispatch[#dispatch+1]={"next",id} end,
  setCurrentAndNextWeather=function(id) dispatch[#dispatch+1]={"resume",id} end,
  readyForInit=function() dispatch[#dispatch+1]="ready" end,
  getCurrentWeather=function() return 2 end}
package.loaded["src.core.game3.field_weather_rse"]=E
local Space={store={flags={},vars={}}}
package.loaded["src.core.game3.scripting.space"]=Space
local Weather=require("src.core.game3.weather")
local Tv=require("src.core.game3.rse.tv")
local NativesTv=require("src.core.game3.scripting.natives_tv")
local Rse=require("src.core.game3.rse.init")
for _,game in ipairs({"ruby","sapphire"}) do
  Version.set(game);sess={version=game,vars={},flags={}}
  local prefix=game=="ruby" and "RU_" or "SA_"
  for stage=0,3 do
    sess.weatherCycleStage=stage
    for input=0,511 do
      local byte=input%256
      local expected=byte<=14 and byte or byte==20 and ({2,3,5,3})[stage+1]
        or byte==21 and ({2,2,3,2})[stage+1] or 0
      T.eq(Weather.translate(input,sess),expected,"RS native u8 weather switch")
    end
  end
  T.eq(Weather.translate(15,{version="emerald"}),15,"explicit Emerald session retains abnormal")
  sess.savedWeather=15;dispatch={};Weather.doCurrent()
  T.same(dispatch,{"stop",{"next",15}},"RS dispatches saved weather without Emerald task")
  dispatch={};Weather.resumePaused()
  T.same(dispatch,{"stop",{"resume",15},"ready"},"RS resume initializes saved weather directly")
  sess.gameStats={[40]=0xFFFFFE};sess.savedWeather=2
  Weather.setSaved(3,sess);T.eq(sess.gameStats[40],0xFFFFFF,"native rain statistic increments")
  Weather.setSaved(3,sess);T.eq(sess.gameStats[40],0xFFFFFF,"unchanged rain does not increment")
  Weather.setSaved(5,sess);T.eq(sess.gameStats[40],0xFFFFFF,"rain statistic saturates24bits")
  Weather.setSaved(15,sess);T.eq(sess.savedWeather,0,"invalid RS weather persists NONE")
  sess.weatherCycleStage=3;Weather.updatePerDay(65535,sess)
  T.eq(sess.weatherCycleStage,2,"native cycle wraps accumulated u16 days")
  for gender=0,1 do
    sess.gender=gender;sess.map=prefix..(gender==0 and "LITTLEROOT_TOWN_BRENDANS_HOUSE_1F" or "LITTLEROOT_TOWN_MAYS_HOUSE_1F")
    Space.store={flags={},vars={}}
    Rse.setFlag("FLAG_SYS_TV_LATI",false,sess);Rse.setFlag("FLAG_SYS_TV_HOME",false,sess)
    T.check(pcall(NativesTv.updateScreensOnMap,sess),"native house TV flag names resolve")
    T.eq(Rse.flag("FLAG_SYS_TV_WATCH",sess),true,"TV update starts native WATCH flag")
    local calls={}
    local opts={mapGroup=1,mapNum=gender==0 and 2 or 3,housesGroup=1,brendanNum=2,mayNum=3,gender=gender,
      latiFlag="FLAG_SYS_TV_LATI",flag=function(name) calls[#calls+1]=name;return Rse.flag(name,sess) end}
    T.eq(Tv.checkForPlayersHouseNews(opts),1,"native default emergency broadcast")
    T.same(calls,{"FLAG_SYS_TV_LATI","FLAG_SYS_TV_HOME"},"RS reads native TV flags")
    Rse.setFlag("FLAG_SYS_TV_HOME",true,sess)
    T.eq(Tv.checkForPlayersHouseNews(opts),2,"movie home flag")
    Rse.setFlag("FLAG_SYS_TV_LATI",true,sess)
    T.eq(Tv.checkForPlayersHouseNews(opts),1,"Lati emergency has priority")
    opts.mapNum=9;T.eq(Tv.checkForPlayersHouseNews(opts),0,"other house has no player broadcast")
  end
end
Version.set("emerald");sess.version="emerald";sess.savedWeather=15;dispatch={};Weather.doCurrent()
T.same(dispatch,{"abnormal",{"next",12}},"Emerald preserves abnormal task")
T.eq(Weather.translate(15,sess),15,"Emerald retains weather15")
T.finish("game3_rs_weather_tv")
