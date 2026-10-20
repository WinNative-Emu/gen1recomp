package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Effects = require("src.battle.gen2.Effects")

local drops = {}
for _, key in ipairs(Effects.BATON_PASS_DROPS) do drops[key] = true end

-- engine/battle/move_effects/baton_pass.asm:140
T.check(drops.disabled, "Baton Pass drops the disabled move")
T.check(drops.disabledTurns, "Baton Pass drops the Disable counter")
T.check(not drops.disable and not drops.disableTurns, "no stale Disable keys")

T.finish("Gen 2 Baton Pass Disable")
