package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ImportGc = require("src.import.ImportGc")

local function envWith(set)
  return function(name) return set[name] end
end

for _, name in ipairs({ "POKEPORT_RG34XXSP", "TRIMUI", "MUOS", "KNULLI" }) do
  check(ImportGc.lowMemoryHost(envWith({ [name] = "1" })), name .. "=1 is a low-memory import host")
end
check(not ImportGc.lowMemoryHost(envWith({})), "a desktop env is not a low-memory host")
check(not ImportGc.lowMemoryHost(envWith({ POKEPORT_RG34XXSP = "0" })), "POKEPORT_RG34XXSP=0 is not a low-memory host")

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

for _, path in ipairs({ "build-rg34xxsp.sh", "scripts/portmaster/Gen1Recomp.sh" }) do
  local env, found = {}, 0
  for line in read(path):gmatch("[^\n]+") do
    local name = line:match('^%s*export%s+([%w_]+)=["\']?1["\']?%s*$')
    if name then
      env[name] = "1"
      found = found + 1
    end
  end
  check(found > 0, path .. " exports at least one launcher marker")
  check(ImportGc.lowMemoryHost(envWith(env)), path .. " launcher markers are recognised as a low-memory host")
end

collectgarbage("setpause", 200)
collectgarbage("setstepmul", 200)
eq(ImportGc.tune(envWith({ POKEPORT_RG34XXSP = "1" })), true, "RG34XXSP import tunes the collector")
eq(collectgarbage("setpause", 200), ImportGc.PAUSE, "RG34XXSP pause applied")
eq(collectgarbage("setstepmul", 200), ImportGc.STEPMUL, "RG34XXSP stepmul applied")

T.finish("import_gc_rg34xxsp_bug2916")
