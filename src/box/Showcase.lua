local Store = require("src.box.Store")
local Theme = require("src.ui.kit.Theme")
local Catalog = require("src.box.Catalog")
local Sprites = require("src.online.OnlineSprites")
local Showcase = {}
Showcase.BACKGROUNDS = { "Forest", "Sky", "Brick", "Sunset", "Ocean", "Midnight", "Meadow", "Lavender", "Sand", "Snow" }
Showcase.PATTERNS = { "Plain", "Checks", "Dots", "Stripes", "Crosses", "Diamonds", "Bricks", "Waves", "Stars", "Grid" }
Showcase.PIECES = { "Platform", "Block", "Steps", "Pillar", "Arch", "Tree", "Flowers", "Rock", "Fence" }
Showcase.MUSIC = { "Silent", "Gentle", "Bright", "Waltz", "March", "Dream", "Waves", "Night", "Playful" }
local COLORS = { Forest={46,92,61},Sky={77,128,173},Brick={112,77,87},Sunset={153,82,64},
  Ocean={36,107,128},Midnight={31,36,66},Meadow={92,128,61},Lavender={110,87,148},
  Sand={166,143,97},Snow={153,171,184} }
local function contains(list,value) for _,v in ipairs(list) do if v==value then return true end end end
local function finite(value,lo,hi)
  return type(value)=="number" and value==value and value>=lo and value<=hi
end
function Showcase.new()
  return {name="Stage",background="Forest",pattern="Plain",music="Silent",pieces={}}
end
function Showcase.validate(stage, nextId)
  if type(stage)~="table" or type(stage.name)~="string" or #stage.name>64
      or not contains(Showcase.BACKGROUNDS,stage.background) or not contains(Showcase.PATTERNS,stage.pattern)
      or not contains(Showcase.MUSIC,stage.music) or type(stage.pieces)~="table" or #stage.pieces>1500 then
    return nil,"A showcase stage is invalid."
  end
  for _,piece in ipairs(stage.pieces) do
    if type(piece)~="table" or not finite(piece.x,0,1) or not finite(piece.y,0,1)
        or not finite(piece.scale,0.25,4) or not finite(piece.rotation,-math.pi,math.pi)
        or piece.flip~=nil and type(piece.flip)~="boolean"
        or piece.flipY~=nil and type(piece.flipY)~="boolean" then return nil,"A stage placement is invalid." end
    if piece.entryId then
      if not finite(piece.entryId,1,nextId-1) or piece.entryId%1~=0 then return nil,"A stage Pokémon reference is invalid." end
    elseif not contains(Showcase.PIECES,piece.kind) then return nil,"A showcase piece is invalid." end
  end
  return stage
end
function Showcase.reorder(stage, index, destination)
  if not stage.pieces[index] or destination < 1 or destination > #stage.pieces then return nil end
  local piece = table.remove(stage.pieces, index)
  table.insert(stage.pieces, destination, piece)
  return destination
end
local sceneryImage, sceneryRects, sceneryQuads
function Showcase.drawProp(kind, x, y, size)
  local g = love and love.graphics
  if not g or not g.newImage or not g.newQuad then return false end
  if sceneryImage == false then return false end
  if not sceneryImage then
    local ok, img = pcall(g.newImage, "assets/box/showcase/scenery-v1.png")
    if not ok then sceneryImage = false; return false end
    sceneryImage = img
    sceneryImage:setFilter("nearest", "nearest")
    local bytes = love.filesystem.read("assets/box/showcase/scenery-v1.json")
    local ok2, data = pcall(function() return bytes and require("src.link.Json").decode(bytes) end)
    local rects = ok2 and type(data) == "table" and data.rects
    sceneryRects, sceneryQuads = type(rects) == "table" and rects or {}, {}
  end
  local rect = sceneryRects[kind]
  if type(rect) ~= "table" then return false end
  for i = 1, 4 do if type(rect[i]) ~= "number" then return false end end
  if not sceneryQuads[kind] then sceneryQuads[kind] = g.newQuad(rect[1],rect[2],rect[3],rect[4],sceneryImage:getDimensions()) end
  local scale = size / math.max(rect[3],rect[4])
  Theme.col({255,255,255},1)
  g.draw(sceneryImage, sceneryQuads[kind], x + (size - rect[3] * scale) / 2,
    y + (size - rect[4] * scale) / 2, 0, scale, scale)
  return true
end
function Showcase.hit(stage, x, y, w, h, mx, my)
  for index = #stage.pieces, 1, -1 do
    local p = stage.pieces[index]
    local size = math.min(w/8,h/2)*p.scale
    local dx,dy = mx-x-p.x*w,my-y-p.y*h
    local c,s = math.cos(p.rotation),math.sin(p.rotation)
    if math.abs(dx*c+dy*s)<=size/2 and math.abs(-dx*s+dy*c)<=size/2 then return index end
  end
end
function Showcase.save(state,index,stage)
  if type(index)~="number" or index%1~=0 or index<1 or index>5 then return nil,"Choose one of five stages." end
  local valid,why=Showcase.validate(stage,state.nextId)
  if not valid then return nil,why end
  local nextState=Store.copy(state)
  nextState.stages=nextState.stages or {};nextState.stages[index]=Store.copy(stage)
  nextState.revision=state.revision+1
  return nextState
end
function Showcase.add(stage,refs,state)
  local draft=Store.copy(stage)
  for _,ref in ipairs(refs) do
    local entry=Store.at(state,ref.box,ref.slot)
    if not entry then return nil,"A selected Pokémon is missing." end
    if #draft.pieces>=1500 then return nil,"The stage has no more room." end
    local index=#draft.pieces
    draft.pieces[#draft.pieces+1]={entryId=entry.id,x=0.12+(index%8)*0.105,y=0.28+(math.floor(index/8)%3)*0.25,
      scale=1,rotation=0,flip=false}
  end
  return draft
end
function Showcase.resolve(state,stage)
  local out,entries={},{}
  for _,box in ipairs(state.boxes) do for _,entry in pairs(box.mons) do entries[entry.id]=entry end end
  for _,piece in ipairs(stage.pieces) do
    local entry=piece.entryId and entries[piece.entryId]
    out[#out+1]={piece=piece,entry=entry,missing=piece.entryId~=nil and entry==nil}
  end
  return out
end
local musicSource, musicTrack, musicOwner, musicVolume, musicFailed, musicHeld
local function audioSuspended()
  local chip=package.loaded["src.core.ChipAudio"]
  return chip and chip.isSuspended and chip.isSuspended() or false
end
local function startPending()
  if musicSource or not musicTrack or musicTrack=="Silent" then return true end
  if musicFailed then return nil,musicFailed end
  if audioSuspended() then return "pending" end
  local sound,why=require("src.box.ShowcaseMusic").request(musicTrack)
  if not sound then
    if why=="pending" then return "pending" end
    musicFailed="Choose a stage music track."
    return nil,musicFailed
  end
  local ok,source=pcall(love.audio.newSource,sound,"static")
  if not ok or not source then
    musicFailed="Audio is unavailable."
    return nil,musicFailed
  end
  musicSource,musicHeld=source,false
  if musicVolume==nil then musicVolume=require("src.core.SaveData").loadOptions().boxMusicVol end
  Showcase.setVolume(musicVolume)
  if not pcall(function() musicSource:setLooping(true);musicSource:play() end) then
    Showcase.stopMusic()
    return nil,"Audio is unavailable."
  end
  return true
end
function Showcase.stopMusic()
  if musicSource then
    pcall(musicSource.stop,musicSource)
    if musicSource.release then pcall(musicSource.release,musicSource) end
    musicSource=nil
  elseif musicTrack then
    local music=package.loaded["src.box.ShowcaseMusic"]
    if music then music.cancel(musicTrack) end
  end
  musicTrack,musicOwner,musicFailed,musicHeld=nil,nil,nil,nil
end
function Showcase.update()
  if musicSource then
    local held=audioSuspended()
    if held~=musicHeld then
      musicHeld=held
      if held then pcall(musicSource.pause,musicSource) else pcall(musicSource.play,musicSource) end
    end
  elseif musicTrack and not musicFailed then startPending() end
end
function Showcase.currentMusic()
  Showcase.update()
  return musicTrack, musicOwner, musicSource
end
function Showcase.ensureMusic(track, owner)
  if musicTrack==track and musicOwner~=owner and not musicSource then
    musicOwner=owner
  elseif musicTrack~=track or musicOwner~=owner then
    Showcase.stopMusic()
    if track~="Silent" and not (love and love.sound and love.sound.newSoundData and love.audio) then return nil,"Audio is unavailable." end
    musicTrack,musicOwner=track,owner
  end
  return startPending()
end
function Showcase.setVolume(level)
  musicVolume=math.max(0,math.min(7,tonumber(level) or 7))
  if musicSource then musicSource:setVolume(musicVolume/7) end
end
function Showcase.playMusic(stage) return Showcase.ensureMusic(stage.music,"editor") end
function Showcase.boxMusic(state, box)
  if not box or box.theme~="Showcase" then return "Silent" end
  if box.showcaseMusic then return box.showcaseMusic end
  local exported=tonumber(tostring(box.wallpaper):match("^box/showcase/%d*(%d)%.png$"))
  local stage=exported and state.stages and state.stages[exported]
  return stage and stage.music or "Silent"
end
function Showcase.draw(state,stage,x,y,w,h)
  if not (w>0 and h>0) then return end
  local color=COLORS[stage.background] or COLORS.Forest
  Theme.fillRounded(x,y,w,h,color,1,0)
  local g=love.graphics
  local sx,sy,sw,sh=g.getScissor()
  if sx then
    local xx,yy=math.max(x,sx),math.max(y,sy)
    g.setScissor(xx,yy,math.max(0,math.min(x+w,sx+sw)-xx),math.max(0,math.min(y+h,sy+sh)-yy))
  else g.setScissor(x,y,w,h) end
  local cell=w/20
  Theme.col({255,255,255},0.1)
  for row=0,math.ceil(h/cell)-1 do
    for col=0,19 do
      local xx,yy=x+col*cell,y+row*cell
      local pw,ph=math.min(cell,w-col*cell),math.min(cell,h-row*cell)
      if stage.pattern=="Checks" and (row+col)%2==0 then g.rectangle("fill",xx,yy,pw,ph)
      elseif stage.pattern=="Dots" then g.circle("fill",xx+pw/2,yy+ph/2,cell/8)
      elseif stage.pattern=="Stripes" and col%2==0 then g.rectangle("fill",xx,yy,pw/2,ph)
      elseif stage.pattern=="Crosses" then
        g.line(xx+cell/2,yy+cell*.3,xx+cell/2,yy+cell*.7)
        g.line(xx+cell*.3,yy+cell/2,xx+cell*.7,yy+cell/2)
      elseif stage.pattern=="Diamonds" then g.polygon("line",xx+pw/2,yy,xx+pw,yy+ph/2,xx+pw/2,yy+ph,xx,yy+ph/2)
      elseif stage.pattern=="Bricks" then
        g.line(xx,yy,xx+pw,yy)
        if (col+row)%2==0 then g.line(xx,yy,xx,yy+ph) end
      elseif stage.pattern=="Waves" then g.line(xx,yy+ph/2,xx+pw/2,yy+ph/3,xx+pw,yy+ph/2)
      elseif stage.pattern=="Stars" then g.circle("fill",xx+pw/2,yy+ph/2,cell/16);g.line(xx+pw/2,yy+ph/4,xx+pw/2,yy+3*ph/4)
      elseif stage.pattern=="Grid" then
        g.line(xx,yy,xx+pw,yy);g.line(xx,yy,xx,yy+ph)
      end
    end
  end
  for _,row in ipairs(Showcase.resolve(state,stage)) do
    local piece=row.piece
    local size=math.min(w/8,h/2)*piece.scale
    local cx,cy=x+piece.x*w,y+piece.y*h
    g.push();g.translate(cx,cy);g.rotate(piece.rotation);g.scale(piece.flip and -1 or 1,piece.flipY and -1 or 1)
    if row.entry then
      local art=Catalog.art(row.entry)
      Theme.col({0,0,0},0.25);g.ellipse("fill",0,size*0.37,size*0.33,size*0.06)
      if art then
        if not Sprites.drawFront(art,-size/2,-size/2,size) then Sprites.drawIcon(art,-size/2,-size/2,size) end
      else
        Theme.fillRounded(-size/5,-size/4,size*0.4,size*0.55,{255,255,255},0.5,8)
      end
    elseif row.missing then
      Theme.col({255,255,255},0.65);g.rectangle("line",-size/3,-size/3,size*2/3,size*2/3)
      g.line(-size/3,-size/3,size/3,size/3);g.line(size/3,-size/3,-size/3,size/3)
    else
      Theme.col({217,219,230},1)
      if Showcase.drawProp(piece.kind,-size/2,-size/2,size) then
      elseif piece.kind=="Platform" then g.rectangle("fill",-size/2,-size/10,size,size/5)
      elseif piece.kind=="Block" then g.rectangle("fill",-size/3,-size/3,size*2/3,size*2/3)
      elseif piece.kind=="Pillar" then g.rectangle("fill",-size/8,-size/2,size/4,size)
      elseif piece.kind=="Arch" then
        g.rectangle("fill",-size/2,-size/2,size,size/6)
        g.rectangle("fill",-size/2,-size/2,size/6,size);g.rectangle("fill",size/3,-size/2,size/6,size)
      else
        for step=1,4 do g.rectangle("fill",-size/2+(step-1)*size/4,size/2-step*size/4,size/4,step*size/4) end
      end
    end
    g.pop()
  end
  if sx then g.setScissor(sx,sy,sw,sh) else g.setScissor() end
end
local function digest(bytes)
  local hex
  if love and love.data and love.data.hash then
    local ok,raw=pcall(love.data.hash,"sha256",bytes)
    if ok and type(raw)=="string" then hex=raw:gsub(".",function(c) return string.format("%02x",c:byte()) end) end
  end
  if not hex then
    local bit=require("bit")
    local parts={}
    for seed=1,3 do
      local h=bit.bxor(2166136261,seed*16777619)
      for i=1,#bytes do
        h=bit.bxor(h,bytes:byte(i))
        h=bit.tobit(h*403+bit.lshift(h,24))
      end
      parts[seed]=bit.tohex(h)
    end
    hex=table.concat(parts)
  end
  local out={}
  for i=0,2 do out[#out+1]=string.format("%08d",tonumber(hex:sub(i*6+1,i*6+6),16)) end
  return table.concat(out)
end
function Showcase.export(state,index,fs)
  local stage=state.stages and state.stages[index]
  if not stage then return nil,"Save the stage before exporting." end
  if not love.graphics.newCanvas then return nil,"PNG export requires the running launcher." end
  local canvas=love.graphics.newCanvas(1136,432)
  love.graphics.push("all")
  local ok,err=pcall(function()
    love.graphics.setCanvas(canvas);love.graphics.origin();love.graphics.setScissor();love.graphics.clear(0,0,0,0)
    Showcase.draw(state,stage,0,0,1136,432)
  end)
  love.graphics.pop()
  if not ok then canvas:release();return nil,tostring(err) end
  local data=canvas:newImageData();canvas:release()
  local bytes=data:encode("png"):getString();data:release()
  local path="box/showcase/"..digest(bytes)..index..".png"
  if not fs.createDirectory("box/showcase") then return nil,"Could not create the showcase folder." end
  local written,why=fs.write(path,bytes)
  if not written or fs.read(path)~=bytes then return nil,why or "Could not verify the exported PNG." end
  Showcase.prune(state,fs,path)
  return path
end
function Showcase.prune(state,fs,keep)
  if not fs.getDirectoryItems or not fs.remove then return 0 end
  if fs.getInfo and fs.getInfo(require("src.box.Transaction").PATH) then return 0 end
  local used={[keep or ""]=true}
  local body=fs.read and fs.read(Store.PATH)
  local persisted=body and require("src.core.SaveSerializer").decode(body)
  for _,source in ipairs({state,type(persisted)=="table" and persisted or {}}) do
    for _,box in ipairs(type(source.boxes)=="table" and source.boxes or {}) do
      if type(box)=="table" and box.wallpaper then used[box.wallpaper]=true end
    end
  end
  local ok,items=pcall(fs.getDirectoryItems,"box/showcase")
  local removed=0
  for _,name in ipairs(ok and type(items)=="table" and items or {}) do
    local path="box/showcase/"..name
    if name:match("^%d+%.png$") and not used[path] and fs.remove(path) then
      require("src.box.Themes").forget(path)
      removed=removed+1
    end
  end
  return removed
end
return Showcase
