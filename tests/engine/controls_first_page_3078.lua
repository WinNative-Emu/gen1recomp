package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local OptionRows = require("src.ui.OptionRows")
local Gen1Options = require("src.ui.OptionsMenu")
local Gen2Options = require("src.ui.gen2.OptionsMenu")
local LauncherSettings = require("src.import.LauncherSettings")

local GEN2_VISIBLE_ROWS = 7

local function newStack()
  local stack = { items = {} }
  function stack:push(s) self.items[#self.items + 1] = s end
  function stack:pop() return table.remove(self.items) end
  function stack:top() return self.items[#self.items] end
  return stack
end

local function gen1Game()
  local game = { data = {}, save = { options = {}, party = {},
                                     flags = {}, inventory = {} } }
  game.stack = newStack()
  game.input = { wasPressed = function() return false end,
                 isDown = function() return false end }
  function game:writeOptions() end
  return game
end

local function gen2Game()
  local game = { data = { audio = { sfx = {} } }, options = {} }
  game.stack = newStack()
  game.input = { wasPressed = function() return false end }
  return game
end

local function indexOf(view, id)
  for i, row in ipairs(view) do
    if row.id == id then return i end
  end
end

local realGetOS = love.system.getOS
local realGetenv = os.getenv

local function withPlatform(osName, touchEnv, fn)
  love.system.getOS = function() return osName end
  os.getenv = function(k)
    if k == "POKEPORT_TOUCH" then return touchEnv end
    return realGetenv(k)
  end
  local ok, err = pcall(fn)
  love.system.getOS = realGetOS
  os.getenv = realGetenv
  if not ok then error(err, 0) end
end

local platforms = {
  { "OS X", "0" }, { "OS X", "1" }, { "Android", nil }, { "iOS", nil },
}

for _, p in ipairs(platforms) do
  local tag = p[1] .. " touch=" .. tostring(p[2])
  withPlatform(p[1], p[2], function()
    for _, version in ipairs({ "red", "blue", "yellow" }) do
      GameVersion.set(version)
      local menu = Gen1Options.new(gen1Game())
      local i = indexOf(menu.view, "controls")
      check(i ~= nil, version .. " " .. tag .. ": CONTROLS is on the top level")
      check(i and i <= OptionRows.VISIBLE,
        version .. " " .. tag .. ": CONTROLS within the first "
        .. OptionRows.VISIBLE .. " rows (got " .. tostring(i) .. ")")
      eq(OptionRows.clampScroll(i or 99, 0, #menu.view, #menu.view + 1), 0,
        version .. " " .. tag .. ": cursor on CONTROLS needs no scroll")
      for _, id in ipairs({ "group.speed", "group.video", "group.graphics",
                            "group.audio", "performance", "group.battle",
                            "group.extras", "mods" }) do
        check(indexOf(menu.view, id) ~= nil,
          version .. " " .. tag .. ": " .. id .. " still on the top level")
      end
      eq(indexOf(menu.view, "group.speed"), 1,
        version .. " " .. tag .. ": SPEED still leads")
    end

    for _, version in ipairs({ "gold", "silver", "crystal" }) do
      GameVersion.set(version)
      local game = gen2Game()
      local menu = Gen2Options.new(game, { options = game.options })
      local view = menu:visible()
      local i = indexOf(view, "controls")
      check(i ~= nil, version .. " " .. tag .. ": CONTROLS is on the top level")
      check(i and i <= GEN2_VISIBLE_ROWS,
        version .. " " .. tag .. ": CONTROLS within the first "
        .. GEN2_VISIBLE_ROWS .. " rows (got " .. tostring(i) .. ")")
      menu.index = i or #view
      menu.scroll = 0
      menu:ensureVisible()
      eq(menu.scroll, 0, version .. " " .. tag .. ": cursor on CONTROLS needs no scroll")
      for _, id in ipairs({ "group.speed", "group.video", "group.graphics",
                            "group.audio", "performance", "group.battle",
                            "group.extras" }) do
        check(indexOf(view, id) ~= nil,
          version .. " " .. tag .. ": " .. id .. " still on the top level")
      end
      eq(indexOf(view, "group.speed"), 1,
        version .. " " .. tag .. ": SPEED still leads")
      check(view[#view].cancel == true, version .. " " .. tag .. ": BACK stays last")
    end
  end)
end

local RomText = require("src.core.game3.rom_text")
RomText.at = function() return "ROW" end
RomText.count = function() return 3 end
RomText.plain = function() return "TEXT" end
local Kit = require("src.ui.game3.rse.scene_kit")
local rsRows = {}
for i, t in ipairs({ "TEXT SPEED", "BATTLE SCENE", "BATTLE STYLE", "SOUND",
                     "BUTTON MODE", "FRAME", "CANCEL" }) do
  rsRows[i] = { text = t, x = 32, y = 24 + i * 16, choices = {} }
end
Kit.manifest = function(sub)
  if sub == "rse/menus" then
    return { layout = "rs", option = { rows = rsRows, title = "OPTION" } }
  end
end
require("src.ui.game3.chrome").setFrameType = function() end
local Screens = require("src.ui.game3.screens")
local Stack = require("src.ui.game3.stack")

local GEN3_VISIBLE_ROWS = 7

local function gen3Input(key)
  return { wasPressed = function(_, k) return k == key end }
end

local gen3Menus = {
  ["src.ui.game3.option_menu"] = {
    top = function(m) return m._pages[1] end,
    down = function(m) m.move(1) end,
  },
  ["src.ui.game3.rse.option_menu"] = {
    top = function(m) return m._st.pages[1] end,
    down = function(m) m.handleInput(gen3Input("down")) end,
  },
  ["src.ui.game3.rs.option_menu"] = {
    top = function(m) return m._pages[1] end,
    down = function(m) m.handleInput(gen3Input("down")) end,
    settle = function(m) for _ = 1, 40 do m.update() end end,
  },
}

for _, p in ipairs(platforms) do
  local tag = p[1] .. " touch=" .. tostring(p[2])
  withPlatform(p[1], p[2], function()
    for _, version in ipairs({ "firered", "leafgreen", "emerald", "ruby", "sapphire" }) do
      local session = { version = version }
      local path = Screens.path("option", session)
      local how = gen3Menus[path]
      check(how ~= nil, version .. " " .. tag .. ": OPTION routes to a known menu (" .. tostring(path) .. ")")
      if how then
        Stack.clear()
        local menu = require(path)
        local game = { options = {}, writeOptions = function() end }
        menu.show({ game = game, session = { version = version, engineOptions = game.options } })
        if how.settle then how.settle(menu) end
        local top = how.top(menu)
        local i = indexOf(top.rows, "controls")
        check(i ~= nil, version .. " " .. tag .. ": CONTROLS is on the top level")
        check(i and i <= GEN3_VISIBLE_ROWS,
          version .. " " .. tag .. ": CONTROLS within the first "
          .. GEN3_VISIBLE_ROWS .. " rows (got " .. tostring(i) .. ")")
        for _ = 1, (i or #top.rows) - 1 do how.down(menu) end
        eq(top.index, i, version .. " " .. tag .. ": cursor reaches CONTROLS")
        eq(top.scroll, 0, version .. " " .. tag .. ": cursor on CONTROLS needs no scroll")
        for _, id in ipairs({ "group.speed", "group.video", "group.graphics",
                              "group.audio", "group.battle", "group.extras",
                              "buttonMode", "mods" }) do
          check(indexOf(top.rows, id) ~= nil,
            version .. " " .. tag .. ": " .. id .. " still on the top level")
        end
        eq(indexOf(top.rows, "group.speed"), 1,
          version .. " " .. tag .. ": SPEED still leads")
        menu.close()
        Stack.clear()
      end
    end
  end)
end

local function findRow(model, label)
  for _, section in ipairs(model.sections) do
    for _, row in ipairs(section.rows) do
      if row.label == label then return row end
    end
  end
end

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local model = LauncherSettings.open({}, version)
  local reset = findRow(model, "RESET REBINDS")
  check(reset ~= nil and type(reset.action) == "function",
    version .. " gear offers RESET REBINDS")
  if reset then
    model.opts.bindings = { a = { key = "z" } }
    model.opts.gold.bindings = { speedUp = false, b = { key = "x" } }
    model.opts.touchControls = { layouts = { landscape = {} } }
    reset.action()
    eq(model.opts.gold.bindings, nil, version .. " reset clears gold.bindings")
    check(type(model.opts.bindings) == "table" and model.opts.bindings.a ~= nil,
      version .. " reset leaves the Gen 1 bindings alone")
    check(model.opts.touchControls.layouts ~= nil,
      version .. " reset leaves the shared touch layouts alone")
  end
end

do
  local model = LauncherSettings.open({}, "red")
  local reset = findRow(model, "RESET REBINDS")
  check(reset ~= nil, "red gear offers RESET REBINDS")
  model.opts.bindings = { a = { key = "z" } }
  model.opts.gold = { bindings = { speedUp = false } }
  reset.action()
  eq(model.opts.bindings, nil, "red reset clears the Gen 1 bindings")
  check(model.opts.gold.bindings and model.opts.gold.bindings.speedUp == false,
    "red reset leaves gold.bindings alone")
end

T.finish("controls first page 3078")
