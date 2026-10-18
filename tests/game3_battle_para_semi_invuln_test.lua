#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("game3_battle_para_semi_invuln_test: two-turn move data comes from the ROM move table")

local Moves = require("src.core.game3.battle.moves")
Moves.loadRomPack()

local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Adapter = require("src.core.game3.battle.adapter")
local Types = require("src.core.game3.battle.types")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function mon(o)
  return {
    species = o.species or 1, level = 50, hp = 200, maxHp = 200,
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = 50, ability = 0,
    nickname = o.nickname, moves = o.moves, pp = { 20, 20, 20, 20 }, status = o.status,
  }
end

local function battle(move)
  local rngMap = {}
  local st = State.new({
    wild = true,
    playerParty = { mon({ nickname = "ALPHA", moves = { move } }) },
    foeParty = { mon({ nickname = "BRAVO", moves = { 33 } }) },
  })
  st.player.type1, st.enemy.type1 = Types.ID.NORMAL, Types.ID.NORMAL
  st.rng = function(lo, hi)
    local v = rngMap[tostring(lo) .. "," .. tostring(hi)]
    if v ~= nil then return v end
    if lo == 1 and hi == 100 then return 1 end
    return hi
  end
  return st, Adapter.new(st), rngMap
end

local function use(st, ad, user, move)
  local target = (user == st.player) and st.enemy or st.player
  local out = {}
  Engine.resolveMove(user, target, move, 1, ad, st, out)
  return table.concat(out, " || "), out
end

local CASES = {
  { 91, "Dig", "UNDERGROUND", "underground" },
  { 19, "Fly", "ON_AIR", "onAir" },
  { 291, "Dive", "UNDERWATER", "underwater" },
  { 340, "Bounce", "ON_AIR", "onAir" },
}

for _, c in ipairs(CASES) do
  local move, name, kind, flag = c[1], c[2], c[3], c[4]
  local st, ad, rngMap = battle(move)
  use(st, ad, st.player, move)
  check(st.player.semiInvulnerable == kind, name .. " turn 1 sets " .. kind)
  check(st.player.twoTurnMove ~= nil, name .. " turn 1 arms the second turn")

  ad:applyStatus(st.player, "PAR", st.enemy, { force = true })
  rngMap["0,3"] = 0
  local txt = use(st, ad, st.player, move)
  check(txt:find("is paralyzed", 1, true) ~= nil, name .. " turn 2 is fully paralyzed")
  check(st.player.semiInvulnerable == nil and st.player[flag] == nil,
    name .. " full paralysis clears " .. kind)
  check(st.player.twoTurnMove == nil and st.player.expLockedMove == nil,
    name .. " full paralysis drops the charged turn")

  rngMap["0,3"] = nil
  local hpBefore = ad:hp(st.player)
  use(st, ad, st.enemy, 33)
  check(ad:hp(st.player) < hpBefore, name .. " foe Tackle lands after the paralysis")
end

if failed > 0 then
  print("[FAIL] game3 paralysis semi-invulnerable")
  os.exit(1)
end
print("[ok] game3 paralysis semi-invulnerable")
