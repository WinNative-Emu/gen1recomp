-- scripts/Route23.asm:237
local U = require('tests.drivers.util')
local Version = require('src.core.GameVersion')
local TextBox = require('src.render.TextBox')

local function pageText(box, i)
  local page = box.pages and box.pages[i]
  return page and table.concat(page, ' ') or ''
end

return function(game)
  local deadline = love.timer.getTime() + 90
  local ok, err = xpcall(function()
    assert(Version.generation() == 1, 'Gen1 edition required')
    local out = assert(os.getenv('POKEPORT_SHOT_DIR'), 'shot directory required')
    love.audio.setVolume(0)
    local function wait(n)
      for _ = 1, n do
        assert(love.timer.getTime() < deadline, '#2649 deadline')
        U.wait(1)
      end
    end
    local function untilReady(fn, limit, label)
      for _ = 1, limit do if fn() then return end; wait(1) end
      error(label)
    end
    local function isBox(s) return s and getmetatable(s) == TextBox end
    assert(game.data.text._Route23GoRightAheadText, '_Route23GoRightAheadText missing from cache')

    game:startNewGame({ intro = false })
    game.save.inventory.CASCADEBADGE = 1
    U.teleport(game, 'ROUTE_23', 7, 137, 'up')
    local ow = assert(game.overworld)
    untilReady(function()
      return game.stack:top() == ow and not ow.transitioning and not ow.player.moving
    end, 400, 'field did not settle')

    U.hold(game, 'up', 4)
    untilReady(function() return isBox(game.stack:top()) end, 200, 'guard text never opened')
    local box = game.stack:top()
    assert(#box.pages == 3, 'step path pages: ' .. #box.pages)
    assert(pageText(box, 2):find('Oh! That is the', 1, true), 'page 2 is not the badge line')
    assert(pageText(box, 3):find('OK then! Please,', 1, true), 'page 3 is not the go-ahead line')
    print('PASS #2649 step path shows three pages ending in OK then! Please, go right ahead!')

    local sawFanfare = false
    untilReady(function()
      if box.pauseSrc or (box.pauseMark and box.pageIndex == 2) then sawFanfare = true end
      if box.pageIndex == 2 and box.waiting and not box.pauseSrc then return true end
      if box.pageIndex == 1 and box.waiting then U.tap(game, 'a') end
      return false
    end, 1200, 'badge page never settled')
    assert(sawFanfare, 'Get_Item1 mark never fired on the badge page')
    print('PASS #2649 Get_Item1 fires after Oh! That is the CASCADEBADGE!')
    assert(U.still(game, out .. '/2649_01_badge_page_after_fanfare.png'), 'capture failed')

    untilReady(function()
      if box.pageIndex < 3 and box.waiting then U.tap(game, 'a') end
      return box.pageIndex == 3 and (box.done or box.waiting)
    end, 600, 'go-ahead page never typed: page ' .. tostring(box.pageIndex))
    assert(U.still(game, out .. '/2649_02_step_go_right_ahead.png'), 'capture failed')
    print('PASS #2649 step path go-ahead page typed in the same box')

    untilReady(function()
      if game.stack:top() == box then U.tap(game, 'a') end
      return game.stack:top() == ow
    end, 300, 'step box never closed')
    assert(ow.player.cellY == 136, 'player was turned back: y=' .. ow.player.cellY)
    assert(game.save.flags.EVENT_PASSED_CASCADEBADGE_CHECK, 'pass flag not set')
    print('PASS #2649 step path lets the player through and sets EVENT_PASSED_CASCADEBADGE_CHECK')

    U.teleport(game, 'ROUTE_23', 7, 136, 'right')
    ow = assert(game.overworld)
    untilReady(function()
      return game.stack:top() == ow and not ow.transitioning and not ow.player.moving
    end, 400, 'field did not settle for talk')
    U.tap(game, 'a')
    untilReady(function() return isBox(game.stack:top()) end, 200, 'talk text never opened')
    local seenOh, goBox = false, nil
    untilReady(function()
      local top = game.stack:top()
      if isBox(top) then
        for i = 1, #top.pages do
          if pageText(top, i):find('Oh! That is the', 1, true) then seenOh = true end
          if seenOh and pageText(top, i):find('OK then! Please,', 1, true) then goBox = top end
        end
        if goBox and goBox.pageIndex == #goBox.pages and (goBox.done or goBox.waiting) then
          return true
        end
        if top.waiting or (top.done and not top.pauseSrc) then U.tap(game, 'a') end
      end
      return false
    end, 2400, 'talk path never reached the go-ahead text')
    assert(U.still(game, out .. '/2649_03_talk_go_right_ahead.png'), 'capture failed')
    print('PASS #2649 talking to the guard also ends in OK then! Please, go right ahead!')
    assert(#goBox.pages == 3, 'talk path pages: ' .. #goBox.pages)
    assert(pageText(goBox, 2):find('Oh! That is the', 1, true), 'talk path: page 2 is not the badge line')
    assert(goBox.pauseAt, 'talk path: no fanfare mark in the box')
    print('PASS #2649 talk path is one box: badge line, fanfare mark, go-ahead page')
    untilReady(function()
      if game.stack:top() ~= ow then U.tap(game, 'a') end
      return game.stack:top() == ow
    end, 300, 'talk box never closed')

    local function failBox(label)
      local fb = game.stack:top()
      assert(isBox(fb), label .. ': no box')
      assert(fb.auto and fb.auto.sound, label .. ': SFX_DENIED not armed after the text')
      assert(not fb.autoStarted, label .. ': sound fired before the text typed')
      untilReady(function()
        if fb.autoStarted then return true end
        if fb.waiting then U.tap(game, 'a') end
        return false
      end, 1200, label .. ': SFX_DENIED never fired after the text')
      assert(fb.done, label .. ': sound fired before the last page typed')
      print('PASS #2649 ' .. label .. ' plays SFX_DENIED after the text')
      untilReady(function()
        if game.stack:top() == fb then U.tap(game, 'a') end
        return game.stack:top() == ow
      end, 300, label .. ': fail box never closed')
      untilReady(function() return not ow.player.moving and #ow.scriptMoves == 0 end,
        200, label .. ': walk-down never settled')
    end

    game.save.inventory.CASCADEBADGE = nil
    game.save.flags.EVENT_PASSED_CASCADEBADGE_CHECK = nil
    U.teleport(game, 'ROUTE_23', 7, 137, 'up')
    ow = assert(game.overworld)
    untilReady(function()
      return game.stack:top() == ow and not ow.transitioning and not ow.player.moving
    end, 400, 'field did not settle for the step fail')
    U.hold(game, 'up', 4)
    untilReady(function() return isBox(game.stack:top()) end, 200, 'step fail text never opened')
    failBox('step fail')
    assert(ow.player.cellY == 137, 'step fail: not pushed back down, y=' .. ow.player.cellY)
    assert(ow.player.facing == 'down', 'step fail: facing ' .. tostring(ow.player.facing))
    assert(not game.save.flags.EVENT_PASSED_CASCADEBADGE_CHECK, 'step fail set the pass flag')
    print('PASS #2649 step fail walks the player back down')

    U.teleport(game, 'ROUTE_23', 8, 137, 'up')
    ow = assert(game.overworld)
    untilReady(function()
      return game.stack:top() == ow and not ow.transitioning and not ow.player.moving
    end, 400, 'field did not settle for the talk fail')
    local canStepDown = ow.map:isWalkableCell(8, 138)
    U.tap(game, 'a')
    untilReady(function() return isBox(game.stack:top()) end, 200, 'talk fail text never opened')
    failBox('talk fail')
    assert(ow.player.facing == 'down', 'talk fail: facing ' .. tostring(ow.player.facing))
    assert(ow.player.cellY == (canStepDown and 138 or 137),
      'talk fail: y=' .. ow.player.cellY .. ' walkable=' .. tostring(canStepDown))
    assert(not game.save.flags.EVENT_PASSED_CASCADEBADGE_CHECK, 'talk fail set the pass flag')
    print('PASS #2649 talk fail runs Route23MovePlayerDownScript')
  end, debug.traceback)
  if not ok then print('FAIL #2649 ' .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
