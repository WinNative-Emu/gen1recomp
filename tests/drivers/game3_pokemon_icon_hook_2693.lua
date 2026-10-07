local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_pokemon_icon_hook_2693"

local MOD_ICON = "mod_icon_2693.png"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS pokemon_icon_hook_2693")
    love.event.quit(0)
  else
    print("FAIL pokemon_icon_hook_2693 failures=" .. failures)
    love.event.quit(1)
  end
end

local function writeModIcon()
  local data = love.image.newImageData(32, 64)
  data:mapPixel(function(x, y)
    if x < 4 or x > 27 or y % 32 < 4 or y % 32 > 27 then return 0, 0, 0, 0 end
    if y < 32 then return 1, 0, 1, 1 end
    return 0, 1, 1, 1
  end)
  data:encode("png", MOD_ICON)
end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Session = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Oam = require("src.core.game3.oam")
  local PartyMenu = require("src.ui.game3.party_menu")
  local Runtime = require("src.mods.Runtime")
  local Hooks = require("src.mods.Hooks")

  local session = Session.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.party = {}
  Party.giveMon(session, 25, 10)
  Party.giveMon(session, 4, 10)

  writeModIcon()
  if not Runtime.hooks.chains then Runtime.hooks = Hooks.new() end
  local fired, mons = 0, 0
  local mode = "swap"
  Runtime.hooks:wrap("pokemon.icon", function(next, path, ctx)
    fired = fired + 1
    if ctx.mon then mons = mons + 1 end
    if ctx.gen3Species ~= 25 then return next(path, ctx) end
    if mode == "hide" then return nil end
    return MOD_ICON
  end)

  PartyMenu.show(session.party, nil, { session = session })
  U.wait(30)

  local function monSprite(i)
    local slot = PartyMenu._oam and PartyMenu._oam[i]
    return slot and slot.mon and Oam.get(slot.mon)
  end

  result(fired > 0, "the party menu raised pokemon.icon")
  result(mons > 0, "with ctx.mon set")
  local Pokemon = require("src.core.game3.pokemon")
  local swapped = Pokemon.monIcon(session.party[1])
  result(swapped and swapped.path == MOD_ICON, "the lead's icon entry is the mod image")
  local s1 = monSprite(1)
  result(s1 ~= nil and swapped ~= nil and s1.image == swapped.image,
    "the lead's party sprite draws the mod image")
  local s2 = monSprite(2)
  local vanilla = Pokemon.monIcon(session.party[2])
  result(s2 ~= nil and vanilla ~= nil and vanilla.path == nil and s2.image == vanilla.image,
    "slot 2 keeps its vanilla icon")
  U.shot(game, DIR .. "/2693_01_party_mod_icon.png")

  mode = "hide"
  PartyMenu.close()
  U.wait(10)
  PartyMenu.show(session.party, nil, { session = session })
  U.wait(30)
  s1 = monSprite(1)
  local blank = Pokemon.monIcon(session.party[1])
  result(blank ~= nil and blank.blank == true, "a nil return gives a blank icon, not nil")
  result(s1 ~= nil and s1.image == blank.image, "the lead's sprite draws the blank icon")
  U.shot(game, DIR .. "/2693_02_party_hidden_icon.png")

  PartyMenu.close()
  U.wait(10)
  finish()
end
