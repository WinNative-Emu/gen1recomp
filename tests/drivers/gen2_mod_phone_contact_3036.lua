local U = require("tests.drivers.util")
local Loader = require("src.mods.Loader")
local Sdk = require("tests.modkit.sdk")
local Phone = require("src.core.gen2.Phone")

return function(game)
  U.wait(45)
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local files = {
    ["mods/probe/manifest.json"] = '{"id":"probe","name":"probe","version":"1.0.0",'
      .. '"api":3,"games":["all"],"entry":"main.lua"}',
    ["mods/probe/main.lua"] = [[local mod = ...
mod.content.map_scripts:register("probe:callee", {{op="setevent",event=1001},{op="end"}})
mod.content.map_scripts:register("probe:caller", {{op="setevent",event=1002},{op="end"}})
mod.content.phone_contacts:register("BSA_GUIDE", {index=60,name="GUIDE",map="ROUTE_31",
  calleeTime=7,callerTime=7,calleeKey="probe:callee",callerKey="probe:caller",rematchEvent=1000})]],
  }
  local loader = Loader.new({ fs = Sdk.memfs(files), generation = 2,
    version = game.save.version, dev = true })
  loader.game = game
  local data = {}
  for key, value in pairs(game.data) do data[key] = value end
  for key in pairs(require("src.mods.Builtins").namespaceRoots(2)) do data[key] = nil end
  loader:load(data)
  Phone.useRegistry(data)
  if not check(not loader.mods.probe.failed and Phone.CONTACTS[60] ~= nil, "3036_fixture_registered") then
    love.event.quit(1)
    return
  end
  local world = game.world
  world:warpToMapId("ROUTE_31", 8, 6, "down")
  U.wait(15)
  world.vm:start({ {op="askforphonenumber",phone=60}, {op="end"} })
  for _ = 1, 180 do
    if Phone.hasContact(game.save, 60) then break end
    U.tap(game, "a")
    U.wait(2)
  end
  check(Phone.hasContact(game.save, 60), "3036_askfornumber")
  world:warpToMapId("ROUTE_29", 48, 3, "up")
  U.wait(15)
  game.save.pokegearFlags = { phone = true }
  game:openStartMenuItem("pokegear")
  for _ = 1, 60 do
    local top = game.stack:top()
    if top and top.cards then break end
    U.wait(1)
  end
  local gear = game.stack:top()
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2_mod_phone_contact_3036"
  if check(gear and gear.cards, "3036_pokegear_open") then
    gear.mode = "card"
    for index, card in ipairs(gear.cards) do if card.id == "phone" then gear.cardIndex = index end end
    check(gear:contactRow(60) == "GUIDE:", "3036_phone_name")
    check(U.still(game, dir .. "/3036_custom_phone_list.png"), "3036_list_shot")
    game.stack:pop()
  end
  local ctx = { mapId = "ROUTE_29", phoneService = true, timeOfDay = Phone.DAY }
  local outgoing = Phone.call(game.save, 60, ctx)
  world.vm:start(outgoing.scriptKey)
  U.wait(10)
  check(world.events:get(1001), "3036_callee_script")
  local incoming = Phone.loadCallerScript(60, "incoming", "caller")
  check(world:receivePhoneCall(incoming), "3036_incoming_started")
  U.wait(180)
  check(U.still(game, dir .. "/3036_custom_caller_box.png"), "3036_caller_shot")
  for _ = 1, 180 do
    if world.events:get(1002) then break end
    U.tap(game, "a")
    U.wait(2)
  end
  check(world.events:get(1002), "3036_caller_script")
  check(Phone.setRematchReady(world.events, 60) and Phone.isReadyForRematch(world.events, 60),
    "3036_rematch_event")
  love.event.quit(failures == 0 and 0 or 1)
end
