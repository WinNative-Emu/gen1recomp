local U = require("tests.drivers.util")
local Loop = require("tests.support.union_prep_loopback")

local D = {}

local function deepCopy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local out = {}
  seen[v] = out
  for k, x in pairs(v) do out[k] = deepCopy(x, seen) end
  return out
end
D.copy = deepCopy

local function deepEqual(a, b, seen)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  seen = seen or {}
  if seen[a] == b then return true end
  seen[a] = b
  for k, v in pairs(a) do if not deepEqual(v, b[k], seen) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
D.equal = deepEqual

function D.run(game, cfg)
  local fails = 0
  local version = cfg.version
  local dir = os.getenv("POKEPORT_SHOT_DIR") or ("/tmp/union-prep-" .. version)
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. version .. " " .. line)
    return cond
  end
  local function finish()
    print((fails == 0 and "PASS" or "FAIL") .. " union_prep_battle " .. version .. " failures=" .. fails)
    love.event.quit(fails == 0 and 0 or 1)
    U.wait(10)
  end
  local function shot(name)
    U.wait(4)
    U.still(game, ("%s/%s_%s.png"):format(dir, version, name))
  end

  local before = deepCopy(cfg.snapshot())
  local loop = Loop.new()
  local prep = loop:prep()
  loop:setRules(cfg.rules)
  local Open = require("src.ui.union.prep.Open")
  local called, result, outcome = false, nil, nil
  local screen, model = Open.battle(game, nil, prep, function(r, o)
    called, result, outcome = true, r, o
  end, { version = version, opponent = cfg.opponent, gameplayMods = false })
  ok(screen ~= nil and model ~= nil, "the prep screen opens")
  U.wait(10)
  local deadline = love.timer.getTime() + 20
  while model and model.rentalSet.pending and love.timer.getTime() < deadline do U.wait(1) end
  ok(model and not model.rentalSet.pending, "the rentals settle")

  local function labels(pg)
    local out = {}
    for _, it in ipairs(pg.items) do out[#out + 1] = it.label end
    return table.concat(out, ",")
  end
  local function find(id, label)
    local pg = model:page()
    for i, it in ipairs(pg.items) do
      if it.id == id and (label == nil or it.label:find(label, 1, true)) then return i, it end
    end
    return nil, nil, pg
  end
  local function choose(id, label)
    local idx, _, pg = find(id, label)
    if not ok(idx ~= nil, ("%s has %s %s"):format(model.step, id, tostring(label or ""))) then
      print("  items: " .. labels(pg or model:page()))
      return false
    end
    for _ = 1, 60 do
      if model.cursor == idx then break end
      U.tap(game, "down")
      U.wait(2)
    end
    U.tap(game, "a")
    U.wait(4)
    return true
  end
  local function lines()
    return table.concat(model:page().lines or {}, " ")
  end

  ok(model.step == "rules", "starts on the opponent and rules")
  ok(lines():find(cfg.opponent.name, 1, true) ~= nil, "names the opponent")
  shot("01_rules")
  choose("changes")
  ok(model.view and model.view.kind == "changes", "the rules list opens")
  shot("02_rules_list")
  U.tap(game, "b")
  U.wait(4)
  choose("rentals")
  ok(model.view and model.view.kind == "rentals", "the rental list opens")
  local rp = model:page()
  ok(#rp.items - 1 == cfg.rentalCount, ("all %d rentals are listed (%d)"):format(cfg.rentalCount, #rp.items - 1))
  shot("03_rentals")
  U.tap(game, "down")
  U.wait(2)
  U.tap(game, "down")
  U.wait(2)
  shot("04_rental_detail")
  U.tap(game, "b")
  U.wait(4)
  choose("continue")
  ok(model.step == "problems", "team check follows")
  for _, want in ipairs(cfg.problems or {}) do
    ok(lines():upper():find(want:upper(), 1, true) ~= nil, "explains: " .. want)
  end
  shot("05_problems")
  choose("continue")
  if cfg.substitute then
    ok(model.step == "substitute", "the incompatible Pokemon gets a substitute screen")
    shot("06_substitute")
    if cfg.substitute.owned then
      local i = find("swap_owned", cfg.substitute.owned)
      ok(i == 1, "an owned " .. cfg.substitute.owned .. " ranks first")
    end
    choose(cfg.substitute.id, cfg.substitute.label)
  end
  if cfg.pickMove then
    ok(model.step == "moves", "move adjustments follow")
    local _, first = find("move")
    ok(first ~= nil, "a legal replacement is offered")
    local _, empty = find("empty")
    ok(empty ~= nil, "an empty slot is offered")
    shot("07_moves")
    choose("move", first and first.label)
  end
  ok(model.step == "size", "team size follows")
  shot("08_size_waiting")
  loop:peerRoster(cfg.peerSize)
  U.wait(8)
  ok(prep.size == cfg.peerSize, "the relay agrees on " .. cfg.peerSize)
  local _, cont = find("continue")
  ok(cont and cont.disabled, "continue needs a sit-out choice first")
  shot("09_size_sit_out")
  choose("toggle", cfg.sitOut)
  shot("10_size_chosen")
  choose("continue")
  ok(model.step == "confirm", "final confirmation follows")
  shot("11_confirm")
  choose("mon")
  ok(model.view and model.view.kind == "mon", "a battler's data opens")
  shot("12_battler")
  U.tap(game, "b")
  U.wait(4)
  choose("ready")
  ok(model.step == "waiting", "confirm waits for the opponent")
  shot("13_waiting")
  loop:peerReady()
  U.wait(12)
  ok(called and outcome == "go", "both confirmations finish the prep with go")
  ok(result and #result.records == cfg.peerSize, "the result has the agreed team size")
  local rental = false
  for _, rec in ipairs(result and result.records or {}) do if rec.rental then rental = true end end
  ok(rental == (cfg.expectRental == true), "the rental is " .. (cfg.expectRental and "in" or "not in") .. " the result")
  ok(deepEqual(before, cfg.snapshot()), "the active save's party and PC are untouched")
  ok(cfg.closed(screen), "the prep screen is gone")
  U.wait(10)
  shot("14_after")
  return finish()
end

return D
