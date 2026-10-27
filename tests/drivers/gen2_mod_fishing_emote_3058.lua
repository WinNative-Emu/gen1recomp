local U = require("tests.drivers.util")
local Assets = require("src.render.Assets")
local Map = require("src.world.gen2.Map")
local PackMenu = require("src.ui.gen2.PackMenu")
local Permissions = require("src.world.gen2.Permissions")
local StartMenu = require("src.ui.gen2.StartMenu")

local MOD = "mods/fish3058"
local PATCHED = MOD .. "/fishing_swapped.png"
local CART = "assets/generated/emotes/fishing.png"
local ROD = "OLD_ROD"
local MAPS = { "ROUTE_28", "VIRIDIAN_CITY", "ROUTE_43" }

local function installMod()
  local data = Assets.imageData(CART)
  data:mapPixel(function(_, _, r, g, b, a)
    if r < 0.1 then return 2 / 3, 2 / 3, 2 / 3, a end
    if r > 0.6 and r < 0.7 then return 0, 0, 0, a end
    return r, g, b, a
  end)
  love.filesystem.createDirectory(MOD)
  love.filesystem.write(PATCHED, data:encode("png"):getString())
  love.filesystem.write(MOD .. "/manifest.json",
    '{"id":"fish3058","name":"fish3058","version":"1.0.0",'
    .. '"api":3,"games":["all"],"entry":"main.lua"}')
  love.filesystem.write(MOD .. "/main.lua", ([[local mod = ...
mod.content.field:patch("emotes", { fishing = %q })]]):format(PATCHED))
end

return function(game)
  U.wait(45)
  if not love.filesystem.getInfo(MOD .. "/manifest.json") then
    installMod()
    print("INFO 3058 installed the probe mod, restarting so the boot loads it")
    love.event.quit("restart")
    return
  end

  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local function tap(btn, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = btn
    game.input.state[btn] = true
    U.wait(2)
    game.input.state[btn] = false
    U.wait(frames or 6)
  end

  local world = game.world
  local probe = game.mods and game.mods.mods and game.mods.mods.fish3058
  check(probe ~= nil and not probe.failed, "3058_mod_loaded_at_boot")
  local field = game.data.field
  check(field and field.emotes and field.emotes.fishing == PATCHED,
    "3058_field_emotes_patched")
  check(field and field.emotes and field.emotes.shock ~= nil,
    "3058_field_emotes_keep_cart_bubbles")
  check(game.data.gen2MenuGfx.emotes.fishing == PATCHED,
    "3058_menu_gfx_emotes_written_back")
  if not check(world and world.fishingSheet == PATCHED, "3058_world_fishing_sheet_patched") then
    love.event.quit(1)
    return
  end

  local function downShore(mapId)
    local def = world.maps and world.maps[mapId]
    local tileset = def and world.tilesets and world.tilesets[def.tileset]
    if not (def and tileset) then return nil end
    local probeMap = Map.new(def, tileset)
    local taken = {}
    for _, obj in ipairs(def.objects or {}) do taken[obj.x .. "," .. obj.y] = true end
    local function land(cx, cy)
      if not probeMap:inBounds(cx, cy) or taken[cx .. "," .. cy] then return false end
      local coll = probeMap:cellCollision(cx, cy)
      return Permissions.isWalkable(coll) and not Permissions.isWater(coll)
    end
    for cy = 0, probeMap.heightCells - 2 do
      for cx = 0, probeMap.widthCells - 1 do
        if land(cx, cy) and Permissions.isWater(probeMap:cellCollision(cx, cy + 1)) then
          return { x = cx, y = cy }
        end
      end
    end
    return nil
  end

  local mapId, shore
  for _, id in ipairs(MAPS) do
    shore = downShore(id)
    if shore then mapId = id break end
  end
  if not check(mapId ~= nil, "3058_found_shore") then
    love.event.quit(1)
    return
  end
  world.maps[mapId].fishGroup = "FISHGROUP_NONE"
  game.save.inventory = { [ROD] = 1 }
  game.save.bagOrder = { ROD }
  world:warpToMapId(mapId, shore.x, shore.y, "down")
  for _ = 1, 600 do
    if world.map and world.map.id == mapId and not world.mapSetup then break end
    U.wait(1)
  end
  U.wait(20)
  check(world.player.cellX == shore.x and world.player.cellY == shore.y,
    "3058_on_shore_facing_water")

  tap("start")
  local menu = game.stack:top()
  if not check(getmetatable(menu) == StartMenu, "3058_start_menu") then
    love.event.quit(1)
    return
  end
  for _ = 1, #menu.items do
    local row = menu.list and menu.list:current()
    if row and row.value == "pack" then break end
    tap("down", 4)
  end
  tap("a", 10)
  local pack
  for _ = 1, 120 do
    pack = game.stack:top()
    if getmetatable(pack) == PackMenu then break end
    U.wait(1)
  end
  if not check(getmetatable(pack) == PackMenu, "3058_pack_open") then
    love.event.quit(1)
    return
  end
  for _ = 1, 4 do
    if pack:pocket().id == "KEY_ITEM" then break end
    tap("right", 6)
  end
  for _ = 1, 20 do
    local row = pack.rows[pack.index]
    if row and row.id == ROD then break end
    tap("down", 4)
  end
  local row = pack.rows[pack.index]
  check(row ~= nil and row.id == ROD, "3058_cursor_on_old_rod")
  tap("a", 8)
  tap("a", 10)

  for _ = 1, 600 do
    if world.player.fishing == true and getmetatable(game.stack:top()) ~= PackMenu then break end
    U.wait(1)
  end
  for _ = 1, 600 do
    if not world.fade and not world.mapSetup then break end
    U.wait(1)
  end
  check(not world.fade, "3058_screen_not_faded " .. tostring(world.fade))
  check(world.player.fishing == true, "3058_fishing_pose_up")
  check(world.player.fishSheet == PATCHED, "3058_pose_drawn_from_patched_sheet")
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2_mod_fishing_emote_3058"
  check(U.still(game, dir .. "/3058_01_patched_fishing_pose.png"), "3058_patched_pose_shot")
  love.event.quit(failures == 0 and 0 or 1)
end
