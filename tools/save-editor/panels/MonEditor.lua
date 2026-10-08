
local Theme = require("Theme")
local PAL = Theme.PAL
local Gen = require("Gen")

local MonEditor = {}

-- Front sprites are read straight off the generated cache.  One image per
-- species, cached for the process: the old panel called newImage every frame,
-- which re-decoded a PNG sixty times a second.
local spriteCache = {}
local SPINDA_CACHE_MAX = 16
local spindaKeys = {}

local function remember(key, value)
  spriteCache[key] = value
  if type(key) == "string" and key:find("^308:") then
    spindaKeys[#spindaKeys + 1] = key
    while #spindaKeys > SPINDA_CACHE_MAX do
      spriteCache[table.remove(spindaKeys, 1)] = nil
    end
  end
end

function MonEditor.spriteKey(S, species, mon)
  if not species then return nil end
  local letter = mon and require("Ops").unownForm(S, mon)
  if letter == nil and mon and Gen.ofState(S) == 3
      and tonumber(species) == require("src.core.game3.pokemon").SPECIES_SPINDA then
    return tostring(species) .. ":" .. tostring((tonumber(mon.personality) or 0) % 4294967296)
  end
  if letter == nil then return species end
  return tostring(species) .. ":" .. letter
end

function MonEditor.sprite(S, species, mon)
  if not species then return nil end
  local key = MonEditor.spriteKey(S, species, mon)
  local letter = key ~= species and require("Ops").unownForm(S, mon) or nil
  if spriteCache[key] ~= nil then return spriteCache[key] or nil end
  if Gen.ofState(S) == 3 then
    local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
    if okP and Pokemon then
      local spId = tonumber(species) or (Pokemon.speciesFromName and Pokemon.speciesFromName(tostring(species)))
      if spId then
        local picId = letter ~= nil and Pokemon.picSpecies(spId, mon.personality) or spId
        local pic = (Pokemon.frontPic and Pokemon.frontPic(picId, nil, nil, mon and mon.personality))
          or (Pokemon.icon and Pokemon.icon(picId))
        if pic and pic.image then
          remember(key, pic.image)
          return pic.image
        end
      end
    end
  end
  local def = S.data and S.data.pokemon and (S.data.pokemon[species] or (type(species) == "number" and S.data.pokemon[species]))
  local path = def and def.spriteFront
  if letter ~= nil and Gen.ofState(S) == 2 then
    path = require("src.core.gen2.Unown").formSprite(S.data.pokemon, letter) or path
  end
  if not path or not love.graphics.newImage then
    remember(key, false)
    return nil
  end
  local ok, img = pcall(love.graphics.newImage, path)
  remember(key, ok and img or false)
  return ok and img or nil
end

-- Draw a species sprite fitted into a box, or a dashed placeholder when the
-- cache has no art for it (a modded species, or a headless run).
function MonEditor.drawSprite(S, Kit, species, x, y, size, mon)
  local img = MonEditor.sprite(S, species, mon)
  if img and love.graphics.draw and img.getDimensions then
    local iw, ih = img:getDimensions()
    if iw > 0 and ih > 0 then
      local scale = math.min(size / iw, size / ih)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, x + (size - iw * scale) / 2,
        y + (size - ih * scale) / 2, 0, scale, scale)
      return
    end
  end
  Theme.col(PAL.blue, 0.1)
  love.graphics.rectangle("fill", x, y, size, size, 8 * Kit.scale, 8 * Kit.scale)
  Theme.col(PAL.cardBorder, 0.35)
  Theme.dashed(x, y, size, size, 8 * Kit.scale, 5 * Kit.scale, 4 * Kit.scale)
  Kit.textCenter("micro", tostring(species or "?"):sub(1, 3), x,
    y + size / 2 - Kit.textHeight("micro") / 2, size, PAL.muted)
end

function MonEditor.isShiny(S, mon)
  if not mon then return false end
  local g = Gen.ofState(S)
  if g == 3 then
    if mon.isShiny ~= nil then return mon.isShiny == true end
    local ok, shiny = pcall(require("src.core.game3.pokemon").isShiny, mon)
    return ok and shiny == true
  elseif g == 2 then
    return require("src.pokemon.Stats").isShiny(mon.dvs)
  end
  return false
end

function MonEditor.displayName(S, mon)
  if mon.nickname and mon.nickname ~= "" then return mon.nickname end
  local def = S.data and S.data.pokemon and S.data.pokemon[mon.species or mon.speciesId]
  if def and def.name then return def.name end
  if type(mon.species) == "string" then return mon.species end
  if type(mon.name) == "string" and mon.name ~= "" then return mon.name end
  return tostring(mon.species or "POKEMON")
end

function MonEditor.draw(S, Kit, x, y, w, h, prelude)
  require("InspectorBody").draw(S, Kit, x, y, w, h, prelude)
end

return MonEditor
