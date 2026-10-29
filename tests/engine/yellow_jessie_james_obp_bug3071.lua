package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("yellow jessie/james advanced obp #3071")
local check, eq = S.check, S.eq

local GameVersion = require("src.core.GameVersion")
local PaletteFX = require("src.render.PaletteFX")

local prevVer = GameVersion.get()
local prevMode = PaletteFX.mode

GameVersion.set("yellow")
PaletteFX.setMode("redpp")

local function obp(idx, seed)
  return PaletteFX.spriteObp({ source = "ROM:SpriteSheetPointerTable[" .. idx .. "]" }, seed)
end

local seeds = {
  "MT_MOON_B2F_obj_2", "MT_MOON_B2F_obj_6", "ROCKET_HIDEOUT_B4F_obj_2",
  "ROCKET_HIDEOUT_B4F_obj_3", "POKEMON_TOWER_7F_obj_1", "POKEMON_TOWER_7F_obj_2",
  "SILPH_CO_11F_obj_6", "SILPH_CO_11F_obj_7", "x", "",
}

for _, seed in ipairs(seeds) do
  local c, g = obp(68, seed)
  eq(g, 0, "Jessie SPR_PAL_ORANGE for seed " .. seed)
  eq(c and c[3][1], 255, "Jessie dark shade is red for seed " .. seed)
  local c2, g2 = obp(69, seed)
  eq(g2, 1, "James SPR_PAL_BLUE for seed " .. seed)
  eq(c2 and c2[3][3], 255, "James dark shade is blue for seed " .. seed)
  for idx = 65, 67 do
    local _, gm = obp(idx, seed)
    eq(gm, 0, "sprite " .. idx .. " SPR_PAL_ORANGE for seed " .. seed)
  end
end

local _, rocket = obp(23, "MT_MOON_B2F_obj_1")
check(rocket ~= 0 and rocket ~= 1, "Jessie/James differ from SPRITE_ROCKET")

for idx = 60, 69 do
  check(type(PaletteFX.worldPack().spriteAssignment[idx]) == "number",
    "Yellow character sprite " .. idx .. " has a fixed group")
end

PaletteFX.setMode(prevMode)
GameVersion.set(prevVer)

S.finish()
