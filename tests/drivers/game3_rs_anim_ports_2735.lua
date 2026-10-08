local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or ".bazinga/BSA/10-07-26-00-userreported/shots/game3_rs_anim_ports_2735"

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end

  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RUBY" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local AnimSprites = require("src.core.game3.battle.anim_sprites")
  local AnimTasks = require("src.core.game3.battle.anim_tasks")
  local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")
  local Secondary = require("src.core.game3.battle.effects.secondary")

  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 6, 36)
  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 41, level = 30 }, { fade = false })
  result(ok == true, "wild battle started " .. tostring(err or ""))
  if not ok then love.event.quit(1) return end
  local ready = false
  for _ = 1, 3000 do
    if Ui._mode == "menu" and not Anim.busy() then ready = true break end
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
  end
  result(ready, "battle reached the action menu")
  if not ready then love.event.quit(1) return end
  U.wait(20)

  local fallbacks, stubs, spawned = 0, 0, {}
  local get, spawn = AnimCallbacks.get, AnimTasks.spawn
  AnimCallbacks.get = function(name)
    local fn = get(name)
    if fn == AnimCallbacks.SimpleFadeOut and name then fallbacks = fallbacks + 1 end
    return fn
  end
  AnimTasks.spawn = function(name, ...)
    spawned[tostring(name)] = true
    if not AnimTasks.REGISTRY[tostring(name)] then stubs = stubs + 1 end
    return spawn(name, ...)
  end

  local function sprites(cb)
    local out = {}
    AnimSprites.forEachActive(function(s)
      if s._cbName == cb and s.visible ~= false and not s.invisible then out[#out + 1] = s end
    end)
    return out
  end
  local function pos(s) return s.x + (s.ox or 0), s.y + (s.oy or 0) end
  local function sideOpts(side)
    local other = side == "player" and "enemy" or "player"
    return { attackerSide = side, targetSide = other, isReversed = side == "enemy",
      attackerSpecies = side == "player" and 6 or 41, targetSpecies = side == "player" and 41 or 6 }
  end
  local function reset()
    for _, s in ipairs({ "player", "enemy" }) do
      local p = Anim.present(s)
      if p then p.visible, p.ox, p.oy, p.sx, p.sy, p.rotation = true, 0, 0, 1, 1, 0 end
    end
    for _ = 1, 20 do U.wait(1) end
  end
  local function run(label, launch, onFrame)
    fallbacks, stubs, spawned = 0, 0, {}
    local launched = launch()
    local f = 0
    while f < 900 do
      onFrame(f)
      U.wait(1)
      f = f + 1
      if f > 4 and not Anim.busy() then break end
    end
    result(launched ~= false, label .. " launched")
    result(fallbacks == 0, label .. " used no SimpleFadeOut fallback callbacks (" .. fallbacks .. ")")
    result(stubs == 0, label .. " spawned no unbound tasks (" .. stubs .. ")")
    result(f < 900, label .. " finished in " .. f .. " frames")
    reset()
  end

  local function purplePixels(path)
    local f = io.open(path, "rb")
    if not f then return -1 end
    local bytes = f:read("*a")
    f:close()
    local img = love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
    local w, h = img:getDimensions()
    local n = 0
    for y = 0, math.floor(h * 0.6) do
      for x = math.floor(w * 0.45), w - 1 do
        local r, g, b = img:getPixel(x, y)
        r, g, b = r * 255, g * 255, b * 255
        if b >= 150 and b - g >= 40 and b - r >= 20 then n = n + 1 end
      end
    end
    return n
  end
  local function targetDrawn()
    local p = Anim.present("enemy")
    return p.visible ~= false and not p.invisible and not p.battlerInvisible and not p.blinkHidden
      and (p.alpha or 1) == 1 and (p.scale or 1) == 1
  end
  local function rockLayers()
    local monZ = require("src.core.game3.battle.anim_coords").monBehindZ("enemy") + 5
    local front, behind, xFront = 0, 0, false
    AnimSprites.forEachActive(function(s)
      if s._cbName == "RockTomb" then
        if s.z > monZ then front = front + 1 elseif s.z < monZ then behind = behind + 1 end
      elseif s._cbName == "RedX" then
        xFront = s.z > monZ
      end
    end)
    return front, behind, xFront
  end

  local vm
  local rockFall, xOk, xShot, rockShot = 0, nil, false, false
  local rockStart = {}
  local rockPx, xPx, xDrawn = -1, -1, false
  local frontRocks, behindRocks, xFront = 0, 0, false
  run("ROCK_TOMB", function() return Anim.launchMove(317, sideOpts("player")) end, function()
    vm = Anim.vm()
    for _, s in ipairs(sprites("RockTomb")) do
      local _, y = pos(s)
      rockStart[s] = rockStart[s] or y
      rockFall = math.max(rockFall, y - rockStart[s])
      if not rockShot and y - rockStart[s] > 20 then
        local path = DIR .. "/2733_01_rock_tomb_rocks_falling.png"
        rockShot = U.still(game, path)
        rockPx = purplePixels(path)
      end
    end
    local xs = sprites("RedX")
    if #xs > 0 then
      local x, y = pos(xs[1])
      local tx, ty = vm:battlerCenter("target")
      xOk = math.abs(x - tx) <= 8 and math.abs(y - ty) <= 16
      if not xShot then
        U.wait(4)
        local path = DIR .. "/2733_02_rock_tomb_red_x_on_target.png"
        xDrawn = targetDrawn()
        frontRocks, behindRocks, xFront = rockLayers()
        xShot = U.still(game, path)
        xPx = purplePixels(path)
      end
    end
  end)
  result(rockFall >= 32, "ROCK_TOMB rocks drop onto the target (fell " .. rockFall .. " px)")
  result(xOk == true, "ROCK_TOMB red X sits on the target picture")
  result(xDrawn, "ROCK_TOMB target picture is still drawn under the red X")
  result(frontRocks == 3 and behindRocks == 1 and xFront,
    "ROCK_TOMB red X and three rocks layer in front of the target, one rock behind (" .. frontRocks .. "/" .. behindRocks .. ")")
  result(rockPx > 1000 and xPx >= 0 and xPx < rockPx * 0.15,
    "ROCK_TOMB red X and rock pile cover the target like the cart (" .. xPx .. " of " .. rockPx .. " purple px)")

  local ringOk, noteMoved, uShot = nil, false, false
  local noteStart = {}
  run("UPROAR", function() return Anim.launchMove(253, sideOpts("enemy")) end, function()
    vm = Anim.vm()
    local rings = sprites("UproarRing")
    if #rings > 0 and ringOk == nil then
      local x, y = pos(rings[1])
      local ax, ay = vm:battlerCenter("attacker")
      ringOk = math.abs(x - ax) <= 8 and math.abs(y - ay) <= 16
    end
    for _, s in ipairs(sprites("JaggedMusicNote")) do
      local x, y = pos(s)
      noteStart[s] = noteStart[s] or { x, y }
      if math.abs(x - noteStart[s][1]) + math.abs(y - noteStart[s][2]) >= 12 then noteMoved = true end
    end
    if not uShot and #rings > 0 and noteMoved then
      uShot = U.still(game, DIR .. "/2734_01_uproar_ring_notes_on_user.png")
    end
  end)
  result(ringOk == true, "UPROAR ring is centered on the user")
  result(noteMoved, "UPROAR notes fly outward")

  run("SUPERSONIC", function() return Anim.launchMove(48, sideOpts("enemy")) end, function() end)
  local ducks, dShot = 0, false
  run("STATUS_CONFUSION", function()
    local o = sideOpts("player")
    o.targetSide = "player"
    return Anim.launchStatus("CONFUSION", o)
  end, function(f)
    local n = #sprites("ConfusionDuck")
    ducks = math.max(ducks, n)
    if not dShot and n > 0 and f >= 12 then
      dShot = U.still(game, DIR .. "/2735_01_confusion_ducks_over_head.png")
    end
  end)
  result(ducks >= 2, "STATUS_CONFUSION ducks circle the head (" .. ducks .. ")")

  local needleFrom, needleTo, nShot = nil, nil, false
  run("LEECH_LIFE", function() return Anim.launchMove(141, sideOpts("enemy")) end, function()
    local n = sprites("LeechLifeNeedle")
    if #n > 0 then
      local x, y = pos(n[1])
      needleFrom = needleFrom or { x, y }
      needleTo = { x, y }
      if not nShot and math.abs(x - needleFrom[1]) + math.abs(y - needleFrom[2]) >= 6 then
        nShot = U.still(game, DIR .. "/2735_02_leech_life_needle_flying.png")
      end
    end
  end)
  local travel = needleFrom and (math.abs(needleTo[1] - needleFrom[1]) + math.abs(needleTo[2] - needleFrom[2])) or 0
  result(travel >= 8, "LEECH_LIFE needle travels before the drain (" .. travel .. " px)")

  local sShot = false
  run("STATS_CHANGE", function()
    local o = sideOpts("enemy")
    o.targetSide = "enemy"
    o.animArg = Secondary.statAnimArg("attack", -1)
    return Anim.launchGeneral("STATS_CHANGE", o)
  end, function(f)
    if not sShot and f == 20 then sShot = U.still(game, DIR .. "/2735_03_stats_change_growl_glow.png") end
  end)
  result(spawned.StatsChange == true, "STATS_CHANGE runs the StatsChange task")

  local hShot = false
  run("HARDEN_STATS_CHANGE", function()
    local o = sideOpts("player")
    o.targetSide = "player"
    o.animArg = Secondary.statAnimArg("defense", 1)
    return Anim.launchGeneral("STATS_CHANGE", o)
  end, function(f)
    if not hShot and f == 20 then hShot = U.still(game, DIR .. "/2735_04_stats_change_harden_glow.png") end
  end)

  AnimCallbacks.get, AnimTasks.spawn = get, spawn
  love.event.quit(fails == 0 and 0 or 1)
end
