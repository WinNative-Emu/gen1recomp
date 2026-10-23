local U = require("tests.drivers.util")

return function(game)
  local failed = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = failed + 1 end
    return ok
  end
  local function finish() love.event.quit(failed == 0 and 0 or 1) end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "3040 boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)
  local Audio = require("src.core.game3.audio")
  if not check(Audio.isReady(), "3040 native cached audio installed") then return finish() end
  local pack = Audio._pack
  local index = pack.index
  local ids = index.cryIds
  local missing, count = 0, 0
  for species = 1, 411 do
    local id = ids[species]
    local cry = id and index.cries[id]
    if id ~= nil then count = count + 1 end
    if not (cry and cry.sampleId and pack.samples[cry.sampleId]) then missing = missing + 1 end
  end
  check(count == 411 and ids[412] == nil, "3040 exactly 411 cached species cry IDs")
  check(missing == 0, "3040 every mapped species has a PCM sample")
  local oldUnown = true
  for species = 252, 276 do if ids[species] ~= 200 then oldUnown = false end end
  check(oldUnown, "3040 old Unown slots retain Unown cry")
  -- pokefirered/src/pokemon.c:5234
  for _, row in ipairs({ { 251, 250, "Celebi" }, { 277, 273, "Treecko" },
    { 288, 378, "Zigzagoon" }, { 289, 375, "Linoone" }, { 411, 387, "Chimecho" } }) do
    check(ids[row[1]] == row[2], "3040 " .. row[3] .. " cached cry mapping")
    Audio.stopCry()
    local played = Audio.playCry(row[1], 0)
    local info = Audio._crySlot and Audio._crySlot.info
    check(played and info and info.cryIndex == row[2], "3040 " .. row[3] .. " playback selects mapped sample")
    local done = false
    for _ = 1, 600 do
      U.wait(1)
      if Audio.isCryFinished() then done = true break end
    end
    check(done, "3040 " .. row[3] .. " cry finishes")
  end
  Audio.stopCry()
  finish()
end
