function love.run()
  if love.load then love.load(love.arg.parseGameArguments(arg), arg) end
  if love.timer then love.timer.step() end
  local FrameCap = require("src.core.FrameCap")
  local paced = pacingEnabled()
  local nextFrame = love.timer and love.timer.getTime() or 0
  local dt = 0
  return function()
    if love.event then
      love.event.pump()
      for name, a, b, c, d, e, f in love.event.poll() do
        if name == "quit" then
          if not love.quit or not love.quit() then
            return a or 0
          end
        end
        love.handlers[name](a, b, c, d, e, f)
      end
    end
    if love.timer then dt = love.timer.step() end
    if love.update then love.update(dt) end
    if love.graphics and love.graphics.isActive() then
      love.graphics.origin()
      love.graphics.clear(love.graphics.getBackgroundColor())
      if love.draw then love.draw() end
      love.graphics.present()
    end
    if love.timer then
      if paced then
        local budget = 1 / FrameCap.current
        nextFrame = nextFrame + budget
        local now = love.timer.getTime()
        if now - nextFrame > budget then
          nextFrame = now
        end
        while true do
          local remaining = nextFrame - love.timer.getTime()
          if remaining <= 0 then break end
          love.timer.sleep(remaining < 0.001 and remaining or 0.001)
        end
      else
        love.timer.sleep(0.001)
      end
    end
  end
end
