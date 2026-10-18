-- POKEPORT_DRIVER_PACED=1 POKEPORT_SPEED=1 tools/run_driver.sh red <id> tests/drivers/intro_audio_starve_2998.lua
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local ChipAudio = require("src.core.ChipAudio")
  local Sound = require("src.core.Sound")
  local Music = require("src.core.Music")
  local IntroMovie = require("src.ui.IntroMovie")
  local getTime = love.timer.getTime

  local function log(...) U.log(...) end
  local failed = false
  local function check(label, ok)
    log(ok and "PASS" or "FAIL", label)
    if not ok then failed = true end
    return ok
  end

  local t0 = getTime()
  local events = {}
  local function note(fmt, ...)
    events[#events + 1] = string.format("%7.3f " .. fmt, getTime() - t0, ...)
  end

  local realPlay = Sound.play
  Sound.play = function(data, name)
    local a = getTime()
    local src = realPlay(data, name)
    note("sfx %s %.1fms", tostring(name), (getTime() - a) * 1000)
    return src
  end
  local realMusic = Music.play
  local musicAt
  Music.play = function(data, song, ...)
    note("music %s", tostring(song))
    if song == "Music_IntroBattle" then musicAt = getTime() end
    return realMusic(data, song, ...)
  end

  local intro = game.stack:top()
  check("boot stack starts on IntroMovie", getmetatable(intro) == IntroMovie)
  if getmetatable(intro) ~= IntroMovie then love.event.quit(1) return end

  local function backlog()
    local s = ChipAudio._effectStateForTest()
    return s.queued + s.inFlight, s
  end

  local backlogAtMusic
  local syncAtStart = ChipAudio.stats().syncRenders
  local running = false
  local lastT = getTime()
  local maxDt, maxDtAt = 0, nil
  local minDepthAfterStart
  local underrunsAtMusic
  local frames = 0
  while game.stack:top() == intro and frames < 60 * 40 do
    U.wait(1)
    frames = frames + 1
    local now = getTime()
    local dt = now - lastT
    lastT = now
    local st = ChipAudio.stats()
    local pend, s = backlog()
    if musicAt and backlogAtMusic == nil then
      backlogAtMusic = pend
      underrunsAtMusic = st.underruns
      note("backlog at music start: queued=%d inFlight=%d pending=%d ready=%d",
        s.queued, s.inFlight, s.pending, s.ready)
    end
    if musicAt and st.depth and st.depth >= ChipAudio.MUSIC_PREROLL then
      running = true
    end
    if running and st.depth then
      if minDepthAfterStart == nil or st.depth < minDepthAfterStart then
        minDepthAfterStart = st.depth
      end
    end
    if dt > maxDt then maxDt, maxDtAt = dt, now - t0 end
    if frames % 15 == 0 or dt > 0.025 then
      note("f=%d phase=%s op=%s dt=%.1fms depth=%s under=%d xrt=%s fx=%d/%d",
        frames, tostring(intro.phase), tostring(intro.opIndex), dt * 1000,
        tostring(st.depth), st.underruns,
        st.xrt and string.format("%.3f", st.xrt) or "-",
        pend, s.pending)
    end
  end
  for _, line in ipairs(events) do log(line) end
  local st = ChipAudio.stats()
  log(st.line)
  log(string.format("max frame dt %.1fms at %.2fs", maxDt * 1000, maxDtAt or -1))
  log(string.format("min music depth once Music_IntroBattle was playing: %s",
    tostring(minDepthAfterStart)))
  check("Music_IntroBattle started", musicAt ~= nil)
  check("worker effect backlog empty when Music_IntroBattle starts",
    backlogAtMusic == 0)
  check("intro sfx come prewarmed, none rendered on the main thread",
    st.syncRenders == syncAtStart)
  check("no music underrun during the fight",
    underrunsAtMusic ~= nil and st.underruns == underrunsAtMusic)
  love.event.quit(failed and 1 or 0)
end
