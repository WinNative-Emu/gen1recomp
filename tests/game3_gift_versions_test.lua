#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.fixture_data.game3_items").install()
love = love or require("tests.love_stub")
local T = require("tests.harness")
local check, eq = T.check, T.eq

local FIXTURE_PUB = "b084317448d99b4451ec0b3f5a4ec746a0de25800d8e5bdce4bedbcae6b7ce1d"
local FEED_FRLG = [==[{"v":1,"payload":"{\"cards\":[{\"bgType\":3,\"bodyText\":[\"Thank you for using the MYSTERY\",\"GIFT System.\",\"There is a ticket here for you.\",\"It is for use at VERMILION CITY port.\"],\"family\":\"frlg\",\"flagId\":1000,\"footerLine1Text\":\"Speak to the deliveryman\",\"footerLine2Text\":\"at a POKéMON CENTER.\",\"gift\":{\"haveFlags\":[679,740],\"item\":371,\"kind\":\"item\",\"quantity\":1,\"setFlags\":[2123,679]},\"iconSpecies\":0,\"idNumber\":2,\"key\":\"aurora_ticket\",\"maxStamps\":0,\"sendType\":0,\"subtitleText\":\"MYSTERY GIFT\",\"titleText\":\"AURORA TICKET\",\"type\":0,\"versions\":[\"firered\",\"leafgreen\"]},{\"bgType\":7,\"bodyText\":[\"A mythical POKéMON has been\",\"sent to you from the\",\"POKéMON CENTER.\",\"Please take good care of it.\"],\"family\":\"frlg\",\"flagId\":1007,\"footerLine1Text\":\"Speak to the deliveryman\",\"footerLine2Text\":\"at a POKéMON CENTER.\",\"gift\":{\"kind\":\"mon\",\"level\":10,\"moves\":{\"1\":1},\"otId\":20078,\"otName\":\"AURA\",\"species\":151},\"iconSpecies\":151,\"idNumber\":7,\"key\":\"lg_mew\",\"maxStamps\":0,\"sendType\":0,\"subtitleText\":\"MYSTERY GIFT\",\"titleText\":\"MEW\",\"type\":0,\"versions\":[\"leafgreen\"]}],\"family\":\"frlg\",\"issued\":5,\"news\":[{\"bgType\":0,\"bodyText\":[\"Every game reads this.\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\"],\"family\":\"frlg\",\"id\":9,\"key\":\"kanto_news\",\"sendType\":0,\"titleText\":\"RELAY NEWS\"}],\"v\":1}","sig":"f21a2cff1f284e7f31f507d27a2190b765f4839ff72077fe31321dce8bb655d460522748b79ef455500699012940a3509286b56820b8a2a657676226d5e9840c","key":"b084317448d99b4451ec0b3f5a4ec746a0de25800d8e5bdce4bedbcae6b7ce1d"}]==]
local FEED_RSE = [==[{"v":1,"payload":"{\"cards\":[{\"bgType\":6,\"bodyText\":[\"Thank you for using the MYSTERY\",\"GIFT System.\",\"We received this OLD SEA MAP\",\"addressed to you.\"],\"family\":\"rse\",\"flagId\":1002,\"footerLine1Text\":\"Speak to the deliveryman\",\"footerLine2Text\":\"at a POKéMON CENTER.\",\"gift\":{\"haveFlags\":[316,458],\"item\":376,\"kind\":\"item\",\"quantity\":1,\"setFlags\":[2262,316]},\"iconSpecies\":0,\"idNumber\":104,\"key\":\"rse_old_sea_map\",\"maxStamps\":0,\"sendType\":0,\"subtitleText\":\"MYSTERY GIFT\",\"titleText\":\"OLD SEA MAP\",\"type\":0,\"versions\":[\"emerald\"]}],\"family\":\"rse\",\"issued\":5,\"news\":[{\"bgType\":0,\"bodyText\":[\"Every game reads this.\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\"],\"family\":\"frlg\",\"id\":9,\"key\":\"kanto_news\",\"sendType\":0,\"titleText\":\"RELAY NEWS\"}],\"v\":1}","sig":"e10196799b4ff259bbf3b20f9ed133d5041dabf4f78bba4a3612d9464ecd2a693f95035e324697f0c31ae00efbcf33c43496882b7af03aeee2a5c99fe0a28f03","key":"b084317448d99b4451ec0b3f5a4ec746a0de25800d8e5bdce4bedbcae6b7ce1d"}]==]
local FEED_RS = [==[{"v":1,"payload":"{\"cards\":[],\"events\":[{\"family\":\"rs\",\"key\":\"rs_eon_ticket\",\"payload\":\"AQAAAAICAAIAAAAEAIABAAAQfhYAAB4AAAKaAgACBggBAWEAAAL7AQACCwEFEwEF+wEAAgLB4wDn2dkA7ePp5gDa1ejc2eYA1egA6NzZAMHTxwDd4v7Kv867xrzPzMGt/7hhAAACRxMBAQAhDYABALsBvwAAAkoTAQEAIQ2AAQC7Ab8AAAIrzgC7Ab8AAAJqWr3JAAACZm1GEwEBACENgAAAuwHAAAACGgCAEwEaAYABAAkAKVMIvQYBAAJmbWwNvYYBAAJmbWwCvru+8AD9AasAwePj2ADo4wDn2dkA7ePpq/7O3Nnm2bTnANUA4Nno6NnmANzZ5tkA2uPmAO3j6bgA/QGt/767vvAAw+gA1eTk2dXm5wDo4wDW2QDVANrZ5ubtAM7DvcW/zrj+1unoAMO06tkA4tnq2eYA59nZ4gDj4tkA4N3f2QDd6ADW2drj5tmt+9Pj6QDn3OPp4NgA6t3n3egAxsPG073J0L8A1eLYANXn3/7V1uPp6ADd6ADo3Nnm2a3/vru+8AD9AbgA6NzZAMW/0wDDzr/HzQDKyb3Fv84A3eL+7ePp5gC8u8EA3ecA2ung4K37x+Pq2QDn4+HZAN/Z7QDd6Nnh5wDa4+YA59Xa2d/Z2eTd4tv+3eIA7ePp5gDKvbgA6NzZ4gDX4+HZAOfZ2QDh2a3/uPsBAAJHEwEBACENgAEAuwFBAgACShMBAQAhDYABALsBQQIAAivOALsBQQIAAkYTAQEAIQ2AAAC7AUkCAAK+NQAAAg4CAr5RAgACDgMCvnUCAAIOAwLO3N3nAL/Qv8jOAOHV7QDW2QDk4NXt2dgA4+Lg7QDj4tfZrf/T4+nmALy7wbTnAMW/0wDDzr/HzQDKyb3Fv84A3ecA2ung4K3/\",\"title\":\"EON TICKET\",\"versions\":[\"ruby\",\"sapphire\"]},{\"family\":\"rs\",\"key\":\"rs_gift_ribbon\",\"payload\":\"AZsIAAICAAIAAAAEAIABAAAQTGwAALkIAAK9CAACCAABAg==\",\"title\":\"GIFT RIBBON\",\"versions\":[\"ruby\",\"sapphire\"]}],\"family\":\"rs\",\"issued\":5,\"news\":[{\"bgType\":0,\"bodyText\":[\"Every game reads this.\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\"],\"family\":\"frlg\",\"id\":9,\"key\":\"kanto_news\",\"sendType\":0,\"titleText\":\"RELAY NEWS\"}],\"v\":1}","sig":"ff759a880d1e32cd6e8962c86e3cb2f56b729b973545f4b748eaa7d571961c6690fae7034d36ef819f7127791d9bf972621097eab735f782558fa8cd1e9a680d","key":"b084317448d99b4451ec0b3f5a4ec746a0de25800d8e5bdce4bedbcae6b7ce1d"}]==]


local Json = require("src.link.Json")
local MysteryGift = require("src.core.game3.mystery_gift")
local Bag = require("src.core.game3.bag")
local Schema = require("src.core.game3.save_schema_firered")
MysteryGift.GIFT_PUBKEY = FIXTURE_PUB

local function keys(list, field)
  local out = {}
  for _, e in ipairs(list or {}) do out[#out + 1] = e[field or "key"] end
  return table.concat(out, ",")
end

local function verify(body, family, version)
  return MysteryGift.verifyFeed(Json.decode(body), family, version)
end

print("[test] 1. Cards only reach the games that had them")
local fr = verify(FEED_FRLG, "frlg", "firered")
local lg = verify(FEED_FRLG, "frlg", "leafgreen")
eq(fr and keys(fr.cards), "aurora_ticket", "FireRed does not see the LeafGreen-only card")
eq(lg and keys(lg.cards), "aurora_ticket,lg_mew", "LeafGreen sees its own card")
eq(lg and lg.cards[1].card.versions and table.concat(lg.cards[1].card.versions, ","), "firered,leafgreen",
  "the card keeps its game list")
local em = verify(FEED_RSE, "rse", "emerald")
eq(em and keys(em.cards), "rse_old_sea_map", "Emerald sees the OLD SEA MAP")
local any = verify(FEED_FRLG, "frlg", nil)
eq(any and #any.cards, 2, "with no game named nothing is dropped")

print("[test] 2. Wonder News reaches every game")
for _, row in ipairs({ { "firered", FEED_FRLG, "frlg" }, { "leafgreen", FEED_FRLG, "frlg" },
    { "emerald", FEED_RSE, "rse" }, { "ruby", FEED_RS, "rs" }, { "sapphire", FEED_RS, "rs" } }) do
  local list = verify(row[2], row[3], row[1])
  eq(list and keys(list.news), "kanto_news", "news reaches " .. row[1])
end

print("[test] 3. LeafGreen receives and collects its Wonder Card")
do
  local session = Schema.newGame({ rngSeed = 0x77 })
  session.version = "leafgreen"
  session.store = { flags = {}, vars = {} }
  session.bag = Bag.new()
  eq(MysteryGift.versionOf(session), "leafgreen", "the session is LeafGreen")
  local entry = lg.cards[1]
  check(MysteryGift.receiveCard(session, entry.card), "the relay AURORA TICKET card is saved on LeafGreen")
  eq(MysteryGift.deliverGift(session, MysteryGift.getSavedCard(session)), MysteryGift.DELIVER_GIVEN,
    "the deliveryman hands it over")
  check(Bag.has(session.bag, MysteryGift.ITEM_AURORA_TICKET, 1), "the AURORA TICKET is in the bag")
  -- pokefirered/data/mystery_event_msg.s:222
  check(MysteryGift.getFlag(session, 0x84B) and MysteryGift.getFlag(session, 0x2A7),
    "FLAG_ENABLE_SHIP_BIRTH_ISLAND and FLAG_RECEIVED_AURORA_TICKET are set")
end

print("[test] 4. The rs feed carries signed Mystery Events")
local ruby = verify(FEED_RS, "rs", "ruby")
local sapphire = verify(FEED_RS, "rs", "sapphire")
eq(ruby and keys(ruby.events), "rs_eon_ticket,rs_gift_ribbon", "Ruby lists both e-Reader events")
eq(sapphire and keys(sapphire.events), "rs_eon_ticket,rs_gift_ribbon", "and so does Sapphire")
eq(ruby and #ruby.cards, 0, "Ruby gets no Wonder Cards")
eq(ruby and ruby.events[1].label, "EON TICKET", "the event keeps its title")
check(ruby and #ruby.events[1].bytes > 17 and #ruby.events[1].bytes <= 0x7D4, "the bytes fit an e-Reader block")
-- pokeruby/data/debug_mystery_event_scripts.s:37 me_setrecordmixinggift 0x1, 0x5, ITEM_EON_TICKET
eq(MysteryGift.eventRecordMixingItem(ruby.events[1].bytes), 275, "the Eon event spreads ITEM_EON_TICKET")
eq(MysteryGift.eventRecordMixingItem(ruby.events[2].bytes), nil, "the ribbon event has no record mixing gift")
local forged = FEED_RS:gsub("EON TICKET", "EON TICKEU")
local bad, why = verify(forged, "rs", "ruby")
check(bad == nil and why == "bad_signature", "a tampered rs feed is refused")
local data = Json.decode(Json.decode(FEED_RS).payload)
local raw = require("src.core.Base64").decode(data.events[1].payload)
local rubyOnly = raw:sub(1, 13) .. string.char(0x80, 0, 0, 0) .. raw:sub(18)
data.events[1].payload = require("src.core.Base64").encode(rubyOnly)
local payload = Json.encode(data)
eq(#MysteryGift.parseFeed(payload, "rs", "ruby").events, 2, "a Ruby-only block still runs on Ruby")
eq(#MysteryGift.parseFeed(payload, "rs", "sapphire").events, 1, "but is dropped on Sapphire by its header")
data.events[2].versions = { "ruby" }
eq(#MysteryGift.parseFeed(Json.encode(data), "rs", "sapphire").events, 0, "and the feed game list drops the other")

T.finish("game3_gift_versions")
