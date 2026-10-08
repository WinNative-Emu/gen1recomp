local F = require("tests.engine._xgen_fixture")
local FakeRelay = require("tests.support.fake_relay")
local Participant = require("src.online.union.Participant")
local Room = require("src.online.union.Room")
local GameVersion = require("src.core.GameVersion")
local Save2 = require("src.core.gen2.Save")

local U = {}

U.CLOCK = { t = 0 }
U.FP = { red = "1111111111111111", gold = "3333333333333333", emerald = "6666666666666666" }

function U.pid(n) return ("%08x"):format(n) end

function U.ctxFor(version, name, tid)
  local gen = Participant.genOf(version)
  return { version = version, name = name, trainerId = tid, gender = 0,
           profile = { engine = gen, version = version, engineVersion = "0.0.0-dev", apiVersion = 2,
                       fingerprint = U.FP[version], rulesetId = gen == 3 and "g3_single" or "union", kind = "vanilla" },
           vanillaFingerprint = U.FP[version], gameplayMods = false }
end

function U.world()
  local w = { relay = FakeRelay.new({ clock = function() return U.CLOCK.t end }), clients = {} }
  function w:add(n, name)
    local seat = self.relay:seat(U.pid(n), name)
    package.loaded["src.online.Client"] = nil
    local C = require("src.online.Client")
    C.reset()
    C.configure({ relayAddress = "fake:3", connect = function() return seat.transport end })
    C.connect({ name = name, profiles = {} })
    self.clients[#self.clients + 1] = C
    return Room.new({ client = C }), C
  end
  function w:pump(rounds)
    for _ = 1, rounds or 4 do
      self.relay:pump()
      for _, C in ipairs(self.clients) do C.update(0) end
    end
  end
  return w
end

function U.pair(va, vb)
  local w = U.world()
  local ra = w:add(1, "A")
  local rb = w:add(2, "B")
  w:pump()
  ra:join(U.ctxFor(va, "A", 1))
  rb:join(U.ctxFor(vb, "B", 2))
  w:pump()
  ra:poll(); rb:poll()
  ra:invite(U.pid(2), "xg_trade")
  w:pump()
  rb:reply(rb:incoming()[1].id, true)
  w:pump()
  return w, ra, rb
end

function U.pika1(level)
  return { species = "PIKACHU", level = level or 25, exp = 15625, hp = 50, nickname = "ZAPPY", ot = "RED", otId = 4242,
    dvs = { attack = 10, defense = 10, speed = 10, special = 10 },
    statExp = { hp = 100, attack = 400, defense = 0, speed = 900, special = 2500 },
    stats = { hp = 50, attack = 40, defense = 30, speed = 60, special = 40 },
    moves = { { id = "THUNDERSHOCK", pp = 30 }, { id = "GROWL", pp = 40 } }, catchRate = 190 }
end

function U.bulba2()
  return { species = "BULBASAUR", level = 10, experience = 560, ot = "GOLD", otId = 9,
    dvs = { attack = 12, defense = 9, speed = 5, special = 7, hp = 8 }, statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 },
    stats = { hp = 30, attack = 15, defense = 15, speed = 12, specialAttack = 16, specialDefense = 16 }, hp = 30,
    moves = { { id = "TACKLE", pp = 35, maxPp = 35 }, { id = "GROWL", pp = 40, maxPp = 40 } }, happiness = 90, pokerus = 0 }
end

function U.g1game()
  local save = { version = "red", party = { U.pika1(), U.pika1(30) }, pokedex = { seen = {}, owned = {} },
    player = { map = "PALLET_TOWN", x = 5, y = 5, facing = "down", name = "RED" } }
  return { save = save, data = F.raw("red") }
end

function U.g2game()
  local was = GameVersion.get()
  GameVersion.set("gold")
  local save = Save2.newGame({ playerName = "GOLD" })
  GameVersion.set(was)
  save.version = "gold"
  save.party = { U.bulba2() }
  return { save = save, data = F.raw("gold") }
end

return U
