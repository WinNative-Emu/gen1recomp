-- scripts/OaksLab.asm:918
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

local M = assert(loadfile("data/scripts/oaks_lab.lua"))()

local cases = {
  { "TEXT_OAKSLAB_CHARMANDER_POKE_BALL", "OAKSLAB_CHARMANDER_POKE_BALL",
    "OAKSLAB_SQUIRTLE_POKE_BALL" },
  { "TEXT_OAKSLAB_SQUIRTLE_POKE_BALL", "OAKSLAB_SQUIRTLE_POKE_BALL",
    "OAKSLAB_BULBASAUR_POKE_BALL" },
  { "TEXT_OAKSLAB_BULBASAUR_POKE_BALL", "OAKSLAB_BULBASAUR_POKE_BALL",
    "OAKSLAB_CHARMANDER_POKE_BALL" },
}

local function find(rows, pred)
  for i, row in ipairs(rows) do
    if pred(row) then return i end
  end
end

for _, c in ipairs(cases) do
  local key, own, rival = c[1], c[2], c[3]
  local rows = M.talk[key]
  T.check(type(rows) == "table", key .. " rows loaded")
  local jumpNo = find(rows, function(r)
    return r[1] == "jump_if_false" and r[2] == "end" end)
  local hideOwn = find(rows, function(r)
    return r[1] == "hide_object" and r[3] == own end)
  local energetic = find(rows, function(r)
    return r[1] == "show_text" and r[2] == "_OaksLabMonEnergeticText" end)
  local received = find(rows, function(r)
    return r[1] == "show_text" and r[2] == "_OaksLabReceivedMonText" end)
  local give = find(rows, function(r) return r[1] == "give_pokemon" end)
  local illTake = find(rows, function(r)
    return r[1] == "show_text" and r[2] == "_OaksLabRivalIllTakeThisOneText" end)
  local hideRival = find(rows, function(r)
    return r[1] == "hide_object" and r[3] == rival end)
  local rivalReceived = find(rows, function(r)
    return r[1] == "show_text" and r[2] == "_OaksLabRivalReceivedMonText" end)

  T.check(jumpNo and hideOwn and energetic and received and give,
    key .. ": all player-pick rows present")
  if jumpNo and hideOwn and energetic and received and give then
    T.eq(hideOwn, jumpNo + 1, key .. ": own ball hides right after YES")
    T.check(hideOwn < energetic, key .. ": ball gone before the energetic line")
    T.check(hideOwn < received, key .. ": ball gone before the received line")
    T.check(hideOwn < give, key .. ": ball gone before the nickname prompt")
    T.check(energetic < received and received < give,
      key .. ": energetic, received, then AddPartyMon")
  end
  T.check(illTake and hideRival and rivalReceived,
    key .. ": all rival-pick rows present")
  if illTake and hideRival and rivalReceived then
    T.check(illTake < hideRival and hideRival < rivalReceived,
      key .. ": rival ball hides between ILL_TAKE_THIS_ONE and RECEIVED")
  end
end

T.finish("oaks_lab_starter_ball_hide_2686")
