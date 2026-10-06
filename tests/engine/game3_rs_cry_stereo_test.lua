package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local Version=require('src.core.GameVersion')
local Audio=require('src.core.game3.audio')
local Sample=require('src.core.game3.m4a_sample')
local pcm={}
for i=0,63 do pcm[#pcm+1]=string.char((i*7)%256) end
pcm=table.concat(pcm)
local created={}
love.audio={}
love.audio.newSource=function(sd,...)
  created[#created+1]=sd
  local source={playing=false}
  function source:play() self.playing=true end
  function source:stop() self.playing=false end
  function source:isPlaying() return self.playing end
  function source:setVolume() end
  return source
end
for _,game in ipairs({'ruby','sapphire'}) do
  Version.set(game)
  for mode=0,5 do for _,pan in ipairs({-64,0,63}) do
    local params=Sample.cryParams(mode,Audio.config().cryDefaultVolume,Audio.config().cryModeOverrides)
    local stereo=assert(Sample.renderCry(pcm,8000,params,{outRate=8000,pan=pan,mono=false}))
    local mono=assert(Sample.renderCry(pcm,8000,params,{outRate=8000,pan=pan,mono=true}))
    T.eq(stereo:getChannelCount(),2,'native stereo DAC routing')
    T.eq(mono:getChannelCount(),1,'native mono DAC routing')
    T.eq(mono:getSampleCount(),stereo:getSampleCount(),'routing preserves duration')
    for i=0,mono:getSampleCount()-1 do
      T.check(math.abs(mono:getSample(i)-(stereo:getSample(i,1)+stereo:getSample(i,2))*0.5)<1e-12,'mono mixes both native channels at half gain')
    end
  end end
  Audio._pack={index={cryIds={[25]=0},cries={[0]={sampleId=1}}},samples={[1]={offset=0,size=#pcm,freq=8000*1024}},samplesBin=pcm}
  Audio._ready=true
  for _,stereo in ipairs({0,1,0}) do
    T.eq(Audio.setCryStereo(stereo),stereo,'native Sound_ProcessInput routing')
    Audio.playCry(25,{mode=0,pan=63})
    T.eq(created[#created]:getChannelCount(),stereo==1 and 2 or 1,'real Audio.playCry uses immediate options routing')
    Audio.stopCry()
  end
end
T.finish('game3_rs_cry_stereo')
