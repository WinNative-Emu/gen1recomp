local Serializer = require("src.core.SaveSerializer")
local Store = require("src.box.Store")
local GameVersion = require("src.core.GameVersion")

local Transaction = { PATH = "box/pending.lua" }

local function allowed(path)
  if path == Store.PATH then return true end
  if type(path) ~= "string" then return false end
  local scope = path:match("^saves/([%w%._%-]+)/slot%d+%.lua$")
  return scope ~= nil and (GameVersion.VERSIONS[scope] ~= nil
    or (#scope <= 69 and scope:match("^cart_%w[%w%._%-]*$") ~= nil))
end

function Transaction.assetValid(path, body)
  if type(path) ~= "string" or not path:match("^box/showcase/%d+%.png$")
      or type(body) ~= "string" or #body < 24 or #body > 2 * 1024 * 1024
      or body:sub(1, 8) ~= "\137PNG\r\n\26\n" then return false end
  local function be(i)
    local a, b, c, d = body:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return be(17) == 1136 and be(21) == 432
end

local function write(fs, path, body)
  local dir = path:match("^(.*)/[^/]+$")
  if dir and fs.createDirectory then
    local ok, err = fs.createDirectory(dir)
    if not ok then return nil, err or "Could not create the save directory." end
  end
  local ok, err = fs.write(path, body)
  if not ok then return nil, err or "Could not write the save." end
  if fs.read(path) ~= body then return nil, "The save could not be verified after writing." end
  return true
end

local function validJournal(journal)
  if type(journal) ~= "table" or (journal.format ~= 1 and journal.format ~= 2 and journal.format ~= 3)
      or type(journal.jobs) ~= "table" or #journal.jobs < 1
      or #journal.jobs > (journal.format ~= 1 and 512 or 2) then return nil, "Invalid Box transfer journal." end
  local seen = {}
  for _, job in ipairs(journal.jobs) do
    if type(job) ~= "table" then return nil, "Invalid Box transfer target." end
    local asset = journal.format == 2 and job.kind == "asset"
    local options = journal.format == 2 and job.path == "options.lua"
    local deleting = journal.format == 2 and job.deleted == true and job.path ~= Store.PATH and not asset and not options
    if type(job) ~= "table" or not (allowed(job.path) or asset or options) or seen[job.path]
        or (not deleting and type(job.after) ~= "string") or deleting and job.after ~= nil
        or (job.before ~= nil and type(job.before) ~= "string") then
      return nil, "Invalid Box transfer target."
    end
    seen[job.path] = true
    if asset then
      if not Transaction.assetValid(job.path, job.after) then return nil, "Invalid Box wallpaper." end
    elseif not deleting then
      local data = Serializer.decode(job.after)
      if type(data) ~= "table" then return nil, "Invalid transfer save data." end
      if job.path == Store.PATH and not Store.validate(data) then return nil, "Invalid Box data." end
    end
  end
  if journal.format ~= 3 and not seen[Store.PATH] then return nil, "The transfer does not include Box storage." end
  return journal
end

local function quarantine(fs, body)
  local stamp = os.time()
  for n = 1, 1000 do
    local path = ("box/conflicts/pending-%d-%d.lua"):format(stamp, n)
    if not fs.getInfo(path) then
      local ok, err = write(fs, path, body)
      if not ok then return nil, err end
      ok, err = fs.remove(Transaction.PATH)
      if not ok or fs.getInfo(Transaction.PATH) then
        return nil, err or "The unfinished Box transfer record could not be set aside."
      end
      return path
    end
  end
  return nil, "Too many unfinished Box transfer records are waiting in box/conflicts."
end

local function abort(fs, journal, body)
  local wrote = false
  for _, job in ipairs(journal.jobs) do
    local current = fs.read(job.path)
    if not job.conflict and current ~= job.before then
      local ok, why
      if job.before == nil then
        ok, why = fs.remove(job.path)
        if ok and fs.getInfo(job.path) then ok = nil end
      else ok, why = write(fs, job.path, job.before) end
      if not ok then return nil, why or "Could not undo the unfinished Box transfer." end
      wrote = true
    end
    if not job.conflict and job.after ~= nil and fs.read(job.path .. ".bak") == job.after then
      local ok, why
      if job.before == nil then ok, why = fs.remove(job.path .. ".bak")
      else ok, why = write(fs, job.path .. ".bak", job.before) end
      if not ok then return nil, why or "Could not undo the unfinished Box transfer." end
    end
  end
  if wrote and journal.format ~= 2 then
    local sync = package.loaded["src.sync.SyncEngine"]
    local engine = type(sync) == "table" and sync._shared
    if type(engine) == "table" then engine:noteSaveWritten() end
  end
  local kept, err = quarantine(fs, body)
  if not kept then return nil, err end
  return true, false, "A save changed while a Box transfer was pending. The transfer was undone and its record kept at " .. kept .. "."
end

local function touched(fs, journal)
  if type(journal) ~= "table" or type(journal.jobs) ~= "table" then return false end
  for _, job in pairs(journal.jobs) do
    if type(job) == "table" and type(job.path) == "string" then
      local ok, current = pcall(fs.read, job.path)
      if not ok then return true end
      if current ~= job.before then
        if job.deleted == true and current == nil then return true end
        if type(job.after) == "string" and type(current) == "string"
            and job.after:sub(1, #current) == current then return true end
      end
    end
  end
  return false
end

function Transaction.recover(fs)
  if not fs or not fs.read or not fs.getInfo then return nil, "Save storage is unavailable." end
  local body = fs.read(Transaction.PATH)
  if not body then
    if fs.getInfo(Transaction.PATH) then return nil, "The pending Box transfer could not be read." end
    return true, false
  end
  local journal = Serializer.decode(body)
  if journal == nil then
    local kept, err = quarantine(fs, body)
    if not kept then return nil, err end
    return true, false, "An unfinished Box transfer record was unreadable and was set aside at " .. kept .. "."
  end
  local valid, why = validJournal(journal)
  if not valid then
    if touched(fs, journal) then return nil, why end
    local kept, err = quarantine(fs, body)
    if not kept then return nil, err end
    return true, false, why .. " The unfinished Box transfer record was set aside at " .. kept .. "."
  end
  local conflict = false
  for _, job in ipairs(journal.jobs) do
    local current = fs.read(job.path)
    if current == nil and fs.getInfo(job.path) then return nil, "A transfer save could not be read." end
    local interrupted = journal.format ~= 1 and type(current) == "string" and type(job.after) == "string"
      and job.after:sub(1, #current) == current
    if current ~= job.before and current ~= job.after and not interrupted
        and (journal.format ~= 1 or current == nil or Serializer.decode(current) ~= nil) then
      job.conflict, conflict = true, true
    end
  end
  if conflict then return abort(fs, journal, body) end
  for _, job in ipairs(journal.jobs) do
    if fs.read(job.path) ~= job.after then
      if job.before then
        local ok, err = write(fs, job.path .. ".box-bak", job.before)
        if not ok then return nil, err end
      end
      if job.deleted then
        local ok, err = fs.remove(job.path)
        if not ok or fs.getInfo(job.path) then return nil, err or "Could not remove the synced save." end
      else
        local ok, err = write(fs, job.path, job.after)
        if not ok then return nil, err end
      end
    end
    if job.deleted then
      for _, suffix in ipairs({ ".bak", ".tmp" }) do
        if fs.getInfo(job.path .. suffix) then
          local ok, err = fs.remove(job.path .. suffix)
          if not ok or fs.getInfo(job.path .. suffix) then return nil, err or "Could not remove a deleted save's recovery file." end
        end
      end
    elseif fs.read(job.path .. ".bak") ~= job.after then
      local ok, err = write(fs, job.path .. ".bak", job.after)
      if not ok then return nil, err end
    end
    if not job.deleted and fs.getInfo(job.path .. ".tmp") then
      local ok, err = fs.remove(job.path .. ".tmp")
      if not ok or fs.getInfo(job.path .. ".tmp") then return nil, err or "Could not clear a stale save recovery file." end
    end
  end
  local ok, err = fs.remove(Transaction.PATH)
  if not ok or fs.getInfo(Transaction.PATH) then
    return nil, err or "The completed Box transfer journal could not be cleared."
  end
  local stored = fs.read(Store.PATH)
  if stored and fs.read(Store.PATH .. ".bak") == stored
      and fs.getInfo(Store.PATH .. ".box-bak") then
    fs.remove(Store.PATH .. ".box-bak")
  end
  if journal.format == 1 or journal.format == 3 then
    local sync = package.loaded["src.sync.SyncEngine"]
    local engine = type(sync) == "table" and sync._shared
    if type(engine) == "table" then engine:noteSaveWritten() end
  end
  return true, true
end

local function commit(fs, jobs, format)
  local ok, why = Transaction.recover(fs)
  if not ok then return nil, why end
  local journal = { format = format, jobs = jobs }
  local valid, err = validJournal(journal)
  if not valid then return nil, err end
  for _, job in ipairs(jobs) do
    if fs.read(job.path) ~= job.before then return nil, "That save changed. Reload before transferring." end
  end
  local body = Serializer.encode(journal)
  ok, err = write(fs, Transaction.PATH, body)
  if not ok and fs.read(Transaction.PATH) ~= body then
    fs.remove(Transaction.PATH)
    return nil, err
  end
  local applied
  ok, applied, err = Transaction.recover(fs)
  if not ok then return nil, "Box transfer is pending: " .. tostring(applied) end
  if not applied then return nil, err or "The Box transfer was not applied." end
  return true
end

function Transaction.commit(fs, jobs) return commit(fs, jobs, 1) end
function Transaction.commitSync(fs, jobs) return commit(fs, jobs, 2) end
function Transaction.commitIdentity(fs, jobs) return commit(fs, jobs, 3) end

return Transaction
