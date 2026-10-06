package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Title = require("src.ui.game3.rs.title")
local fades, target = 0, nil
local machine = { globals = {}, ppu = {
  set = function() end,
  palette = { load = function() end, beginFade = function() fades = fades + 1 end },
} }
function machine:manifest() return { layout = "rs", game = "ruby" } end
function machine:setCb2() end
function machine:joyNew() return false end
function machine:joyHeld() return 0 end

local title = Title.new(machine, { params = { song = "MUS_TITLE" }, songFrames = function() return nil end })
function title:leaveTo(value) target = value end
title.songDuration, title.songStart, title.frames = title.songLength(413), 0, 6000
local task = { [0] = 0, [4] = 0 }
T.check(pcall(title.phase3, title, 0, task), "missing song duration does not resolve to the class function")
T.eq(fades, 0, "unknown song status leaves the title running")
T.eq(target, nil, "unknown duration has no copyright handoff")
T.eq(task[0], 1, "title animation continues without a song duration")

title.songDuration, title.frames = 5996, 5995
title:phase3(0, task)
T.eq(fades, 0, "title remains until the native active-track mask refresh")
title.frames = 5996
title:phase3(0, task)
T.eq(fades, 1, "known song status ends on the measured native frame")
T.eq(target, "copyright", "song EOF returns through copyright")

T.finish("game3_rs_title_song_status_test")
