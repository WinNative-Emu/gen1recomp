package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Version = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Profile = require("src.core.game3.profile")

local BODY = [[
local mod = ...
mod.content.music:register("MOD_SONG", { file = "mods/reg/song.ogg" })
mod.content.sfx:register("MOD_CHIME", { file = "mods/reg/chime.ogg" })
mod.content.sfx:register("SE_PIN", { file = "mods/reg/pin.ogg" })
mod.content.cries:register("MEW", { file = "mods/reg/mew.ogg" })
mod.content.map_songs:register("FR_OAKS_LAB", "MOD_SONG")
mod.content.tokens:register("MODCLOCK", function(game) return "12:30" end)
mod.content.text:register("ModLine", "It is {MODCLOCK}.")
mod.content.icons:register("MEW", { image = "mods/reg/mewicon.png", frames = 2 })
mod.content.icons:register("CHARMANDER", "PIDGEY")
mod.content.sprites:register("MOD_NPC", { image = "mods/reg/npc.png", frames = 6, walker = true })
mod.content.items:register("MOD_BALL", { id = "MOD_BALL", index = 500, name = "MOD BALL", price = 100, pocket = "POKE_BALLS" })
mod.content.items:register("MOD_MASTER", { id = "MOD_MASTER", index = 501, name = "MOD MASTER", price = 100, pocket = "POKE_BALLS" })
mod.content.balls:register("MOD_BALL", { multiplier = 25 })
mod.content.balls:register("MOD_MASTER", { autoCatch = true })
mod.content.trainers:register("900", { name = "ACE", class = 200, className = "MODDER",
  pic = "mods/reg/ace.png", baseMoney = 7, party = { { species = "MEW", level = 10 }, { species = "MEW", level = 30 } } })
]]

local sources = {}
local realAudio = love.audio
love.audio = {
  newSource = function(file)
    local src = { file = file, playing = false, plays = 0 }
    function src:setLooping() end
    function src:setVolume() end
    function src:setPitch() end
    function src:setFilter() end
    function src:stop() self.playing = false end
    function src:play() self.playing = true self.plays = self.plays + 1 end
    function src:isPlaying() return self.playing end
    sources[#sources + 1] = src
    return src
  end,
}

local function played(file)
  for _, src in ipairs(sources) do
    if src.file == file and src.plays > 0 then return true end
  end
  return false
end

local versions = { "firered", "leafgreen", "ruby", "sapphire", "emerald" }
for _, version in ipairs(versions) do
  Version.set(version)
  Versions.select(version)
  Profile.reset()
  sources = {}
  local data = T.sdk.gen3Data()
  T.sdk.captureRuntime()
  local files = {
    ["mods/reg/manifest.json"] = '{"id":"reg","name":"reg","version":"1.0.0","api":2,"games":["all"],"entry":"main.lua"}',
    ["mods/reg/main.lua"] = BODY,
  }
  local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 3, version = version, dev = true })
  T.check(loader:load(data), version .. " loads with audio registries")
  T.same(loader.errors, {}, version .. " no unavailable reports")
  T.eq(data.audio.songs.MOD_SONG.file, "mods/reg/song.ogg", version .. " song merged")
  T.eq(data.audio.mapSongs.FR_OAKS_LAB, "MOD_SONG", version .. " map song merged")

  local ModAudio = require("src.core.game3.mod_audio")
  local Audio = require("src.core.game3.audio")
  ModAudio.install(data)
  Audio.playSong("MOD_SONG")
  T.check(played("mods/reg/song.ogg"), version .. " Audio.playSong plays the mod song")
  T.eq(ModAudio.playing(), "MOD_SONG", version .. " mod song is current")
  Audio.playSong(0)
  T.eq(ModAudio.playing(), nil, version .. " stop silences the mod song")

  Audio.playSe("MOD_CHIME")
  T.check(played("mods/reg/chime.ogg"), version .. " Audio.playSe plays the mod sfx")
  Audio.playSe("SE_PIN")
  T.check(played("mods/reg/pin.ogg"), version .. " a mod overrides a native SE by name")
  Audio.playSe(require("src.core.game3.se_ids").SE_PIN)
  local pins = 0
  for _, src in ipairs(sources) do if src.file == "mods/reg/pin.ogg" then pins = pins + src.plays end end
  T.check(pins >= 2, version .. " numeric native SE id reaches the override")

  Audio.playCry(151)
  T.check(played("mods/reg/mew.ogg"), version .. " Audio.playCry plays the mod cry")
  T.check(not Audio.isCryFinished(), version .. " cry waits on the mod source")

  local Trainers = require("src.core.game3.scripting.trainers")
  local Prize = require("src.core.game3.battle.prize")
  local TrainerPic = require("src.core.game3.trainer_pic")
  local Compat = require("src.mods.Gen3Compat")
  local savedPack, savedSprite = Trainers._pack, Compat.centredSprite
  Trainers._pack = data.gen3Trainers
  local info = Trainers.info(900)
  T.eq(info.className, "MODDER", version .. " mod trainer class name reaches battle info")
  T.eq(info.class, 200, version .. " mod trainer class id")
  T.eq(info.pic, "mods/reg/ace.png", version .. " mod trainer pic path survives")
  T.eq(info.lastLevel, 30, version .. " last level comes from the party")
  T.eq(Prize.calc(900), 4 * 30 * 7, version .. " prize money uses the mod class money")
  local asked
  Compat.centredSprite = function(path) asked = path return { image = {}, w = 64, h = 64 } end
  T.check(TrainerPic.front(info.pic) ~= nil and asked == "mods/reg/ace.png", version .. " trainer pic loads the mod image")
  Compat.centredSprite, Trainers._pack = savedSprite, savedPack

  local TextIR = require("src.core.game3.scripting.text_ir")
  Compat.applyMerged({ data = data, options = {} })
  local out = {}
  for _, seg in ipairs(data.gen3Text.ModLine) do out[#out + 1] = TextIR.expandSeg(seg, {}) or "" end
  T.eq(table.concat(out), "It is 12:30.", version .. " mod token expands in Gen 3 text")
  TextIR.modTokens, TextIR.modGame = nil, nil

  T.eq(data.sprites.MOD_NPC.image, "mods/reg/npc.png", version .. " sprites registry reaches data.sprites for the field renderer")
  local Catching = require("src.core.game3.battle.catching")
  local Schemas = require("src.mods.Schemas")
  Compat.applyMerged({ data = data, options = {} })
  local ballNum = Schemas.gen3View.itemNum(data.gen3Items, "MOD_BALL")
  local masterNum = Schemas.gen3View.itemNum(data.gen3Items, "MOD_MASTER")
  T.check(ballNum and Catching.isBall(ballNum), version .. " a mod ball is a ball")
  T.eq(Catching.ballMultiplier(ballNum, nil, nil, nil), 25, version .. " mod ball multiplier reaches the catch roll")
  T.eq(Catching.ballMultiplier(masterNum, nil, nil, nil), 255, version .. " mod autoCatch ball never fails")
  T.eq(Catching.tryCatch(masterNum, { mon = { hp = 10, maxHp = 100, level = 5 }, species = 16 }, {}, {}), true, version .. " autoCatch ball catches")
  Catching.installBalls({}, function() end)
  T.check(not Catching.isBall(ballNum), version .. " the mod ball is gone without the registry")
  local fake = { icon = function(sp) return { vanilla = sp } end,
    monIcon = function() return nil end, monPicSpecies = function(mon) return mon.species end }
  local savedPokemon = package.loaded["src.core.game3.pokemon"]
  package.loaded["src.core.game3.pokemon"] = fake
  local savedName, savedId = Compat.speciesName, Compat.speciesId
  local nameOf = { [151] = "MEW", [4] = "CHARMANDER", [16] = "PIDGEY" }
  local idOf = { MEW = 151, CHARMANDER = 4, PIDGEY = 16 }
  Compat.speciesName = function(sp) return nameOf[sp] end
  Compat.speciesId = function(ref) return idOf[ref] end
  Compat.applyMerged({ data = data, options = {} })
  local mewIcon = fake.icon(151)
  T.check(mewIcon and mewIcon.path == "mods/reg/mewicon.png", version .. " icons registry image reaches the party icon")
  T.same(fake.icon(4), { vanilla = 16 }, version .. " icons registry species string borrows that species icon")
  T.same(fake.icon(16), { vanilla = 16 }, version .. " unmodded species keep the native icon")
  package.loaded["src.core.game3.pokemon"] = savedPokemon
  Compat.speciesName, Compat.speciesId = savedName, savedId

  ModAudio.reset()
  T.sdk.restoreRuntime()
end

love.audio = realAudio
T.finish("unified registries gen3")
