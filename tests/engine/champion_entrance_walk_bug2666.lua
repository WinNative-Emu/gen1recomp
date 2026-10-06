-- scripts/ChampionsRoom.asm:30
-- home/map_objects.asm:179
-- home/overworld.asm:1844

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local story = require("data.scripts.story")

local queued = {}
local ow = {
  player = { cellX = 3, cellY = 7 },
  npcs = { { def = { name = "CHAMPIONSROOM_RIVAL" } } },
  queueScript = function(_, script, extra)
    queued[#queued + 1] = { script = script, extra = extra }
  end,
}
story.CHAMPIONS_ROOM.onEnter({ save = { flags = {} } }, ow)
eq(#queued, 2, "entrance walk and rival script are queued")

local walk = queued[1] and queued[1].script or {}
local rle = { { "up", 1 }, { "right", 1 }, { "up", 3 } }
local expected = {}
for i = #rle, 1, -1 do expected[#expected + 1] = rle[i] end
eq(#walk, #expected, "entrance walk has one row per RLE entry")
for i, e in ipairs(expected) do
  local row = walk[i] or {}
  eq(row[1], "move_player", "row " .. i .. " is move_player")
  eq(row[2], e[1], "row " .. i .. " direction plays the RLE back to front")
  eq(row[3], e[2], "row " .. i .. " count plays the RLE back to front")
end

local dx = { up = 0, down = 0, left = -1, right = 1 }
local dy = { up = -1, down = 1, left = 0, right = 0 }
local x, y = 3, 7
local cells = { x .. "," .. y }
local lastDir
for _, row in ipairs(walk) do
  if row[1] == "move_player" then
    for _ = 1, row[3] do
      x, y = x + dx[row[2]], y + dy[row[2]]
      cells[#cells + 1] = x .. "," .. y
    end
    lastDir = row[2]
  end
end
eq(table.concat(cells, " "), "3,7 3,6 3,5 3,4 4,4 4,3",
   "player walks up the left carpet column and sidesteps just below the rival")
eq(lastDir, "up", "player ends facing up at the rival")

T.finish("champion_entrance_walk_bug2666")
