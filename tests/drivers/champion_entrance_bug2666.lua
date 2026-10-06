-- scripts/ChampionsRoom.asm:30
local U = require('tests.drivers.util')
local Version = require('src.core.GameVersion')
local TextBox = require('src.render.TextBox')

local WANT = '3,7 3,6 3,5 3,4 4,4 4,3'

return function(game)
  local deadline = love.timer.getTime() + 90
  local ok, err = xpcall(function()
    assert(Version.generation() == 1, 'Gen1 edition required')
    local out = assert(os.getenv('POKEPORT_SHOT_DIR'), 'shot directory required')
    love.audio.setVolume(0)
    game:startNewGame({ intro = false })

    local function run(shootAt)
      game.save.flags.EVENT_BEAT_CHAMPION_RIVAL_THIS_RUN = nil
      U.teleport(game, 'CHAMPIONS_ROOM', 3, 7, 'up')
      local ow = assert(game.overworld)
      local cells, last = {}, nil
      local frames, turnFrame = 0, nil
      for _ = 1, 1200 do
        assert(love.timer.getTime() < deadline, '#2666 deadline')
        local p = ow.player
        local key = p.cellX .. ',' .. p.cellY
        if key ~= last then
          cells[#cells + 1] = key
          last = key
          if key == '3,4' and not turnFrame then
            turnFrame = frames
            if shootAt then
              assert(U.still(game, out .. '/2666_01_turn_point_left_column.png'), 'capture failed')
            end
          end
        end
        if getmetatable(game.stack:top()) == TextBox then
          return table.concat(cells, ' '), turnFrame, p.facing
        end
        U.wait(1)
        frames = frames + 1
      end
      error('rival text never opened; walked ' .. table.concat(cells, ' '))
    end

    local path, turnFrame, facing = run(false)
    if path == WANT then
      print('PASS #2666 entrance walk ' .. path)
    else
      error('entrance walk ' .. path .. ' want ' .. WANT)
    end
    if facing == 'up' then
      print('PASS #2666 player faces the rival')
    else
      error('player faces ' .. tostring(facing))
    end
    assert(turnFrame, 'never reached (3,4)')

    run(true)
    U.wait(40)
    assert(U.still(game, out .. '/2666_02_rival_hey.png'), 'capture failed')
    print('PASS #2666 turn point shot at frame ' .. turnFrame)
  end, debug.traceback)
  if not ok then print('FAIL #2666 ' .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
