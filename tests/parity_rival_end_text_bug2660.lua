-- scripts/ChampionsRoom.asm:65
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local S = require("tests.harness").suite("parity rival end text")
local check = S.check

local init = require("data.scripts.init")
local champ = init.get("CHAMPIONS_ROOM")
local rows = champ and champ.talk and champ.talk.TEXT_CHAMPIONSROOM_RIVAL or {}

local found, armed = false, false
for i, r in ipairs(rows) do
  if r[1] == "rival_battle" and r[2] == "OPP_RIVAL3" then
    found = true
    local p = rows[i - 1]
    armed = p ~= nil and p[1] == "save_end_battle_text" and p[2] == "_RivalDefeatedText"
  end
end
check(found, "champion script has rival_battle OPP_RIVAL3")
check(armed, "champion arms _RivalDefeatedText right before rival_battle OPP_RIVAL3")

local text = Data.text and Data.text._RivalDefeatedText
if text then
  check(text:find("NO!", 1, true) ~= nil, "_RivalDefeatedText is the cart's champion loss line")
end

local SKIP = { play_music = true, set_option = true }
local seen, offenders, total = {}, {}, 0
local function walk(t, path)
  if type(t) ~= "table" or seen[t] then return end
  seen[t] = true
  for i, r in ipairs(t) do
    if type(r) == "table" and r[1] == "rival_battle" then
      total = total + 1
      local j = i - 1
      while t[j] and type(t[j]) == "table" and SKIP[t[j][1]] do j = j - 1 end
      local p = t[j]
      if not (type(p) == "table" and p[1] == "save_end_battle_text") then
        offenders[#offenders + 1] = path .. "[" .. i .. "] " .. tostring(r[2])
      end
    end
  end
  for k, v in pairs(t) do walk(v, path .. "." .. tostring(k)) end
end

for _, mod in ipairs({ "story", "story2", "story3", "story4", "story5",
                       "story6", "story7", "flavor_all", "gyms",
                       "oaks_lab", "oaks_lab_yellow" }) do
  local ok, m = pcall(require, "data.scripts." .. mod)
  if ok then walk(m, mod) end
end
check(total > 0, "sweep found scripted rival battles")
check(#offenders == 0, "every scripted rival_battle arms its loss line: "
  .. table.concat(offenders, ", "))

S.finish()
