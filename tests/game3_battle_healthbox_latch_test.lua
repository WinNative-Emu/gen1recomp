#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("game3_battle_healthbox_latch_test: move effects and texts come from the ROM")

local Moves = require("src.core.game3.battle.moves")
Moves.loadRomPack()

local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Adapter = require("src.core.game3.battle.adapter")
local AnimSeq = require("src.core.game3.battle.anim_seq")
local Anim = require("src.core.game3.battle.anim")
local Healthbox = require("src.core.game3.battle.healthbox")
local Experience = require("src.core.game3.battle.experience")
local SummaryData = require("src.core.game3.summary_data")
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
    species = 1, level = 50, hp = o.hp or 100, maxHp = 100, growthRate = 0, exp = o.exp,
    attack = 50, defense = 50, spAtk = 50, spDef = 50, speed = o.speed or 50, ability = 0,
    nickname = o.nickname, moves = o.moves or { 33 }, pp = { 20, 20, 20, 20 }, status = o.status,
  }
end

local function battle(party, foeParty, wild)
  local st = State.new({ wild = wild ~= false, playerParty = party, foeParty = foeParty })
  st.player.type1, st.enemy.type1 = Types.ID.NORMAL, Types.ID.NORMAL
  st.rng = function(lo, hi)
    if lo == 1 and hi == 100 then return 1 end
    return hi
  end
  package.loaded["src.core.game3.battle"] = { _st = st }
  Anim.reset({ headless = true })
  Anim.syncDisplayFromState(st)
  return st, Adapter.new(st)
end

local function use(st, ad, user, move)
  local target = (user == st.player) and st.enemy or st.player
  local out = {}
  Engine.resolveMove(user, target, move, 1, ad, st, out)
  return out
end

local function play(events, onMsg)
  AnimSeq.beginEvents(events, onMsg)
  local guard = 0
  while not AnimSeq.update() and guard < 400 do guard = guard + 1 end
end

local function index_of(steps, pred)
  for i, s in ipairs(steps) do
    if pred(s) then return i end
  end
  return nil
end

print("=== status icon waits for updatestatusicon ===")
do
  local st, ad = battle({ mon({ nickname = "ALPHA", moves = { 86 } }) }, { mon({ nickname = "BRAVO" }) })
  local out = use(st, ad, st.player, 86)
  check(ad:status(st.enemy) == "PAR", "Thunder Wave paralyzes the foe")
  local p = Anim.present("enemy")
  check(Healthbox.shownAilment(p, st.enemy) == 0, "foe healthbox shows no icon before playback")

  local steps = AnimSeq.buildSteps(out._anim.events, out._anim)
  local iMove = index_of(steps, function(s) return s.kind == "move" end)
  local iAnim = index_of(steps, function(s) return s.kind == "anim" and s.data.name == "PARALYSIS" end)
  local iMsg = index_of(steps, function(s) return s.kind == "msg" and (s.data.text or ""):find("paralyzed", 1, true) end)
  local iIcon = index_of(steps, function(s) return s.kind == "status_apply" end)
  check(iMove and iAnim and iMsg and iIcon and iMove < iAnim and iAnim < iMsg and iMsg < iIcon,
    "icon step follows the move anim, status anim and message")

  local atMsg
  play(out._anim.events, function(text)
    if text:find("paralyzed", 1, true) then atMsg = Healthbox.shownAilment(p, st.enemy) end
  end)
  check(atMsg == 0, "icon still hidden while the paralysis message prints")
  check(Healthbox.shownAilment(p, st.enemy) == 2, "PAR icon shows after the message")
end

print("=== KO keeps the status icon until the faint animation ===")
do
  local st, ad = battle({ mon({ nickname = "ALPHA", moves = { 33 } }) },
    { mon({ nickname = "BRAVO", hp = 1, status = "PSN" }) })
  local p = Anim.present("enemy")
  local out = use(st, ad, st.player, 33)
  check(ad:hp(st.enemy) == 0, "Tackle knocks the foe out")
  check(Healthbox.shownAilment(p, st.enemy) == 1, "PSN icon still shown when the attack starts")
  local atFaintMsg
  play(out._anim.events, function(text)
    if text:find("fainted", 1, true) and atFaintMsg == nil then atFaintMsg = Healthbox.shownAilment(p, st.enemy) end
  end)
  check(atFaintMsg ~= nil and not (atFaintMsg >= 1 and atFaintMsg <= 6), "icon gone once the faint animation hid the healthbox")
end

print("=== forced switch-in refreshes the EXP bar ===")
do
  local lo = SummaryData.expForLevel(0, 50)
  local hi = SummaryData.expForLevel(0, 51)
  local first = mon({ nickname = "FULL", exp = hi - 1 })
  local second = mon({ nickname = "EMPTY", exp = lo })
  local st, ad = battle({ first, second }, { mon({ nickname = "BRAVO", moves = { 46 } }) }, false)
  local p = Anim.present("player")
  check(p.displayExp and p.displayExp > 0.9, "lead's EXP bar starts nearly full")
  local out = use(st, ad, st.enemy, 46)
  check(st.player.mon == second or st.player.partyIndex == 2, "Roar drags out the second mon")
  play(out._anim.events, function() end)
  local want = Experience.progress(st.player.mon).progressPercent
  check(math.abs((p.displayExp or -1) - want) < 1e-6,
    ("dragged-out mon's EXP bar is its own (got %s, want %s)"):format(tostring(p.displayExp), tostring(want)))
end

if failed > 0 then
  print("[FAIL] game3 healthbox latch")
  os.exit(1)
end
print("[ok] game3 healthbox latch")
