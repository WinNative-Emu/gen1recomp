package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Music = require("src.core.Music")
local BattleState = require("src.battle.BattleState")

local played
local realPlayVictory = Music.playVictory
Music.playVictory = function(data, kind) played = kind end

local function run(kind, id, partyIndex)
  local b = setmetatable({
    data = {},
    kind = kind,
    oppClass = id,
    partyIndex = partyIndex,
    trainer = id and { id = id } or nil,
  }, { __index = BattleState })
  b.musicKind = b:computeMusicKind()
  played = nil
  b:playVictoryMusic()
  return b.musicKind, played
end

local cases = {
  { "trainer", "OPP_LANCE", 1, "gym", "trainer" },
  { "trainer", "OPP_LORELEI", 1, "trainer", "trainer" },
  { "trainer", "OPP_AGATHA", 1, "trainer", "trainer" },
  { "trainer", "OPP_BROCK", 1, "gym", "gym" },
  { "trainer", "OPP_GIOVANNI", 3, "gym", "gym" },
  { "trainer", "OPP_GIOVANNI", 2, "trainer", "trainer" },
  { "trainer", "OPP_RIVAL3", 1, "final", "gym" },
  { "trainer", "OPP_YOUNGSTER", 1, "trainer", "trainer" },
  { "wild", nil, nil, "wild", "wild" },
}

for _, c in ipairs(cases) do
  local label = tostring(c[2] or "wild") .. "#" .. tostring(c[3] or "-")
  local battleKind, victoryKind = run(c[1], c[2], c[3])
  T.eq(battleKind, c[4], label .. " battle theme kind")
  T.eq(victoryKind, c[5], label .. " victory theme kind")
end

Music.playVictory = realPlayVictory
T.finish("lance victory music bug2659")
