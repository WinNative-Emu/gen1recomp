package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Names = require("src.import.gba.rs.anim_names")
local Emerald = require("src.import.gba.anim_names_emerald")
local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")
local AnimTasks = require("src.core.game3.battle.anim_tasks")
local Versions = require("src.import.gba.versions")

local function count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

eq(count(Names.templates), 329, "329 RS sprite templates")
eq(count(Names.callbacks), 269, "269 RS sprite callbacks")
eq(count(Names.tasks), 208, "208 RS visual/sound tasks")

local missCb, missTask = {}, {}
for key, name in pairs(Names.callbacks) do
  local bound = AnimCallbacks.get(name) ~= AnimCallbacks.SimpleFadeOut
    or AnimTasks.REGISTRY["_noGfx_" .. name] ~= nil
  if not bound then missCb[#missCb + 1] = key .. ">" .. name end
end
for key, name in pairs(Names.tasks) do
  if not AnimTasks.REGISTRY[name] then missTask[#missTask + 1] = key .. ">" .. name end
end
table.sort(missCb)
table.sort(missTask)
eq(table.concat(missCb, " "), "", "every RS callback resolves to a runtime callback")
eq(table.concat(missTask, " "), "", "every RS task resolves to a runtime task")

local emTemplates = {}
for _, v in pairs(Emerald.templates) do emTemplates[v] = true end
local seen, dup = {}, {}
for key, name in pairs(Names.templates) do
  if seen[name] then dup[#dup + 1] = name end
  seen[name] = key
  check(emTemplates[name], "RS template " .. key .. " carries an Emerald template name (" .. name .. ")")
end
eq(#dup, 0, "RS template canonical names are unique")

local spot = {
  callbacks = {
    sub_80DC8F4 = "LeechLifeNeedle", sub_80DC068 = "RedX", sub_80DD8E8 = "RockTomb",
    sub_80D1318 = "UproarRing", sub_80D2D68 = "JaggedMusicNote", AnimConfusionDuck = "ConfusionDuck",
    sub_80CA9A8 = "sub_80CA9A8",
  },
  tasks = {
    sub_807BB88 = "StatsChange", sub_80D2CF8 = "UproarDistortion", sub_80E26BC = "ShakeBattleTerrain",
    sub_80CE7E0 = "DoubleTeam", sub_812B2B8 = "sub_812B2B8",
  },
  templates = {
    gBattleAnimSpriteTemplate_83DA8F4 = "gRedXSpriteTemplate",
    gBattleAnimSpriteTemplate_83DADA8 = "gRockTombRockSpriteTemplate",
    gBattleAnimSpriteTemplate_83D79A4 = "gUproarRingSpriteTemplate",
    gBattleAnimSpriteTemplate_83D7CC8 = "gJaggedMusicNoteSpriteTemplate",
    gBattleAnimSpriteTemplate_83DAB10 = "gLeechLifeNeedleSpriteTemplate",
  },
}
for section, rows in pairs(spot) do
  for key, want in pairs(rows) do eq(Names[section][key], want, section .. " " .. key) end
end

local V = Versions.forGame("sapphire")
for i, n in pairs({ [0] = "PSN", "CONFUSION", "BRN", "INFATUATION", "SLP", "PRZ", "FRZ", "CURSED", "NIGHTMARE" }) do
  eq(V.BATTLE_ANIM_STATUS_NAMES[i], "STATUS_" .. n, "RS status anim " .. i)
end
eq(V.BATTLE_ANIM_GENERAL_NAMES[7], "HELD_ITEM_EFFECT", "RS general anim 7 uses the runtime name")
eq(V.BATTLE_ANIM_GENERAL_NAMES[9], "FOCUS_BAND", "RS general anim 9 uses the runtime name")
eq(count(V.ANIM_CALLBACK_NAMES), 269, "RS callback address map built from syms")
eq(count(V.ANIM_TASK_NAMES), 208, "RS task address map built from syms")
eq(count(V.ANIM_TEMPLATE_NAMES), 329, "RS template address map built from syms")

T.finish("game3_rs_anim_names_test")
