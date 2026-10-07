local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_soak_2695"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local MAPS = {
  emerald = { "EM_LITTLEROOT_TOWN", "EM_ROUTE101", "EM_OLDALE_TOWN", "EM_ROUTE102", "EM_PETALBURG_CITY",
    "EM_ROUTE104", "EM_RUSTBORO_CITY", "EM_DEWFORD_TOWN", "EM_SLATEPORT_CITY", "EM_ROUTE110", "EM_MAUVILLE_CITY",
    "EM_VERDANTURF_TOWN", "EM_FALLARBOR_TOWN", "EM_LAVARIDGE_TOWN", "EM_FORTREE_CITY", "EM_LILYCOVE_CITY",
    "EM_MOSSDEEP_CITY", "EM_SOOTOPOLIS_CITY", "EM_PACIFIDLOG_TOWN", "EM_ROUTE113", "EM_ROUTE119", "EM_ROUTE120",
    "EM_ROUTE123", "EM_ROUTE124", "EM_ROUTE134" },
  firered = { "FR_PALLET_TOWN", "FR_ROUTE_1", "FR_VIRIDIAN_CITY", "FR_ROUTE_2", "FR_VIRIDIAN_FOREST",
    "FR_PEWTER_CITY", "FR_CERULEAN_CITY", "FR_VERMILION_CITY", "FR_LAVENDER_TOWN", "FR_CELADON_CITY",
    "FR_SAFFRON_CITY", "FR_FUCHSIA_CITY", "FR_CINNABAR_ISLAND", "FR_POKEMON_TOWER_6F", "FR_SEAFOAM_ISLANDS_B3F",
    "FR_ROUTE_18", "FR_OAKS_LAB", "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F" },
}
MAPS.leafgreen = MAPS.firered

return function(game)
  local ok, err = xpcall(function()
    local function untilReady(fn, label, limit)
      for _ = 1, limit or 3000 do if fn() then return end; U.wait(1) end
      error("did not settle: " .. label)
    end
    untilReady(function() return game.phase == "boot" and game.boot end, "boot")
    game:_handleBootAction({ action = "new_game", name = "MAY", gender = 1 })
    local Runtime = require("src.core.game3.runtime")
    local Party = require("src.core.game3.party")
    local Pokemon = require("src.core.game3.pokemon")
    local Bridge = require("src.core.game3.battle_bridge")
    local Battle = require("src.core.game3.battle")
    local Anim = require("src.core.game3.battle.anim")
    local Map = require("src.core.game3.map")
    local Native = require("src.core.game3.tileset_native")
    local version = require("src.core.GameVersion").get()
    local maps = MAPS[version] or MAPS.emerald
    untilReady(function() return Runtime.getSession() and game.phase == "field" end, "field")
    local Fade = require("src.ui.game3.fade")
    untilReady(function() return not Fade.isActive() and Fade.t == 0 and not Fade.lockInput end, "uncovered")
    local session = Runtime.getSession()
    session.party = {}
    assert(Party.giveMon(session, 277, 60))
    session.party[1].moves = { 53, 0, 0, 0 }; session.party[1].pp = { 15, 0, 0, 0 }
    require("src.core.game3.encounters").onStep = function() return nil end

    local function resident()
      local n = 0
      for _ in pairs(Native._pairs or {}) do n = n + 1 end
      return n
    end

    local function texMB()
      collectgarbage("collect"); collectgarbage("collect")
      return (love.graphics.getStats().texturememory or 0) / 1048576
    end

    local draws = 0
    local origDraw = love.draw
    love.draw = function(...)
      draws = draws + 1
      return origDraw(...)
    end
    local function waitDraws(n)
      local target = draws + n
      for _ = 1, 20000 do
        if draws >= target then return end
        U.wait(1)
      end
    end

    local maxPairs, warped = 0, 0
    local function warp(mapId)
      local okL, e = pcall(function() Map.load(nil, game, mapId, { x = 10, y = 10, facing = "down" }) end)
      if not okL then print("[driver] Map.load " .. mapId .. ": " .. tostring(e)) return end
      local s = Runtime.getSession()
      if s then s.x, s.y, s.facing = 10, 10, "down" end
      U.wait(30)
      waitDraws(3)
      warped = warped + 1
      local n = resident()
      if n > maxPairs then maxPairs = n end
      if os.getenv("SOAK_VERBOSE") then
        local names, world = {}, {}
        for p in pairs(Native._pairs) do names[#names + 1] = p end
        local x0, y0, x1, y1 = Map.warmRect()
        for _, entry in ipairs(Map.world or {}) do
          local def = entry.def
          local p = def and (def.pair or (def.midLayout and def.midLayout.pair))
          if p and Map.warmNear(entry, x0, y0, x1, y1) then world[p] = true end
        end
        local wl = {}
        for p in pairs(world) do wl[#wl + 1] = p end
        print("[driver] " .. mapId .. " pairs=" .. n .. " {" .. table.concat(names, " ") .. "} warm={" .. table.concat(wl, " ") .. "}")
      end
    end

    local function dex()
      for sp = 1, 411 do
        Pokemon.frontPic(sp); Pokemon.backPic(sp)
        Pokemon.frontPic(sp, 0, true); Pokemon.backPic(sp, 0, true)
        if sp % 20 == 0 then U.wait(1) end
      end
      for i = 1, 50 do Pokemon.frontPic(Pokemon.SPECIES_SPINDA, 0, false, i * 7919) end
    end

    local function battle(species)
      local s = Runtime.getSession()
      s.party[1].hp = s.party[1].maxHp
      assert(Bridge.startWild(Runtime._mod, game, { species = species, level = 2, moves = { 150 }, pp = { 40 } },
        { fade = false }), "battle start")
      local frames = 0
      while Battle.isActive() do
        frames = frames + 1
        if frames > 20000 then error("battle bound") end
        if Anim.vm() and Anim.vm():busy() then U.wait(1) else U.tap(game, "a"); U.wait(3) end
      end
      untilReady(function() return game.phase == "field" end, "battle writeback")
      U.wait(20)
    end

    local function pics(store)
      local n = 0
      for _, v in pairs(store or {}) do if type(v) == "table" then n = n + 1 end end
      return n
    end

    local tex = {}
    for pass = 1, 2 do
      dex()
      for _, m in ipairs(maps) do warp(m) end
      for _, sp in ipairs({ 263, 265, 270, 273 }) do battle(sp) end
      warp(maps[1])
      tex[pass] = texMB()
      print(string.format("[driver] pass %d texMB=%.2f pairs=%d front=%d back=%d spinda=%d heapKB=%.0f", pass,
        tex[pass], resident(), pics(Pokemon._front), pics(Pokemon._back), pics(Pokemon._spindaPics),
        collectgarbage("count")))
    end
    U.shot(game, DIR .. "/2695_01_" .. version .. "_field_after_soak.png")

    check(warped == #maps * 2 + 2, "every soak map loaded (" .. warped .. "/" .. #maps * 2 + 2 .. ")")
    check(maxPairs <= 6, "resident tileset pairs stay at or under 6 (max " .. maxPairs .. ")")
    check(tex[2] <= tex[1] + 1, string.format("textures do not grow on pass 2 (%.2f -> %.2f MB)", tex[1], tex[2]))
    check(pics(Pokemon._front) <= 48, "front pic cache bounded (" .. pics(Pokemon._front) .. ")")
    check(pics(Pokemon._back) <= 48, "back pic cache bounded (" .. pics(Pokemon._back) .. ")")
    check(pics(Pokemon._spindaPics) <= 8, "spinda pic cache bounded (" .. pics(Pokemon._spindaPics) .. ")")
  end, debug.traceback)
  if not ok then
    print("[driver] error: " .. tostring(err))
    failures = failures + 1
  end
  print((failures == 0 and "PASS" or "FAIL") .. " game3_soak_2695 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end
