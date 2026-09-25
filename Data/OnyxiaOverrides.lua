--[[
  Warmane Onyxia specific overrides.
  Keep this file as the only place for realm-specific economic constants.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Data = OnyxiaGold.Data or {}

OnyxiaGold.Data.OnyxiaOverrides = {
  -- Set to a number to replace OnyxiaGold.Config.AuctionHouseCut (e.g. 0.05).
  auctionHouseCut = nil,
  -- Set true/false to force Transmute Master EV regardless of saved settings.
  transmuteMaster = nil,
}

function OnyxiaGold.Data.ApplyOnyxiaOverrides()
  local ov = OnyxiaGold.Data.OnyxiaOverrides
  if not ov then
    return
  end
  if ov.auctionHouseCut then
    OnyxiaGold.Log:Debug("Data", "Onyxia override: AH cut " .. tostring(ov.auctionHouseCut))
  end
end
