local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("game3_rs_naming_kb_top_2701", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_rs_naming_kb_top_2701")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Naming = require("src.ui.game3.naming")
  local version = Runtime.getSession().version
  local C = require("src.core.game3.constants").of(version)

  local function pixels()
    local canvas = love.graphics.newCanvas(240, 160)
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.origin()
    Naming.draw()
    love.graphics.pop()
    local data = canvas:newImageData()
    return function(x, y)
      local r, g, b = data:getPixel(x, y)
      return string.format("%d,%d,%d", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
    end
  end

  for _, spec in ipairs({
    { template = "PLAYER", shot = "2701_01_" .. version .. "_player_kb_top_rim.png" },
    { template = "NICKNAME", species = C:require("species", "SPECIES_PIKACHU"), shot = "2701_02_" .. version .. "_nickname_kb_top_rim.png" },
  }) do
    local title = spec.species and Naming.monTitle(require("src.core.game3.pokemon").name(spec.species)) or nil
    Naming.open({ template = spec.template, species = spec.species, title = title, session = Runtime.getSession() })
    U.wait(40)
    local px = pixels()
    -- pokeruby/src/naming_screen.c:1677
    S.check(px(100, 67) == px(100, 142), spec.template .. " top rim row 67 matches bottom rim row 142 ("
      .. px(100, 67) .. " vs " .. px(100, 142) .. ")")
    S.check(px(100, 68) == px(100, 141), spec.template .. " top frame row 68 matches bottom frame row 141 ("
      .. px(100, 68) .. " vs " .. px(100, 141) .. ")")
    S.check(px(100, 67) ~= px(100, 75), spec.template .. " rim differs from panel fill (" .. px(100, 75) .. ")")
    S.check(U.still(game, S.dir .. "/" .. spec.shot), spec.template .. " keyboard shot")
    Naming.dismiss()
    U.wait(30)
  end
  S.finish()
end
