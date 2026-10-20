local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")

local NAME = "api3_gen3_art"
local S = F.new(NAME, os.getenv("POKEPORT_SHOT_DIR") or "/tmp/" .. NAME)

local MOD = "api3art"
local ROOT = "mods/" .. MOD

local PLAYER_GFX = {
  firered = "OBJ_EVENT_GFX_RED_NORMAL", leafgreen = "OBJ_EVENT_GFX_GREEN_NORMAL",
  emerald = "OBJ_EVENT_GFX_BRENDAN_NORMAL", ruby = "OBJ_EVENT_GFX_BRENDAN_NORMAL",
  sapphire = "OBJ_EVENT_GFX_BRENDAN_NORMAL",
}

local function mainFor(version)
  return string.format([[
local mod = ...
mod.content.sprites:register("API3_NPC", { image = "mods/api3art/npc.png", frames = 6, walker = true, trueColor = true })
mod.content.sprites:register("API3_PLAIN", { image = "mods/api3art/npc.png", frames = 6, walker = true })
mod.content.pokemon:patch("CHARMANDER", { spriteFront = "mods/api3art/front.png", spriteBack = "mods/api3art/back.png" })
mod.content.palettes:register("SQUIRTLEMON", { {255,255,0}, {0,255,0}, {0,0,255}, {0,0,0} })
mod.content.palettes:register("SQUIRTLEMON_SHINY", { {255,255,255}, {255,0,0}, {0,0,255}, {0,0,0} })
mod.content.palettes:register("%s", { {255,255,0}, {0,255,0}, {0,0,255}, {0,0,0} })
mod.content.font:register("api3page", { image = "mods/api3art/font.png", base = 768, glyphsPerRow = 2, advance = 9 })
mod.content.font:register("charmap:hash", { seq = "#", code = 768 })
mod.content.font:register("ttf", {})
]], PLAYER_GFX[version])
end

local function png(path, w, h, painter)
  local data = love.image.newImageData(w, h)
  painter(data)
  local file = data:encode("png")
  love.filesystem.write(path, file:getString())
end

local function writeMod(version)
  love.filesystem.createDirectory(ROOT)
  love.filesystem.write(ROOT .. "/manifest.json",
    '{"id":"api3art","name":"api3 art","version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}')
  love.filesystem.write(ROOT .. "/main.lua", mainFor(version))
  png(ROOT .. "/npc.png", 16, 96, function(d)
    for f = 0, 5 do
      for y = 2, 15 do
        for x = 3, 12 do d:setPixel(x, f * 16 + y, 1, 0, 1, 1) end
      end
      for y = 4, 6 do
        for x = 5, 10 do d:setPixel(x, f * 16 + y, 1, 1, 0, 1) end
      end
    end
  end)
  png(ROOT .. "/font.png", 16, 8, function(d)
    for y = 0, 7 do
      for x = 0, 7 do d:setPixel(x, y, 0, 0, 0, 1) end
    end
    for i = 0, 7 do d:setPixel(8 + i, i, 0, 0, 0, 1) end
  end)
  png(ROOT .. "/front.png", 64, 64, function(d)
    for y = 6, 58 do
      for x = 6, 58 do d:setPixel(x, y, 0.1, 0.9, 0.9, 1) end
    end
    for y = 16, 30 do
      for x = 16, 30 do d:setPixel(x, y, 1, 1, 1, 1) end
    end
  end)
  png(ROOT .. "/back.png", 64, 64, function(d)
    for y = 6, 58 do
      for x = 6, 58 do d:setPixel(x, y, 0.9, 0.2, 0.9, 1) end
    end
  end)
end

local function reloadMods(game)
  for _, key in ipairs({ "type_chart", "growth_rates", "evolution_methods" }) do game.data[key] = nil end
  local ok, err = pcall(function() game:_loadMods() end)
  if not ok then S.note("loadMods error: " .. tostring(err)) end
  return ok
end

local function loadShot(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local bytes = f:read("*a")
  f:close()
  local ok, data = pcall(function()
    return love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
  end)
  return ok and data or nil
end

local function countIn(data, pred, box)
  local n = 0
  local w, h = data:getDimensions()
  local x0, y0, x1, y1 = 0, 0, w - 1, h - 1
  if box then
    local sx, sy = w / 240, h / 160
    x0, y0 = math.max(0, math.floor(box[1] * sx)), math.max(0, math.floor(box[2] * sy))
    x1, y1 = math.min(w - 1, math.floor(box[3] * sx)), math.min(h - 1, math.floor(box[4] * sy))
  end
  for y = y0, y1 do
    for x = x0, x1 do
      local r, g, b, a = data:getPixel(x, y)
      if a > 0 and pred(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)) then
        n = n + 1
      end
    end
  end
  return n
end

local function countAll(data, pred) return countIn(data, pred) end

local PLAYER_BOX = { 113, 69, 131, 85 }

local function isPink(r, g, b) return r > 200 and g > 30 and g < 80 and b > 200 end

local function isMagenta(r, g, b) return r > 217 and g < 38 and b > 217 end
local function isYellow(r, g, b) return r == 255 and g == 255 and b == 0 end
local function isGreen(r, g, b) return r == 0 and g == 255 and b == 0 end
local function isRedDominant(r, g, b) return r > 150 and r > g + 60 and r > b + 60 end
local function isCyan(r, g, b) return r < 40 and g > 200 and b > 200 end
local function onRamp(r, _, b) return r == 0 or b == 0 end

local function sheetPixels(image, w, h)
  local canvas = love.graphics.newCanvas(w, h)
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image, 0, 0)
  love.graphics.setCanvas()
  love.graphics.pop()
  local data = canvas:newImageData()
  canvas:release()
  return data
end

local function opaque(data)
  return countAll(data, function() return true end)
end

local function allOnRamp(data)
  return opaque(data) > 0 and countAll(data, onRamp) == opaque(data)
end

local function textPixels(FrlgFont, text)
  local canvas = love.graphics.newCanvas(96, 20)
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  FrlgFont.draw(text, 1, 1, {})
  love.graphics.setCanvas()
  love.graphics.pop()
  local data = canvas:newImageData()
  canvas:release()
  return data
end

local function sameImage(a, b)
  local w, h = a:getDimensions()
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r1, g1, b1, a1 = a:getPixel(x, y)
      local r2, g2, b2, a2 = b:getPixel(x, y)
      if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 or a1 ~= a2 then return false end
    end
  end
  return true
end


local function modLoaded(game)
  return game.data.sprites ~= nil and game.data.sprites.API3_NPC ~= nil
end

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  local version = session.version
  local C = require("src.core.game3.constants").active(session)
  local frlg = version == "firered" or version == "leafgreen"
  local mapId = frlg and "FR_PALLET_TOWN" or "EM_ROUTE101"
  local ox, oy = 8, 8
  if not frlg then ox, oy = 10, 12 end
  local Pokemon = require("src.core.game3.pokemon")
  local OwSprites = require("src.core.game3.ow_sprites")
  local WorldAPI = require("src.world.game3.WorldAPI")
  local FrlgFont = require("src.ui.game3.frlg_font")
  local FontMods = require("src.ui.game3.font_mods")
  local nativeText, nativeWidth

  S.check(F.goTo(game, mapId, ox, oy, "down"), "in " .. mapId)
  U.wait(30)

  local gid = C.event_objects.byName[PLAYER_GFX[version]]
  local squirtle = C.species.byName.SPECIES_SQUIRTLE
  local bulbasaur = C.species.byName.SPECIES_BULBASAUR
  local charmander = C.species.byName.SPECIES_CHARMANDER

  if modLoaded(game) then
    S.note("mod already present at boot")
  else
    local front = Pokemon.frontPic(squirtle)
    S.check(front ~= nil, "native Squirtle front pic loads")
    local native = sheetPixels(front.image, 64, 64)
    S.check(countAll(native, onRamp) < opaque(native), "native Squirtle art is full colour")
    S.check(S.still(game, "00_native_player.png"), "shot 00_native_player.png")
    nativeText = textPixels(FrlgFont, "AB#")
    nativeWidth = FrlgFont.measure("AB#")
    local nativeShot = loadShot(S.dir .. "/00_native_player.png")
    S.check(nativeShot ~= nil and countIn(nativeShot, isRedDominant, PLAYER_BOX) > 40,
      "native overworld player has red pixels")
    writeMod(version)
    S.check(reloadMods(game), "mod loaded into the live Data")
  end
  S.check(modLoaded(game), "data.sprites has API3_NPC")
  S.check(game.data.gen3Palettes ~= nil and game.data.gen3Palettes.SQUIRTLEMON ~= nil,
    "data.palettes routes to gen3Palettes")
  U.wait(20)

  local world = WorldAPI.new(game, MOD)
  local id1 = world:spawnNpc(mapId, { x = ox, y = oy + 2, sprite = "API3_NPC", facing = "up",
    movement = "MOVEMENT_TYPE_FACE_UP" })
  S.check(id1 ~= nil, "mod NPC spawned with sprite API3_NPC: " .. tostring(id1))
  local id2 = world:spawnNpc(mapId, { x = ox + 3, y = oy + 2, sprite = "API3_PLAIN", facing = "up",
    movement = "MOVEMENT_TYPE_FACE_UP" })
  S.check(id2 ~= nil, "mod NPC spawned from a record without trueColor: " .. tostring(id2))
  U.wait(20)
  S.check(S.still(game, "01_mod_sprites_and_recoloured_player.png"),
    "shot 01_mod_sprites_and_recoloured_player.png")
  local shot = loadShot(S.dir .. "/01_mod_sprites_and_recoloured_player.png")
  S.check(shot ~= nil, "shot decodes")
  if shot then
    local n = countAll(shot, isMagenta)
    S.check(n >= 3000, "both mod NPC sprites draw with true colour (magenta " .. n .. ")")
    S.check(countIn(shot, isRedDominant, PLAYER_BOX) == 0, "no native red left on the recoloured player")
    S.check(countIn(shot, isYellow, PLAYER_BOX) > 0, "palette highlight colour present in the shot")
  end

  local spr = OwSprites.get(gid)
  S.check(spr ~= nil and spr.nativeImageData ~= nil, "overworld sheet went through the palette seam")
  if spr then
    local sheet = sheetPixels(spr.image, spr.width, spr.height * spr.frameCount)
    S.check(allOnRamp(sheet), "every overworld pixel sits on the mod ramp")
  end

  local front = Pokemon.frontPic(squirtle)
  S.check(allOnRamp(sheetPixels(front.image, 64, 64)), "Squirtle front pic follows SQUIRTLEMON")
  local back = Pokemon.backPic(squirtle)
  S.check(allOnRamp(sheetPixels(back.image, 64, 64)), "Squirtle back pic follows SQUIRTLEMON")
  local shiny = Pokemon.frontPic(squirtle, nil, true)
  local sdata = sheetPixels(shiny.image, 64, 64)
  S.check(opaque(sdata) > 0 and countAll(sdata, function(r, g, b)
    return r > 0 and r > g and g == b
  end) > 0, "Squirtle shiny pic follows SQUIRTLEMON_SHINY (red ramp)")
  local bulb = sheetPixels(Pokemon.frontPic(bulbasaur).image, 64, 64)
  S.check(countAll(bulb, onRamp) < opaque(bulb), "a species with no palette record keeps its native art")

  S.check(countAll(sheetPixels(Pokemon.frontPic(charmander).image, 64, 64), isCyan) > 1000,
    "Charmander front pic is the mod art")
  S.check(countAll(sheetPixels(Pokemon.backPic(charmander).image, 64, 64), isPink) > 1000,
    "Charmander back pic is the mod art")

  local modText = textPixels(FrlgFont, "AB#")
  S.check(FontMods.active(), "font registry reached the Gen 3 text renderer")
  S.check(FrlgFont.measure("#") == 9, "page glyph advance is the record's advance")
  S.check(FrlgFont.measure("A") == FontMods.ttfAdvance("A") and FrlgFont.measure("A") ~= 0,
    "ttf advance drives measure")
  local fgc = FrlgFont.COLOR.NORMAL.fg
  local fr, fg, fb = math.floor(fgc[1] * 255 + 0.5), math.floor(fgc[2] * 255 + 0.5), math.floor(fgc[3] * 255 + 0.5)
  S.check(countAll(textPixels(FrlgFont, "#"), function(r, g, b) return r == fr and g == fg and b == fb end) >= 60, "charmap row draws the page glyph in the text colour")
  if nativeText then
    S.check(not sameImage(nativeText, modText), "mod font changes the rendered string")
    FrlgFont.setModFont(nil)
    S.check(sameImage(nativeText, textPixels(FrlgFont, "AB#")) and FrlgFont.measure("AB#") == nativeWidth,
      "with the font records removed the text is native again")
    FrlgFont.setModFont(game.data.gen3Font)
    S.check(sameImage(modText, textPixels(FrlgFont, "AB#")), "font records restored")
  end
  local OptionMenu = require("src.ui.game3.option_menu")
  OptionMenu.show({ session = session, game = game })
  U.wait(20)
  S.check(S.still(game, "04_ttf_option_menu.png"), "shot 04_ttf_option_menu.png")
  U.tap(game, "b")
  U.wait(20)

  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  session.party = {}
  Party.giveMon(session, squirtle, 12, "SQUIRTLE")
  session.party[1].hp = session.party[1].maxHp or session.party[1].hp
  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = charmander, level = 8 }, {})
  S.check(ok == true, "wild battle started " .. tostring(err or ""))
  local reached, last = false, 0
  for i = 1, 6000 do
    if Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu" then reached = true break end
    if Ui.dialogPending and Ui.dialogPending() and i - last >= 14 then
      last = i
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end
  S.check(reached, "battle reached the command menu")
  U.wait(40)
  S.check(S.still(game, "02_battle_mod_pic_and_recoloured_back.png"),
    "shot 02_battle_mod_pic_and_recoloured_back.png")
  local bshot = loadShot(S.dir .. "/02_battle_mod_pic_and_recoloured_back.png")
  S.check(bshot ~= nil, "battle shot decodes")
  if bshot then
    S.check(countAll(bshot, isCyan) > 2000, "enemy front pic on screen is the mod art")
    S.check(countAll(bshot, isYellow) + countAll(bshot, isGreen) > 100,
      "player back pic on screen wears the SQUIRTLEMON ramp")
  end
  Battle.abort("run")
  for _ = 1, 600 do
    if not Battle.isActive() then break end
    U.wait(1)
  end
  U.wait(60)

  local Objects = require("src.core.game3.objects")
  local Space = require("src.core.game3.scripting.space")
  local Player = require("src.core.game3.player")
  local pick
  for _, eo in ipairs(Objects.forDraw()) do
    if not eo.def.runtime and not eo.invisible and not eo.hidden and eo.visible ~= false
        and (tonumber(eo.graphicsId) or 0) < 200 and Space.objectVisible(eo.def) then
      pick = eo
      break
    end
  end
  S.check(pick ~= nil, "found a template NPC to reskin")
  if pick then
    local lid = pick.localId
    S.check(F.goTo(game, mapId, ox, oy, "down"), "back at the start cell")
    U.wait(30)
    local handle = world:npc(mapId, lid)
    S.check(handle ~= nil, "WorldAPI resolved the template NPC")
    if handle then
      S.check(handle:placeAt(ox - 3, oy, "down") == true, "template NPC placed beside the player")
      S.check(handle:setAppearance("API3_NPC") == true, "setAppearance accepts the mod sprite")
      U.wait(2)
      S.check(S.still(game, "03_template_npc_reskinned.png"), "shot 03_template_npc_reskinned.png")
      local reskin = loadShot(S.dir .. "/03_template_npc_reskinned.png")
      S.check(reskin ~= nil and countIn(reskin, isMagenta, { 48, 56, 80, 100 }) > 500,
        "template NPC now draws the mod sprite")
    end
  end
  S.finish()
end
