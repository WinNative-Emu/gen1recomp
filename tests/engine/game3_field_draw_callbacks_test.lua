package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")
local Objects = require("src.core.game3.objects")
local seen, spriteCalls = {}, {}
package.loaded["src.online.union.Avatars"] = {
  resolve = function(person, host)
    T.eq(host, "emerald", "foreign avatar retains its host")
    return person
  end,
  draw = function(person, x, y, facing, phase, flip, scale)
    seen = { person, x, y, facing, phase, flip, scale }
    return true
  end,
}
package.loaded["src.core.game3.player"] = { isVisible = function() return false end }
package.loaded["src.world.game3.Follower"] = { actor = function() end }
package.loaded["src.core.game3.field_effects"] = {}
package.loaded["src.core.game3.ow_sprites"] = {
  ready = function() return true end,
  draw = function(gid, px, py, camX, camY)
    spriteCalls[#spriteCalls + 1] = gid
    if type(gid) == "table" then return gid.draw(gid, px - camX, py - camY) end
    return true
  end,
}
local followerCalls = 0
local follower = {
  localId = -101, cellX = 4, cellY = 5, px = 64, py = 80, y2 = -8,
  facing = "down", elevation = 3,
}
follower.graphicsId = follower
follower.draw = function(a, sx, sy)
  followerCalls = followerCalls + 1
  T.eq(a, follower, "follower draw receives the original actor")
  T.eq(sx, 54, "follower receives screen x")
  T.eq(sy + a.y2, 52, "follower retains jump offset and screen y")
  return true
end
local visitor = {
  localId = 2, cellX = 6, cellY = 7, px = 96, py = 112, elevation = 3,
  facing = "left", foreign = { game = "crystal", host = "emerald" },
  draw = Objects.drawForeign,
}
local ordinary = {
  localId = 3, cellX = 8, cellY = 9, graphicsId = 19, elevation = 3,
  draw = function() error("ordinary object bypassed its sprite hook") end,
}
Objects.hasMap = function() return true end
Objects.forDraw = function() return { follower, visitor, ordinary } end
Objects.walkPhase = function() return 1 end
Objects.fadeAlpha = function() return nil end
local FieldView = require("src.core.game3.field_view")
local function up(fn, wanted)
  for i = 1, 100 do
    local name, value = debug.getupvalue(fn, i)
    if name == wanted then return value end
  end
  error("renderer missing " .. wanted)
end
local collect = up(FieldView.draw, "collectGame3Actors")
local drawActor = up(FieldView.draw, "drawSingleActor")
local game, map = { mapId = "test" }, {}
local function renderObjects()
  local under, over = collect(game, map, 10, 20, 0, 0, "down", 0, false, 0, 0)
  for _, list in ipairs({ under, over }) do
    for _, actor in ipairs(list) do drawActor(game, map, actor, 10, 20) end
  end
end
renderObjects()
T.eq(followerCalls, 1, "follower draws once through its sprite hook")
T.eq(#spriteCalls, 2, "follower and ordinary NPC use the sprite path")
T.eq(seen[1], visitor.foreign, "foreign callback receives the original visitor")
T.eq(seen[2], 94, "foreign avatar receives centered screen x")
T.eq(seen[3], 108, "foreign avatar receives foot screen y")
T.eq(seen[4], "left", "foreign avatar retains direction")
T.eq(seen[5], 1, "foreign avatar retains walk phase")
T.eq(seen[7], 1, "foreign avatar retains native scale")
visitor.foreign, visitor.graphicsId = nil, 22
seen, spriteCalls = {}, {}
renderObjects()
T.eq(#spriteCalls, 3, "reused visitor record returns to its ordinary sprite path")
T.eq(seen[1], nil, "reused visitor record clears its foreign callback")
local customCalls = 0
drawActor(game, map, { x = 0, y = 0, kind = "mod", draw = function()
  customCalls = customCalls + 1
end }, 10, 20)
T.eq(customCalls, 1, "direct render actors retain their custom callback")
T.finish("game3_field_draw_callbacks")
