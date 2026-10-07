local Music = {}

local RATE = 22050
local TAU = math.pi * 2
local sin, exp, floor, abs, max, min, random = math.sin, math.exp, math.floor, math.abs, math.max, math.min, math.random

local INST = {
  flute = { wave = "sine", h2 = 0.25, a = 0.07, d = 0.3, s = 0.75, r = 0.18, vib = 0.14, vibRate = 5 },
  chip = { wave = "pulse", duty = 0.25, a = 0.004, d = 0.1, s = 0.7, r = 0.04, vib = 0.1, vibRate = 6.5, gate = 0.85 },
  chiparp = { wave = "pulse", duty = 0.125, a = 0.002, d = 0.06, s = 0.4, r = 0.02, gate = 0.7 },
  tri = { wave = "tri", a = 0.003, d = 0.08, s = 0.85, r = 0.03, gate = 0.85 },
  accordion = { wave = "pulse", duty = 0.4, detune = 14, a = 0.03, d = 0.12, s = 0.85, r = 0.06, lp = 2800, vib = 0.04, vibRate = 5.5 },
  brass = { wave = "saw", detune = 7, a = 0.03, d = 0.2, s = 0.75, r = 0.08, lp = 2200, vib = 0.07, vibRate = 5.2, gate = 0.9 },
  tuba = { wave = "saw", a = 0.02, d = 0.15, s = 0.7, r = 0.06, lp = 500, gate = 0.7 },
  bell = { wave = "fm", ratio = 3.5, index = 2.2, idxDecay = 0.5, a = 0.002, decay = 1.1, r = 0.8 },
  epiano = { wave = "fm", ratio = 1, index = 1.4, idxDecay = 0.3, a = 0.004, decay = 1.0, r = 0.12 },
  pad = { wave = "tri", detune = 10, a = 0.8, d = 0.6, s = 0.8, r = 0.9, lp = 1500 },
  harp = { wave = "harp", a = 0.002, decay = 0.9, bright = 5, r = 0.3, gate = 2.5 },
  nylon = { wave = "harp", a = 0.003, decay = 1.3, bright = 3, r = 0.25, gate = 2 },
  ocarina = { wave = "tri", a = 0.05, d = 0.2, s = 0.8, r = 0.12, lp = 2400, vib = 0.16, vibRate = 5 },
  muted = { wave = "saw", a = 0.05, d = 0.25, s = 0.65, r = 0.1, lp = 850, vib = 0.12, vibRate = 4.6, gate = 0.9 },
  upright = { wave = "tri", a = 0.004, decay = 0.45, r = 0.05, lp = 700, gate = 0.95 },
  sub = { wave = "sine", a = 0.02, d = 0.3, s = 0.8, r = 0.2 },
  square = { wave = "pulse", duty = 0.5, a = 0.002, d = 0.08, s = 0.5, r = 0.03, lp = 3500, gate = 0.55 },
}

local SONGS = {
  Gentle = {
    bpm = 76, spb = 2,
    chords = "F:8 Dm:8 Bb:8 C:8 F:8 Am:8 Bb:4 C:4 F:8",
    melody = "a4:2 c5:2 f5:3 e5:1 d5:2 c5:2 a4:4 bb4:2 d5:2 f5:2 d5:2 c5:6 -:2 "
      .. "a4:2 c5:2 f5:3 g5:1 a5:2 g5:1 f5:1 e5:4 d5:2 f5:2 e5:2 g5:2 f5:6 -:2",
    lead = { inst = "flute", vol = 0.32, pan = 0.1, send = 0.35 },
    parts = {
      { role = "chord", inst = "harp", pattern = "12343212", oct = 1, vol = 0.12, pan = -0.35, send = 0.3 },
      { role = "chord", inst = "pad", pattern = "c---c---", vol = 0.05, pan = 0.25 },
      { role = "bass", inst = "sub", pattern = "r---f---", vol = 0.3 },
    },
    echo = { steps = 3, fb = 0.4, mix = 0.35 },
  },
  Bright = {
    bpm = 144, spb = 4,
    chords = "D:16 A:16 Bm:16 G:16 D:16 A:16 G:8 A:8 D:16",
    melody = "f#5:2 a5:2 d6:4 c#6:2 b5:2 a5:4 e5:2 a5:2 c#6:4 b5:2 a5:2 e5:4 "
      .. "f#5:2 b5:2 d6:3 c#6:1 b5:2 a5:2 f#5:4 g5:4 f#5:2 e5:2 d5:6 -:2 "
      .. "f#5:2 a5:2 d6:4 e6:2 f#6:2 e6:2 d6:2 c#6:4 a5:2 b5:2 c#6:2 e6:2 c#6:2 a5:2 "
      .. "b5:2 d6:2 g5:4 a5:2 c#6:2 e6:4 d6:8 -:4 d5:2 e5:2",
    lead = { inst = "chip", oct = -1, vol = 0.2, pan = 0.1, send = 0.3 },
    parts = {
      { role = "chord", inst = "chiparp", pattern = "1324132413241324", vol = 0.09, pan = -0.3, send = 0.2 },
      { role = "bass", inst = "tri", pattern = "r-.ro.r.r-.ro.r.", vol = 0.35 },
      { role = "drum", pattern = "K...s..kk.k.S...", vol = 0.45 },
      { role = "drum", pattern = "h.h.h.hoh.h.h.h.", vol = 0.22, pan = 0.35 },
    },
    echo = { steps = 3, fb = 0.3, mix = 0.2 },
  },
  Waltz = {
    bpm = 132, spb = 2,
    chords = "G:6 G:6 C:6 C:6 D7:6 D7:6 G:6 G:6 Em:6 Em:6 Am:6 Am:6 D:6 D7:6 G:12",
    melody = "d5:2 g5:2 b5:2 d6:4 b5:2 c6:2 e6:2 c6:2 g5:6 a5:2 c6:2 f#5:2 a5:4 d5:2 "
      .. "g5:2 b5:2 d6:2 g6:4 -:2 g6:2 f#6:1 e6:1 b5:2 e6:4 d6:2 c6:2 e6:1 c6:1 a5:2 e5:4 c6:2 "
      .. "b5:2 a5:2 f#5:2 a5:2 c6:2 f#5:2 g5:6 -:6",
    lead = { inst = "accordion", oct = -1, vol = 0.2, pan = 0.15, send = 0.15 },
    parts = {
      { role = "bass", inst = "tuba", pattern = "r-....f-....", vol = 0.35 },
      { role = "chord", inst = "square", pattern = "..c.c.", oct = 1, vol = 0.045, pan = -0.3, send = 0.1 },
      { role = "drum", pattern = "..u.u.", vol = 0.12, pan = 0.4 },
    },
    echo = { steps = 2, fb = 0.25, mix = 0.18 },
  },
  March = {
    bpm = 112, spb = 4,
    chords = "Bb:16 Eb:16 Bb:16 F:16 Bb:16 Eb:16 F7:16 Bb:16",
    melody = "f5:3 f5:1 bb5:4 d6:3 c6:1 bb5:4 g5:3 bb5:1 eb6:4 d6:2 c6:2 bb5:4 "
      .. "d6:3 c6:1 bb5:4 f5:3 g5:1 a5:2 bb5:2 c6:8 a5:2 bb5:2 c6:4 "
      .. "f5:3 f5:1 bb5:4 d6:3 c6:1 bb5:4 eb6:3 d6:1 c6:2 bb5:2 g5:4 bb5:2 c6:2 "
      .. "d6:4 c6:2 a5:2 f5:2 a5:2 c6:2 eb6:2 bb5:8 -:4 f5:3 f5:1",
    lead = { inst = "brass", oct = -1, vol = 0.22, pan = 0.1, send = 0.15 },
    parts = {
      { role = "bass", inst = "tuba", pattern = "r-......f-......", vol = 0.35 },
      { role = "chord", inst = "brass", pattern = "....c-......c-..", vol = 0.04, pan = -0.3 },
      { role = "drum", pattern = "S..ss.s.S..ss.ss", vol = 0.28, pan = 0.2 },
      { role = "drum", pattern = "k.......k.......", vol = 0.5 },
    },
    echo = { steps = 4, fb = 0.2, mix = 0.15 },
  },
  Dream = {
    bpm = 72, spb = 2,
    chords = "Ebmaj7:8 F:8 Ebmaj7:8 F:8 Cm7:8 Abmaj7:8 Bbsus4:8 Bb:8",
    melody = "g5:2 bb5:2 d6:4 c6:2 a5:2 f5:4 g5:2 bb5:2 d6:2 f6:2 c6:6 -:2 "
      .. "eb6:2 d6:2 bb5:4 c6:2 eb6:2 g6:4 f6:4 eb6:4 d6:6 -:2",
    lead = { inst = "bell", vol = 0.25, send = 0.5 },
    parts = {
      { role = "chord", inst = "pad", pattern = "c-------", vol = 0.07, send = 0.3 },
      { role = "chord", inst = "bell", pattern = "..3...4.", oct = 1, vol = 0.06, pan = -0.5, send = 0.6 },
      { role = "bass", inst = "sub", pattern = "r-------", vol = 0.25 },
    },
    echo = { steps = 3, fb = 0.5, mix = 0.45 },
  },
  Waves = {
    bpm = 60, spb = 3,
    chords = "A:6 D:6 A:6 E:6 F#m:6 D:6 Bm:6 E:6 A:6 D:6 E:6 A:6",
    melody = "e5:3 c#5:2 e5:1 f#5:4 a5:2 e5:3 c#5:2 a4:1 b4:6 c#5:2 e5:1 a5:3 f#5:3 e5:2 d5:1 "
      .. "d5:2 c#5:1 b4:3 g#4:3 b4:3 a4:2 c#5:1 e5:3 f#5:2 a5:1 d6:3 c#6:2 b5:1 g#5:3 a5:6",
    lead = { inst = "ocarina", vol = 0.28, pan = 0.15, send = 0.35 },
    parts = {
      { role = "chord", inst = "nylon", pattern = "123432", vol = 0.13, pan = -0.3, send = 0.2 },
      { role = "bass", inst = "sub", pattern = "r--f--", vol = 0.25 },
      { role = "drum", pattern = "w-----------", vol = 0.35 },
      { role = "drum", pattern = "..r..r", vol = 0.12, pan = 0.5 },
    },
    echo = { steps = 2, fb = 0.35, mix = 0.25 },
  },
  Night = {
    bpm = 92, spb = 2, swing = 0.33,
    chords = "Am7:8 Dm7:8 G7:8 Cmaj7:8 Fmaj7:8 Bm7b5:8 E7:8 Am7:8",
    melody = "e5:2 g5:1 a5:1 c6:2 b5:1 a5:1 f5:4 -:2 a5:1 c6:1 b5:2 a5:1 g5:1 f5:2 d5:2 e5:6 -:2 "
      .. "a5:2 c6:1 e6:1 d6:2 c6:2 b5:2 d6:1 f6:1 e6:2 d6:1 c6:1 b5:2 g#5:2 d6:2 c6:1 b5:1 a5:6 -:2",
    lead = { inst = "muted", oct = -1, vol = 0.3, pan = 0.15, send = 0.3 },
    parts = {
      { role = "bass", inst = "upright", pattern = "r-t-f-w-", vol = 0.4 },
      { role = "chord", inst = "epiano", pattern = "c--...c-", vol = 0.07, pan = -0.25, send = 0.2 },
      { role = "drum", pattern = "u.uuu.uu", vol = 0.2, pan = 0.3 },
      { role = "drum", pattern = "..x...x.", vol = 0.2, pan = -0.2 },
    },
    echo = { steps = 3, fb = 0.3, mix = 0.2 },
  },
  Playful = {
    bpm = 126, spb = 4,
    chords = "C:16 A7:16 D7:16 G7:16 C:16 C7:16 F:8 G7:8 C:16",
    melody = "e5:2 g5:2 c6:2 g5:2 e5:1 f5:1 g5:2 -:4 c#6:2 e6:2 a5:2 e6:2 d6:1 c#6:1 a5:2 -:4 "
      .. "d6:2 f#5:2 a5:2 c6:2 b5:1 a5:1 f#5:2 d5:2 -:2 g5:1 f#5:1 g5:2 b5:2 d6:2 f6:4 d6:2 b5:2 "
      .. "e5:2 g5:2 c6:2 g5:2 e5:1 f5:1 g5:2 c6:4 bb5:2 g5:2 e5:2 g5:2 bb5:2 c6:2 bb5:2 g5:2 "
      .. "a5:2 c6:2 f6:2 c6:2 g5:2 b5:2 d6:2 f6:2 e6:4 c6:2 g5:2 c6:4 -:4",
    lead = { inst = "square", vol = 0.14, pan = 0.1, send = 0.15 },
    parts = {
      { role = "bass", inst = "tri", pattern = "r.......f.......", vol = 0.35 },
      { role = "chord", inst = "square", pattern = "....c.......c...", oct = 1, vol = 0.04, pan = -0.3 },
      { role = "drum", pattern = "b..b..b.....b.b.", vol = 0.2, pan = 0.4 },
    },
    echo = { steps = 3, fb = 0.25, mix = 0.15 },
  },
}

local LETTER = { c = 0, d = 2, e = 4, f = 5, g = 7, a = 9, b = 11 }
local QUALITY = {
  [""] = { 0, 4, 7 }, m = { 0, 3, 7 }, ["7"] = { 0, 4, 7, 10 }, m7 = { 0, 3, 7, 10 }, maj7 = { 0, 4, 7, 11 },
  dim = { 0, 3, 6 }, dim7 = { 0, 3, 6, 9 }, m7b5 = { 0, 3, 6, 10 }, sus4 = { 0, 5, 7 },
}

local function split(name)
  local letter, accidental, rest = name:match("^(%a)([#b]?)(.*)$")
  return (LETTER[letter:lower()] + (accidental == "#" and 1 or accidental == "b" and -1 or 0)) % 12, rest
end

local function midi(name)
  local pc, octave = split(name)
  return pc + 12 * (tonumber(octave) + 1)
end

local function seq(text)
  local out = {}
  for name, len in text:gmatch("(%S+):(%d+)") do out[#out + 1] = { name, tonumber(len) } end
  return out
end

local function held(inst, t)
  if t < inst.a then return t / inst.a end
  if inst.decay then return exp(-(t - inst.a) / inst.decay) end
  if t < inst.a + inst.d then return 1 - (1 - inst.s) * (t - inst.a) / inst.d end
  return inst.s
end

local function gains(pan)
  local angle = ((pan or 0) + 1) * math.pi / 4
  return math.cos(angle) * 1.414, math.sin(angle) * 1.414
end

local function osc(inst, p)
  p = p % 1
  if inst.wave == "tri" then return 4 * abs(p - 0.5) - 1 end
  if inst.wave == "saw" then return 2 * p - 1 end
  return p < (inst.duty or 0.5) and 0.7 or -0.7
end

local function voice(mix, inst, note, t0, gate, vol, pan, send)
  local L, R, SL, SR, n, pause = mix.L, mix.R, mix.SL, mix.SR, mix.n, mix.pause
  local work = mix.work
  local freq = 440 * 2 ^ ((note - 69) / 12)
  local gl, gr = gains(pan)
  send = send or 0
  local start = floor(t0 * RATE)
  local released = held(inst, gate)
  local k = inst.lp and (1 - exp(-TAU * inst.lp / RATE))
  local spread = inst.detune and 2 ^ (inst.detune / 1200)
  local wave = inst.wave
  local ph, ph2, y = 0, 0, 0
  for j = 0, floor((gate + inst.r) * RATE) - 1 do
    local t = j / RATE
    local env = t < gate and held(inst, t) or released * max(0, 1 - (t - gate) / inst.r)
    local f = freq
    if inst.vib then f = f * 2 ^ (inst.vib / 12 * sin(TAU * inst.vibRate * t) * min(1, t / 0.3)) end
    local inc = f / RATE
    ph = ph + inc
    local x
    if wave == "sine" then
      x = sin(TAU * ph) + (inst.h2 or 0) * sin(TAU * 2 * ph)
    elseif wave == "fm" then
      x = sin(TAU * ph + inst.index * exp(-t / inst.idxDecay) * sin(TAU * inst.ratio * ph))
    elseif wave == "harp" then
      local e, a = exp(-t * inst.bright), 1
      x = 0
      for h = 1, 5 do
        x = x + sin(TAU * h * ph) * a / h
        a = a * e
      end
    else
      x = osc(inst, ph)
      if spread then
        ph2 = ph2 + inc * spread
        x = (x + osc(inst, ph2)) * 0.5
      end
    end
    if k then
      y = y + k * (x - y)
      x = y
    end
    x = x * env * vol
    local i = (start + j) % n + 1
    L[i] = L[i] + x * gl
    R[i] = R[i] + x * gr
    if send > 0 then
      SL[i] = SL[i] + x * gl * send
      SR[i] = SR[i] + x * gr * send
    end
    work = work + 1
    if work >= 1024 then
      work = 0
      pause()
    end
  end
  mix.work = work
end

local DRUM_LENGTH = { k = 0.35, s = 0.25, h = 0.08, o = 0.4, x = 0.05, u = 0.3, b = 0.12, r = 0.15 }

local function hit(mix, kind, t0, dur, vol, pan)
  local length = kind == "w" and dur * 1.3 or DRUM_LENGTH[kind]
  if not length then return end
  local L, R, n, pause = mix.L, mix.R, mix.n, mix.pause
  local work = mix.work
  local gl, gr = gains(pan)
  local start = floor(t0 * RATE)
  local lp, lp2, prev, ph = 0, 0, 0, 0
  for j = 0, floor(length * RATE) - 1 do
    local t = j / RATE
    local noise = random() * 2 - 1
    local x, xr
    if kind == "k" then
      ph = ph + (48 + 120 * exp(-t / 0.025)) / RATE
      x = sin(TAU * ph) * exp(-t / 0.11)
    elseif kind == "s" then
      lp = lp + 0.35 * (noise - lp)
      x = (noise - lp) * exp(-t / 0.07) * 0.8 + sin(TAU * 190 * t) * exp(-t / 0.04) * 0.5
    elseif kind == "h" or kind == "o" or kind == "x" then
      x = (noise - prev) * 0.3 * exp(-t / (kind == "o" and 0.12 or kind == "h" and 0.02 or 0.01))
      prev = noise
    elseif kind == "u" then
      lp = lp + 0.5 * (noise - lp)
      x = lp * 0.5 * min(1, t / 0.008) * exp(-t / 0.08)
    elseif kind == "b" then
      x = (sin(TAU * 1050 * t) + 0.5 * sin(TAU * 1650 * t)) * exp(-t / 0.025) * 0.5
    elseif kind == "r" then
      x = (noise - prev) * 0.25 * (t < 0.012 and t / 0.012 or exp(-(t - 0.012) / 0.035))
      prev = noise
    else
      local env = sin(math.pi * t / length) ^ 2 * 3
      lp = lp + 0.05 * (noise - lp)
      lp2 = lp2 + 0.05 * ((random() * 2 - 1) - lp2)
      x, xr = lp * env, lp2 * env
    end
    local i = (start + j) % n + 1
    L[i] = L[i] + x * vol * gl
    R[i] = R[i] + (xr or x) * vol * gr
    work = work + 1
    if work >= 1024 then
      work = 0
      pause()
    end
  end
  mix.work = work
end

local function render(song, pause)
  local sd = 60 / song.bpm / song.spb
  local chords, total = {}, 0
  for _, token in ipairs(seq(song.chords)) do
    local pc, quality = split(token[1])
    chords[#chords + 1] = { start = total, pc = pc, iv = QUALITY[quality] }
    total = total + token[2]
  end
  local function at(step)
    return (step + ((song.swing and step % 2 == 1) and song.swing or 0)) * sd
  end
  local function chordAt(step)
    for i = #chords, 1, -1 do
      if chords[i].start <= step then return chords[i], chords[i % #chords + 1] end
    end
  end
  local n = floor(total * sd * RATE)
  local mix = { L = {}, R = {}, SL = {}, SR = {}, n = n, pause = pause, work = 0 }
  for i = 1, n do
    mix.L[i], mix.R[i], mix.SL[i], mix.SR[i] = 0, 0, 0, 0
    if i % 8192 == 0 then pause() end
  end

  local lead, step = song.lead, 0
  local leadInst = INST[lead.inst]
  for _, token in ipairs(seq(song.melody)) do
    if token[1] ~= "-" then
      local t0 = at(step)
      voice(mix, leadInst, midi(token[1]) + 12 * (lead.oct or 0), t0,
        (at(step + token[2]) - t0) * (leadInst.gate or 0.92), lead.vol, lead.pan, lead.send)
    end
    step = step + token[2]
  end

  for _, part in ipairs(song.parts) do
    local pattern, size = part.pattern, #part.pattern
    local inst = INST[part.inst]
    for s = 0, total - 1 do
      local ch = pattern:sub(s % size + 1, s % size + 1)
      if ch ~= "." and ch ~= "-" then
        local len = 1
        while len < size and pattern:sub((s + len) % size + 1, (s + len) % size + 1) == "-" do len = len + 1 end
        local t0 = at(s)
        local dur = at(s + len) - t0
        if part.role == "drum" then
          hit(mix, ch:lower(), t0, dur, part.vol * (ch:match("%u") and 1.4 or 1), part.pan)
        else
          local chord, nextChord = chordAt(s)
          local notes = {}
          if part.role == "bass" then
            local root = 36 + chord.pc
            if ch == "w" then
              local approach = 36 + (nextChord.pc + 11) % 12
              if abs(approach + 12 - (root + 7)) < abs(approach - (root + 7)) then approach = approach + 12 end
              notes[1] = approach
            else
              notes[1] = ch == "f" and root + 7 or ch == "o" and root + 12 or ch == "t" and root + chord.iv[2] or root
            end
          elseif ch == "c" then
            for i, iv in ipairs(chord.iv) do notes[i] = 48 + chord.pc + iv end
          else
            local i = tonumber(ch) - 1
            notes[1] = 48 + chord.pc + chord.iv[i % #chord.iv + 1] + 12 * floor(i / #chord.iv)
          end
          for _, note in ipairs(notes) do
            voice(mix, inst, note + 12 * (part.oct or 0), t0, dur * (inst.gate or 0.92), part.vol, part.pan, part.send)
          end
        end
      end
    end
  end

  local echo = song.echo
  if echo then
    local d = floor(echo.steps * sd * RATE)
    local L, R, SL, SR = mix.L, mix.R, mix.SL, mix.SR
    for i = 1, n do
      local g, wl, wr = echo.mix, 0, 0
      for tap = 1, 3 do
        local j = (i - 1 - tap * d) % n + 1
        if tap % 2 == 1 then
          wl, wr = wl + g * SR[j], wr + g * SL[j]
        else
          wl, wr = wl + g * SL[j], wr + g * SR[j]
        end
        g = g * echo.fb
      end
      L[i], R[i] = L[i] + wl, R[i] + wr
      if i % 4096 == 0 then pause() end
    end
  end
  mix.SL, mix.SR = nil, nil

  local peak = 1e-6
  for i = 1, n do
    peak = max(peak, abs(mix.L[i]), abs(mix.R[i]))
    if i % 16384 == 0 then pause() end
  end
  return mix, 0.55 / peak, total
end

local function build(song, pause, job)
  local mix, scale = render(song, pause)
  local sound = love.sound.newSoundData(mix.n, RATE, 16, 2)
  job.sound = sound
  local L, R = mix.L, mix.R
  for i = 0, mix.n - 1 do
    sound:setSample(i, 1, L[i + 1] * scale)
    sound:setSample(i, 2, R[i + 1] * scale)
    if i % 8192 == 8191 then pause() end
  end
  return sound
end

local function now()
  return love and love.timer and love.timer.getTime and love.timer.getTime() or os.clock()
end

Music.BUDGET = 0.004
Music.MAX_CACHED = 2
local cache, order, jobs, failed = {}, {}, {}, {}

local function free(sound)
  if sound and sound.release then pcall(sound.release, sound) end
end

local function drop(name)
  local job = jobs[name]
  jobs[name] = nil
  if job then free(job.sound) end
end

local function remember(name, sound)
  cache[name] = sound
  order[#order + 1] = name
  while #order > Music.MAX_CACHED do
    local old = table.remove(order, 1)
    free(cache[old])
    cache[old] = nil
  end
end

function Music.request(name, budget)
  if cache[name] then return cache[name] end
  if failed[name] then return nil, failed[name] end
  local song = SONGS[name]
  if not song then return nil, "unknown" end
  local job = jobs[name]
  if not job then
    job = { deadline = 0 }
    local function pause()
      if now() >= job.deadline then coroutine.yield() end
    end
    job.co = coroutine.create(function() return build(song, pause, job) end)
    jobs[name] = job
  end
  job.deadline = now() + (budget or Music.BUDGET)
  local ok, result = coroutine.resume(job.co)
  if not ok then
    drop(name)
    failed[name] = tostring(result)
    return nil, failed[name]
  end
  if coroutine.status(job.co) ~= "dead" then return nil, "pending" end
  jobs[name] = nil
  remember(name, result)
  return result
end

function Music.cancel(name)
  if name then
    drop(name)
  else
    for key in pairs(jobs) do drop(key) end
  end
end

function Music.reset()
  Music.cancel()
  for _, sound in pairs(cache) do free(sound) end
  cache, order, failed = {}, {}, {}
end

require("src.render.Assets").register({ invalidate = Music.reset, release = Music.reset })
return Music
