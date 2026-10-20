return function(mod)
  local out = mod.exports
  out.steps, out.speed = 0, 0
  mod.events:on("world.stepped", function() out.steps = out.steps + 1 end)
  mod.hooks:wrap("core.logic_speed", function(next, game)
    out.speed = out.speed + 1
    return next(game)
  end)
  mod.log:info("legacy acceptance mod loaded")
end
