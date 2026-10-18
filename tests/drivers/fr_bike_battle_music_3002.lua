local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/fr_bike_battle_music_3002"
local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  result(failures == 0, "fr_bike_battle_music_3002")
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not result(game.phase == "boot" and game.boot ~= nil, "boot_ready") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Audio = require("src.core.game3.audio")
  local Field = require("src.core.game3.field")
  local ItemUse = require("src.core.game3.item_use")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Song = require("src.core.game3.song_ids")
  require("src.core.game3.encounters").onStep = function() return nil end
  require("src.core.game3.trainer_sight").check = function() return false end
  local session = Runtime.getSession()
  if not result(session ~= nil, "new_game_reached_field") then return finish() end
  session.party = {}
  Party.giveMon(session, 6, 50)
  local S = Song.forVersion(os.getenv("POKEPORT_VERSION") or "firered")

  local function song() return Audio._currentSong and Audio._currentSong.id end
  local function waitSong(id, frames)
    for _ = 1, frames or 400 do
      if song() == id and not Audio._fadeOut then return true end
      U.wait(1)
    end
    return song() == id
  end
  local function settle()
    for _ = 1, 120 do
      if not Player.moving and not Field.locked then break end
      U.wait(1)
    end
  end
  local function wildBattle(tag)
    local ok = BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 2 }, { fade = false })
    result(ok == true, tag .. "_wild_started")
    for _ = 1, 240 do
      if Battle.isActive() then break end
      U.wait(1)
    end
    U.wait(60)
    result(song() ~= nil and song() ~= S.MUS_CYCLING, tag .. "_battle_music (" .. tostring(song()) .. ")")
    BattleBridge.finishPending("run")
    for _ = 1, 240 do
      if not Battle.isActive() then break end
      U.wait(1)
    end
    U.wait(30)
  end

  Map.load(Runtime._mod, game, "FR_ROUTE_1", { x = 12, y = 37, facing = "down" })
  session = Runtime.getSession()
  session.x, session.y, session.facing = 12, 37, "down"
  Player.reset(12, 37, "down")
  U.wait(40)
  local Space = require("src.core.game3.scripting.space")
  if Space.vm and Space.vm:isRunning() then Space.vm:halt(true) end
  Field.unlock()
  U.wait(5)
  local route1 = Audio._mapSong
  result(route1 == S.MUS_ROUTE1 and waitSong(route1), "route1_map_song (" .. tostring(song()) .. ")")

  ItemUse.useBike(session)
  result(Player.biking == true, "bike_on")
  result(waitSong(S.MUS_CYCLING), "mount_plays_cycling (" .. tostring(song()) .. ")")

  wildBattle("route1")
  result(waitSong(S.MUS_CYCLING, 200), "route1_battle_returns_to_cycling (" .. tostring(song()) .. ")")
  U.still(game, DIR .. "/3002_01_route1_after_battle_on_bike.png")

  local entered = false
  for _ = 1, 4 do
    Player.tryMove("down", game, false)
    for _ = 1, 90 do
      U.wait(1)
      if not Player.moving and (tonumber(Player.turnTimer) or 0) <= 0 then break end
    end
    if Map.current == "FR_PALLET_TOWN" then entered = true break end
  end
  settle()
  result(entered and Player.biking == true, "rode_into_pallet_town_on_bike")
  result(Audio._savedSong == nil, "connection_clears_saved_music")
  result(waitSong(S.MUS_PALLET), "connection_plays_pallet (" .. tostring(song()) .. ")")
  U.still(game, DIR .. "/3002_02_pallet_on_bike_before_battle.png")

  wildBattle("pallet")
  result(waitSong(S.MUS_PALLET, 200), "3002_pallet_battle_returns_to_pallet (" .. tostring(song()) .. ")")
  result(Player.biking == true, "still_biking_after_battle")
  U.still(game, DIR .. "/3002_03_pallet_after_battle_on_bike.png")

  ItemUse.useBike(session)
  U.wait(20)
  ItemUse.useBike(session)
  result(Player.biking == true and waitSong(S.MUS_CYCLING), "remount_plays_cycling (" .. tostring(song()) .. ")")
  wildBattle("remount")
  result(waitSong(S.MUS_CYCLING, 200), "remount_battle_returns_to_cycling (" .. tostring(song()) .. ")")

  finish()
end
