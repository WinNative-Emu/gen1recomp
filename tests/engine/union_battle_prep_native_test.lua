package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._xgen_fixture")
local Model = require("src.online.union.BattlePrepModel")

local real, list = F.allReal()
if #list == 0 then
  print("[skip] union_battle_prep_native_test: no imported game cache")
  os.exit(0)
end

local function sampleMon(data, national, level)
  local sp = data.species[national]
  local moves = {}
  for _, row in ipairs(sp.levelMoves) do
    if row.level <= level and #moves < 4 then moves[#moves + 1] = row.move end
  end
  if data.generation == 3 then
    return { species = sp.localKey, level = level, personality = 0, otId = 1, ivs = {}, evs = {}, moves = moves,
      pp = { 35, 35, 35, 35 }, maxHp = 40, attack = 20, defense = 20, spAtk = 20, spDef = 20, speed = 20 }
  end
  local rows = {}
  for i, id in ipairs(moves) do rows[i] = { id = data.moveToLocal[id], pp = data.moves[id].pp } end
  return { species = sp.localKey, level = level, dvs = { attack = 1, defense = 2, speed = 3, special = 4 },
    statExp = {}, moves = rows, maxHp = 40 }
end

for _, version in ipairs(list) do
  local data = real[version]
  local gen = data.generation
  local rec = sampleMon(data, 25, 20)
  local m = Model.new({ version = version, gen = gen, data = data, rules = { ruleset = "native", gen = gen },
    owned = { party = { rec }, generation = gen } })
  local ok, lines = pcall(m.recordLines, m, rec, nil, false)
  T.check(ok, version .. " native record lines build (" .. tostring(not ok and lines or "") .. ")")
  if ok then
    local text = table.concat(lines, " ")
    T.check(text:upper():find(data.species[25].name:upper(), 1, true) ~= nil, version .. " names the species")
    T.check(text:find("No. ", 1, true) == nil, version .. " no raw ids in the native record lines: " .. text)
  end
end

T.finish()
