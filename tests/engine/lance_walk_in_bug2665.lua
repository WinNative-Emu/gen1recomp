-- scripts/LancesRoom.asm:96
-- home/map_objects.asm:179
-- home/overworld.asm:1845

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
local savedSound = package.loaded["src.core.Sound"]
local played = {}
package.loaded["src.core.Sound"] = {
  play = function(_, name) played[#played + 1] = name end,
}

local story4 = require("data.scripts.story4")
local hooks = story4.LANCES_ROOM

local function reversed(rle)
  local out = {}
  for i = #rle, 1, -1 do out[#out + 1] = rle[i] end
  return out
end

local function sameRoute(got, want, label)
  eq(#got, #want, label .. ": segment count")
  for i, w in ipairs(want) do
    local g = got[i] or {}
    eq(g[1], w[1], label .. ": segment " .. i .. " direction")
    eq(g[2], w[2], label .. ": segment " .. i .. " count")
  end
end

local redRle = { { "up", 12 }, { "left", 12 }, { "down", 7 }, { "left", 6 } }
local yellowRle = { { "up", 13 }, { "left", 12 }, { "down", 7 }, { "left", 6 } }

sameRoute(hooks.walkInRoute, reversed(redRle), "red walkInRoute")
sameRoute(hooks.walkInRouteFor(false), reversed(redRle), "red walkInRouteFor")
sameRoute(hooks.walkInRouteFor(true), reversed(yellowRle), "yellow walkInRouteFor")
eq(hooks.walkInRoute[1][1], "left", "walk-in leaves the staircase going left first")

local D = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

local function runWalkIn(version)
  local prev = GameVersion.current
  GameVersion.current = version
  played = {}
  local blocks = {}
  local moves = {}
  local game = { data = {}, save = { flags = {} } }
  local ow = { player = { cellX = 24, cellY = 16 } }
  function ow:replaceBlock(bx, by, id) blocks[bx .. "," .. by] = id end
  function ow:scriptMove(entity, dir, n, onDone)
    moves[#moves + 1] = { dir, n }
    local d = D[dir]
    entity.cellX, entity.cellY = entity.cellX + d[1] * n, entity.cellY + d[2] * n
    if onDone then onDone() end
  end
  hooks.onEnter(game, ow)
  GameVersion.current = prev
  return game, ow, moves, blocks
end

do
  local game, ow, moves, blocks = runWalkIn("red")
  sameRoute(moves, reversed(redRle), "red onEnter moves")
  eq(ow.player.cellX, 6, "red walk-in lands at x=6")
  eq(ow.player.cellY, 11, "red walk-in lands at y=11")
  eq(game.save.flags.EVENT_LANCES_ROOM_LOCK_DOOR, true, "red landing locks the door")
  eq(played[#played], "Go_Inside", "red landing plays SFX_GO_INSIDE")
  eq(blocks["2,6"], 0x72, "red door block (2,6) closed")
  eq(blocks["3,6"], 0x73, "red door block (3,6) closed")
end

do
  local game, ow, moves, blocks = runWalkIn("yellow")
  sameRoute(moves, reversed(yellowRle), "yellow onEnter moves")
  eq(ow.player.cellX, 6, "yellow walk-in lands at x=6")
  eq(ow.player.cellY, 10, "yellow walk-in lands at y=10")
  check(not game.save.flags.EVENT_LANCES_ROOM_LOCK_DOOR, "yellow landing leaves the door open")
  eq(#played, 0, "yellow landing plays no SFX")
  eq(blocks["2,6"], 0x31, "yellow door block (2,6) open")
end

package.loaded["src.core.Sound"] = savedSound
T.finish("lance_walk_in_bug2665")
