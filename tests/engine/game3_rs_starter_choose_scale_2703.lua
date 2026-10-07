#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq

local Policy = require("src.ui.game3.rs.starter_choose_policy")
local Starter = require("src.ui.game3.rse.starter_choose")

local function settle(cmds)
  local a = Starter._affine.new(cmds)
  for _ = 1, 64 do
    Starter._affine.step(a)
    if a.ended then break end
  end
  return a
end

T.suite("rs starter choose affine scale")

eq(Policy.affineScale(320), 1.25, "circle 320 -> 1.25x")
eq(Policy.affineScale(256), 1, "mon 256 -> 1.0x")
eq(Policy.affineScale(20), 20 / 256, "first circle frame starts small")

local circle = settle({
  { op = "frame", xScale = 20, duration = 0 },
  { op = "frame", xScale = 20, duration = 15 },
})
eq(circle.scale, 320, "circle table settles at 320")
eq(Policy.affineScale(circle.scale), 1.25, "circle drawn at 1.25x")

local mon = settle({
  { op = "frame", xScale = 16, duration = 0 },
  { op = "frame", xScale = 16, duration = 15 },
})
eq(mon.scale, 256, "mon table settles at 256")
eq(Policy.affineScale(mon.scale), 1, "mon drawn at 1.0x")

T.finish("rs starter choose affine scale")
