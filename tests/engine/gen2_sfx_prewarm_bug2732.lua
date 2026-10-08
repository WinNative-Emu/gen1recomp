-- engine/battle_anims/anim_commands.asm:1191
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 sfx prewarm 2732")
local check, eq = S.check, S.eq

love = require("tests.love_stub")
local ffi = require("ffi")

local cache = os.getenv("CRYSTAL_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/crystal-dev/crystal"
end
local gen = cache .. "/data/generated/"
local audioFile = io.open(gen .. "audio.lua", "r")
local animFile = io.open(gen .. "battle_anims.lua", "r")
local progFile = io.open(cache .. "/assets/generated/audio/programs.bin", "rb")
if not (audioFile and animFile and progFile) then
  for _, f in ipairs({ audioFile or false, animFile or false, progFile or false }) do
    if f then f:close() end
  end
  print("[skip] no crystal cache at " .. cache)
  os.exit(0)
end
audioFile:close()
animFile:close()
local progBytes = progFile:read("*a")
progFile:close()

local audio = assert(loadfile(gen .. "audio.lua"))()
local anims = assert(loadfile(gen .. "battle_anims.lua"))()
local constants = loadfile(gen .. "constants.lua")
constants = constants and constants() or nil
if audio.runtime ~= true or not audio.sfx or not audio.sfx.Sfx_Item then
  print("[skip] crystal cache has no runtime audio")
  os.exit(0)
end
love.filesystem.write(audio.programFile, progBytes)

local SoundData = {}
SoundData.__index = SoundData
function SoundData:setSample(index, a, b)
  if b == nil then
    self.buf[index * self.channels] = a * 32767
  else
    self.buf[index * self.channels + (a - 1)] = b * 32767
  end
end
function SoundData:getSample(index, channel)
  return self.buf[index * self.channels + ((channel or 1) - 1)] / 32767
end
function SoundData:getFFIPointer() return self.buf end
function SoundData:getSampleCount() return self.samples end
function SoundData:getSampleRate() return self.rate end
function SoundData:getBitDepth() return 16 end
function SoundData:getChannelCount() return self.channels end
love.sound.newSoundData = function(samples, rate, _, channels)
  return setmetatable({ samples = samples, rate = rate, channels = channels,
    buf = ffi.new("int16_t[?]", samples * channels) }, SoundData)
end

local Source = {}
Source.__index = Source
function Source:play() self.plays = (self.plays or 0) + 1 end
function Source:stop() self.playing = false end
function Source:isPlaying() return self.playing == true end
function Source:setVolume() end
function Source:setPitch(p) self.pitch = p end
function Source:getPitch() return self.pitch or 1 end
function Source:getDuration() return self.sd.samples / self.sd.rate end
function Source:tell() return 0 end
love.audio = {
  newSource = function(sd) return setmetatable({ sd = sd }, Source) end,
}
love.timer.getTime = os.clock

local channels = {}
local function channel(name)
  local ch = channels[name]
  if ch then return ch end
  local items = {}
  ch = {}
  function ch:push(v) items[#items + 1] = v end
  function ch:pop() return table.remove(items, 1) end
  function ch:clear() for i = #items, 1, -1 do items[i] = nil end end
  function ch:getCount() return #items end
  channels[name] = ch
  return ch
end
love.thread = {
  newThread = function()
    return { start = function() end, getError = function() return nil end }
  end,
  getChannel = channel,
}

local ChipSynth = require("src.core.ChipSynth")
local ChipAudio = require("src.core.ChipAudio")
local Sound = require("src.core.Sound")
local UI = require("src.ui.gen2.BattleState")

local inWorker = false
local mainRenders = 0
local realRender = ChipSynth.renderEffectData
ChipSynth.renderEffectData = function(...)
  if not inWorker then mainRenders = mainRenders + 1 end
  return realRender(...)
end

local function workerStep()
  local cmdCh, fxCh = channel("chipaudio_cmd"), channel("chipaudio_fx")
  local did = false
  inWorker = true
  while true do
    local req = cmdCh:pop()
    if not req then break end
    if req.cmd == "effect" then
      did = true
      local sd = ChipSynth.renderEffectData({ audio = req.audio }, req.header,
        req.options or {})
      fxCh:push({ key = req.key, epoch = req.epoch, sd = sd })
    end
  end
  inWorker = false
  return did
end

local function pump()
  if ChipAudio.pumpEffects then ChipAudio.pumpEffects() end
  ChipAudio.update()
end

local function drain()
  for _ = 1, 400 do
    pump()
    if not workerStep() then
      pump()
      local st = ChipAudio._effectStateForTest()
      if (st.queued or 0) == 0 and (st.inFlight or 0) == 0 then return end
    end
  end
end

local function resetStats()
  mainRenders = 0
  if ChipAudio.resetSyncStats then ChipAudio.resetSyncStats() end
end

local data = { audio = audio, gen2BattleAnims = anims,
  gen2Constants = constants }

if jit and jit.off then jit.off() end
local before = os.clock()
realRender(data, audio.sfx.Sfx_Item, { frequencyOffset = 0, frameTicks = 0x100 })
local syncMs = (os.clock() - before) * 1000
check(Sound.prewarmSfx(data, "Sfx_Item"), "Sfx_Item prewarm queued")
drain()
resetStats()
before = os.clock()
check(Sound.play(data, "Sfx_Item") ~= nil, "Sfx_Item plays")
local warmMs = (os.clock() - before) * 1000
print(("Sfx_Item first play, jit off: sync render %.1f ms, prewarmed %.1f ms")
  :format(syncMs, warmMs))
eq(mainRenders, 0, "prewarmed Sfx_Item: no main-thread render")

local enemy = { species = "RATTATA", moves = {
  { id = "TACKLE" }, { id = "TAIL_WHIP" }, { id = "BITE" } } }
local player = { species = "CYNDAQUIL", moves = {
  { id = "EMBER" }, { id = "SMOKESCREEN" }, { id = "QUICK_ATTACK" },
  { id = "LEER" } } }
local battle = { wild = true, enemy = enemy, player = player,
  party = { player }, enemyParty = { enemy } }

local s = UI.new({ data = data, options = {}, save = {} }, { battle = battle })
drain()
resetStats()

local played = {}
local realStereo = Sound.playStereo
Sound.playStereo = function(d, name)
  played[#played + 1] = name
  return realStereo(d, name)
end
for _, turn in ipairs({ { player, "player" }, { enemy, "enemy" } }) do
  for _, move in ipairs(turn[1].moves) do
    if s:animForMove(move.id, turn[2]) then
      for _ = 1, 2000 do
        if not s.anim:step() then break end
      end
    end
    s:playHitSound(10)
  end
end
Sound.playStereo = realStereo

check(#played >= 5, "the turn's anims played their sounds (" .. #played .. ")")
eq(mainRenders, 0, "zero main-thread ChipSynth renders during the turn")
local stats = ChipAudio.stats()
eq(stats.syncRenders, 0, "zero main-thread sfx renders during the turn"
  .. (stats.syncRenderLast and (" (last " .. stats.syncRenderLast .. ")") or ""))
check((stats.prewarmHits or 0) > 0, "plays took prewarmed PCM")
check(stats.line and stats.line:find("sync=0/", 1, true) ~= nil,
  "stats.line carries the sync counters")

resetStats()
check(Sound.play(data, "Sfx_GetTm") ~= nil, "cold Sfx_GetTm plays")
eq(ChipAudio.stats().syncRenders, 1, "a cold play is counted as a sync render")
check((ChipAudio.stats().syncRenderMsMax or 0) > 0, "its render time is recorded")

local Game2 = require("src.core.Game2")
Game2.prewarmSessionSfx({ data = data })
drain()
local function mon(species, moves)
  local m = { species = species, moves = {} }
  for _, id in ipairs(moves) do m.moves[#m.moves + 1] = { id = id } end
  return m
end
local party = {
  mon("TYPHLOSION", { "FLAMETHROWER", "THUNDERPUNCH", "EARTHQUAKE", "SWIFT" }),
  mon("FERALIGATR", { "SURF", "ICE_PUNCH", "CRUNCH", "SLASH" }),
  mon("MEGANIUM", { "RAZOR_LEAF", "BODY_SLAM", "SYNTHESIS", "REFLECT" }),
  mon("AMPHAROS", { "THUNDER", "FIRE_PUNCH", "THUNDER_WAVE", "LIGHT_SCREEN" }),
  mon("PIDGEOT", { "FLY", "WING_ATTACK", "MIRROR_MOVE", "QUICK_ATTACK" }),
  mon("GYARADOS", { "HYDRO_PUMP", "HYPER_BEAM", "DRAGON_RAGE", "BITE" }),
}
local enemyParty = {
  mon("ALAKAZAM", { "PSYCHIC", "RECOVER", "REFLECT", "FUTURE_SIGHT" }),
  mon("EXEGGUTOR", { "SOLARBEAM", "PSYCHIC", "SLEEP_POWDER", "EXPLOSION" }),
  mon("SLOWBRO", { "SURF", "AMNESIA", "PSYCHIC", "CURSE" }),
  mon("JYNX", { "ICE_BEAM", "LOVELY_KISS", "PSYCHIC", "DREAM_EATER" }),
  mon("MR__MIME", { "BARRIER", "PSYBEAM", "SUBSTITUTE", "ENCORE" }),
  mon("XATU", { "PSYCHIC", "FLY", "CONFUSE_RAY", "NIGHT_SHADE" }),
}
local trainer = { player = party[1], enemy = enemyParty[1],
  party = party, enemyParty = enemyParty }
local names = UI.battleSfxNames(data, anims, trainer)
check(#names + #Game2.SESSION_SFX > 64, "6v6 list plus session set exceeds the cap ("
  .. #names .. " + " .. #Game2.SESSION_SFX .. ")")
for _, name in ipairs(names) do Sound.prewarmSfx(data, name) end
drain()
for _, name in ipairs({ "Sfx_KeyItem", "Sfx_ReadText2", "Sfx_Menu", "Sfx_Save" }) do
  resetStats()
  check(Sound.play(data, name) ~= nil, name .. " plays")
  eq(mainRenders, 0, name .. " stays prewarmed after a 6v6 battle prewarm")
end

S.finish()
