package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

package.loaded["src.core.game3.battle"] = package.loaded["src.core.game3.battle"]
  or { isActive = function() return false end }

local Zoom = require("src.render.Zoom")
local Renderer = require("src.render.Renderer")
local DeferredWrite = require("src.core.DeferredWrite")
local SessionLifecycle = require("src.core.SessionLifecycle")
local Game = require("src.core.Game")
local Game2 = require("src.core.Game2")
local Game3 = require("src.core.Game3")

Renderer.fitScale = function() return 4 end

local clock = 100
DeferredWrite.clock = function() return clock end

local function gen1()
  local writes = 0
  local ow = {}
  local g = setmetatable({
    save = { options = { zoom = 0 } },
    overworld = ow,
    stack = { top = function() return ow end },
    writeOptions = function() writes = writes + 1 end,
  }, { __index = Game })
  return g, function() return writes end, function() return g.save.options.zoom end
end

local function gen2()
  local writes = 0
  local world = { map = {}, fitScale = function() return 4 end }
  function world:zoomStep(delta) Zoom.step(delta, self:fitScale()) end
  local g = setmetatable({
    world = world,
    stack = { top = function() return nil end },
    options = { zoom = 0 },
    save = {},
    persistOptions = function() writes = writes + 1 end,
  }, { __index = Game2 })
  return g, function() return writes end, function() return g.options.zoom end
end

local function gen3()
  local writes = 0
  local g = setmetatable({
    phase = "field",
    options = { zoom = 0 },
    writeOptions = function() writes = writes + 1 end,
  }, { __index = Game3 })
  return g, function() return writes end, function() return g.options.zoom end
end

for _, case in ipairs({ { "gen1", gen1, Game }, { "gen2", gen2, Game2 }, { "gen3", gen3, Game3 } }) do
  local name, make, cls = case[1], case[2], case[3]

  Zoom.reset()
  DeferredWrite.flush()
  local g, writes, zoom = make()
  for _ = 1, 12 do
    cls.wheelmoved(g, 0, -1)
    clock = clock + 0.03
  end
  eq(writes(), 0, name .. ": a fast wheel spin writes nothing while it is still spinning")
  check(zoom() < 0, name .. ": the live options table still tracks the zoom")
  check(DeferredWrite.isPending("options"), name .. ": the write is pending")
  DeferredWrite.tick(clock + DeferredWrite.DELAY / 2)
  eq(writes(), 0, name .. ": not yet idle long enough")
  DeferredWrite.tick(clock + DeferredWrite.DELAY + 0.01)
  eq(writes(), 1, name .. ": one write once the wheel goes idle")
  DeferredWrite.tick(clock + 10)
  eq(writes(), 1, name .. ": and only one")

  cls.wheelmoved(g, 0, 1)
  cls.focus(g, false)
  eq(writes(), 2, name .. ": focus loss flushes the pending write")

  cls.wheelmoved(g, 0, 1)
  cls.visible(g, false)
  eq(writes(), 3, name .. ": minimize / mobile suspend flushes the pending write")

  cls.wheelmoved(g, 0, 1)
  SessionLifecycle.endProcess()
  eq(writes(), 4, name .. ": process exit flushes the pending write")
  check(not DeferredWrite.isPending("options"), name .. ": nothing left pending")
end

Zoom.reset()
T.finish("wheel zoom persist is debounced")
