package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")
local Tv = require("src.save_convert.gen3_port.sections.rs_tv_shows")
local Codec = require("src.save_convert.Gen3Save").forVersion("ruby")
local Same = require("src.save_convert.gen3_port.rse").same
local function native(kind, outcome)
  local b = Codec.newBuf(36)
  for i=0,35 do b:w8(i,(i*19+7)%256) end
  b:w8(0,kind);b:w8(1,7)
  if kind==5 then
    b:bytes(4,Codec.encodeString("TORCHIC",11,0));b:w8(13,0x97);b:w8(14,0x91)
    b:bytes(15,Codec.encodeString("BRENDAN",11,0));b:w8(24,0x98);b:w8(25,0x92)
  elseif kind==7 then
    b:bytes(2,Codec.encodeString("BRENDAN",8,0));b:bytes(12,Codec.encodeString("WALLY",8,0))
    b:w8(28,outcome or 1);b:w8(30,0xA5);b:w8(31,0xC3)
  end
  return b:str()
end
for _, kind in ipairs({1,2,3,4,5,6,7,21,22,23,24,25,41,0,8,12,26,39,255}) do
  local raw=native(kind)
  local show=Tv.readSlot(raw,Codec)
  T.eq(Tv.render(Codec,raw,show,Same),raw,"native union unchanged kind "..kind)
  T.eq(Tv.render(Codec,string.rep("\0",36),show,Same),raw,"native record moved kind "..kind)
end
local raw=native(5)
local show=Tv.readSlot(raw,Codec)
T.eq(show.trainerName,"BRENDAN","RS eleven-byte trainer-name domain")
show.trainerName="MAY"
local edited=Tv.render(Codec,raw,show,Same)
T.eq(Codec.decodeString(edited,15,11),"MAY","native name mutation")
T.eq(edited:sub(1,15),raw:sub(1,15),"name edit preserves earlier fields/padding")
T.eq(edited:sub(27),raw:sub(27),"name edit preserves subsequent fields")
T.eq(edited:byte(2),7,"unchanged native noncanonical active byte retained")
for outcome=1,3 do
  raw=native(7,outcome);show=Tv.readSlot(raw,Codec)
  T.eq(show.battleOutcome,outcome,"native numeric Tower outcome")
  T.eq(show.wonTheChallenge,outcome==1,"Tower semantic outcome")
  show.words[1]=1234
  edited=Tv.render(Codec,raw,show,Same)
  T.eq(edited:byte(29),outcome,"word mutation retains numeric outcome")
  T.eq(edited:sub(31,32),raw:sub(31,32),"RS Tower unused language bytes retained")
end
raw=native(255);show=Tv.readSlot(raw,Codec);show.active=false
edited=Tv.render(Codec,raw,show,Same)
T.eq(edited:byte(2),0,"unknown union changes active header")
T.eq(edited:sub(3),raw:sub(3),"unknown union payload remains opaque")
edited=Tv.render(Codec,native(5),{kind=7,active=true,playerName="MAY",opponentName="WALLY",battleOutcome=3},Same)
T.eq(edited:sub(31,32),"\0\0","new known record clears stale union padding")
T.eq(edited:byte(29),3,"fresh Tower preserves supplied native outcome")
T.eq(Tv.render(Codec,native(5),{kind=0,active=false},Same),string.rep("\0",36),"cleared TV slot zeroes all bytes")
local Policy=require("src.core.game3.profiles.rs.tv")
T.eq(Policy.currentWinStreak({curStreakChallengesNum={1},curChallengeBattleNum={1}},0),0,"Tower first battle streak zero")
T.eq(Policy.currentWinStreak({curStreakChallengesNum={2},curChallengeBattleNum={3}},0),9,"Tower challenge+current battle")
T.eq(Policy.currentWinStreak({curStreakChallengesNum={0},curChallengeBattleNum={0}},0),9999,"native uint16 underflow capped")
T.eq(Policy.currentWinStreak({curStreakChallengesNum={2000},curChallengeBattleNum={7}},0),9999,"Tower streak cap")
local context=Policy.towerInterview({battleTower={lastStreakLevelType=1,battleOutcome=3,curStreakChallengesNum={0,2},curChallengeBattleNum={0,3},firstMonSpecies=280,defeatedBySpecies=283,defeatedByTrainerName="MAY"}})
T.eq(context.playerSpecies,280,"interview uses native Tower's first saved mon")
T.eq(context.numFights,9,"interview selects saved native level streak")
T.eq(context.battleOutcome,3,"interview retains loss/draw numeric value")
T.finish("gen3_save_rs_tv")
