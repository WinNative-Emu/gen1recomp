local Rng32 = require("src.core.game3.rng")

local Rng = {}

-- pokefirered/src/random.c:15 ISO_RANDOMIZE1
function Rng.make(seed, counter)
  local value = math.floor(tonumber(seed) or 0) % 4294967296
  local function word()
    if counter then counter.n = counter.n + 1 end
    value = (Rng32.mulU32(value, 1103515245) + 24691) % 4294967296
    return math.floor(value / 65536) % 65536
  end
  return function(lo, hi)
    if lo == nil and hi == nil then return word() / 65536 end
    if hi == nil then
      lo = math.floor(tonumber(lo) or 1)
      if lo <= 0 then return 0 end
      return 1 + (word() % lo)
    end
    lo = math.floor(tonumber(lo) or 0)
    hi = math.floor(tonumber(hi) or lo)
    if hi < lo then lo, hi = hi, lo end
    local span = hi - lo + 1
    if span <= 0 then return lo end
    return lo + (word() % span)
  end
end

return Rng
