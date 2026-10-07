#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq

local M = require("src.ui.game3.rs.bag_menu")

T.suite("rs bag popup cursor width")

eq(type(M.cursorWidth), "function", "cursorWidth exists")
if type(M.cursorWidth) == "function" then
  local w = M.cursorWidth
  local battle = { _battle = true }
  eq(w(battle, { rows = 2, cols = 1 }, 1), 40, "battle USE")
  eq(w(battle, { rows = 2, cols = 1 }, 2), 40, "battle CANCEL")
  eq(w(battle, { rows = 1, cols = 1 }, 1), 40, "battle CANCEL only")

  local party = { _location = "party" }
  eq(w(party, { rows = 2, cols = 1 }, 1), 48, "party GIVE")
  eq(w(party, { rows = 1, cols = 1 }, 1), 48, "party CANCEL only")

  local field = {}
  local g22 = { rows = 2, cols = 2 }
  eq(w(field, g22, 1), 47, "field 2x2 left top")
  eq(w(field, g22, 2), 47, "field 2x2 left bottom")
  eq(w(field, g22, 3), 48, "field 2x2 right top")
  eq(w(field, g22, 4), 48, "field 2x2 right bottom")

  local g32 = { rows = 3, cols = 2 }
  eq(w(field, g32, 1), 96, "berry pouch CHECK TAG")
  eq(w(field, g32, 2), 47, "berry pouch left middle")
  eq(w(field, g32, 3), 47, "berry pouch left bottom")
  eq(w(field, g32, 4), 48, "berry pouch right top")
  eq(w(field, g32, 6), 48, "berry pouch right bottom")

  local blender = { _location = "blender" }
  eq(w(blender, g22, 1), 96, "blender CHECK TAG")
  eq(w(blender, g22, 2), 47, "blender CONFIRM")
  eq(w(blender, g22, 4), 48, "blender CANCEL")
end

T.finish("rs bag popup cursor width")
