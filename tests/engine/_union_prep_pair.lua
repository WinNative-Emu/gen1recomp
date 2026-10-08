local FakeRelay = require("tests.support.fake_relay")
local Participant = require("src.online.union.Participant")
local Room = require("src.online.union.Room")

local P = {}

P.CLOCK = 0
love.timer.getTime = function() return P.CLOCK end

local function pid(n) return ("%08x"):format(n) end
P.pid = pid

local FP = { red = "1111111111111111", yellow = "2222222222222222", gold = "3333333333333333",
             crystal = "4444444444444444", emerald = "6666666666666666", firered = "5555555555555555" }

local function ctxFor(version, name, tid)
  local gen = Participant.genOf(version)
  return { version = version, name = name, trainerId = tid, gender = 0,
           profile = { engine = gen, version = version, engineVersion = "0.0.0-dev", apiVersion = 2,
                       fingerprint = FP[version], rulesetId = gen == 3 and "g3_single" or "union",
                       kind = "vanilla" },
           vanillaFingerprint = FP[version], gameplayMods = false }
end

local function world()
  local w = { relay = FakeRelay.new({ clock = function() return P.CLOCK end }), clients = {}, rooms = {}, seats = {} }
  function w:add(n, name)
    local seat = self.relay:seat(pid(n), name)
    package.loaded["src.online.Client"] = nil
    local C = require("src.online.Client")
    C.reset()
    C.configure({ relayAddress = "fake:3", connect = function() return seat.transport end })
    C.connect({ name = name, profiles = {} })
    self.clients[#self.clients + 1] = C
    self.seats[#self.seats + 1] = seat
    local r = Room.new({ client = C })
    self.rooms[#self.rooms + 1] = r
    return r, C, seat
  end
  function w:pump(rounds)
    for _ = 1, rounds or 4 do
      self.relay:pump()
      for _, C in ipairs(self.clients) do C.update(0) end
    end
  end
  return w
end

function P.pair(va, vb, activity)
  local w = world()
  local ra = w:add(1, "ALICE")
  local rb = w:add(2, "BOB")
  w:pump()
  ra:join(ctxFor(va, "ALICE", 1))
  rb:join(ctxFor(vb, "BOB", 2))
  w:pump()
  ra:poll(); rb:poll()
  ra:invite(pid(2), activity or "xg_battle")
  w:pump()
  rb:reply(rb:incoming()[1].id, true)
  w:pump()
  return w, ra:prep(), rb:prep(), ra, rb
end

return P
