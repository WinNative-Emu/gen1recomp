package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local check, eq = T.check, T.eq
love = require("tests.love_stub")
local Version = require("src.core.GameVersion")
local Audio = require("src.core.game3.audio")
local Song = require("src.core.game3.song_ids")
local M4a = require("src.core.game3.m4a_player")
local Player = require("src.core.game3.player")

local function channel()
  local ch = { items = {} }
  function ch:push(v) self.items[#self.items + 1] = v end
  function ch:pop() return table.remove(self.items, 1) end
  function ch:clear() self.items = {} end
  return ch
end

local function source()
  local src = { playing = true, volume = 1, queued = {}, stops = 0 }
  function src:stop() self.playing = false; self.stops = self.stops + 1; self.queued = {} end
  function src:play() self.playing = true end
  function src:isPlaying() return self.playing end
  function src:setVolume(v) self.volume = v end
  function src:getFreeBufferCount() return M4a.BUFFER_COUNT end
  function src:queue(data) self.queued[#self.queued + 1] = data; return true end
  return src
end

local function setup(version, first)
  Version.set(version)
  Audio._ready, Audio._worker = true, true
  Audio._pack = { index = { songs = {} } }
  Audio._meta, Audio._fanfareCh, Audio._statusCh = nil, nil, nil
  Audio._cmdCh, Audio._outCh = channel(), channel()
  Audio._bgmSource, Audio._fanfareSource = source(), source()
  Audio._currentSong, Audio._bgmGen = { id = first }, first
  Audio._bgmEpoch, Audio._bgmQueuedAt, Audio._bgmBaseAt = 3, {}, 0
  Audio._bgmLocal, Audio._pendingBgm, Audio._bgmPaused = nil, nil, false
  Audio._fadeOut, Audio._fadeIn = nil, nil
  Audio._fanfareActive, Audio._fanfareFrames = false, 0
  Audio._fanfareRestore, Audio._fanfareDeferred, Audio._fanfarePending = nil, nil, nil
  Audio._waitFanfareCb, Audio._suspended = nil, false
  Audio._mapSong, Audio._savedSong = first, nil
  Player.surfing, Player.surfHopping, Player.dismounting, Player.biking = false, false, false, false
end

for _, version in ipairs({ "firered", "leafgreen" }) do
  local S = Song.forVersion(version)
  local route, nextRoute = S.MUS_ROUTE1, S.MUS_ROUTE3
  assert(type(route) == "number" and type(nextRoute) == "number" and route ~= nextRoute)
  eq(Audio.MUS_CYCLING, S.MUS_CYCLING, version .. " MUS_CYCLING resolves")

  setup(version, route)
  Player.biking = true
  -- pokefirered/src/bike.c:328
  Audio.bikeMusic(true)
  eq(Audio._savedSong, S.MUS_CYCLING, version .. " mounting saves MUS_CYCLING")
  eq(Audio.currentMapMusic(), S.MUS_CYCLING, version .. " mounting changes to MUS_CYCLING")
  -- pokefirered/src/overworld.c:1039
  eq(Audio.specialMapSong(), S.MUS_CYCLING, version .. " battle on the mount map keeps MUS_CYCLING")

  -- pokefirered/src/overworld.c:769
  Audio.setSavedSong(nil)
  Audio.playMapSong(nextRoute, { mapSong = nextRoute })
  eq(Audio.currentMapMusic(), nextRoute, version .. " connection plays the new route music")
  check(Player.biking, version .. " still on the bike after the connection")
  eq(Audio.specialMapSong(), nextRoute, version .. " battle after a connection picks route music, not MUS_CYCLING")
  Audio._currentSong, Audio._fadeOut = { id = S.MUS_VS_WILD or 0 }, nil
  Audio.restoreMapSong()
  eq(Audio.currentMapMusic(), nextRoute, version .. " CB2_ReturnToField restores route music")

  setup(version, route)
  Player.biking = true
  -- pokefirered/src/bike.c:319
  Player.biking = false
  Audio.bikeMusic(false)
  eq(Audio.specialMapSong(), route, version .. " dismount returns to map music")

  setup(version, route)
  Player.biking, Player.surfing = true, true
  eq(Audio.specialMapSong(), S.MUS_SURF, version .. " surf still overrides map music without saved music")
end

T.finish()
