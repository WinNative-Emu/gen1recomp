
local SrmDecompress = {}

local function read_le_u32(b, off)
  return (string.byte(b, off) or 0)
       + (string.byte(b, off+1) or 0) * 256
       + (string.byte(b, off+2) or 0) * 65536
       + (string.byte(b, off+3) or 0) * 16777216
end

local function read_le_u64(b, off)
  local low = read_le_u32(b, off)
  local high = read_le_u32(b, off+4)
  return low + high * 4294967296
end

local function has_rzip_header(bytes)
  if not bytes or #bytes < 8 then return false end
  local b1,b2,b3,b4,b5 = string.byte(bytes,1),string.byte(bytes,2),string.byte(bytes,3),string.byte(bytes,4),string.byte(bytes,5)
  if b1==35 and b2==82 and b3==90 and b4==73 and b5==80 then return true end
  return false
end

function SrmDecompress.isCompressed(bytes)
  return has_rzip_header(bytes)
end

function SrmDecompress.decompress(bytes)
  if not has_rzip_header(bytes) then return nil, "not compressed SRM" end
  if #bytes < 20 then return nil, "truncated SRM header" end
  local chunk_size = read_le_u32(bytes, 9)
  local total_size = read_le_u64(bytes, 13)
  if chunk_size == 0 or chunk_size > 64*1024*1024 then return nil, "invalid chunk size" end
  if total_size == 0 or total_size > 256*1024*1024 then return nil, "invalid total size" end
  local pos = 21
  local parts = {}
  while pos + 4 <= #bytes do
    local csize = read_le_u32(bytes, pos)
    pos = pos + 4
    if csize == 0 then break end
    if pos + csize - 1 > #bytes then return nil, "truncated chunk" end
    local cdata = bytes:sub(pos, pos + csize - 1)
    pos = pos + csize
    local ok, d = pcall(love.data.decompress, "string", "zlib", cdata)
    if not ok then return nil, "decompress failed" end
    table.insert(parts, d)
    if #table.concat(parts) >= total_size then break end
  end
  local res = table.concat(parts)
  return res
end

return SrmDecompress
