-- engine/overworld/player_state.asm:353
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Collision = require("src.world.Collision")
  local MAP = "SEAFOAM_ISLANDS_1F"
  local DIRS = { "right", "left", "down", "up" }
  local STEP = { down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }

  local ok = true
  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    if not pass then ok = false end
    return pass
  end
  local function finish()
    for _, d in ipairs(DIRS) do game.input.state[d] = false end
    U.log(ok and "PASS boulder_ledge_pair" or "FAIL boulder_ledge_pair")
    love.event.quit(ok and 0 or 1)
    while true do coroutine.yield() end
  end

  U.teleport(game, MAP, 17, 10, "right")
  U.wait(10)
  local ow = game.overworld
  game.data.encounters[MAP] = nil
  local rock = ow and ow:npcAtCell(18, 10)
  if not check("boulder present on " .. MAP, rock ~= nil and rock.def.sprite == "SPRITE_BOULDER") then
    finish()
  end
  ow.strengthActive = true

  local function free(x, y)
    if not (ow.map:inBounds(x, y) and ow.map:isWalkableCell(x, y)) then return false end
    local n = ow:npcAtCell(x, y)
    return n == nil or n == rock
  end
  local function find(wantPair)
    for y = 0, ow.map.heightCells - 1 do
      for x = 0, ow.map.widthCells - 1 do
        for _, d in ipairs(DIRS) do
          local s = STEP[d]
          local mx, my, bx, by = x + s[1], y + s[2], x + 2 * s[1], y + 2 * s[2]
          if free(x, y) and free(mx, my) and free(bx, by)
              and not Collision.pairBlocked(ow.map, {}, x, y, mx, my)
              and Collision.pairBlocked(ow.map, {}, x, y, bx, by) == wantPair
              and ow.map:cellTile(bx, by) ~= 0x15 then
            return { x = x, y = y, mx = mx, my = my, bx = bx, by = by, dir = d }
          end
        end
      end
    end
  end

  local function push(spot)
    for _, d in ipairs(DIRS) do game.input.state[d] = false end
    ow.dustAnim, ow.boulderTried = nil, nil
    rock.cellX, rock.cellY = spot.mx, spot.my
    rock.px, rock.py = spot.mx * 16, spot.my * 16
    rock.moving, rock.targetX, rock.targetY = false, nil, nil
    local p = ow.player
    p.cellX, p.cellY = spot.x, spot.y
    p.px, p.py = spot.x * 16, spot.y * 16
    p.moving, p.targetX, p.targetY = false, nil, nil
    p.facing = spot.dir
    U.wait(8)
    table.insert(game.input.pressQueue, spot.dir)
    for _ = 1, 300 do
      if ow.dustAnim and ow.dustAnim.boulder then break end
      game.input.state[spot.dir] = true
      U.wait(1)
    end
    game.input.state[spot.dir] = false
    U.wait(30)
    return rock.cellX, rock.cellY
  end

  local blocked = find(true)
  local open = find(false)
  if not check("found a ledge pair spot", blocked ~= nil) then finish() end
  if not check("found an open spot", open ~= nil) then finish() end
  U.log("ledge", blocked.x, blocked.y, blocked.dir, "open", open.x, open.y, open.dir)

  local ox, oy = push(open)
  check("control push moves the boulder", ox == open.bx and oy == open.by)
  local rx, ry = push(blocked)
  check("boulder stays put against an elevation pair", rx == blocked.mx and ry == blocked.my)
  finish()
end
