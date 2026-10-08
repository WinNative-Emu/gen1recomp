-- pokeyellow engine/events/pokecenter_chansey.asm:1
local function chansey()
  return {
    { "play_cry", "CHANSEY", true },
    { "show_text", "_NurseChanseyText" },
  }
end

local TEXTS = {
  VIRIDIAN_POKECENTER = "TEXT_VIRIDIANPOKECENTER_CHANSEY",       -- scripts/ViridianPokecenter.asm:29
  PEWTER_POKECENTER = "TEXT_PEWTERPOKECENTER_CHANSEY",           -- scripts/PewterPokecenter.asm:39
  MT_MOON_POKECENTER = "TEXT_MTMOONPOKECENTER_CHANSEY",          -- scripts/MtMoonPokecenter.asm:40
  CERULEAN_POKECENTER = "TEXT_CERULEANPOKECENTER_CHANSEY",       -- scripts/CeruleanPokecenter.asm:29
  ROCK_TUNNEL_POKECENTER = "TEXT_ROCKTUNNELPOKECENTER_CHANSEY",  -- scripts/RockTunnelPokecenter.asm:29
  VERMILION_POKECENTER = "TEXT_VERMILIONPOKECENTER_CHANSEY",     -- scripts/VermilionPokecenter.asm:29
  LAVENDER_POKECENTER = "TEXT_LAVENDERPOKECENTER_CHANSEY",       -- scripts/LavenderPokecenter.asm:29
  CELADON_POKECENTER = "TEXT_CELADONPOKECENTER_CHANSEY",         -- scripts/CeladonPokecenter.asm:29
  SAFFRON_POKECENTER = "TEXT_SAFFRONPOKECENTER_CHANSEY",         -- scripts/SaffronPokecenter.asm:29
  FUCHSIA_POKECENTER = "TEXT_FUCHSIAPOKECENTER_CHANSEY",         -- scripts/FuchsiaPokecenter.asm:29
  CINNABAR_POKECENTER = "TEXT_CINNABARPOKECENTER_CHANSEY",       -- scripts/CinnabarPokecenter.asm:29
  INDIGO_PLATEAU_LOBBY = "TEXT_INDIGOPLATEAULOBBY_CHANSEY",      -- scripts/IndigoPlateauLobby.asm:42
}

local M = {}
for mapId, text in pairs(TEXTS) do
  M[mapId] = { talk = { [text] = chansey() } }
end
return M
