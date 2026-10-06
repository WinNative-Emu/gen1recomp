package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
local T=require("tests.harness")
local Version=require("src.core.GameVersion")
local sess={version="ruby"}
package.loaded["src.core.game3.runtime"]={getSession=function() return sess end}
local grid,writes={},{}
package.loaded["src.core.game3.step_callbacks_rse"]={metatileAt=function(x,y) return grid[y*32+x] end}
package.loaded["src.core.game3.field"]={setMetatile=function(x,y,id,solid) grid[y*32+x]=id;writes[y*32+x]=solid end}
local Gym=require("src.core.game3.scripting.natives_rs_gym").BY_NAME
local Story=require("src.core.game3.rse.story_specials")
for _,game in ipairs({"ruby","sapphire"}) do
  Version.set(game);sess.version=game
  local C=require("src.core.game3.constants").of(game)
  local raised=C:require("metatile_labels","METATILE_MauvilleGym_RaisedSwitch")
  local pressed=C:require("metatile_labels","METATILE_MauvilleGym_PressedSwitch")
  local coords={{0,9},{8,11},{4,15}}
  for chosen=0,2 do
    grid,writes={},{}
    Gym.MauvilleGymSpecial1({getVar=function() return chosen end})
    for i,xy in ipairs(coords) do T.eq(grid[xy[2]*32+xy[1]],i-1==chosen and pressed or raised,"RS three-switch layout") end
    T.eq(grid[9*32+3],nil,"Emerald fourth switch is absent")
  end
  local door,frames={},{}
  local step=Story.slideDoorsTask(4,function(x,y,id) door[y*256+x]=id end,C,function(f) frames[#frames+1]=f end)
  local done
  for i=1,20 do if step() then done=i;break end end
  T.eq(done,9,"native Petalburg five frames with 0,1,1,1,1 delays")
  T.same(frames,{0,1,2,3,4},"native door frames")
  T.eq(door[39*256+7],C:require("metatile_labels","METATILE_PetalburgGym_SlidingDoor_Frame4"),"native Petalburg coordinates")

  local raw={}
  for i=1,1328 do raw[i]=(i*13+5)%256 end
  raw[11]=3;raw[21]=4
  local sum=0
  for off=0,1323 do if off<12 or off>=20 then sum=sum+raw[off+1] end end
  for off=1324,1327 do raw[off+1]=math.floor(sum/256^(off-1324))%256 end
  sess.enigmaBerryNativeBytes=raw
  local _,valid=Gym.IsEnigmaBerryValid();T.eq(valid,1,"valid native Enigma checksum")
  for i=13,20 do raw[i]=255-raw[i] end
  _,valid=Gym.IsEnigmaBerryValid();T.eq(valid,1,"description pointers are excluded")
  raw[30]=(raw[30]+1)%256
  _,valid=Gym.IsEnigmaBerryValid();T.eq(valid,0,"mutated native payload fails checksum")
  raw[30]=(raw[30]-1)%256;raw[11]=0
  _,valid=Gym.IsEnigmaBerryValid();T.eq(valid,0,"zero native berry size is invalid")
  raw[11]=3;raw[21]=0
  _,valid=Gym.IsEnigmaBerryValid();T.eq(valid,0,"zero native growth time is invalid")
  sess.enigmaBerryNativeBytes=nil
  _,valid=Gym.IsEnigmaBerryValid();T.eq(valid,0,"absent native Enigma berry is invalid")
end
T.finish("game3_rs_gym")
