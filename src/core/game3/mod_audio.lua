local Song = require("src.core.game3.song_ids")
local SE = require("src.core.game3.se_ids")

local ModAudio = {}

ModAudio.data = nil
ModAudio.songName = nil

local function populated(audio)
  if type(audio) ~= "table" then return false end
  for _, key in ipairs({ "songs", "sfx", "cries", "mapSongs" }) do
    if type(audio[key]) == "table" and next(audio[key]) ~= nil then return true end
  end
  return false
end

function ModAudio.install(data)
  ModAudio.stopSong()
  local audio = type(data) == "table" and data.audio or nil
  ModAudio.data = populated(audio) and { audio = audio } or nil
  ModAudio.songName = nil
  local pokemon = type(data) == "table" and data.gen3Pokemon or nil
  ModAudio.pokemon = type(pokemon) == "table" and pokemon or nil
end

function ModAudio.reset()
  ModAudio.stopSong()
  ModAudio.data = nil
  ModAudio.songName = nil
end

local function table_of(kind)
  local audio = ModAudio.data and ModAudio.data.audio
  return audio and audio[kind] or nil
end

local seNames
local function se_name(id)
  if not seNames then
    seNames = {}
    for key, value in pairs(SE) do
      if type(key) == "string" and type(value) == "number" and key:find("^SE_") then
        seNames[value] = key
      end
    end
  end
  return seNames[id]
end

local function name_of(kind, id)
  if type(id) == "string" then
    local text = id:gsub("^%s+", ""):gsub("%s+$", "")
    return text
  end
  if type(id) ~= "number" then return nil end
  if kind == "sfx" then return se_name(id) or Song.nameOf(id) end
  return Song.nameOf(id)
end

function ModAudio.songKey(id)
  local songs = table_of("songs")
  if not songs then return nil end
  local name = name_of("song", id)
  if name and songs[name] ~= nil then return name end
  return nil
end

function ModAudio.sfxKey(id)
  local sfx = table_of("sfx")
  if not sfx then return nil end
  local name = name_of("sfx", id)
  if name and sfx[name] ~= nil then return name end
  return nil
end

function ModAudio.cryKey(species)
  local cries = table_of("cries")
  if not cries then return nil end
  if type(species) == "string" and cries[species] ~= nil then return species end
  local number = tonumber(species)
  if not number then return nil end
  local names = ModAudio.pokemon and ModAudio.pokemon._names
  local raw = names and names[number]
  local name = raw and require("src.mods.Schemas").gen3View.idOf(raw)
  if name and cries[name] ~= nil then return name end
  return nil
end

function ModAudio.mapSong(mapId)
  local songs = table_of("mapSongs")
  if not songs or mapId == nil then return nil end
  return songs[mapId]
end

function ModAudio.playing()
  return ModAudio.songName
end

function ModAudio.playSong(id)
  local key = ModAudio.songKey(id)
  if not key then return false end
  local Music = require("src.core.Music")
  Music.play(ModAudio.data, key, true, { reason = "gen3" })
  ModAudio.songName = key
  return true
end

function ModAudio.stopSong()
  if not ModAudio.songName then return end
  ModAudio.songName = nil
  local Music = require("src.core.Music")
  Music.stop()
  Music.setVolumeLevel(ModAudio.userLevel or 7)
end

function ModAudio.fadeOut(speed)
  if not ModAudio.songName then return false end
  require("src.core.Music").fadeOut(math.max(1, math.floor((tonumber(speed) or 4) * 16 / 7)))
  return true
end

function ModAudio.playSe(id)
  local key = ModAudio.sfxKey(id)
  if not key then return nil end
  local src = require("src.core.Sound").play(ModAudio.data, key)
  return src or false
end

function ModAudio.playCry(species)
  local key = ModAudio.cryKey(species)
  if not key then return nil end
  local src = require("src.core.Sound").playCry(ModAudio.data, key, false)
  return src or false
end

function ModAudio.applyOptions(options)
  if type(options) ~= "table" or not ModAudio.data then return end
  ModAudio.userLevel = tonumber(options.musicVol) or 7
  require("src.core.Music").applyOptions(options)
  require("src.core.Sound").applyOptions(options)
end

function ModAudio.setFade(factor)
  if not ModAudio.songName then return end
  local level = (ModAudio.userLevel or 7) * math.max(0, math.min(1, factor))
  require("src.core.Music").setVolumeLevel(level)
end

function ModAudio.update()
  if not ModAudio.songName then return end
  local Music = require("src.core.Music")
  Music.update(ModAudio.data)
  if Music.current() == nil then ModAudio.songName = nil end
end

return ModAudio
