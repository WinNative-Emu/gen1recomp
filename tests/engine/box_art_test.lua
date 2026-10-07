package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Serializer = require("src.core.SaveSerializer")
local GameVersion = require("src.core.GameVersion")
local CacheFs = require("src.import.CacheFs")
local Catalog = require("src.box.Catalog")
local Store = require("src.box.Store")
local realSprites = require("src.online.OnlineSprites")
local bodies, available, calls = {}, {}, {}
local readAt = CacheFs.readAt
CacheFs.readAt = function(path) return bodies[path] end
local function put(version, path, value)
  bodies[GameVersion.cachePrefix(version) .. path] = Serializer.encode(value)
end
put("gold", "data/generated/pokemon.lua", {
  PIKACHU = { dex = 25, name = "PIKACHU" }, UNOWN = { dex = 201, name = "UNOWN" } })
put("emerald", "data/generated/gba/pokemon/names.lua", { [25] = "PIKACHU", [201] = "UNOWN" })
put("emerald", "data/generated/gba/pokemon/national.lua", {
  toNational = { [25] = 25, [201] = 201 }, toSpecies = { [25] = 25, [201] = 201 } })
put("sapphire", "data/generated/gba/pokemon/names.lua", { [25] = "PIKACHU" })
put("sapphire", "data/generated/gba/pokemon/national.lua", { toNational = { [25] = 25 }, toSpecies = { [25] = 25 } })

package.loaded["src.online.OnlineSprites"] = {
  reset = function() calls = {} end,
  ensure = function(version, mon)
    calls[#calls + 1] = { version = version, mon = Store.copy(mon) }
    if available[version] then return { front = {}, icon = {} } end
    return { front = false, icon = false }
  end,
}
Catalog.reset()
local mon = { species = "PIKACHU", nickname = "Spark", hp = 22, level = 10,
  dvs = { attack = 2, defense = 10, speed = 10, special = 10 }, opaque = "keep" }
local entry = { version = "gold", generation = 2, mon = mon, display = Catalog.describe("gold", mon) }
local before = Serializer.encode(entry)
available.emerald = true
local art, version = Catalog.art(entry)
T.eq(version, "emerald", "highest imported generation supplies art")
T.eq(calls[1].mon.species, 25, "canonical species maps to destination art id")
T.check(calls[1].mon.isShiny, "Gen 2 shiny DVs choose shiny Gen 3 art")
T.eq(Serializer.encode(entry), before, "art lookup does not alter stored Pokémon")
local n = #calls
Catalog.art(entry)
T.eq(#calls, n, "steady draws reuse resolved art")

local order = GameVersion.ORDER
GameVersion.ORDER = { "emerald", "gold", "sapphire" }
available.sapphire = true
Catalog.reset()
art, version = Catalog.art(entry)
T.eq(version, "emerald", "Emerald preference is independent of launcher column order")
local _, _, mappedMon = Catalog.art(entry)
T.eq(mappedMon.species, 25, "cached art retains its mapped animation species")
GameVersion.ORDER = order
local namesPath = "emerald/data/generated/gba/pokemon/names.lua"
local emeraldNames = bodies[namesPath]
bodies[namesPath] = nil
Catalog.reset()
art, version = Catalog.art(entry)
T.eq(version, "sapphire", "an unimported Emerald does not displace an available imported game")
bodies[namesPath] = emeraldNames

available.emerald, available.sapphire = nil, true
Catalog.reset()
art, version = Catalog.art(entry)
T.eq(version, "sapphire", "missing high-generation art falls back to another imported source")
T.eq(Serializer.encode(entry), before, "fallback leaves native data intact")

available.sapphire, available.gold = nil, true
Catalog.reset()
art, version = Catalog.art(entry)
T.eq(version, "gold", "lower generation is used when newer art is absent")

available.emerald = true
Catalog.reset()
local unown = { species = "UNOWN", unownLetter = 3, dvs = { attack = 1, defense = 1, speed = 1, special = 1 } }
local record = { version = "gold", generation = 2, mon = unown, display = Catalog.describe("gold", unown) }
Catalog.art(record)
local mapped = calls[1].mon
T.eq(require("src.core.game3.pokemon").unownLetter(mapped.personality), 2, "Unown letter C survives art generation change")
T.eq(unown.personality, nil, "display personality is not written into the native record")
local other = Store.copy(record)
other.mon.unownLetter = 4
local _, _, otherMon = Catalog.art(other)
T.eq(require("src.core.game3.pokemon").unownLetter(otherMon.personality), 3, "different Gen 2 Unown forms do not share the first form's cached art")

available.emerald, available.gold = nil, nil
Catalog.reset()
art, version = Catalog.art(entry)
T.eq(art, nil, "missing artwork is a safe placeholder")
T.eq(GameVersion.get(), "red", "artwork lookup does not switch the active game")
T.eq(CacheFs.prefix, "", "artwork lookup does not change the cache prefix")

CacheFs.readAt = readAt
package.loaded["src.online.OnlineSprites"] = realSprites
Catalog.reset()
T.finish()
