package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen1 prewarm pump 2998")
local check, eq = S.check, S.eq

love = require("tests.love_stub")
local ffi = require("ffi")

local SoundData = {}
SoundData.__index = SoundData
function SoundData:setSample(index, a, b)
  if b == nil then
    self.buf[index * self.channels] = a * 32767
  else
    self.buf[index * self.channels + (a - 1)] = b * 32767
  end
end
function SoundData:getFFIPointer() return self.buf end
function SoundData:getSampleCount() return self.samples end
function SoundData:getSampleRate() return self.rate end
function SoundData:getChannelCount() return self.channels end
love.sound.newSoundData = function(samples, rate, _, channels)
  return setmetatable({ samples = samples, rate = rate, channels = channels,
    buf = ffi.new("int16_t[?]", samples * channels) }, SoundData)
end
love.audio = { newSource = function(sd) return { sd = sd } end }

local channels = {}
local function channel(name)
  local ch = channels[name]
  if ch then return ch end
  local items = {}
  ch = { items = items }
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
local ChipAsm = require("src.audio.ChipAsm")
local ChipAudio = require("src.core.ChipAudio")
local FixedStep = require("src.core.FixedStep")
local Music = require("src.core.Music")
local Game = require("src.core.Game")
local StateStack = require("src.core.StateStack")

local beep = ChipAsm.sfx{ channels = { { hw = 1, program = {
  { squareNote = { len = 4, volume = 15, fade = 1, frequency = 0x600 } },
} } } }
local data = { audio = { sfx = { Beep = beep }, cries = {} } }

local function workerStep()
  local cmdCh, fxCh = channel("chipaudio_cmd"), channel("chipaudio_fx")
  while true do
    local req = cmdCh:pop()
    if not req then return end
    if req.cmd == "effect" then
      fxCh:push({ key = req.key, epoch = req.epoch,
        sd = ChipSynth.renderEffectData({ audio = req.audio }, req.header,
          req.options or {}) })
    end
  end
end

check(Music.current() == nil, "no song is playing")

for pitch = 1, 8 do ChipAudio.prewarmSfx(data, "Beep", pitch) end
local st = ChipAudio._effectStateForTest()
eq(st.inFlight, 2, "boot prewarm hands two renders to the worker")
eq(st.queued, 6, "the rest wait on the main thread")

FixedStep:init(function() end)
local game = setmetatable({ save = { playTime = 0, options = {} },
  stack = StateStack }, { __index = Game })
for _ = 1, 8 do
  workerStep()
  Game.update(game, 1 / 60)
end
st = ChipAudio._effectStateForTest()
eq(st.queued + st.inFlight, 0,
  "Game:update drains the prewarm queue while no song plays")
eq(st.ready, 8, "every boot prewarm is ready before the first song")

S.finish()
