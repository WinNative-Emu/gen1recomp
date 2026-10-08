function love.run()
  if love.load then love.load(love.arg.parseGameArguments(arg), arg) end
  if love.timer then love.timer.step() end
  local FrameCap = require("src.core.FrameCap")
  local paced = pacingEnabled()
  local nextFrame = love.timer and love.timer.getTime() or 0
  local dt = 0
  local idleFor = 0
  local SLEEP_FLOOR = 0.001
  local WAKE = {
    keypressed = true, keyreleased = true, textinput = true,
    mousepressed = true, mousereleased = true, mousemoved = true,
    wheelmoved = true, touchpressed = true, touchreleased = true,
    touchmoved = true, joystickpressed = true, joystickreleased = true,
    joystickhat = true, gamepadpressed = true, gamepadreleased = true,
    joystickadded = true, joystickremoved = true, filedropped = true,
    directorydropped = true, focus = true, visible = true, resize = true,
  }
  return function()
    if love.event then
      love.event.pump()
      for name, a, b, c, d, e, f in love.event.poll() do
        if name == "quit" then
          if not love.quit or not love.quit() then
            if love.system and love.system.getOS() == "Android" then
              os.exit(a or 0)
            end
            return a or 0
          end
        end
        if WAKE[name] then
          idleFor = 0
        elseif name == "joystickaxis" and type(c) == "number" and math.abs(c) > 0.5 then
          idleFor = 0
        end
        love.handlers[name](a, b, c, d, e, f)
      end
    end
    if love.timer then dt = love.timer.step() end
    idleFor = idleFor + dt
    checkEmergencyQuit(dt)
    if love.update then love.update(dt) end
    local visible = not (love.window and love.window.isVisible)
      or love.window.isVisible()
    local focused = not (love.window and love.window.hasFocus)
      or love.window.hasFocus()
    local cap = FrameCap.current
    if not visible then
      cap = 10
    elseif Importer and (not focused or idleFor > 30) then
      cap = 15
    end
    if visible and love.graphics and love.graphics.isActive() then
      love.graphics.origin()
      love.graphics.clear(love.graphics.getBackgroundColor())
      if love.draw then love.draw() end
      love.graphics.present()
    end
    if love.timer then
      if paced then
        local budget = 1 / cap
        nextFrame = nextFrame + budget
        local now = love.timer.getTime()
        if now - nextFrame > budget then
          nextFrame = now
        end
        while true do
          local remaining = nextFrame - love.timer.getTime()
          if remaining <= SLEEP_FLOOR then break end
          love.timer.sleep(0.001)
        end
      else
        love.timer.sleep(0.001)
      end
    end
  end
end
