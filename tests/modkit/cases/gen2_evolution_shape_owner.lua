package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Version = require("src.core.GameVersion")

local function manifest(id, api, extra)
  return ('{"id":"%s","name":"%s","version":"1.0.0","api":%d,"games":["all"],"entry":"main.lua"%s}')
    :format(id, id, api, extra or "")
end

local files = {
  ["mods/a_new/manifest.json"] = manifest("a_new", 3),
  ["mods/a_new/main.lua"] = [[
local mod = ...
mod.content.evolution_methods:register("SHAPED", { check = function() return true end })
]],
  ["mods/b_old/manifest.json"] = manifest("b_old", 2, ',"dependencies":{"a_new":"*"}'),
  ["mods/b_old/main.lua"] = [[
local mod = ...
mod.content.evolution_methods:patch("SHAPED", { describe = function() return "x" end })
mod.content.evolution_methods:register("PLAIN", { check = function() return true end })
]],
  ["mods/c_new/manifest.json"] = manifest("c_new", 3, ',"dependencies":{"b_old":"*"}'),
  ["mods/c_new/main.lua"] = [[
local mod = ...
mod.content.evolution_methods:patch("PLAIN", { describe = function() return "y" end })
]],
}

Version.set("gold")
T.sdk.captureRuntime()
local data = require("tests.modkit.fixtures").fresh()
local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 2, version = "gold", dev = true })
local ok, err = pcall(loader.load, loader, data)
T.check(ok, "loads: " .. tostring(err))
T.eq(#loader.errors, 0, "no load errors: " .. table.concat(loader.errors, "; "))
local methods = data.gen2EvolutionMethods or {}
T.check(methods.SHAPED ~= nil and methods.SHAPED.gen1Shape == true,
  "an API 3 check keeps the Gen 1 shape after an API 2 patch of another field")
T.check(methods.PLAIN ~= nil and methods.PLAIN.gen1Shape == nil,
  "an API 2 check does not take the Gen 1 shape from a later API 3 patch")
T.sdk.restoreRuntime()
T.finish("gen2 evolution shape owner")
