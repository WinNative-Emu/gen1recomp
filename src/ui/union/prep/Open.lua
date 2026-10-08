local Model = require("src.online.union.BattlePrepModel")

local Open = {}

Open.RENDERERS = {
  [1] = "src.ui.union.prep.Gen1BattlePrep",
  [2] = "src.ui.union.prep.Gen2BattlePrep",
  [3] = "src.ui.union.prep.Gen3BattlePrep",
}

function Open.source(game, gen)
  if gen == 3 then
    local session = game and game.session
    if not session then
      local ok, Runtime = pcall(require, "src.core.game3.runtime")
      session = ok and Runtime.getSession and Runtime.getSession() or nil
    end
    if not session then return { party = {}, generation = 3 } end
    local PartyView = require("src.core.game3.battle.party_view")
    local party = PartyView.fromSession(session.party, session.move_overlay)
    return { party = party, save = { storage = session.storage }, generation = 3 }
  end
  local save = game and game.save or {}
  return { party = save.party or {}, save = save, generation = gen }
end

function Open.opponent(room, prep)
  local r = room and room.xgRoom and room:xgRoom() or nil
  local mine = prep and prep.seat and prep:seat() or nil
  for _, p in ipairs(r and r.players or {}) do
    if mine == nil or p.seat ~= mine then
      local av = type(p.avatar) == "table" and p.avatar or {}
      return { name = av.name or p.name, version = av.version, gen = p.gen or av.gen }
    end
  end
  return { name = "?" }
end

function Open.gameplayMods(game)
  return require("src.online.union.Caps").gameplayMods(game)
end

function Open.model(game, room, prep, opts)
  opts = opts or {}
  local GameVersion = require("src.core.GameVersion")
  local version = opts.version or GameVersion.get()
  local gen = GameVersion.generation(version)
  local mods = opts.gameplayMods
  if mods == nil then mods = Open.gameplayMods(game) end
  return Model.new({
    version = version, gen = gen, data = opts.data, prep = prep,
    opponent = opts.opponent or Open.opponent(room, prep),
    gameplayMods = mods, owned = opts.owned or Open.source(game, gen), rules = opts.rules,
  })
end

function Open.battle(game, room, prep, onDone, opts)
  local model = Open.model(game, room, prep, opts)
  local Renderer = require(Open.RENDERERS[model.gen] or Open.RENDERERS[1])
  local screen = Renderer.open(game, model, function()
    local result, outcome = model:result(), model.outcome
    model:discard()
    if outcome ~= "go" and prep and prep.leave then prep:leave() end
    if onDone then onDone(result, outcome) end
  end)
  return screen, model
end

function Open.screen(act, opts)
  opts = opts or {}
  local peer = act.peer or {}
  opts.opponent = opts.opponent or { name = peer.name, version = peer.game, gen = peer.gen }
  return Open.battle(act.game, act.room, act.prep, function(result, outcome)
    act.battlePrep = result
    act:finish(outcome == "go" and "go" or outcome or "cancel")
  end, opts)
end

function Open.register(Activity)
  if type(Activity) == "table" and type(Activity.screens) == "table" then
    Activity.screens.battle = Open.screen
  end
  return Activity
end

Open.register(require("src.ui.gen2.union.Activity"))
Open.register(require("src.ui.union.gen1.Activity"))

return Open
