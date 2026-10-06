local U = require("tests.drivers.util")

local BIG = {}
local function census()
  collectgarbage("collect")
  print(string.format("HEAP_AFTER_COLLECT_KB %.0f", collectgarbage("count")))
  local seen, rows = {}, {}
  local function size(t, depth)
    if seen[t] then return 0, 0 end
    seen[t] = true
    local slots, bytes = 0, 0
    for k, v in next, t do
      slots = slots + 1
      if type(v) == "string" then
        bytes = bytes + #v
        if #v > 262144 then BIG[#BIG + 1] = { #v, tostring(k) } end
      end
      if type(k) == "string" then bytes = bytes + #k end
    end
    return slots, bytes
  end
  local function walk(t, path, depth)
    if type(t) ~= "table" or seen[t] or depth > 12 then return 0 end
    local slots, bytes = size(t, depth)
    local total = slots * 40 + bytes
    for k, v in next, t do
      if type(v) == "table" then
        total = total + walk(v, path .. "." .. tostring(k), depth + 1)
      elseif type(v) == "function" then
        for i = 1, 60 do
          local n, uv = debug.getupvalue(v, i)
          if not n then break end
          if type(uv) == "table" then total = total + walk(uv, path .. "." .. tostring(k) .. "^" .. n, depth + 1) end
        end
      end
    end
    rows[#rows + 1] = { path, total, slots }
    return total
  end
  for name, mod in pairs(package.loaded) do
    if type(mod) == "table" then walk(mod, name, 0) end
    if type(mod) == "function" then
      for i = 1, 60 do
        local n, uv = debug.getupvalue(mod, i)
        if not n then break end
        if type(uv) == "table" then walk(uv, name .. "^" .. n, 1) end
      end
    end
  end
  walk(debug.getregistry(), "REG", 0)
  table.sort(rows, function(a, b) return a[2] > b[2] end)
  local bigTotal = 0
  table.sort(BIG, function(a, b) return a[1] > b[1] end)
  for i, b in ipairs(BIG) do bigTotal = bigTotal + b[1]; if i <= 25 then print(string.format("BIGSTR %8.0fKB key=%s", b[1] / 1024, b[2])) end end
  print(string.format("BIGSTR_TOTAL %.0fKB n=%d", bigTotal / 1024, #BIG))
  print(string.format("HEAP_TOTAL_KB %.0f", collectgarbage("count")))
  local shown = 0
  for _, r in ipairs(rows) do
    if shown >= 60 then break end
    print(string.format("HEAP %8.0fKB slots=%-8d %s", r[2] / 1024, r[3], r[1]))
    shown = shown + 1
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(300)
  census()
  love.event.quit(0)
end
