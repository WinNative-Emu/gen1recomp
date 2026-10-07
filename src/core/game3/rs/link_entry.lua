local CableEntry = require("src.core.game3.link.cable_entry")
local M = {}
-- pokeruby/src/cable_club.c:558
M.SERVICES = {
  [1] = {wire = "battle_single", linkType = 0x2233, min = 2, max = 2},
  [2] = {wire = "battle_double", linkType = 0x2244, min = 2, max = 2},
  [5] = {wire = "battle_multi", linkType = 0x2255, min = 4, max = 4},
  trade = {wire = "trade", linkType = 0x1133, min = 2, max = 2},
  records = {wire = "record_corner", linkType = 0x3311, min = 2, max = 4},
  blender = {wire = "berry_blender", linkType = 0x4411, min = 2, max = 4},
}
-- pokeruby/src/cable_club.c:651
function M.contest(category)
  return {wire = assert(CableEntry.CONTEST_WIRES[tonumber(category) or -1]), linkType = 0x6601, min = 4, max = 4}
end
M.run = CableEntry.run
return M
