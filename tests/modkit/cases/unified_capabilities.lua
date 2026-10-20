package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")
local Callbacks = require("src.mods.UnifiedCallbacks")

local GEN2 = { gold = true, silver = true, crystal = true }
local GEN3 = { firered = true, leafgreen = true, ruby = true, sapphire = true, emerald = true }

local function set(...)
  local out = {}
  for _, group in ipairs({ ... }) do for v in pairs(group) do out[v] = true end end
  return out
end

local EXPECT = {
  { "events", "phone.call_received", GEN2 },
  { "events", "radio.channel", GEN2 },
  { "events", "clock.day_changed", GEN2 },
  { "events", "mail.written", GEN2 },
  { "events", "mail.read", GEN2 },
  { "events", "unown.unlocked", GEN2 },
  { "events", "apricorn.converted", GEN2 },
  { "events", "bug_contest.scored", GEN2 },
  { "events", "intro.boot.title", GEN2 },
  { "hooks", "phone.contact_list", GEN2 },
  { "hooks", "battle.enemy_switch_or_item", set(GEN2, GEN3) },
  { "events", "breeding.egg_created", set(GEN2, GEN3) },
  { "events", "egg.hatched", set(GEN2, GEN3) },
  { "events", "happiness.changed", set(GEN2, GEN3) },
  { "events", "pokerus.infected", set(GEN2, GEN3) },
  { "events", "roamer.moved", set(GEN2, GEN3) },
  { "events", "roamer.encountered", set(GEN2, GEN3) },
  { "hooks", "breeding.compatibility", set(GEN2, GEN3) },
  { "hooks", "shiny.roll", set(GEN2, GEN3) },
  { "hooks", "gender.roll", set(GEN2, GEN3) },
  { "hooks", "held_item.trigger", set(GEN2, GEN3) },
  { "events", "battle.started", set(GEN2, GEN3, { red = true, blue = true, yellow = true }) },
}

for _, row in ipairs(EXPECT) do
  local surface, name, versions = row[1], row[2], row[3]
  for _, version in ipairs(GameVersion.ORDER) do
    local generation = GameVersion.generation(version)
    local ok = Callbacks.supports(surface, name, generation, version)
    T.eq(ok, versions[version] == true, ("%s %s on %s"):format(surface, name, version))
  end
  local gens = {}
  for version in pairs(versions) do gens[GameVersion.generation(version)] = true end
  for generation = 1, 3 do
    T.eq(Callbacks.supports(surface, name, generation) == true, gens[generation] == true,
      ("%s %s on generation %d"):format(surface, name, generation))
  end
end

for _, name in ipairs({ "phone.call_received", "radio.channel" }) do
  T.eq(Callbacks.supports("events", name, 3, "firered"), false, name .. " is not native to FireRed")
  local list = Callbacks.nativeVersions("events", name)
  T.same(list, { "gold", "silver", "crystal" }, name .. " native versions")
end
T.eq(Callbacks.nativeVersions("events", "no.such"), nil, "unknown name has no native versions")
T.finish()
