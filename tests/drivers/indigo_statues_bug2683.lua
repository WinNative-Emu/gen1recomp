local U = require('tests.drivers.util')
local Version = require('src.core.GameVersion')
local TextBox = require('src.render.TextBox')

local function flatten(t, out)
  out = out or {}
  if type(t) == 'string' then out[#out + 1] = t
  elseif type(t) == 'table' then for _, v in ipairs(t) do flatten(v, out) end end
  return out
end

return function(game)
  local deadline = love.timer.getTime() + 60
  local ok, err = xpcall(function()
    assert(Version.generation() == 1, 'Gen1 edition required')
    local out = assert(os.getenv('POKEPORT_SHOT_DIR'), 'shot directory required')
    love.audio.setVolume(0)
    local function wait(n)
      for _ = 1, n do
        assert(love.timer.getTime() < deadline, '#2683 deadline')
        U.wait(1)
      end
    end
    local function untilReady(fn, limit, label)
      for _ = 1, limit do if fn() then return end; wait(1) end
      error(label)
    end
    local text = game.data.text
    local want = {
      odd = assert(text._IndigoPlateauStatuesText2, 'Text2 missing from cache'),
      even = assert(text._IndigoPlateauStatuesText3, 'Text3 missing from cache'),
    }
    game:startNewGame({ intro = false })
    U.teleport(game, 'INDIGO_PLATEAU', 9, 8, 'down')
    local ow = assert(game.overworld)
    local map = ow.map
    local spots = {}
    for cy = 0, map.heightCells - 1 do
      for cx = 0, map.widthCells - 1 do
        if map:inBounds(cx, cy) and map:inBounds(cx, cy + 1)
           and map:cellTile(cx, cy) == 0x30 and map:isWalkableCell(cx, cy + 1) then
          local key = (cx % 2 == 1) and 'odd' or 'even'
          if not spots[key] then spots[key] = { cx, cy + 1 } end
        end
      end
    end
    assert(spots.odd and spots.even, 'no statue spots found on INDIGO_PLATEAU')
    for i, key in ipairs({ 'odd', 'even' }) do
      local x, y = spots[key][1], spots[key][2]
      U.teleport(game, 'INDIGO_PLATEAU', x, y, 'up')
      ow = assert(game.overworld)
      untilReady(function()
        return game.stack:top() == ow and not ow.transitioning and not ow.player.moving
      end, 400, 'field did not settle')
      assert(ow.player.cellX == x and ow.player.facing == 'up', 'player not placed facing the statue')
      U.tap(game, 'a')
      untilReady(function() return getmetatable(game.stack:top()) == TextBox end, 120, 'statue text never opened')
      local box = game.stack:top()
      local joined = table.concat(flatten(box.pages), ' ')
      local expect = TextBox.strip(TextBox.substitute(game, want[key])):gsub('[\n\f]', ' ')
      local firstWord = expect:match('%S+%s+%S+')
      assert(joined:find(firstWord, 1, true), key .. ' X ' .. x .. ' printed the wrong caption: ' .. joined)
      untilReady(function()
        if box.pageIndex == #box.pages and box.waiting then return true end
        if box.waiting then U.tap(game, 'a') end
        return false
      end, 1200, 'caption page never settled')
      local name = string.format('2683_%02d_%s_x%d_%s.png', i, key, x,
        key == 'odd' and 'ultimate_goal' or 'highest_authority')
      assert(U.still(game, out .. '/' .. name), 'capture failed')
      print('PASS #2683 ' .. Version.get() .. ' ' .. key .. ' X=' .. x .. ' shows ' .. (key == 'odd' and 'Text2' or 'Text3'))
      for _ = 1, 20 do
        if game.stack:top() ~= box then break end
        U.tap(game, 'a'); wait(4)
      end
    end
  end, debug.traceback)
  if not ok then print('FAIL #2683 ' .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
