-- engine/pokegear/pokegear.asm:2237
local U = require("tests.drivers.util")

return function(game)
  local deadline = love.timer.getTime() + 60
  local speed, volume = game.speedOverride, love.audio.getVolume()
  local writes = {}
  for _, key in ipairs({ "writeSave", "writeOptions", "persistOptions" }) do
    writes[key] = rawget(game, key)
    game[key] = function() end
  end
  local fails = 0
  local function label(ok, name, detail)
    if not ok then fails = fails + 1 end
    print((ok and "PASS " or "FAIL ") .. name
      .. (detail and (" (" .. tostring(detail) .. ")") or ""))
    return ok
  end
  local function check()
    assert(love.timer.getTime() < deadline, "60 second driver deadline")
  end
  local function wait(n) for _ = 1, n do check(); U.wait(1) end end
  local function settle(predicate, what)
    for _ = 1, 1800 do
      check()
      if predicate() then return end
      wait(1)
    end
    error("bounded settle failed: " .. what)
  end
  local function tap(key) check(); U.tap(game, key); wait(2) end
  local function top() return game.stack:top() end
  local function id() return top() and top().screenId end
  local out

  local ok, err = xpcall(function()
    out = assert(os.getenv("POKEPORT_SHOT_DIR"), "POKEPORT_SHOT_DIR required")
    local version = require("src.core.GameVersion").get()
    assert(version == "gold" or version == "silver" or version == "crystal",
      "G/S/C only")
    love.audio.setVolume(0)
    game.speedOverride = 200
    settle(function()
      return game.world and game.world.map and not top()
        and not game.world:busy()
    end, "field ready")

    local FieldMoves = require("src.world.gen2.FieldMoves")
    local Mon = require("src.battle.gen2.Mon")
    local save, world = game.save, game.world
    save.player.badges = save.player.badges or {}
    save.player.badges.STORM = true
    save.engineFlags = save.engineFlags or {}
    local keep = { SPAWN_NEW_BARK = true, SPAWN_VIOLET = true,
      SPAWN_MAHOGANY = true }
    local indigoFlag
    for _, row in ipairs(FieldMoves.FLYPOINTS) do
      save.engineFlags[row.flag] = keep[row.spawn] == true
      if row.spawn == "SPAWN_INDIGO" then indigoFlag = row.flag end
    end
    local flyer = assert(Mon.new(game.data, "PIDGEOTTO", 24))
    table.remove(flyer.moves, 1)
    Mon.learnMove(flyer, "FLY", game.data)
    save.party = { flyer }

    world.mapScenes = world.mapScenes or {}
    world.mapScenes.ROUTE_27 = 1
    world:warpToMapId("ROUTE_27", 19, 10, "left")
    settle(function()
      return world.map.id == "ROUTE_27" and not world:busy() and not top()
    end, "Route 27 field uncovered")
    label(world:region() == "kanto", "route27_is_kanto",
      world:currentLandmarkId())
    label(not FieldMoves.hasVisitedSpawn(save, "SPAWN_INDIGO"),
      "indigo_not_visited")

    local party
    local function openFly()
      if id() ~= "Gen2PartyMenu" then
        game:openStartMenuItem("pokemon")
        settle(function() return id() == "Gen2PartyMenu" end, "party menu")
      end
      party = top()
      tap("a")
      local sub = assert(party.submenu, "action submenu")
      local row
      for n, item in ipairs(sub.items) do
        if item.id == "FLY" then row = n end
      end
      assert(row, "FLY action")
      for _ = 1, #sub.items do
        if sub.index == row then break end
        tap("down")
      end
      tap("a")
      settle(function() return id() == "Gen2Pokegear" and top().fly end,
        "fly picker")
      return top()
    end

    local function probeDraw(picker)
      local seen = { icons = 0, frames = 0 }
      local drawTilemap, drawPlayerIcon = picker.drawTilemap,
        picker.drawPlayerIcon
      picker.drawTilemap = function(self, map)
        seen.map = map
        seen.frames = seen.frames + 1
        return drawTilemap(self, map)
      end
      picker.drawPlayerIcon = function(self, x, y)
        seen.icons = seen.icons + 1
        return drawPlayerIcon(self, x, y)
      end
      game.speedOverride = speed
      settle(function() return seen.map ~= nil and seen.frames >= 3 end,
        "picker drawn")
      game.speedOverride = 200
      picker.drawTilemap, picker.drawPlayerIcon = nil, nil
      return seen
    end

    local picker = openFly()
    label(picker:region() == "kanto", "picker_player_in_kanto")
    label(picker.flyRegion == "johto", "nokanto_johto_map", picker.flyRegion)
    local row = picker:flyRow()
    label(row and row.spawn == "SPAWN_NEW_BARK", "nokanto_default_new_bark",
      row and row.spawn)
    label(#picker.fly == 3, "nokanto_three_johto_rows", #picker.fly)
    local maps = picker.gfx and picker.gfx.maps
    local seen = probeDraw(picker)
    label(maps and seen.map == maps.johto, "nokanto_draws_johto_art")
    label(seen.icons == 0, "nokanto_no_player_icon", seen.icons)
    wait(8)
    assert(U.still(game, out .. "/01-route27-fly-johto-map-new-bark.png"))

    tap("b")
    settle(function() return top() == party end, "cancel back to party")
    save.engineFlags[indigoFlag] = true
    picker = openFly()
    label(picker.flyRegion == "kanto", "indigo_kanto_map", picker.flyRegion)
    row = picker:flyRow()
    label(row and row.spawn == "SPAWN_INDIGO", "indigo_default_indigo",
      row and row.spawn)
    maps = picker.gfx and picker.gfx.maps
    seen = probeDraw(picker)
    label(maps and seen.map == maps.kanto, "indigo_draws_kanto_art")
    label(seen.icons > 0, "indigo_player_icon", seen.icons)
    wait(8)
    assert(U.still(game, out .. "/02-route27-fly-kanto-map-indigo.png"))
    tap("b")
    settle(function() return top() == party end, "second cancel")
  end, debug.traceback)

  game.speedOverride = speed
  love.audio.setVolume(volume)
  for _, key in ipairs({ "writeSave", "writeOptions", "persistOptions" }) do
    game[key] = writes[key]
  end
  if not ok then
    fails = fails + 1
    print("FAIL driver_error " .. tostring(err))
  end
  print(fails == 0 and "PASS gen2_fly_kanto_pre_indigo_bug2646"
    or ("FAIL gen2_fly_kanto_pre_indigo_bug2646 " .. fails .. " failures"))
  love.event.quit(fails == 0 and 0 or 1)
  while true do coroutine.yield() end
end
