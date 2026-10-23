package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Versions = require("src.import.gba.versions")
local GameVersion = require("src.core.GameVersion")
local Rom = require("src.import.gba.rom")
local E = require("src.import.gba.extract_audio")
local root = os.getenv("POKEFIRERED") or "../pokefirered"
local tested = 0

-- pokefirered/src/data/pokemon/cry_ids.h:3
for _, row in ipairs({
  { "fr10", "pokefirered.gba", "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc", 0x2539D4 },
  { "fr11", "pokefirered_rev1.gba", "dd5945db9b930750cb39d00c84da8571feebf417", 0x253A44 },
  { "lg10", "pokeleafgreen.gba", "574fa542ffebb14be69902d1d36f1ec0a4afd71e", 0x2539B0 },
  { "lg11", "pokeleafgreen_rev1.gba", "7862c67bdecbe21d1d69ce082ce34327e1c6ed5e", 0x253A20 },
}) do
  local f = io.open(root .. "/" .. row[2], "rb")
  if not f then
    print("[skip] no " .. row[1] .. " pret ROM")
  else
    local data = f:read("*a")
    f:close()
    local sha1 = row[3]
    T.eq(#data, 0x1000000, row[1] .. " ROM size")
    local game = GameVersion.forSha1(sha1)
    GameVersion.set(game)
    local rom = assert(Rom.open({
      info = function() return { size = #data, md5 = sha1 } end,
      read = function(_, _, off, len) return data:sub(off + 1, off + len) end,
    }, game))
    local files = {}
    local ok, index = E.run({ data = rom:ensureBuffer() }, { write = function(_, path, bytes)
      if path:match("index%.lua$") then files[path] = bytes end
      return true
    end }, { cacheRoot = "g", sha1 = sha1 })
    T.check(ok, row[1] .. " audio extraction succeeds")
    local encoded = assert(loadstring(files["g/audio/index.lua"]))()
    local mismatches, missing = 0, 0
    -- pokefirered/src/sound.c:384
    for species = 1, 411 do
      local want
      if species <= 251 then want = species - 1
      elseif species <= 276 then want = 200
      else
        local a, b = data:byte(row[4] + (species - 277) * 2 + 1, row[4] + (species - 277) * 2 + 2)
        want = a + b * 256
      end
      if index.cryIds[species] ~= want or encoded.cryIds[species] ~= want then mismatches = mismatches + 1 end
      local cry = index.cries[index.cryIds[species]]
      if not (cry and cry.sampleId and index.samples[cry.sampleId]) then missing = missing + 1 end
    end
    T.eq(mismatches, 0, row[1] .. " all 411 cached IDs match the raw ROM")
    T.eq(missing, 0, row[1] .. " all mapped cries have decoded samples")
    T.eq(index.cryIds[412], nil, row[1] .. " no cry ID beyond the species range")
    T.eq(index.cryIds[251], 250, row[1] .. " Celebi")
    T.eq(index.cryIds[277], 273, row[1] .. " Treecko")
    T.eq(index.cryIds[288], 378, row[1] .. " Zigzagoon")
    T.eq(index.cryIds[289], 375, row[1] .. " Linoone")
    T.eq(index.cryIds[411], 387, row[1] .. " Chimecho")
    T.eq(Versions.AUDIO.cry_id_count, 135, row[1] .. " 135 ROM table entries")
    tested = tested + 1
  end
end
print("FRLG cry mapping ROM revisions tested: " .. tested)
T.finish("game3_frlg_cry_mapping_3040")
