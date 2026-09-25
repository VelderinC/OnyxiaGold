--[[
  Shard conversion engine.
  Same structure as Essence.lua; conversion math lives in the opportunity engine.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Engines = OnyxiaGold.Engines or {}
OnyxiaGold.Engines.Shards = OnyxiaGold.Engines.Shards or {}

local Shards = OnyxiaGold.Engines.Shards

function Shards:Collect()
  local out = {}
  local conversions = OnyxiaGold.Data.Conversions or {}
  for i = 1, table.getn(conversions) do
    local def = conversions[i]
    if def and def.kind == "shard" then
      OnyxiaGold.OpportunityEngine:AppendConversionOpportunities(out, def)
    end
  end
  return out
end
