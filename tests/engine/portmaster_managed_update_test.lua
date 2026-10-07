-- Catalogue installs must not download or boot standalone application updates.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local Boot = require("src.update.Boot")
local Check = require("src.update.Check")
local Prelaunch = require("src.core.Prelaunch")
local oldEnv, oldLove = os.getenv, _G.love
local enabled = "1"
os.getenv = function(name)
  if name == "POKEPORT_PORTMASTER_MANAGED" then return enabled end
  return oldEnv(name)
end
local threads = 0
_G.love = {
  filesystem = { isFused = function() return true end },
  thread = { newThread = function() threads = threads + 1; error("must not start") end },
}
T.eq(Boot.canUpdateInPlace(), false, "managed fused builds cannot chainload")
T.eq(Boot.run({}), false, "managed boot ignores downloaded updates")
Check.start(true)
T.eq(threads, 0, "forced checks do not start the network worker")
T.eq(Check.state().status, "idle", "managed update UI stays idle")
T.eq(Prelaunch.new({ tasks = { update = true, sync = false },
  allowUpdate = true, fs = false }), nil, "prelaunch cannot override package manager")
enabled = "0"
T.eq(Boot.canUpdateInPlace(), true, "standalone fused builds still update")
os.getenv, _G.love = oldEnv, oldLove
T.finish()
