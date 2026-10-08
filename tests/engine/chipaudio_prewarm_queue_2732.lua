package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("chipaudio prewarm queue 2732")
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

local clock = 0
local clockStep = 0
love.timer.getTime = function()
  clock = clock + clockStep
  return clock
end

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

local beep = ChipAsm.sfx{ channels = { { hw = 1, program = {
  { squareNote = { len = 4, volume = 15, fade = 1, frequency = 0x600 } },
} } } }
local data = { audio = { sfx = { Beep = beep }, cries = {} } }

local function workerStep(limit)
  local cmdCh, fxCh = channel("chipaudio_cmd"), channel("chipaudio_fx")
  local n = 0
  while n < (limit or math.huge) do
    local req = cmdCh:pop()
    if not req then break end
    if req.cmd == "effect" then
      n = n + 1
      fxCh:push({ key = req.key, epoch = req.epoch,
        sd = ChipSynth.renderEffectData({ audio = req.audio }, req.header,
          req.options or {}) })
    end
  end
  return n
end

for pitch = 1, 5 do ChipAudio.prewarmSfx(data, "Beep", pitch) end
local st = ChipAudio._effectStateForTest()
eq(st.inFlight, 2, "two prewarms handed to the worker at once")
eq(st.queued, 3, "the rest wait on the main thread")
eq(#channel("chipaudio_cmd").items, 2, "only two effect commands pushed")

ChipAudio.resetSyncStats()
check(ChipAudio.newSfx(data, "Beep", 5) ~= nil, "a queued sfx still plays")
eq(ChipAudio._effectStateForTest().queued, 2,
  "playing a queued sfx drops its prewarm")
eq(ChipAudio.stats().syncRenders, 1, "and is counted as a sync render")

workerStep()
ChipAudio.pumpEffects()
st = ChipAudio._effectStateForTest()
eq(st.ready, 2, "finished prewarms are ready")
eq(st.inFlight, 2, "the queue refills the worker as results land")
workerStep()
ChipAudio.pumpEffects()
st = ChipAudio._effectStateForTest()
eq(st.ready, 4, "all four left are ready")
eq(st.queued + st.inFlight, 0, "nothing left queued")

ChipAudio.resetSyncStats()
check(ChipAudio.newSfx(data, "Beep", 1) ~= nil, "prewarmed sfx plays")
eq(ChipAudio.stats().syncRenders, 0, "a prewarmed play renders nothing")
eq(ChipAudio.stats().prewarmHits, 1, "and is counted as a hit")

ChipAudio.prewarmPinned(function()
  for pitch = 50, 66 do ChipAudio.prewarmSfx(data, "Beep", pitch) end
end)
for _ = 1, 20 do
  workerStep()
  ChipAudio.pumpEffects()
end
st = ChipAudio._effectStateForTest()
eq(st.pinned, 17, "a session set of 17 is pinned")
eq(st.ready, 20, "pinned prewarms are ready")

for pitch = 100, 199 do
  ChipAudio.prewarmSfx(data, "Beep", pitch)
  workerStep()
  ChipAudio.pumpEffects()
end
for _ = 1, 10 do
  workerStep()
  ChipAudio.pumpEffects()
end
st = ChipAudio._effectStateForTest()
eq(st.unpinnedReady, 64, "unpinned ready prewarms are capped")
eq(st.ready, 64 + 17, "pinned ones sit outside the cap")
ChipAudio.resetSyncStats()
for pitch = 50, 66 do ChipAudio.newSfx(data, "Beep", pitch) end
eq(ChipAudio.stats().syncRenders, 0,
  "every pinned session sound survives a 100-sound battle prewarm")
ChipAudio.newSfx(data, "Beep", 199)
eq(ChipAudio.stats().syncRenders, 0, "the newest unpinned prewarm survives the cap")
ChipAudio.newSfx(data, "Beep", 100)
eq(ChipAudio.stats().syncRenders, 1, "the oldest unpinned one was evicted")
eq(ChipAudio._effectStateForTest().pinned, 17, "the pin budget is unchanged")

ChipAudio.prewarmPinned(function()
  for pitch = 400, 440 do ChipAudio.prewarmSfx(data, "Beep", pitch) end
end)
eq(ChipAudio._effectStateForTest().pinned, 24, "pins stop at the pin budget")
for _ = 1, 30 do
  workerStep()
  ChipAudio.pumpEffects()
end
check(ChipAudio._effectStateForTest().ready <= 64 + 24,
  "ready PCM never exceeds both budgets together")

FixedStep:init(function() end)
ChipAudio.resetSyncStats()
clockStep = 0.001
ChipAudio.newSfx(data, "Beep", 300)
check(not FixedStep.suppressCatchup, "a short sync render keeps the catch-up")
clockStep = 0.05
ChipAudio.newSfx(data, "Beep", 301)
check(FixedStep.suppressCatchup, "a sync render over a frame drops the catch-up")
eq(FixedStep.accum, 0, "and clears the accumulator")
check(ChipAudio.stats().syncRenderMsMax >= 16, "its duration is recorded")
check(ChipAudio.stats().line:find("sync=2/", 1, true) ~= nil,
  "stats.line carries the counters")
clockStep = 0

S.finish()
