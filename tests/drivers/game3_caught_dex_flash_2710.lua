local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("game3_caught_dex_flash_2710", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_caught_dex_flash_2710")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Pokedex = require("src.ui.game3.rse.pokedex")
  local Gfx = require("src.ui.game3.rse.pokedex_gfx")
  local session = Runtime.getSession()
  local version = session.version
  local rs = version == "ruby" or version == "sapphire"
  local C = require("src.core.game3.constants").of(version)

  local function rgb(c)
    local r, g, b = Gfx.rgb8(c)
    return string.format("%d,%d,%d", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
  end
  local function pixels(s)
    local canvas = love.graphics.newCanvas(240, 160)
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.origin()
    Pokedex.draw(s)
    love.graphics.pop()
    local data = canvas:newImageData()
    return function(x, y)
      local r, g, b = data:getPixel(x, y)
      return string.format("%d,%d,%d", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
    end
  end

  local s = Pokedex.showCaughtMon(C:require("species", "SPECIES_WURMPLE"), { session = session })
  for _ = 1, 600 do
    if s.fn == "caughtInput" then break end
    U.wait(1)
  end
  if not S.check(s.fn == "caughtInput", version .. " caught page reached input") then return S.finish() end

  local slot = rs and 80 or 48
  local function phaseSet(pal)
    local set = {}
    for i = 1, 7 do set[rgb(pal[slot + i])] = true end
    return set
  end
  local offSet, onSet = phaseSet(s.caught.offPal), phaseSet(s.caught.onPal)
  local read = {}
  for _, at in ipairs({ { 8, "base" }, { 24, "gray" } }) do
    for _ = 1, 200 do
      if (s.caught.palTimer or 0) >= at[1] then break end
      U.wait(1)
    end
    S.check(s.caught.palTimer == at[1], version .. " palette timer reached " .. at[1])
    local px = pixels(s)
    -- pokeruby/src/pokedex.c:3900, pokeemerald/src/pokedex.c:4039
    read[at[2]] = { panel = px(84, 124), bar = px(rs and 8 or 3, 130) }
    S.check(U.still(game, S.dir .. "/2710_0" .. (at[1] == 8 and 1 or 2) .. "_" .. version .. "_caught_dex_" .. at[2] .. "_phase.png"),
      version .. " " .. at[2] .. " phase shot")
  end
  S.check(read.base.panel == read.gray.panel and read.base.panel ~= "0,0,0",
    version .. " description panel holds one non-black color (" .. read.base.panel .. " / " .. read.gray.panel .. ")")
  S.check(offSet[read.base.bar] == true, version .. " bar shows the base phase color at timer 8 (" .. read.base.bar .. ")")
  S.check(onSet[read.gray.bar] == true, version .. " bar shows the gray phase color at timer 24 (" .. read.gray.bar .. ")")
  S.check(read.base.bar ~= read.gray.bar, version .. " bar flashes between phases")
  U.tap(game, "b")
  U.wait(60)
  S.finish()
end
