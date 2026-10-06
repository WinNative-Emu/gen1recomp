package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq, check = T.eq, T.check
local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local Family = require("src.import.gba.family")
local Versions = require("src.import.gba.versions")
local Builds = require("src.import.gba.rs_builds")
local C = require("src.core.game3.constants").of("ruby")
local Capabilities = require("src.core.game3.capabilities")
local Catalog = require("src.import.gba.map_catalog")
local before = GameVersion.get()

for _, game in ipairs({"ruby", "sapphire"}) do
  GameVersion.set(game)
  local row = Profile.active()
  eq(row.id,game,"native profile identity")
  local prefix = game == "ruby" and "RU_" or "SA_"
  eq(row.map.enginePrefix,prefix,"edition map namespace")
  eq(Catalog.resolve("MAP_INSIDE_OF_TRUCK"),prefix .. "INSIDE_OF_TRUCK","truck catalog")
  eq(row.map.newGameStart.map,prefix .. "INSIDE_OF_TRUCK","new-game truck")
  for _, name in pairs(row.map.semantics.vars) do check(C:var(name) ~= nil,"RS variable " .. name) end
  for _, name in pairs(row.map.semantics.flags) do check(C:flag(name) ~= nil,"RS flag " .. name) end
  for _, name in ipairs(row.map.tempFieldEventFlags) do check(C:flag(name) ~= nil,"RS temporary flag " .. name) end
  eq(#row.map.tempFieldEventFlags,4,"no Emerald Union Room reminder flag")
  eq(row.badges.flagBase,C:flag("FLAG_BADGE01_GET"),"RS badge flag base")
  eq(row.dex.national.var,"VAR_NATIONAL_DEX","national dex native variable")
  eq(row.dex.national.value,0x302,"national dex marker")
  local clean, problems = Capabilities.audit(row.capabilities)
  check(clean,"RS capabilities audit: " .. table.concat(problems or {},", "))
  for _, absent in ipairs({"unionRoom","mysteryGift","mirageTower","matchCall","battleFrontier","battleTents","battlePyramid","pyramidBag","frontierPass","apprentice","trainerHill","lilycoveLady","rayquazaScene"}) do
    eq(Profile.has({version=game},absent),false,"cart has no " .. absent)
  end
  for _, present in ipairs({"trainersEyes","pokeNav","battleTower","contests","secretBase","recordMixing","rtc","berryTrees","machAcroBike"}) do
    eq(Profile.has({version=game},present),true,"cart has " .. present)
  end
  local F = Family.active()
  local Collision = require("src.core.game3.collision")
  local Player = require("src.core.game3.player")
  local MB = require("src.core.game3.mb")
  local savedDef, savedBehavior, savedElevation = Collision._mapDef, Collision.behavior, Player.currentElevation
  local behavior = MB.id("NORMAL")
  Collision.behavior = function() return behavior end
  Collision._mapDef = { allowRunning=0 }
  check(Player.runningDisallowed(0,0),"runtime refuses running indoors")
  Collision._mapDef = { allowRunning=1 }
  check(not Player.runningDisallowed(0,0),"runtime permits normal outdoor tile")
  behavior = MB.id("LONG_GRASS")
  check(Player.runningDisallowed(0,0),"runtime refuses long grass")
  behavior = MB.id("FORTREE_BRIDGE")
  Player.currentElevation = 4
  check(Player.runningDisallowed(0,0),"runtime refuses bridge at even elevation")
  Player.currentElevation = 3
  check(not Player.runningDisallowed(0,0),"runtime permits bridge at odd elevation")
  Collision._mapDef, Collision.behavior, Player.currentElevation = savedDef, savedBehavior, savedElevation
  eq(C:id("event_objects",row.field.invalidGfx),5,"RS invalid graphics falls back to little boy")
  local Ow = require("src.core.game3.ow_sprites")
  eq(Ow.pose({frameCount=18},"down",1,true,{running=0}),12,"RS running lead frame")
  eq(Ow.pose({frameCount=18},"down",1,true,{running=1}),9,"RS running tail frame")
  for _, build in ipairs(Builds[game]) do
    Versions.select(build.sha1)
    eq(F:syms().game,build.build,"family uses selected native revision")
    local S = F:syms()
    check(S.size("gTilesetTiles_SecretBase") > 512*32,"Secret Base ELF span contains unused anonymous tiles")
    eq(F:uncompressedTileBytes(nil,S.off("gTilesetTiles_SecretBase")),512*32,"raw tiles follow RS copy length, not ELF span")
    local bytes = { [23]=3,[24]=255,[25]=255,[26]=1,[27]=8 }
    local rom = { get = function(_, offset) return bytes[offset % 28] or 0 end }
    local function header(mapType, offset)
      local h = {mapType=mapType}
      return F:decodeHeaderFlags(rom,offset or 0,h)
    end
    local outdoor = header(3)
    eq(outdoor.showMapName,1,"show name is the whole byte at 26")
    eq(outdoor.allowRunning,1,"running independent of show-name bit")
    eq(outdoor.allowEscaping,0,"unused escapeRope byte ignored")
    eq(outdoor.allowCycling,1,"outdoor cycling")
    eq(outdoor.battleType,8,"battle scene byte")
    eq(header(8).allowRunning,0,"running denied indoors")
    eq(header(8).allowCycling,0,"cycling denied indoors")
    eq(header(9).allowCycling,0,"cycling denied in secret bases")
    eq(header(5).allowCycling,0,"cycling denied underwater")
    eq(header(4).allowEscaping,1,"rope allowed underground")
    eq(header(4,S.off("SeafloorCavern_Room9")).allowCycling,0,"Seafloor sacred ground excludes bikes")
    eq(header(4,S.off("CaveOfOrigin_B4F")).allowCycling,0,"Origin sacred ground excludes bikes")
    eq(header(8,S.off("Route110_SeasideCyclingRoadNorthEntrance")).allowCycling,1,"north cycling road entrance exception")
    eq(header(8,S.off("Route110_SeasideCyclingRoadSouthEntrance")).allowCycling,1,"south cycling road entrance exception")
  end

  local Items = require("src.core.game3.items_data")
  local Bag = require("src.core.game3.bag")
  Items.applyProfile(game)
  Items.installPack({ count=349, items={
    [4]={name="POKE BALL",pocket="POKE_BALLS"},
    [13]={name="POTION",pocket="ITEMS"}, [14]={name="ANTIDOTE",pocket="ITEMS"},
    [133]={name="CHERI BERRY",pocket="BERRIES"}, [259]={name="MACH BIKE",pocket="KEY_ITEMS"},
    [289]={name="TM01",pocket="TM_HM"},
  }})
  eq(Items.CAPACITY.ITEMS,20,"RS twenty item slots")
  eq(Items.CAPACITY.KEY_ITEMS,20,"RS twenty key item slots")
  local bag = Bag.new()
  check(Bag.add(bag,13,99*19),"nineteen full Potion slots")
  check(Bag.add(bag,14,99),"twentieth item slot")
  check(not Bag.add(bag,13,1),"full RS item pocket rejects overflow")
  eq(Bag.get(bag,13),99*19,"failed add preserves quantities")
  check(Bag.add(bag,4,1),"other pocket remains available")
  check(Bag.add(bag,289,99),"TM stack reaches 99")
  check(not Bag.add(bag,289,1),"TM does not split into spare slots")
  check(Bag.add(bag,133,999),"berry stack reaches 999")
  check(not Bag.add(bag,133,1),"berry does not split into spare slots")
  check(Bag.add(bag,259,99*20),"twenty full key item slots")
  check(not Bag.add(bag,259,1),"RS key pocket capacity enforced")
end

GameVersion.set("emerald")
local Items = require("src.core.game3.items_data")
Items.ensureModel()
eq(Items.CAPACITY.ITEMS,30,"Emerald retains thirty item slots")
eq(Profile.has({version="emerald"},"unionRoom"),true,"Emerald wireless unchanged")
eq(Profile.has({version="emerald"},"matchCall"),true,"Emerald Match Call unchanged")
GameVersion.set(before)
Versions.select("firered")
T.finish("game3_rs_profile_test")
