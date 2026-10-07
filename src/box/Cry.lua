local CacheFs = require("src.import.CacheFs")
local Catalog = require("src.box.Catalog")
local GameVersion = require("src.core.GameVersion")
local Cry = {}
local packs, sources, sourceCount, playing = {}, {}, 0, nil
local suspended = false
local MAX_SOURCES = 24
local MAX_PACKS = 2
local packOrder = {}

local function read(version, path)
  return CacheFs.readAt(GameVersion.cachePrefix(version) .. path)
end

local function readTable(version, path)
  local body = read(version, path)
  if not body then return nil end
  local chunk = (loadstring or load)(body, "@box-cry/" .. version .. "/" .. path)
  if not chunk then return nil end
  if setfenv then setfenv(chunk, {}) end
  local ok, value = pcall(chunk)
  return ok and type(value) == "table" and value or nil
end

function Cry.stop()
  if playing then pcall(playing.stop, playing) end
  playing = nil
end

local function clearSources()
  Cry.stop()
  for _, source in pairs(sources) do
    pcall(source.stop, source)
    if source.release then pcall(source.release, source) end
  end
  sources, sourceCount = {}, 0
end

function Cry.reset()
  clearSources()
  packs, packOrder = {}, {}
end

function Cry.setSuspended(value)
  suspended = value == true
  Cry.reset()
end

local function pack(version)
  if packs[version] ~= nil then return packs[version] or nil end
  local result
  if GameVersion.generation(version) == 3 then
    local root = "data/generated/gba/audio/"
    local index = readTable(version, root .. "index.lua")
    local bytes = index and read(version, root .. "samples.bin")
    if index and bytes then
      result = { index = index, bytes = bytes,
        samples = index.samples or readTable(version, root .. "samples.lua") or {} }
    end
  else
    local audio = readTable(version, "data/generated/audio.lua")
    local bytes = audio and audio.programFile and read(version, audio.programFile)
    if audio and bytes then
      audio.programBytes = bytes
      result = { audio = audio }
    end
  end
  packs[version] = result or false
  packOrder[#packOrder + 1] = version
  while #packOrder > MAX_PACKS do packs[table.remove(packOrder, 1)] = nil end
  return result
end

local function voicedPikachu(version, data, species)
  if species ~= "PIKACHU" or not data.audio.pikaCries then return nil end
  local bytes = read(version, "assets/generated/audio/pika_cries/cry_01.wav")
  if not bytes then return nil end
  local file = love.filesystem.newFileData(bytes, "box-pikachu.wav")
  local sound = love.sound.newSoundData(file)
  file:release()
  if sound:getChannelCount() == 1 then
    local stereo = love.sound.newSoundData(sound:getSampleCount(), sound:getSampleRate(), 16, 2)
    for i = 0, sound:getSampleCount() - 1 do
      local value = sound:getSample(i)
      stereo:setSample(i, 1, value); stereo:setSample(i, 2, value)
    end
    sound:release(); sound = stereo
  end
  local source = love.audio.newSource(sound, "static")
  sound:release()
  return source
end

local function render(version, species)
  local data = pack(version)
  if not data then return nil end
  if GameVersion.generation(version) < 3 then
    local voiced, source = pcall(voicedPikachu, version, data, species)
    if voiced and source then return source end
    return require("src.core.ChipAudio").newCry(data, species)
  end
  local index = data.index
  local id = (index.cryIds or {})[species] or (index.cryIds or {})[tostring(species)]
  local row = id ~= nil and ((index.cries or {})[id] or (index.cries or {})[tostring(id)])
  local sample = row and (data.samples[row.sampleId] or data.samples[tostring(row.sampleId)])
  if not sample then return nil end
  local Sample = require("src.core.game3.m4a_sample")
  local pcm = Sample.loadPcm(data.bytes, sample)
  if not pcm then return nil end
  local config = require("src.core.game3.profile").of(version).audio or {}
  local params = Sample.cryParams(0, config.cryDefaultVolume, config.cryModeOverrides)
  local sound = Sample.renderCry(pcm, Sample.waveRate(sample.freq), params,
    { pan = 0, outRate = require("src.core.game3.m4a_mix").SAMPLE_RATE })
  if not sound then return nil end
  local source = love.audio.newSource(sound, "static")
  sound:release()
  return source
end

function Cry.play(entry)
  Cry.stop()
  if suspended or not entry or not entry.mon or entry.mon.isEgg or entry.display and entry.display.egg
      or not (love and love.audio and love.audio.newSource and love.sound and love.sound.newSoundData) then return nil end
  local chip = package.loaded["src.core.ChipAudio"]
  if chip and chip.isSuspended() then return nil end
  local options = require("src.core.SaveData").loadOptions()
  local volume = math.max(0, math.min(7, tonumber(options.boxCryVol) or 7)) / 7
  if volume == 0 then return nil end
  local order = { entry.version }
  for i = #GameVersion.ORDER, 1, -1 do
    local version = GameVersion.ORDER[i]
    if version ~= entry.version then order[#order + 1] = version end
  end
  for _, version in ipairs(order) do
    local data = Catalog.get(version)
    local national = entry.display and entry.display.national
    local species = version == entry.version and entry.mon.species
      or data.generation == 3 and (data.national.toSpecies or {})[national]
      or data.byNational and data.byNational[national]
    if data.ready and species then
      local key = version .. ":" .. tostring(species)
      local source = sources[key]
      if not source then
        local ok, result = pcall(render, version, species)
        if ok and result then
          if sourceCount >= MAX_SOURCES then clearSources() end
          source, sources[key], sourceCount = result, result, sourceCount + 1
        end
      end
      if source then
        local gain = volume
        if version == "yellow" and species == "PIKACHU" then
          gain = gain * math.max(0, math.min(7, tonumber(options.pikaVol) or 7)) / 7
        end
        local ok = pcall(function() source:setVolume(gain); source:play() end)
        if ok then playing = source; return source, version end
      end
    end
  end
end

require("src.render.Assets").register({ invalidate = Cry.reset, release = Cry.reset })
return Cry
