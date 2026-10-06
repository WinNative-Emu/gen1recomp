return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Probe = dofile("tests/drivers/shot_probe.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local GameVersion = require("src.core.GameVersion")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "."

  local fails = 0
  local function check(cond, label)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. label)
  end

  local savedVer = GameVersion.get()
  game.save.options = game.save.options or {}
  game.save.options.colors = "ogred"
  PaletteFX.setMode("ogred")

  local function visit(version, shotName)
    GameVersion.set(version)
    U.teleport(game, "OAKS_LAB", 5, 5, "up")
    U.wait(60)
    local base = PaletteFX.ogObjBase()
    local shot = Probe.grab()
    if not shot then
      check(false, version .. " screen probe available")
    else
      local counts = Probe.count(shot, {
        light = base[2], dark = base[3],
      }, 1)
      U.log(version, "OBJ light px", counts.light, "OBJ dark px", counts.dark)
      check(counts.dark == 0, version .. " no dark OBJ shade on overworld sprites")
      check(counts.light > 0, version .. " light OBJ shade drawn on overworld sprites")
    end
    local colors = PaletteFX.ogObjWorld()
    check(colors[2] == base[1] and colors[3] == base[2] and colors[4] == base[4],
          version .. " overworld bake is rOBP0 $D0")
    check(U.shot(game, DIR .. "/" .. shotName), version .. " shot reached disk")
  end

  local ok, err = pcall(function()
    visit("red", "2689_01_red_oaks_lab_white_faces.png")
    visit("blue", "2689_02_blue_oaks_lab_white_faces.png")
  end)
  if not ok then check(false, "driver ran: " .. tostring(err)) end
  GameVersion.set(savedVer)
  love.event.quit(fails == 0 and 0 or 1)
end
