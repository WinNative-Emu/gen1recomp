package.path = "./?.lua;./?/init.lua;" .. package.path

local Vm = require("src.core.game3.scripting.vm")
local Adapters = require("src.core.game3.scripting.adapters")
local Hud = require("src.ui.game3.hud")

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function waitingVm()
  local adapters = Adapters.stub({})
  adapters.armWaitButton = function(cb) Hud.armWaitButton(cb) end
  adapters.clearWaitButton = function() Hud.clearWaitButton() end
  local vm = Vm.new({
    adapters = adapters,
    scripts = { WAIT = { { op = "waitbuttonpress" }, { op = "end" } } },
  })
  vm:start("WAIT")
  for _ = 1, 3 do vm:tick() end
  return vm
end

print("=== halting a script parked on waitbuttonpress drops the HUD wait ===")
do
  Hud.clearWaitButton()
  local vm = waitingVm()
  check(Hud._waitButton ~= nil, "waitbuttonpress arms the HUD wait")
  check(Hud.busy() == true, "the armed wait keeps the HUD busy")
  vm:halt(true)
  check(Hud._waitButton == nil, "halt clears the HUD wait")
  check(Hud.busy() == false, "field input is free after the halt")
end

print("=== a pressed wait does not clear a later script's wait ===")
do
  Hud.clearWaitButton()
  local vm = waitingVm()
  local cb = Hud._waitButton
  Hud._waitButton = nil
  if cb then cb() end
  check(vm.ctx.waitButtonArmed == nil, "the press disarms the context")
  local other = function() end
  Hud.armWaitButton(other)
  vm:halt(true)
  check(Hud._waitButton == other, "halt leaves a wait it did not arm alone")
  Hud.clearWaitButton()
end

print("=== the host adapters expose clearWaitButton ===")
do
  local src = io.open("src/core/game3/scripting/adapters.lua"):read("*a")
  local host = src:match("function Adapters%.host.*")
  check(host and host:find("clearWaitButton = function", 1, true) ~= nil, "Adapters.host defines clearWaitButton")
end

print(string.format("\nTotal: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
