package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")

local okFfi, ffi = pcall(require, "ffi")
local RELAY_JS = os.getenv("POKESERVER_RELAY") or "../pokeserver/relay.js"

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function hasNode()
  local p = io.popen("command -v node 2>/dev/null")
  local out = p and p:read("*a") or ""
  if p then p:close() end
  return out:match("%S") ~= nil
end

if not okFfi or not (ffi.os == "OSX" or ffi.os == "Linux") or not exists(RELAY_JS) or not hasNode() then
  print("[skip] no local pokeserver checkout, node or ffi for the live relay test")
  os.exit(0)
end

local Json = require("src.link.Json")
local Participant = require("src.online.union.Participant")
local Room = require("src.online.union.Room")

ffi.cdef([[
int socket(int domain, int type, int protocol);
int connect(int s, const void *addr, unsigned int len);
long recv(int s, void *buf, unsigned long len, int flags);
long send(int s, const void *buf, unsigned long len, int flags);
int close(int fd);
int fcntl(int fd, int cmd, ...);
int setsockopt(int s, int level, int name, const void *val, unsigned int len);
int usleep(unsigned int usec);
]])

local OSX = ffi.os == "OSX"
local O_NONBLOCK = OSX and 0x4 or 0x800
local EAGAIN = OSX and 35 or 11
local SEND_FLAGS = OSX and 0 or 0x4000

local function sockaddr(port)
  local buf = ffi.new("uint8_t[16]")
  if OSX then
    buf[0], buf[1] = 16, 2
  else
    buf[0], buf[1] = 2, 0
  end
  buf[2], buf[3] = math.floor(port / 256), port % 256
  buf[4], buf[5], buf[6], buf[7] = 127, 0, 0, 1
  return buf
end

local function tcp(port)
  local fd = ffi.C.socket(2, 1, 0)
  if fd < 0 then return nil, "socket" end
  if OSX then
    local one = ffi.new("int[1]", 1)
    ffi.C.setsockopt(fd, 0xffff, 0x1022, one, 4)
  end
  if ffi.C.connect(fd, sockaddr(port), 16) ~= 0 then
    ffi.C.close(fd)
    return nil, "connect"
  end
  ffi.C.fcntl(fd, 4, ffi.cast("int", O_NONBLOCK))
  local t = { paired = true, closed = false, error = nil, fd = fd, rx = "", inbox = {} }
  local chunk = ffi.new("uint8_t[8192]")
  function t:rawSend(text)
    local at = 0
    while at < #text and not self.closed do
      local n = tonumber(ffi.C.send(self.fd, ffi.cast("const char *", text) + at, #text - at, SEND_FLAGS))
      if n > 0 then
        at = at + n
      elseif ffi.errno() == EAGAIN then
        ffi.C.usleep(1000)
      else
        self.closed = true
      end
    end
  end
  function t:update()
    while not self.closed do
      local n = tonumber(ffi.C.recv(self.fd, chunk, 8192, 0))
      if n > 0 then
        self.rx = self.rx .. ffi.string(chunk, n)
      elseif n == 0 then
        self.closed = true
      else
        if ffi.errno() ~= EAGAIN then self.closed = true end
        break
      end
    end
    while true do
      local nl = self.rx:find("\n", 1, true)
      if not nl then break end
      local line = self.rx:sub(1, nl - 1)
      self.rx = self.rx:sub(nl + 1)
      local msg = Json.decode(line)
      if type(msg) == "table" then
        if msg.type == "ping" then
          self:rawSend(Json.encode({ type = "pong", t = msg.t }) .. "\n")
        elseif msg.type ~= "pong" then
          self.inbox[#self.inbox + 1] = msg
        end
      end
    end
  end
  function t:poll()
    local out = self.inbox
    self.inbox = {}
    return out
  end
  function t:send(msg)
    self:rawSend(Json.encode(msg) .. "\n")
  end
  function t:close()
    if self.fd then ffi.C.close(self.fd) end
    self.fd = nil
    self.closed = true
  end
  return t
end

local launcher = os.tmpname()
local portFile = os.tmpname()
os.remove(portFile)
do
  local f = io.open(launcher, "wb")
  f:write([[
const path = require('path');
const { createRelay } = require(path.resolve(process.argv[2]));
const fs = require('fs');
const relay = createRelay({ log: () => {}, lobbyEnabled: true });
relay.server.listen(0, '127.0.0.1', () => {
  fs.writeFileSync(process.argv[3], String(relay.server.address().port));
});
process.stdin.on('end', () => process.exit(0));
process.stdin.on('data', () => {});
process.stdin.resume();
setTimeout(() => process.exit(0), 60000);
]])
  f:close()
end

local node = io.popen(("node %q %q %q"):format(launcher, RELAY_JS, portFile), "w")
local port
for _ = 1, 500 do
  local f = io.open(portFile, "rb")
  if f then
    port = tonumber(f:read("*a"))
    f:close()
    if port then break end
  end
  ffi.C.usleep(10000)
end

local function stop()
  if node then node:close() end
  node = nil
  os.remove(launcher)
  os.remove(portFile)
end

if not port then
  stop()
  T.check(false, "the local relay started")
  T.finish()
end

local clients = {}

local function newClient(name)
  package.loaded["src.online.Client"] = nil
  local C = require("src.online.Client")
  C.reset()
  C.configure({ relayAddress = "127.0.0.1:" .. port, connect = function() return tcp(port) end })
  C.connect({ name = name, profiles = {} })
  clients[#clients + 1] = C
  return C
end

local function pumpUntil(cond, ms)
  for _ = 1, math.floor((ms or 3000) / 5) do
    for _, C in ipairs(clients) do C.update(0) end
    if cond() then return true end
    ffi.C.usleep(5000)
  end
  return false
end

local FP = { red = "1111111111111111", emerald = "6666666666666666", gold = "3333333333333333" }

local function ctxFor(version, name, tid)
  local gen = Participant.genOf(version)
  return { version = version, name = name, trainerId = tid, gender = 0,
           profile = { engine = gen, version = version, engineVersion = "0.0.0-dev", apiVersion = 2,
                       fingerprint = FP[version], rulesetId = gen == 3 and "g3_single" or "union",
                       kind = "vanilla" },
           vanillaFingerprint = FP[version], gameplayMods = false }
end

local ok, err = pcall(function()
  local ca, cb, cc = newClient("RED"), newClient("MAY"), newClient("GOLD")
  T.check(pumpUntil(function() return ca.state() == "online" and cb.state() == "online"
                                and cc.state() == "online" end), "three clients reach the live relay")
  local ra, rb, rc = Room.new({ client = ca }), Room.new({ client = cb }), Room.new({ client = cc })
  ra:join(ctxFor("red", "RED", 11))
  rb:join(ctxFor("emerald", "MAY", 22))
  rc:join(ctxFor("gold", "GOLD", 33))
  T.check(pumpUntil(function()
    ra:poll(); rb:poll(); rc:poll()
    return #ra:members() == 2 and #rb:members() == 2 and #rc:members() == 2
  end), "Gen 1, 2 and 3 share one live instance")
  T.eq(ra:error(), nil, "the live relay accepts the Gen 1 xgen join")
  local seen = {}
  for _, p in ipairs(ra:members()) do seen[p.gen] = p end
  T.check(seen[2] and seen[3] and not seen[2].legacy and not seen[3].legacy,
    "live rows carry relay gens")
  T.eq(seen[3] and seen[3].caps and seen[3].caps.gens["3"][1].version, "emerald", "live rows carry caps")
  T.eq(ra:self().gen, 1, "my own live row has gen 1")

  local cd = newClient("LEAF")
  T.check(pumpUntil(function() return cd.state() == "online" end), "a legacy client connects")
  cd.joinPlaza("union", ctxFor("emerald", "LEAF", 44).profile,
    { name = "LEAF", trainerId = 44, gender = 1, version = "emerald" }, 40)
  pumpUntil(function() return cd.plaza() ~= nil end)
  T.eq(#(cd.plaza() and cd.plaza().members or {}), 1, "a legacy Gen 3 join keeps its own shard")
  ra:poll()
  T.eq(#ra:members(), 2, "the xgen room never sees the legacy member")

  local h = ra:invite(rb:self() and rb:self().id or nil, "xg_battle")
  T.check(pumpUntil(function() return #rb:incoming() > 0 end), "the live xg invite arrives")
  rb:reply(rb:incoming()[1].id, true)
  T.check(pumpUntil(function() return ra:xgRoom() ~= nil and rb:xgRoom() ~= nil end), "the live xg room opens")
  T.eq(h.state, "accepted", "the live invite is accepted")
  local pa, pb = ra:prep(), rb:prep()
  T.check(pumpUntil(function() pa:poll(); pb:poll() return pa.rules ~= nil and pb.rules ~= nil end),
    "live rules arrive")
  T.eq(pa.rules.ruleset, "g3u", "the live relay resolves g3u")
  T.eq(pa.rules.dexMax, 151, "the live g3u dex is Gen 1's")
  pa:roster(3, "00000000000000a1")
  T.check(pumpUntil(function() pa:poll(); pb:poll() return pb.peer.roster ~= nil and pa.mine.roster ~= nil end),
    "a live roster is confirmed and relayed")
  pb:roster(2, "00000000000000b2")
  T.check(pumpUntil(function() pa:poll(); pb:poll() return pa.size ~= nil and pa.rev == pb.rev end),
    "the live size is agreed")
  T.eq(pa.size, 2, "the live size is the smaller roster")
  pa:ready("00000000000000a1")
  pb:ready("00000000000000b2")
  T.check(pumpUntil(function() pa:poll(); pb:poll() return pa.state == "go" and pb.state == "go" end),
    "both live seats reach xg_go")
  T.eq(pa.go and pa.go.size, 2, "the live go carries the size")
  T.eq(pa.go and pa.go.seed, pb.go and pb.go.seed, "the live go seed matches")
  local ce = newClient("BLUE")
  T.check(pumpUntil(function() return ce.state() == "online" end), "a fourth client connects")
  local re = Room.new({ client = ce })
  re:join(ctxFor("red", "BLUE", 55))
  pumpUntil(function() re:poll(); rc:poll() return re:self() ~= nil and #rc:members() >= 3 end)
  local ht = rc:invite(re:self() and re:self().id or nil, "xg_trade")
  T.check(pumpUntil(function() re:poll(); rc:poll() return #re:incoming() > 0 end), "the live trade invite arrives")
  re:reply(re:incoming()[1].id, true)
  T.check(pumpUntil(function() re:poll(); rc:poll() return ht.state == "accepted" and rc:prep() ~= nil
    and re:prep() ~= nil end), "the live trade room opens")
  local te, tc = re:prep(), rc:prep()
  pumpUntil(function() te:poll(); tc:poll() return te.rules ~= nil and tc.rules ~= nil end)
  tc:cancel("refused:personality_unrepresentable")
  T.check(pumpUntil(function() te:poll(); tc:poll() return te.state == "closed" end), "a refusal closes the live trade")
  T.eq(te.closed and te.closed.why, "cancel", "the peer sees a cancel")
  T.eq(te.closed and te.closed.detail, "refused:personality_unrepresentable", "with the whole refusal code")
  ca.disconnect(); cb.disconnect(); cc.disconnect(); cd.disconnect(); ce.disconnect()
end)
if not ok then T.check(false, "live relay run: " .. tostring(err)) end
stop()
T.finish()
