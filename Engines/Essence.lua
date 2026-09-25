--[[
  Essence conversion engine.
  Evaluates both directions of each essence pair using current scan prices.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Engines = OnyxiaGold.Engines or {}
OnyxiaGold.Engines.Essence = OnyxiaGold.Engines.Essence or {}

local Essence = OnyxiaGold.Engines.Essence

function Essence:Collect()
  local out = {}
  local conversions = OnyxiaGold.Data.Conversions or {}
  for i = 1, table.getn(conversions) do
    local def = conversions[i]
    if def and def.kind == "essence" then
      OnyxiaGold.OpportunityEngine:AppendConversionOpportunities(out, def)
    end
  end
  return out
end
