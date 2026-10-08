#!/usr/bin/env luajit
-- pokeruby/src/starter_choose.c:522

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq

local Policy = require("src.ui.game3.rs.starter_choose_policy")

T.suite("rs starter category")

eq(Policy.categoryText("WOOD GECKO", "POKéMON"), "WOOD GECKO POKéMON", "a short category is kept whole")
eq(Policy.categoryText("ABCDEFGHIJKLMN", "POKéMON"), "ABCDEFGHIJK POKéMON", "a long category keeps 11 characters")
eq(Policy.categoryText("もりトカゲ", "ポケモン"), "もりトカゲ ポケモン", "a 15-byte Japanese category is kept whole")
eq(Policy.categoryText("ぬまうお", "ポケモン"), "ぬまうお ポケモン", "a 12-byte Japanese category is kept whole")
eq(Policy.categoryText("もりトカゲポケモンのなかま", "ポケモン"), "もりトカゲポケモンのな ポケモン",
  "a Japanese category keeps 11 whole characters")
eq(Policy.categoryText("ÉCLAIRÉCLAIRÉ", "POKéMON"), "ÉCLAIRÉCLAI POKéMON", "accented letters count as one character")

T.finish("rs starter category")
