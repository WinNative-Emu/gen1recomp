-- ../pokecrystal/engine/overworld/scripting.asm:467
--   tools/run_driver.sh crystal <identity> tests/drivers/crystal_item_jingle_2732.lua <shotdir>
local U = require("tests.drivers.util")
local Sound = require("src.core.Sound")
local Vm = require("src.script.gen2.Vm")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR")
  or ".bazinga/BSA/10-07-26-02-gen3text/shots/2732"

local GIFTS = {
  { item = "POTION", want = "Sfx_Item", tag = "potion" },
  { item = "TM_ROAR", want = "Sfx_GetTm", tag = "tm_roar" },
}

return function(game)
  local fails = 0
  local function say(line) print("[2732] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
    return cond
  end
  local function finish()
    say(fails == 0 and "all claims passed" or (fails .. " claims failed"))
    love.event.quit(fails == 0 and 0 or 1)
    while true do U.wait(60) end
  end

  local f = 0
  local function step(n)
    for _ = 1, (n or 1) do
      U.wait(1)
      f = f + 1
    end
  end

  local plays = {}
  local realPlay = Sound.play
  Sound.play = function(data, name, ...)
    local src = realPlay(data, name, ...)
    plays[#plays + 1] = { name = Sound.resolve and Sound.resolve(data, name) or name,
      frame = f, started = src ~= nil }
    return src
  end

  local function boxText(top)
    if not (top and top.isTextBox and top.pages) then return "" end
    local out = {}
    for _, page in ipairs(top.pages) do
      for _, line in ipairs(page) do out[#out + 1] = tostring(line) end
    end
    return table.concat(out, " ")
  end
  local function isBox(top, needle)
    return boxText(top):find(needle, 1, true) ~= nil
  end
  local function press()
    table.insert(game.input.pressQueue, "a")
    game.input.state.a = true
    step(1)
    game.input.state.a = false
  end

  step(45)
  local world = game.world
  if not ok(world and world.map, "the gen 2 world booted") then finish() end
  world:warpToMapId("ROUTE_29", 48, 3, "up")
  step(30)
  world.noWildEncounters = true

  for _, gift in ipairs(GIFTS) do
    local def = game.data.items and game.data.items[gift.item]
    if not ok(def ~= nil, "the cache names " .. gift.item) then finish() end
    game.save.inventory = game.save.inventory or {}
    game.save.inventory[gift.item] = nil
    local first = #plays + 1
    world.vm:start({
      { op = "opentext" },
      { op = "verbosegiveitem", item = def.index, quantity = 1 },
      { op = "closetext" },
      { op = "end" },
    })

    local function chimeFrame()
      for i = first, #plays do
        if plays[i].name == gift.want and plays[i].started then
          return plays[i].frame
        end
      end
      return nil
    end

    local typed, box
    for _ = 1, 600 do
      step(1)
      local top = game.stack:top()
      if isBox(top, "received") and top.done then
        typed, box = f, top
        break
      end
    end
    if not ok(typed ~= nil, gift.item .. ": the received line finished typing") then
      finish()
    end
    for _ = 1, 30 do
      if chimeFrame() then break end
      step(1)
    end
    local chime = chimeFrame()
    say(("%s: typed@%d chime@%s"):format(gift.item, typed, tostring(chime)))
    ok(chime ~= nil and chime >= typed - 1 and chime - typed <= 2,
      ("jingle starts on the typing-end frame (%s, typed %d, %s at %s)")
        :format(gift.item, typed, gift.want, tostring(chime)))

    local stayed = game.stack:top() == box
    if chime then
      step(20)
      press()
      step(2)
      stayed = stayed and game.stack:top() == box
      U.still(game, ("%s/2732_%s_01_received_jingle_ringing.png")
        :format(SHOT_DIR, gift.tag))
      local deadline = love.timer.getTime() + 8
      while Sound.sfxBusy() and love.timer.getTime() < deadline do
        stayed = stayed and game.stack:top() == box
        step(1)
      end
      step(30)
      stayed = stayed and game.stack:top() == box
    end

    local pressFrame = f + 1
    press()
    ok(stayed and chime ~= nil and chime < pressFrame,
      ("box stays up until the press (%s, chime %s, press %d)")
        :format(gift.item, tostring(chime), pressFrame))

    local pocketAt, bare = nil, 0
    for _ = 1, 600 do
      local top = game.stack:top()
      if isBox(top, "put the") then pocketAt = f break end
      if top == nil then bare = bare + 1 end
      if top == box and not chime then press() else step(1) end
    end
    ok(pocketAt ~= nil and pocketAt - pressFrame <= 2 and bare == 0,
      ("pocket page after the press (%s, press %d, pocket %s, %d bare frames)")
        :format(gift.item, pressFrame, tostring(pocketAt), bare))
    for _ = 1, 600 do
      local top = game.stack:top()
      if not isBox(top, "put the") or top.done then break end
      step(1)
    end
    U.still(game, ("%s/2732_%s_02_pocket_page.png"):format(SHOT_DIR, gift.tag))

    for _ = 1, 60 do
      if not world:busy() and game.stack:top() == nil then break end
      press()
      step(6)
    end
    ok((game.save.inventory[gift.item] or 0) > 0,
      gift.item .. " reached the pack")
  end

  -- ../pokecrystal/engine/events/hidden_item.asm:1
  local HiddenItems = require("src.world.gen2.HiddenItems")
  local potion = game.data.items.POTION
  game.save.inventory.POTION = nil
  world.events:set(173, false)
  local first = #plays + 1
  world.vm:start(HiddenItems.pickupScript(potion.index, 173))
  local typed, box
  for _ = 1, 600 do
    step(1)
    local top = game.stack:top()
    if isBox(top, "found") and top.done then
      typed, box = f, top
      break
    end
  end
  ok(typed ~= nil, "hidden item: the found line finished typing")
  local chime
  for _ = 1, 30 do
    for i = first, #plays do
      if plays[i].name == "Sfx_Item" and plays[i].started then
        chime = chime or plays[i].frame
      end
    end
    if chime then break end
    step(1)
  end
  ok(typed and chime and chime >= typed - 1 and chime - typed <= 2,
    ("hidden item: jingle starts on the typing-end frame (typed %s, chime %s)")
      :format(tostring(typed), tostring(chime)))
  if chime then
    step(20)
    U.still(game, SHOT_DIR .. "/2732_hidden_01_found_jingle_ringing.png")
  end
  local stayed, pocketAt, busyAtPocket, bare = true, nil, nil, 0
  local deadline = love.timer.getTime() + 8
  while love.timer.getTime() < deadline do
    local top = game.stack:top()
    if isBox(top, "put the") then
      pocketAt, busyAtPocket = f, Sound.sfxBusy()
      break
    end
    if top == nil then bare = bare + 1 end
    stayed = stayed and top == box
    step(1)
  end
  ok(box ~= nil and stayed and pocketAt ~= nil and not busyAtPocket and bare == 0,
    ("hidden item: found line holds through the jingle, then itemnotify with no press"
      .. " (pocket %s, %d bare frames)"):format(tostring(pocketAt), bare))
  for _ = 1, 600 do
    local top = game.stack:top()
    if not isBox(top, "put the") or top.done then break end
    step(1)
  end
  U.still(game, SHOT_DIR .. "/2732_hidden_02_pocket_page.png")
  for _ = 1, 60 do
    if not world:busy() and game.stack:top() == nil then break end
    press()
    step(6)
  end
  ok((game.save.inventory.POTION or 0) > 0, "hidden item: POTION reached the pack")

  -- ../pokecrystal/maps/VioletGym.asm:26
  -- ../pokecrystal/maps/GoldenrodBikeShop.asm:23
  -- ../pokecrystal/maps/ElmsLab.asm:259
  local SITES = {
    { tag = "badge", needle = "received\nZEPHYRBADGE", want = "Sfx_GetBadge",
      after = "next" },
    { tag = "key_item", needle = "borrowed a\nBICYCLE", want = "Sfx_KeyItem",
      after = "pocket" },
    { tag = "phone", needle = "ELM's\nphone number", want = "Sfx_RegisterPhoneNumber",
      after = "button" },
  }
  local function findSite(needle)
    local vm = world.vm
    for _, list in pairs(vm.scripts) do
      if type(list) == "table" then
        for i, row in ipairs(list) do
          local body = type(row) == "table"
            and (row.op == "writetext" or row.op == "farwritetext")
            and vm.text[row.text]
          if type(body) == "string" and body:find(needle, 1, true)
              and list[i + 1] and list[i + 1].op == "playsound" then
            return list, i
          end
        end
      end
    end
  end
  local function slice(list, i)
    local rows = {}
    if list[i - 1] and list[i - 1].op == "giveitem" then rows[1] = list[i - 1] end
    local texts, closed = 0, false
    for n = i, math.min(#list, i + 20) do
      local row = list[n]
      local op = row.op
      if op ~= "iftrue" and op ~= "iffalse" and op ~= "scall"
          and op ~= "specialphonecall" then
        rows[#rows + 1] = row
      end
      if op == "writetext" or op == "farwritetext" then texts = texts + 1 end
      if op == "closetext" then closed = true break end
      if texts == 2 then break end
    end
    if not closed then
      rows[#rows + 1] = { op = "waitbutton" }
      rows[#rows + 1] = { op = "closetext" }
    end
    rows[#rows + 1] = { op = "end" }
    return rows
  end

  for _, site in ipairs(SITES) do
    local list, at = findSite(site.needle)
    if not ok(list ~= nil, site.tag .. ": the cache has the writetext / playsound site") then
      finish()
    end
    local rows = slice(list, at)
    local idleBy = love.timer.getTime() + 8
    while Sound.sfxBusy() and love.timer.getTime() < idleBy do step(1) end
    local first = #plays + 1
    world.vm:start(rows)
    local typed, box
    for _ = 1, 600 do
      step(1)
      local top = game.stack:top()
      if isBox(top, site.needle:match("[^\n]+$")) and top.done then
        typed, box = f, top
        break
      end
    end
    ok(typed ~= nil, site.tag .. ": the line finished typing")
    local chime
    for _ = 1, 30 do
      for n = first, #plays do
        if plays[n].name == site.want and plays[n].started then
          chime = chime or plays[n].frame
        end
      end
      if chime then break end
      step(1)
    end
    local heard = {}
    for n = first, #plays do
      heard[#heard + 1] = ("%s@%d%s"):format(tostring(plays[n].name), plays[n].frame,
        plays[n].started and "" or "(dropped)")
    end
    say(site.tag .. ": sfx " .. table.concat(heard, " "))
    ok(typed and chime and chime >= typed - 1 and chime - typed <= 2
        and game.stack:top() == box,
      ("%s jingle starts while the text is up (typed %s, %s at %s)")
        :format(site.tag, tostring(typed), site.want, tostring(chime)))
    if chime then
      step(20)
      press()
      step(2)
      U.still(game, ("%s/2732b_%s_01_jingle_under_text.png"):format(SHOT_DIR, site.tag))
    end
    local held, deadline = true, love.timer.getTime() + 8
    while Sound.sfxBusy() and love.timer.getTime() < deadline do
      held = held and game.stack:top() == box
      step(1)
    end
    ok(box ~= nil and held and not Sound.sfxBusy(),
      site.tag .. ": the box ignores A and stays up while the jingle rings")

    local bare, nextAt = 0, nil
    if site.after == "button" then
      step(30)
      ok(game.stack:top() == box,
        site.tag .. ": after the jingle the box waits for the press (WaitButton)")
      press()
      step(3)
      ok(game.stack:top() ~= box, site.tag .. ": one press closes it")
    else
      local needle = site.after == "pocket" and "put the" or nil
      for _ = 1, 120 do
        local top = game.stack:top()
        if top == nil then bare = bare + 1 end
        if top ~= box and top and top.isTextBox
            and (not needle or isBox(top, needle)) then
          nextAt = f
          break
        end
        step(1)
      end
      ok(nextAt ~= nil and bare == 0,
        ("%s: the next page replaces the line with no press (%s, %d bare frames)")
          :format(site.tag, tostring(nextAt), bare))
      for _ = 1, 600 do
        local top = game.stack:top()
        if not (top and top.isTextBox) or top.done then break end
        step(1)
      end
      U.still(game, ("%s/2732b_%s_02_next_page.png"):format(SHOT_DIR, site.tag))
    end
    for _ = 1, 60 do
      if not world:busy() and game.stack:top() == nil then break end
      press()
      step(6)
    end
    ok(not world.vm:running() and game.stack:top() == nil,
      site.tag .. ": the script ran to the end and the box came down")
  end

  -- ../pokecrystal/engine/overworld/scripting.asm:2224
  do
    local vm = world.vm
    local keys = {}
    for key, rows in pairs(vm.scripts) do
      if type(key) == "string" and type(rows) == "table" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    local list, at, pauseN
    for _, key in ipairs(keys) do
      local rows = vm.scripts[key]
      for i, row in ipairs(rows) do
        local nxt = rows[i + 1]
        local body = type(row) == "table" and row.op == "writetext" and vm.text[row.text]
        if type(body) == "string" and type(nxt) == "table" and nxt.op == "pause"
            and (nxt.frames or nxt.length or 0) >= 45
            and not body:find("{PROMPT}", 1, true) and not body:find("[\v\f]")
            and #body > 12 then
          list, at, pauseN = rows, i, (nxt.frames or nxt.length)
          break
        end
      end
      if list then break end
    end
    if not ok(list ~= nil, "pause: the cache has a writetext / pause N>=45 site") then
      finish()
    end
    local want = Vm.pauseLength(pauseN)
    say(("pause: site pause %d (%d frames) after %q"):format(pauseN, want,
      vm.text[list[at].text]:gsub("\n", " "):sub(1, 50)))
    vm:start({
      { op = "opentext" },
      list[at],
      list[at + 1],
      { op = "writetext", text = list[at].text },
      { op = "waitbutton" },
      { op = "closetext" },
      { op = "end" },
    })
    local box
    for _ = 1, 600 do
      step(1)
      local top = game.stack:top()
      if top and top.isTextBox then box = top break end
    end
    if not ok(box ~= nil, "pause: the line went up") then finish() end
    local typed, replacedAt
    for _ = 1, want + 900 do
      if box.done and not typed then typed = f end
      if game.stack:top() ~= box then replacedAt = f break end
      step(1)
    end
    local heldFor = typed and replacedAt and (replacedAt - typed) or nil
    ok(replacedAt ~= nil,
      "pause: the line advanced on its own with no press (Script_pause, no WaitButton)")
    ok(heldFor ~= nil and heldFor >= want - 2,
      ("pause: the line stayed up for the pause (%s >= %d frames)")
        :format(tostring(heldFor), want - 2))
    for _ = 1, 60 do
      if not world:busy() and game.stack:top() == nil then break end
      press()
      step(6)
    end
    ok(not vm:running() and game.stack:top() == nil,
      "pause: the script ran to the end and the box came down")
  end

  Sound.play = realPlay
  finish()
end
