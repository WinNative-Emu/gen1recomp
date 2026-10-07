package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")
local Serializer = require("src.core.SaveSerializer")
local CacheFs = require("src.import.CacheFs")
local Catalog = require("src.box.Catalog")
local GameVersion = require("src.core.GameVersion")
local SaveData = require("src.core.SaveData")
local bodies, made, renders, volume, suspended = {}, {}, 0, 7, false
local oldRead, oldOptions = CacheFs.readAt, SaveData.loadOptions
CacheFs.readAt = function(path) return bodies[path] end
SaveData.loadOptions = function() return { boxCryVol = volume, pikaVol = 3 } end
local function put(version, path, value)
  bodies[version .. "/" .. path] = type(value) == "table" and Serializer.encode(value) or value
end
local function source(sound)
  local s = { sound = sound, plays = 0, stops = 0 }
  function s:setVolume(value) self.volume = value end
  function s:play() self.plays = self.plays + 1; self.playing = true end
  function s:stop() self.stops = self.stops + 1; self.playing = false end
  function s:release() self.released = true end
  made[#made + 1] = s
  return s
end
love.audio = { newSource = function(sound) renders = renders + 1; return source(sound) end }
love.sound = { newSoundData = function(count, rate, bits, channels)
  local data = { count = count, rate = rate, bits = bits, channels = channels, peak = 0 }
  function data:setSample(_, channel, value) self.peak = math.max(self.peak, math.abs(value or channel)) end
  function data:release() self.released = true end
  return data
end }
local chip = require("src.core.ChipAudio")
local oldChip, oldSuspended = chip.newCry, chip.isSuspended
chip.isSuspended = function() return suspended end
chip.newCry = function(data, species)
  T.eq(data.audio.programBytes, "gold-ROM-programs", "chip cry carries its own version's programs")
  T.eq(species, "PIKACHU", "old-generation cry uses canonical species key")
  return source({ chip = true })
end
put("gold", "data/generated/pokemon.lua", { PIKACHU = { name = "PIKACHU", dex = 25 } })
put("gold", "data/generated/audio.lua", { generation = 2, programFile = "assets/generated/audio/programs.bin",
  cries = { PIKACHU = { header = {}, pitch = 0, length = 0 } } })
put("gold", "assets/generated/audio/programs.bin", "gold-ROM-programs")
for _, version in ipairs({ "ruby", "emerald" }) do
  put(version, "data/generated/gba/pokemon/names.lua", { [25] = "PIKACHU", [1] = "BULBASAUR" })
  put(version, "data/generated/gba/pokemon/national.lua", { toNational = { [25] = 25, [1] = 1 }, toSpecies = { [25] = 25, [1] = 1 } })
  put(version, "data/generated/gba/audio/index.lua", { cryIds = { [25] = 0, [1] = 1 },
    cries = { [0] = { sampleId = 9 }, [1] = { sampleId = 9 } },
    samples = { [9] = { offset = 0, size = 32, freq = 13379 * 1024 } } })
  put(version, "data/generated/gba/audio/samples.bin", string.rep(string.char(35, 90, 200, 220), 8))
end
local Cry = require("src.box.Cry")
local function entry(version, species)
  return { version = version, generation = GameVersion.generation(version), mon = { species = species }, display = { national = 25 } }
end
Catalog.reset()
local a, version = Cry.play(entry("gold", "PIKACHU"))
T.check(a ~= nil, "Gen 2 cry starts")
T.eq(version, "gold", "source-game cry wins over newer imported audio")
T.eq(a.plays, 1, "selection plays once")
local count = #made
local repeated = Cry.play(entry("gold", "PIKACHU"))
T.eq(repeated, a, "repeat selection reuses synthesized source")
T.eq(#made, count, "cached cry does not allocate a source again")
T.eq(a.plays, 2, "explicit repeat restarts the cry")
local b = Cry.play(entry("emerald", 25))
T.eq(a.playing, false, "new popup stops the preceding cry")
T.check(b ~= nil and b.playing, "Gen 3 cry plays from imported PCM")
T.eq(b.sound.channels, 2, "Gen 3 cry uses centered stereo")
T.check(b.sound.peak > 0, "actual cry renderer produces non-silent samples")
T.eq(b.volume, 1, "default Showcase Cry volume is applied")
volume = 2
T.eq(Cry.play(entry("emerald", 25)), b, "volume change keeps reusable source")
T.eq(b.volume, 2 / 7, "Showcase Cry setting updates next playback")
volume = 0
T.eq(Cry.play(entry("ruby", 25)), nil, "Showcase Cry mute prevents cry playback")
T.eq(b.playing, false, "muted selection also stops prior audio")
volume = 7
local egg = entry("emerald", 25); egg.mon.isEgg = true
local played = b.plays
T.eq(Cry.play(egg), nil, "egg does not reveal its species by crying")
T.eq(b.plays, played, "egg selection never starts cached species cry")
suspended = true
T.eq(Cry.play(entry("emerald", 25)), nil, "suspended device stays silent")
suspended = false
T.eq(GameVersion.get(), "red", "playback leaves active game unchanged")
T.eq(CacheFs.prefix, "", "playback leaves importer cache prefix unchanged")
local before = Serializer.encode(egg)
Cry.play(egg)
T.eq(Serializer.encode(egg), before, "cry lookup leaves stored Pokémon unchanged")

bodies["gold/data/generated/audio.lua"] = nil
Catalog.reset()
local fallback, fallbackVersion = Cry.play(entry("gold", "PIKACHU"))
T.check(fallback ~= nil, "missing source audio uses an imported fallback")
T.eq(fallbackVersion, "emerald", "fallback maps national species into the newest available game")
local unknown = entry("emerald", 999); unknown.display.national = nil
T.eq(Cry.play(unknown), nil, "unknown species is safely silent")
local oldAudio = love.audio
love.audio = nil
T.eq(Cry.play(entry("emerald", 25)), nil, "headless/audio-unavailable selection is safe")
love.audio = oldAudio
Cry.play(entry("emerald", 25))
Cry.stop()
T.eq(fallback.playing, false, "leaving Box stops playback")
Catalog.reset()
T.check(fallback.released, "cache refresh releases old audio sources")

local active = Cry.play(entry("emerald", 25))
Cry.setSuspended(true)
T.check(active.released, "device suspension releases cached sources")
package.loaded["src.core.ChipAudio"] = nil
T.eq(Cry.play(entry("emerald", 25)), nil, "Gen 3 suspension works without a loaded chip engine")
Cry.reset()
T.eq(Cry.play(entry("emerald", 25)), nil, "cache refresh cannot lift the device suspension gate")
Cry.setSuspended(false)
local resumed = Cry.play(entry("emerald", 25))
T.check(resumed and resumed.playing, "device reset allows new playback")
T.check(resumed ~= active, "device reset creates a fresh source")
package.loaded["src.core.ChipAudio"] = chip

local synth = require("src.core.ChipSynth")
local banks = synth._loadBanksForTest({ audio = { programFile = "wrong-active-game.bin",
  bankOrder = { 2 }, programBytes = string.rep("G", 0x4000) } })
T.eq(banks[2], string.rep("G", 0x4000), "chip synth uses supplied ROM bytes, independent of mount")

local oldProfile = require("src.core.game3.profile").of("ruby").audio
T.eq(oldProfile.cryDefaultVolume, 125, "Ruby normal cry uses its own profile parameters")
T.check(renders >= 1, "real Gen 3 renderer was exercised")
chip.newCry, chip.isSuspended = oldChip, oldSuspended
CacheFs.readAt, SaveData.loadOptions = oldRead, oldOptions
Cry.reset()
T.finish()
