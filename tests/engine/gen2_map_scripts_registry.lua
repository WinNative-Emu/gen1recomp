package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Schemas = require("src.mods.Schemas")
local Vm = require("src.script.gen2.Vm")

local spec = Schemas.shapeFor("map_scripts", Schemas.REGISTRIES.map_scripts, 2)
T.eq(Schemas.targetFor("map_scripts", Schemas.REGISTRIES.map_scripts, 2), "gen2Scripts",
  "map_scripts lands in the Gen 2 VM's script pool")
T.eq(Schemas.gatedFor("map_scripts", 2), false, "map_scripts is not gated on Gen 2")
T.eq(spec.semantics, "record", "Gen 2 scripts are whole row lists, not compose chains")
T.eq(Schemas.shapeFor("map_scripts", Schemas.REGISTRIES.map_scripts, 1).semantics, "compose",
  "Gen 1 keeps the compose chains")

local MOD = {
  ["mods/fix_gold_scripts/manifest.json"] = [[{
    "id": "fix_gold_scripts",
    "name": "Fixture Gold Scripts",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2,
    "gen2compat": true
  }]],
  ["mods/fix_gold_scripts/main.lua"] = [[
    local mod = ...
    local scripts = mod.content.map_scripts
    mod.exports.cartScript = scripts:get("55:4e2e")
    mod.exports.cartMovement = scripts:get("movement:5a:580a")
    mod.exports.ids = {}
    for id in scripts:each() do mod.exports.ids[id] = true end
    mod.exports.collides = not pcall(scripts.register, scripts, "55:4e2e", { { op = "end" } })
    mod.exports.reserved = not pcall(scripts.register, scripts, "movements", { { op = "end" } })
    mod.content.text:register("MYMOD_HELLO", "Hello from a mod.")
    scripts:register("MYMOD_TALK", {
      { op = "opentext" },
      { op = "writetext", text = "MYMOD_HELLO" },
      { op = "closetext" },
      { op = "applymovement", object = 2, movement = "MYMOD_WALK" },
      { op = "end" },
    })
    scripts:register("movement:MYMOD_WALK", { 0x0d, 0x0d, 0x47 })
    scripts:override("55:4e2e", { { op = "jumptext", text = "MYMOD_HELLO" } })
    scripts:override("movement:5a:580a", { 0x0c, 0x47 })
  ]],
}

local function freshData()
  local data = require("tests.modkit.fixtures").fresh()
  data.gen2Scripts = {
    generation = 2,
    ["55:4e2e"] = { { op = "opentext" }, { op = "writetext", text = "55:51b9" },
                    { op = "closetext" }, { op = "end" } },
    movements = { ["5a:580a"] = { 0x0f, 0x47 } },
  }
  data.gen2Text = { ["55:51b9"] = "Cart text." }
  return data
end

local data = freshData()
local scriptsTable, movementsTable = data.gen2Scripts, data.gen2Scripts.movements
local run = T.sdk.loadMods({ "mods/fix_gold_scripts" }, {
  fs = T.sdk.memfs(MOD), data = data, generation = 2,
})
local status
for _, entry in ipairs(run.loader:status().available) do
  if entry.id == "fix_gold_scripts" then status = entry end
end
T.eq(status and status.state, "loaded",
  "the Gold scripts mod loads (" .. tostring(run.errors[1]) .. ")")

local exports = run.loader.exports.fix_gold_scripts or {}
T.eq(exports.cartScript and exports.cartScript[2].text, "55:51b9",
  "a mod reads the cart's own rows by script key")
T.eq(exports.cartMovement and exports.cartMovement[1], 0x0f,
  "and a cart movement through the movement: prefix")
T.check(exports.ids and exports.ids["55:4e2e"] and exports.ids["movement:5a:580a"]
  and not exports.ids.movements and not exports.ids.generation,
  "each() lists scripts and movements, not the pool's own bookkeeping keys")
T.check(exports.collides, "register on a cart key collides and asks for override")
T.check(exports.reserved, "the movements subtable is not a writable script id")

T.check(data.gen2Scripts == scriptsTable and data.gen2Scripts.movements == movementsTable,
  "the merge lands in the tables the VM already holds")
T.eq(#data.gen2Scripts.MYMOD_TALK, 5, "a registered script lands in data.gen2Scripts")
T.eq(data.gen2Scripts["55:4e2e"][1].op, "jumptext", "an override replaces the cart script")
T.eq(data.gen2Scripts.movements.MYMOD_WALK[3], 0x47,
  "a registered movement lands in data.gen2Scripts.movements")
T.eq(data.gen2Scripts.movements["5a:580a"][1], 0x0c, "an override replaces a cart movement")
T.eq(data.gen2Scripts.movement, nil, "no stray key is left at the pool root")
T.eq(data.gen2Scripts["movement:MYMOD_WALK"], nil, "the prefixed id is not written as a script")
T.eq(data.gen2Scripts.generation, 2, "the pool's own keys survive")

local shown, moved = {}, nil
local vm = Vm.new(data.gen2Scripts, data.gen2Text, nil, {
  showText = function(text, done) shown[#shown + 1] = text; done() end,
  applyMovement = function(object, bytes, done) moved = { object = object, bytes = bytes }; done() end,
})
T.check(vm:start("MYMOD_TALK"), "the VM starts a mod's script by its key")
T.eq(shown[1], "Hello from a mod.", "the mod's writetext prints the mod's text")
T.eq(moved and moved.object, 2, "applymovement moves the named object")
T.eq(moved and moved.bytes and moved.bytes[1], 0x0d, "with the mod's own steps")
T.check(not vm:running(), "and the script runs to its end")

run.release()

T.finish()
