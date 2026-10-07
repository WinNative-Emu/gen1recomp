package.path = "./?.lua;./?/init.lua;" .. package.path

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Objects = require("src.core.game3.objects")

local def = { localId = 1, index = 1, x = 10, y = 12, graphicsId = 10, sprite = "SPRITE_PROF_OAK" }
Objects.loadMap(nil, "TEST_MAP", { objects = { def } })
local eo = Objects.find(1)
assert(eo ~= nil, "object spawned")

local done = false
Objects.applyMovement(1, { 0x60, 0xFE }, function() done = true end)
for _ = 1, 4 do Objects.update(nil) end
assert(done, "set_invisible movement finished")
assert(eo.invisible == true, "set_invisible sets invisible")
assert(eo.hidden ~= true and eo.visible ~= false, "set_invisible does not despawn the object")
assert(Objects.at(10, 12) == eo, "invisible object is still found by Objects.at")
assert(Objects.blocks(10, 12, nil, 0), "invisible object still blocks its cell")
for _, d in ipairs(Objects.forDraw()) do
  assert(d ~= eo, "invisible object is not drawn")
end

done = false
Objects.applyMovement(1, { 0x61, 0xFE }, function() done = true end)
for _ = 1, 4 do Objects.update(nil) end
assert(done, "set_visible movement finished")
assert(eo.invisible == false, "set_visible clears invisible")
assert(Objects.at(10, 12) == eo, "visible object found by Objects.at")

print("[ok] game3_set_invisible_2712_test")
