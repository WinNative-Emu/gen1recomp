local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("em_faraway_mew_2712", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_faraway_mew_2712")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Player = require("src.core.game3.player")
  local Objects = require("src.core.game3.objects")
  local Faraway = require("src.core.game3.faraway_island")
  local FxRse = require("src.core.game3.field_effects_rse")
  local Space = require("src.core.game3.scripting.space")
  local Message = require("src.ui.game3.message")
  local Battle = require("src.core.game3.battle")
  local session = require("src.core.game3.runtime").getSession()
  local C = require("src.core.game3.constants").of("emerald")
  session.party = {}
  require("src.core.game3.party").giveMon(session, C.species.byName.SPECIES_SWAMPERT, 50, "SWAMPERT")
  F.noTrainerSight()
  F.setFlag("FLAG_HIDE_MEW", false)
  F.setFlag("FLAG_CAUGHT_MEW", false)
  if not S.check(F.goTo(game, "EM_FARAWAY_ISLAND_INTERIOR", 13, 19, "up"), "interior loaded") then return S.finish() end
  local function mew()
    for _, lid in ipairs(Objects._order) do
      local eo = Objects._byId[lid]
      if Faraway.isMew(eo) then return eo end
    end
  end
  local function vmBusy() return Space.vm and Space.vm:isRunning() end
  for _ = 1, 600 do
    F.settle(game, 1)
    U.wait(1)
    local m = mew()
    if m and m.invisible and not m.moving and not m.frozen and not m.scriptBusy and not vmBusy() then break end
  end
  local m = mew()
  if not S.check(m ~= nil, "mew object present") then return S.finish() end
  S.check(m.invisible == true and not m.hidden and m.visible ~= false, "intro set_invisible leaves mew in the world, sprite hidden")
  S.check(Objects.at(m.cellX, m.cellY) == m, "invisible mew is found by Objects.at")
  S.check(Objects.blocks(m.cellX, m.cellY, nil, 0), "invisible mew blocks its cell")

  local c0 = F.var("VAR_FARAWAY_ISLAND_STEP_COUNTER")
  local mx0, my0 = m.cellX, m.cellY
  F.holdKeys(game, { "up" }, 16 * 3 + 4)
  U.wait(24)
  S.note(string.format("held up player=(%d,%d) mew=(%d,%d) counter %d -> %d",
    Player.cellX, Player.cellY, m.cellX, m.cellY, c0, F.var("VAR_FARAWAY_ISLAND_STEP_COUNTER")))
  S.check(F.var("VAR_FARAWAY_ISLAND_STEP_COUNTER") - c0 >= 3, "step counter counts held-direction steps")
  S.check(m.cellX ~= mx0 or m.cellY ~= my0, "mew runs while the player holds a direction")

  local visOk, sawVisible, sawShake, shotDone = true, false, false, false
  for i = 1, 16 do
    local dir = (i % 2 == 0) and "left" or "right"
    F.holdKeys(game, { dir }, 18, function()
      for _, e in ipairs(FxRse._list) do
        if e.name == "long_grass" or e.name == "tall_grass" then sawShake = true end
      end
      if not m.invisible and not shotDone and m.moving then
        shotDone = true
        S.still(game, "2712_01_mew_flashes_visible.png")
      end
    end)
    U.wait(20)
    local c = F.var("VAR_FARAWAY_ISLAND_STEP_COUNTER")
    local want = (c - 1) % 8 ~= 0
    if m.invisible ~= want then
      visOk = false
      S.note(string.format("tap %d counter=%d invisible=%s want=%s", i, c, tostring(m.invisible), tostring(want)))
    end
    if not m.invisible then sawVisible = true end
  end
  S.check(visOk, "mew visibility follows the step counter (visible on every 8th step)")
  S.check(sawVisible, "mew flashed visible at least once")
  S.check(sawShake, "mew shook the grass on a 4th step")

  for _ = 1, 40 do
    if not m.moving then break end
    U.wait(1)
  end
  Player.cellX, Player.cellY = m.cellX, m.cellY + 1
  Player.px, Player.py = Player.cellX * 16, Player.cellY * 16
  Player.targetX, Player.targetY = Player.cellX, Player.cellY
  Player.facing = "up"
  U.wait(4)
  U.tap(game, "a")
  local started = false
  for _ = 1, 30 do
    if vmBusy() then started = true break end
    U.wait(1)
  end
  S.check(started, "A on hidden mew starts its script")
  local appeared, battle = false, false
  for _ = 1, 1500 do
    if not appeared and not m.invisible then
      appeared = true
      S.still(game, "2712_02_mew_appears_from_grass.png")
    end
    if Battle.isActive() then battle = true break end
    if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
    U.wait(1)
  end
  S.check(appeared, "mew script set_visible shows mew")
  S.check(battle, "mew battle starts")
  local st = Battle._st
  local enemy = st and st.enemy and st.enemy.mon
  S.check(enemy ~= nil and tonumber(enemy.species) == C.species.byName.SPECIES_MEW, "enemy is mew")
  S.finish()
end
