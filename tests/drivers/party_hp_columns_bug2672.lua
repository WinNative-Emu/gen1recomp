-- engine/menus/party_menu.asm:71
-- engine/menus/party_menu.asm:93
-- engine/pokemon/status_screen.asm:46
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local PartyMenu = require("src.ui.PartyMenu")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local Font = require("src.render.Font")

  local failed = false
  local function check(label, ok)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = true end
    return ok
  end

  local party = {}
  for i, sp in ipairs({ "NIDOKING", "BULBASAUR", "MAGIKARP" }) do
    local mon = Pokemon.new(game.data, sp, 50)
    mon.stats.hp = 266
    mon.hp = 266
    party[i] = mon
  end
  game.save.party = party
  game.save.player.name = game.save.player.name or "RED"

  U.teleport(game, "PALLET_TOWN", 10, 12, "down")
  U.wait(10)

  local function render(drawFn)
    local c = love.graphics.newCanvas(160, 144)
    love.graphics.setCanvas(c)
    love.graphics.clear(1, 1, 1, 1)
    love.graphics.setColor(1, 1, 1, 1)
    drawFn()
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    return c:newImageData()
  end

  local function ink(id, x0, y0, x1, y1)
    local n = 0
    for y = y0, y1 do
      for x = x0, x1 do
        local r, g, b = id:getPixel(x, y)
        if r + g + b < 2.7 then n = n + 1 end
      end
    end
    return n
  end

  local function sameInk(a, b, x0, y0, x1, y1)
    for y = y0, y1 do
      for x = x0, x1 do
        local ra, ga, ba = a:getPixel(x, y)
        local rb, gb, bb = b:getPixel(x, y)
        if (ra + ga + ba < 2.7) ~= (rb + gb + bb < 2.7) then return false end
      end
    end
    return true
  end

  Screens.push(game, "PartyMenu", {})
  U.wait(12)
  local pm = game.stack:top()
  check("party_list_open", getmetatable(pm) == PartyMenu)

  if getmetatable(pm) == PartyMenu then
    local id = render(function() pm:draw() end)
    for i = 1, #party do
      local hy = PartyMenu.entryY(i) + 8
      check(("row%d_col3_blank_under_name_start"):format(i),
            ink(id, 24, hy, 31, hy + 7) == 0)
      check(("row%d_hp_tile_at_col4"):format(i), ink(id, 32, hy, 39, hy + 7) > 0)
      check(("row%d_cap_at_col12"):format(i), ink(id, 96, hy, 103, hy + 7) > 0)
      local frac = render(function()
        love.graphics.setColor(0, 0, 0, 1)
        Font.draw(("%3d/%3d"):format(party[i].hp, party[i].stats.hp), 104, hy)
      end)
      check(("row%d_col13_is_fraction_only"):format(i),
            sameInk(id, frac, 104, hy, 111, hy + 7))
    end
    U.still(game, DIR .. "/2672_01_party_hp_bar_gap_before_fraction.png")
  end

  game.stack:pop()
  U.wait(4)
  Screens.push(game, "PartyMenu", { tmhm = { move = "SWORDS_DANCE", kind = "TM" } })
  U.wait(12)
  local tm = game.stack:top()
  check("tm_list_open", getmetatable(tm) == PartyMenu and tm.tmhm ~= nil)
  if getmetatable(tm) == PartyMenu then
    local id = render(function() tm:draw() end)
    for i = 1, #party do
      local hy = PartyMenu.entryY(i) + 8
      check(("tm_row%d_learn_text_starts_col12"):format(i),
            ink(id, 88, hy, 95, hy + 7) == 0 and ink(id, 96, hy, 103, hy + 7) > 0)
    end
    U.still(game, DIR .. "/2672_02_tm_able_not_able_col12.png")
  end

  print(failed and "FAIL party_hp_columns_bug2672" or "PASS party_hp_columns_bug2672")
  love.event.quit(failed and 1 or 0)
end
