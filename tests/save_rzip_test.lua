package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("RZIP compressed save")
local check, eq = S.check, S.eq

local SrmDecompress = require("src.import.SrmDecompress")

love.data = love.data or {}
local realDecompress = love.data.decompress
love.data.decompress = function(_, _, cdata)
  return "D(" .. cdata .. ")"
end

local function le32(n)
  local b1 = n % 256; n = math.floor(n / 256)
  local b2 = n % 256; n = math.floor(n / 256)
  local b3 = n % 256; n = math.floor(n / 256)
  return string.char(b1, b2, b3, n % 256)
end

local function rzip(chunkSize, totalSize, chunks)
  local out = { "#RZIPv", string.char(1), "#",
                le32(chunkSize), le32(totalSize), le32(0) }
  for _, c in ipairs(chunks) do
    out[#out + 1] = le32(#c)
    out[#out + 1] = c
  end
  return table.concat(out)
end

local blob = rzip(131072, 131072, { "hello" })
check(SrmDecompress.isCompressed(blob), "rzip header detected")
check(not SrmDecompress.isCompressed("PK\3\4body"), "zip magic is not rzip")
check(not SrmDecompress.isCompressed("RIP"), "too short to sniff")
check(not SrmDecompress.isCompressed(nil), "nil is not rzip")

local got, err = SrmDecompress.decompress(blob)
eq(got, "D(hello)", "chunk ending exactly at EOF decompresses")
eq(err, nil, "no error for exact-EOF chunk")

local g2, e2 = SrmDecompress.decompress(blob:sub(1, #blob - 2))
eq(g2, nil, "chunk claiming bytes past EOF rejected")
eq(e2, "truncated chunk", "truncated error message")

local two = rzip(4, 99, { "ab", "cd" })
eq(SrmDecompress.decompress(two), "D(ab)D(cd)", "all chunks concatenated")

local raw = string.rep("\255", 32768)
local g3, e3 = SrmDecompress.decompress(raw)
eq(g3, nil, "raw save not decompressible")
eq(e3, "not compressed SRM", "raw save error message")

love.data.decompress = realDecompress
S.finish()
