package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")

local files = {}
package.loaded["src.core.game3.dataset"] = {
  cache = function()
    return { read = function(_, rel) return files[rel] end }
  end,
}

local LB = require("src.core.game3.link.battle")
LB._unionRoomClasses = nil
LB.unionRoom = true

local ok, pic = pcall(LB.peerPicId, { gender = 1, trainerId = 3 })
T.check(ok, "a union battle on a cart with no union room classes picks a picture (" .. tostring(not ok and pic or "") .. ")")
T.eq(ok and pic, LB.TRAINER_PIC_LEAF, "it uses the cable club link picture")
T.check(not LB.hasUnionRoomClasses(), "the cart has no union room classes")

files["data/generated/gba/trainers/union_room_classes.lua"] =
  "return { trainerPic = { [11] = 77 }, trainerClass = { [11] = 5 } }"
T.check(LB.hasUnionRoomClasses(), "a cart with union room classes is seen")
T.eq(LB.peerPicId({ gender = 1, trainerId = 3 }), 77, "and its union room picture is used")

LB.unionRoom = false
T.finish()
