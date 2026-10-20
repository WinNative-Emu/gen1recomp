package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Version = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Profile = require("src.core.game3.profile")

local BODY = [[
local mod = ...
mod.content.music:register("MOD_SONG", { file = "mods/reg/song.ogg" })
mod.content.items:register("MOD_BALL", { id = "MOD_BALL", index = 500, name = "MOD BALL", price = 100, pocket = "POKE_BALLS" })
mod.content.balls:register("MOD_BALL", { multiplier = 25 })
]]

local sources = {}
local realAudio = love.audio
love.audio = {
  newSource = function(file)
    local src = { file = file, playing = false, plays = 0, stops = 0 }
    function src:setLooping() end
    function src:setVolume() end
    function src:setPitch() end
    function src:setFilter() end
    function src:stop() self.playing = false self.stops = self.stops + 1 end
    function src:play() self.playing = true self.plays = self.plays + 1 end
    function src:isPlaying() return self.playing end
    sources[#sources + 1] = src
    return src
  end,
}

Version.set("firered")
Versions.select("firered")
Profile.reset()
T.sdk.captureRuntime()
local files = {
  ["mods/reg/manifest.json"] = '{"id":"reg","name":"reg","version":"1.0.0","api":2,"games":["all"],"entry":"main.lua"}',
  ["mods/reg/main.lua"] = BODY,
}
local data = T.sdk.gen3Data()
local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 3, version = "firered", dev = true })
T.check(loader:load(data), "loads")

local Compat = require("src.mods.Gen3Compat")
local ModAudio = require("src.core.game3.mod_audio")
local Audio = require("src.core.game3.audio")
local Catching = require("src.core.game3.battle.catching")
local Schemas = require("src.mods.Schemas")

ModAudio.install(data)
Audio.playSong("MOD_SONG")
T.eq(ModAudio.playing(), "MOD_SONG", "mod song plays")
local source
for _, src in ipairs(sources) do if src.file == "mods/reg/song.ogg" then source = src end end
T.check(source and source.playing, "mod song source is looping")
ModAudio.install(data)
T.eq(ModAudio.playing(), nil, "a re-install clears the current song")
T.check(source and not source.playing, "a re-install stops the looping mod source")

Audio.playSong("MOD_SONG")
ModAudio.reset()
T.check(source and not source.playing, "reset stops the looping mod source")

Compat.applyMerged({ data = data, options = {} })
local ballNum = Schemas.gen3View.itemNum(data.gen3Items, "MOD_BALL")
T.check(ballNum and Catching.isBall(ballNum), "mod ball registered by applyMerged")
Compat.applyMerged(nil)
T.check(not Catching.isBall(ballNum), "applyMerged with no game unregisters the mod balls")

local palette = require("src.core.game3.palette_mods")
local realInstall, realAudioInstall = palette.install, ModAudio.install
local reached = false
ModAudio.install = function() error("audio exploded") end
palette.install = function() reached = true end
local ok, err = pcall(Compat.applyMerged, { data = data, options = {} })
ModAudio.install, palette.install = realAudioInstall, realInstall
T.check(ok, "a failing install step does not abort applyMerged: " .. tostring(err))
T.check(reached, "steps after a failing install still run")

love.audio = realAudio
ModAudio.reset()
T.sdk.restoreRuntime()
T.finish("gen3 applyMerged cleanup")
