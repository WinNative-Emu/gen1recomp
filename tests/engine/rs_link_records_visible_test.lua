package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Records = require("src.ui.game3.rs.link_records")
local vm = {}
package.loaded["src.core.game3.scripting.space"] = { vm = vm }

check(type(Records.isVisible) == "function", "ui_pass can ask the link records window if it is up")
eq(Records.isVisible(), false, "hidden before the 2F record machine is read")
Records.show({ gameStats = {}, linkBattleRecords = {} })
eq(Records.isVisible(), true, "shown while the machine's script runs")
package.loaded["src.core.game3.scripting.space"] = { vm = {} }
eq(Records.isVisible(), false, "a new script owner closes it")
Records.show({})
Records.eraseBox(0, 0, 29, 19)
eq(Records.isVisible(), false, "erasing the box closes it")

package.loaded["src.core.game3.scripting.space"] = nil
T.finish("rs_link_records_visible")
