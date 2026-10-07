package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

local function ir(s) return { { t = "text", s = s }, { t = "eos" } } end

local started
local Space = {
  ensureBundle = function()
    return { text = { gText_DadsAdvice = ir("gText_DadsAdvice"), gOtherText_DadsAdvice = ir("gOtherText_DadsAdvice") } }
  end,
  scriptKey = function(name) return "key:" .. name end,
  startScript = function(key, lid) started = { key = key, lid = lid } end,
}
package.loaded["src.core.game3.scripting.space"] = Space

local TextIR = require("src.core.game3.scripting.text_ir")
TextIR.toTextBox = function(x, ctx) return TextIR.toPlain(x, ctx or {}) end

local P = { facing = "left", cellX = 10, cellY = 10 }
package.loaded["src.core.game3.player"] = P
local facing
package.loaded["src.core.game3.objects"] = { at = function(x, y) return facing and facing(x, y) end }
local watered = {}
local STAGE = {}
package.loaded["src.core.game3.rse.berry_trees"] = {
  water = function(id)
    local s = STAGE[id] or 0
    if s < 1 or s > 4 then return false end
    watered[id] = true
    return true
  end,
}

local GameVersion = require("src.core.GameVersion")
local ItemsData = require("src.core.game3.items_data")
local ItemUse = require("src.core.game3.item_use")

local realInfo = ItemsData.info
ItemsData.info = function(id)
  if id == 268 then return { id = 268, fieldUseName = "ItemUseOutOfBattle_WailmerPail", pocket = "KEY_ITEMS" } end
  return realInfo(id)
end
ItemsData.fieldUseKind = function() return "key" end

local function sudowoodo(x, y)
  if x == 9 and y == 10 then return { localId = 14, def = { localId = 14, graphicsId = 228 } } end
end
local function tree(x, y)
  if x == 9 and y == 10 then return { localId = 3, def = { localId = 3, graphicsId = 0 }, berryTree = { id = 7 } } end
end

for _, version in ipairs({ "emerald", "ruby", "sapphire" }) do
  GameVersion.set(version)
  require("src.core.game3.profile").reset()
  local session = { version = version, party = {} }

  facing, started = sudowoodo, nil
  local ok, kind, text = ItemUse.useField(session, {}, 268)
  if version == "emerald" then
    T.check(ok == true and kind == "on_field", "emerald pail on the Sudowoodo is used")
    T.eq(started and started.key, "key:BattleFrontier_OutsideEast_EventScript_WaterSudowoodo",
      "emerald pail on the Sudowoodo starts WaterSudowoodo")
    T.eq(started and started.lid, 14, "emerald WaterSudowoodo runs as the Sudowoodo")
  else
    T.check(not ok and started == nil, version .. " has no Sudowoodo branch")
  end

  facing, started, STAGE[7], watered[7] = tree, nil, 2, nil
  ok, kind, text = ItemUse.useField(session, {}, 268)
  T.check(ok == true and kind == "on_field" and watered[7], version .. " pail waters a growing berry tree")
  local label = (version == "emerald") and "BerryTree_EventScript_ItemUseWailmerPail" or "S_WaterBerryTreeFromBag"
  T.eq(started and started.key, "key:" .. label, version .. " pail on a berry tree starts " .. label)
  T.eq(started and started.lid, 3, version .. " berry script runs as the tree")

  facing, started, STAGE[7] = tree, nil, 5
  ok, kind, text = ItemUse.useField(session, {}, 268)
  T.check(not ok and started == nil, version .. " berry-laden tree is not watered from the bag")
  T.check(type(text) == "string" and text:find("DadsAdvice", 1, true) ~= nil, version .. " refused pail gives DAD's advice")

  facing, started = nil, nil
  ok, kind, text = ItemUse.useField(session, {}, 268)
  T.check(not ok and started == nil, version .. " pail facing nothing is refused")
end

T.finish("game3_wailmer_pail_2697_test")
