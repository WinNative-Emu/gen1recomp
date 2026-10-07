return function(need)
  local Json = need("src.link.Json")
  local Serializer = need("src.core.SaveSerializer")
  local Base64 = need("src.core.Base64")
  local ops = {}

  function ops.hash(body)
    if love and love.data and love.data.hash then
      local digest = love.data.hash("sha256", body)
      return "sha256:" .. (digest:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
    end
    return "sha512:" .. need("src.core.crypto.sha512").hex(body)
  end

  function ops.jsonDecode(raw, maxLength) return Json.decode(raw, maxLength) end
  function ops.jsonEncode(value) return Json.encode(value) end
  function ops.decode(body, limits) return Serializer.decode(body, limits) end
  function ops.encode(value) return Serializer.encode(value) end
  function ops.base64Encode(bytes) return Base64.encode(bytes) end
  function ops.base64Decode(text) return Base64.decode(text) end

  function ops.normalizeSave(blob, version, id, cart)
    local save = Serializer.decode(blob)
    if not save then return nil end
    save.meta = type(save.meta) == "table" and save.meta or {}
    save.meta.playthroughId = id
    save.version = save.version or version
    if cart then save.meta.cartId = cart end
    return Serializer.encode(save)
  end

  function ops.fingerprint(blob, assets, bodies)
    local state = Serializer.decode(blob)
    local paths = {}
    for key, member in pairs(state.syncMembers or {}) do
      paths[member.path] = key
      member.path, member.slotId = nil, nil
    end
    local function portable(entry)
      entry.slotId = nil
      for _, original in ipairs(entry.archives or {}) do portable(original) end
    end
    for _, box in ipairs(state.boxes) do for _, entry in pairs(box.mons) do portable(entry) end end
    for _, departure in pairs(state.departures or {}) do
      departure.path = paths[departure.path] or departure.path
      portable(departure.entry)
    end
    return ops.hash(Serializer.encode({ box = state, assets = assets, saves = bodies }))
  end

  return ops
end
