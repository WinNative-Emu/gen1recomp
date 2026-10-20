return function(mod)
  local mew = mod.content.pokemon:get("MEW")
  if mew then
    mod.content.pokemon:patch("MEW", {
      baseStats = { attack = math.min(255, mew.baseStats.attack + 10) },
    })
  end

  if mod.content.moves:get("TACKLE") then
    mod.content.moves:patch("TACKLE", { power = 45 })
  end
  if mod.content.items:get("POTION") then
    mod.content.items:patch("POTION", { price = 100 })
  end

  local world = mod.world
  mod.events:once("world.stepped", function()
    local ok, reason = world:setFlag("mod:visited", true)
    if not ok then mod.log:warn("%s", reason) end
  end)
end
