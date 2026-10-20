return function(mod)
  local out = mod.exports
  local generation = mod.generation
  out.mod = mod
  out.counts = { steps = 0, speed = 0, level = 0, pushed = 0, popped = 0, enters = 0, exits = 0, used = 0 }
  out.errors = {}
  local function must(label, ok, reason)
    if not ok then out.errors[#out.errors + 1] = label .. ": " .. tostring(reason) end
    return ok
  end

  out.supports = {}
  for key, spec in pairs({
    phone = { "events", "phone.call_received" },
    radio = { "events", "radio.channel" },
    shiny = { "hooks", "shiny.roll" },
    nickname = { "hooks", "catch.nickname" },
    style = { "hooks", "battle.style" },
    speed = { "hooks", "core.logic_speed" },
    level = { "hooks", "pokemon.level_visible" },
    stepped = { "events", "world.stepped" },
    pokemon = { "content", "pokemon" },
    fly = { "world", "flyTo" },
  }) do
    out.supports[key] = mod:supports(spec[1], spec[2]) == true
  end

  local patched, patchWhy = mod.content.pokemon:patch("PIDGEY", { baseStats = { attack = 190 } })
  must("PIDGEY patch", patched, patchWhy)
  local seen = mod.content.pokemon:get("PIDGEY")
  out.patchedAttack = seen and seen.baseStats and seen.baseStats.attack

  local item = { name = "ACC TONIC", price = 100, effect = "ACC_TONIC_FX" }
  if generation == 3 then item.pocket = "ITEMS" end
  must("ACC_TONIC item", mod.content.items:register("ACC_TONIC", item))
  local effect = { field = true, needsTarget = generation == 2 or nil, use = function()
    out.counts.used = out.counts.used + 1
    return "consumed", { "ACC TONIC worked!" }
  end }
  must("ACC_TONIC_FX", mod.content.item_effects:register("ACC_TONIC_FX", effect))
  out.itemIndex = function()
    local row = mod.content.items:get("ACC_TONIC")
    return row and row.index
  end

  mod.events:on("world.stepped", function() out.counts.steps = out.counts.steps + 1 end)
  mod.events:on("script.ended", function(e) out.ended = e end)
  mod.events:on("screen.pushed", function() out.counts.pushed = out.counts.pushed + 1 end)
  mod.events:on("screen.popped", function() out.counts.popped = out.counts.popped + 1 end)
  mod.hooks:wrap("core.logic_speed", function(next, game)
    out.counts.speed = out.counts.speed + 1
    return next(game)
  end)
  mod.hooks:wrap("pokemon.level_visible", function(next, mon, ctx)
    out.counts.level = out.counts.level + 1
    return next(mon, ctx)
  end)

  local Screen = {}
  Screen.__index = Screen
  function Screen.new(game)
    return setmetatable({ game = game }, Screen)
  end
  function Screen:enter() out.counts.enters = out.counts.enters + 1 end
  function Screen:exit() out.counts.exits = out.counts.exits + 1 end
  function Screen:update()
    if self.game.input:wasPressed("b") then self.game.stack:pop() end
  end
  function Screen:draw()
    love.graphics.setColor(0.1, 0.2, 0.6, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("line", 4, 4, 152, 136)
    love.graphics.print("API3 MOD SCREEN", 12, 12)
    love.graphics.print("mod.ui push/pop", 12, 32)
  end
  must("screen", mod.content.screens:register("Api3AccScreen", { new = function(game) return Screen.new(game) end }))
  out.openScreen = function(game) return mod.ui.push(game, "Api3AccScreen") end

  out.script = {}
  out.runScript = function(giftText)
    out.script = {}
    local ok, reason = mod.world:queueScript({
      { "show_text", "Hello {PLAYER}!\nAPI 3 mod." },
      { "fade", "out" },
      { "fade", "in" },
      { "give_pokemon", "PIDGEY", 50, true, giftText },
    }, { onDone = function(ok2, why) out.script.done, out.script.ok, out.script.reason = true, ok2, why end })
    out.script.queued, out.script.queueReason = ok, reason
    return ok, reason
  end
end
