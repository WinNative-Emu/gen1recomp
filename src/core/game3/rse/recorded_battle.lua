local Rse = require("src.core.game3.rse.init")

local RB = {}

-- pokeemerald/src/recorded_battle.c:23
RB.BATTLER_RECORD_SIZE = 664
local MAX_BATTLERS_COUNT, MAX_LINK_PLAYERS = 4, 4
-- pokeemerald/include/constants/battle.h:93
RB.BATTLE_TYPE_RECORDED_INVALID = 0x7D007E92
-- pokeemerald/include/constants/trainers.h:9
local TRAINER_RECORD_MIXING_FRIEND, TRAINER_RECORD_MIXING_APPRENTICE = 300, 400
-- pokeemerald/include/constants/global.h:21
local LANGUAGE_ENGLISH = 2
-- pokeemerald/include/constants/battle.h:100
local B_OUTCOME_WON = 1

RB._live = nil

local function bit() return rawget(_G, "bit") or require("bit") end

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

local function frontier(sess)
  return require("src.core.game3.rse.frontier.util").frontier(sess)
end

local function emptyPlayer()
  return { trainerId = 0, name = "", gender = 0, battler = 0, language = 0 }
end

local function newLive()
  local players, record = {}, {}
  for i = 1, MAX_LINK_PLAYERS do players[i] = emptyPlayer() end
  for i = 1, MAX_BATTLERS_COUNT do record[i] = {} end
  return {
    battleFlags = 0, aiScripts = 0, rngSeed = 0, frontierFacility = 0, frontierBrainSymbol = 0,
    multiplayerId = 0, playerParty = {}, opponentParty = {}, players = players, battleRecord = record,
  }
end

local function playerTrainerId(sess)
  local tid = math.floor(tonumber(sess.trainerId or sess.playerId) or 0) % 65536
  local sid = math.floor(tonumber(sess.secretId) or 0) % 65536
  return tid + sid * 65536
end

local function playerGender(sess)
  local g = sess.gender
  return (g == "female" or g == "F" or g == 1) and 1 or 0
end

-- pokeemerald/src/recorded_battle.c:104
-- pokeemerald/src/recorded_battle.c:127
-- pokeemerald/src/recorded_battle.c:625
function RB.begin(sess, info)
  info = info or {}
  local live = newLive()
  live.battleFlags = math.floor(tonumber(info.battleFlags) or 0) % 4294967296
  live.aiScripts = math.floor(tonumber(info.aiFlags) or 0)
  live.rngSeed = math.floor(tonumber(info.rngSeed) or 0)
  live.playerParty = copy(info.playerParty or {})
  live.opponentParty = copy(info.opponentParty or {})
  live.opponentA = tonumber(info.opponentA)
  live.opponentB = tonumber(info.opponentB)
  live.partnerId = tonumber(info.partnerId)
  live.multiplayerId = math.floor(tonumber(info.multiplayerId) or 0)
  if type(info.players) == "table" then
    for i = 1, MAX_LINK_PLAYERS do
      if type(info.players[i]) == "table" then live.players[i] = copy(info.players[i]) end
    end
  end
  if sess and Rse.isRse(sess) then
    local facility = Rse.var("VAR_FRONTIER_FACILITY", sess)
    live.frontierFacility = facility
    local okD, D = pcall(require, "src.core.game3.rse.frontier.trainers")
    if okD then
      local okS, symbol = pcall(D.brainSymbol, sess, facility)
      live.frontierBrainSymbol = okS and tonumber(symbol) or 0
    end
  end
  -- pokeemerald/src/recorded_battle.c:174
  if sess and bit().band(live.battleFlags, 0x2) == 0 then
    live.players[1] = {
      trainerId = playerTrainerId(sess), name = tostring(sess.name or ""), gender = playerGender(sess),
      battler = 0, language = LANGUAGE_ENGLISH,
    }
  end
  RB._live = live
  return live
end

-- pokeemerald/src/recorded_battle.c:858
function RB.saveBattleOutcome(outcome)
  if RB._live then RB._live.battleOutcome = tonumber(outcome) or 0 end
end

local function friendInfo(sess, rec, id, won)
  local tr = frontier(sess).towerRecords
  local row = type(tr) == "table" and tr[id - TRAINER_RECORD_MIXING_FRIEND + 1] or {}
  rec.recordMixFriendName = tostring(row.name or "")
  rec.recordMixFriendClass = tonumber(row.facilityClass) or 0
  if won ~= nil then rec.easyChatSpeech = copy((won and row.speechLost or row.speechWon) or {}) end
  rec.recordMixFriendLanguage = tonumber(row.language) or 0
end

local function apprenticeInfo(sess, rec, id, speech)
  local list = type(sess.apprentices) == "table" and sess.apprentices or {}
  local row = list[id - TRAINER_RECORD_MIXING_APPRENTICE + 1] or {}
  rec.apprenticeId = tonumber(row.id) or 0
  if speech then rec.easyChatSpeech = copy(row.speechWon or {}) end
  rec.apprenticeLanguage = tonumber(row.language) or 0
end

local function isFriend(id) return id >= TRAINER_RECORD_MIXING_FRIEND and id < TRAINER_RECORD_MIXING_APPRENTICE end

-- pokeemerald/src/recorded_battle.c:319
function RB.moveToSaveData(sess)
  if type(sess) ~= "table" then return false end
  local live = RB._live or newLive()
  local f = frontier(sess)
  local B = bit()
  local rec = {
    playerParty = copy(live.playerParty), opponentParty = copy(live.opponentParty),
    players = copy(live.players), rngSeed = live.rngSeed, multiplayerId = live.multiplayerId,
    frontierFacility = live.frontierFacility, frontierBrainSymbol = live.frontierBrainSymbol,
    aiScripts = live.aiScripts, battleRecord = copy(live.battleRecord),
    recordMixFriendName = "", recordMixFriendClass = 0, apprenticeId = 0, easyChatSpeech = {},
    recordMixFriendLanguage = 0, apprenticeLanguage = 0,
  }
  local flags = live.battleFlags
  -- pokeemerald/src/recorded_battle.c:348
  if B.band(flags, 0x2) ~= 0 then
    local out = B.bor(B.band(flags, B.bnot(0x22)), 0x2000000)
    local master = B.band(flags, 0x4) ~= 0
    if not master and B.band(flags, 0x40) ~= 0 then
      local own = (live.players[1] or {}).battler or 0
      local mine = (live.players[(live.multiplayerId or 0) + 1] or {}).battler or 0
      master = (own % 2) == (mine % 2)
    end
    if master then out = B.bor(out, 0x80000000) end
    flags = out
  end
  rec.battleFlags = flags % 4294967296
  local a = live.opponentA or tonumber(sess.frontierOpponentA) or 0
  local b = live.opponentB or tonumber(sess.frontierOpponentB) or 0
  local p = live.partnerId or 0
  rec.opponentA, rec.opponentB, rec.partnerId = a, b, p
  rec.lvlMode = tonumber(f.lvlMode) or 0
  local Options = require("src.core.game3.options")
  rec.battleScene = Options.battleScene(sess) and 0 or 1
  rec.textSpeed = Options.textSpeed(sess)
  local won = (tonumber(live.battleOutcome or sess.battleOutcome) or 0) == B_OUTCOME_WON
  -- pokeemerald/src/recorded_battle.c:392
  if isFriend(a) then friendInfo(sess, rec, a, won)
  elseif isFriend(b) then friendInfo(sess, rec, b, won)
  elseif isFriend(p) then friendInfo(sess, rec, p, nil)
  end
  -- pokeemerald/src/recorded_battle.c:437
  if a >= TRAINER_RECORD_MIXING_APPRENTICE then apprenticeInfo(sess, rec, a, true)
  elseif b >= TRAINER_RECORD_MIXING_APPRENTICE then apprenticeInfo(sess, rec, b, true)
  elseif p >= TRAINER_RECORD_MIXING_APPRENTICE then apprenticeInfo(sess, rec, p, false)
  end
  sess.recordedBattle = rec
  return true
end

-- pokeemerald/src/recorded_battle.c:294
function RB.isValid(rec)
  if type(rec) ~= "table" then return false end
  local flags = tonumber(rec.battleFlags) or 0
  if flags == 0 then return false end
  if bit().band(flags, RB.BATTLE_TYPE_RECORDED_INVALID) ~= 0 then return false end
  return true
end

return RB
