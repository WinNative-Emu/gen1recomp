#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq

require("src.core.game3.rom_text").plain = function(key) return "<" .. key .. ">" end
package.loaded["src.ui.game3.rse.mapsec"] = {
  name = function(sec) return "SEC" .. tostring(sec) end,
}
package.loaded["src.import.gba.map_sections_extract"] = {
  getInfo = function() error("region_map/names.lua is not in the cache") end,
}

local S = require("src.ui.game3.rs.summary_menu")

for _, version in ipairs({ "ruby", "sapphire" }) do
  require("src.core.GameVersion").set(version)
  S._playerState = { version = version }
  T.suite("rs summary memo location " .. version)
  eq(type(S.locationName), "function", version .. " locationName exists")
  if type(S.locationName) == "function" then
    eq(S.locationName(16), "SEC16", version .. " route 101 from rs mapsec pack")
    eq(S.locationName(0), "SEC0", version .. " littleroot from rs mapsec pack")
    eq(S.locationName(66), "<gOtherText_Hideout>", version .. " evil team hideout")
    eq(S.locationName(86), "<gOtherText_SecretBase>", version .. " secret base")
    eq(S.locationName(87), "<gOtherText_Ferry>", version .. " dynamic is ferry")
  end
end

T.finish("rs summary memo location")
