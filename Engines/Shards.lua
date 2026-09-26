--[[
  Shard conversion engine.
  Same structure as Essence.lua; conversion math lives in the opportunity engine.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Engines = OnyxiaGold.Engines or {}
OnyxiaGold.Engines.Shards = OnyxiaGold.Engines.Shards or {}

local Shards = OnyxiaGold.Engines.Shards

local function enchantRows()
  local out = {}
  local crafts = OnyxiaGold.Data.EnchantCrafts or {}
  local engine = OnyxiaGold.Engines.Transmute
  if not engine or not engine.RecipeGate then
    return out
  end
  for i = 1, table.getn(crafts) do
    local def = crafts[i]
    local gate = engine:RecipeGate(def)
    if gate == "unknown" then
      local row = engine:UnknownRow(def)
      row.type = "ENCHANTING"
      row.typeLabel = "Enchanting"
      table.insert(out, row)
    elseif gate == "ready" then
      local quote = engine:QuoteFirstCraft(def)
      if quote and def.compareToSelling and quote.profit <= 0 then
        table.insert(out, {
          type = "ENCHANTING",
          typeLabel = "Enchanting",
          name = "Sell Void Crystal",
          shatterDecision = "sell",
          expectedProfit = quote.profit,
          totalExpectedProfit = 0,
          marketProfitableCrafts = 0,
          availableQuantity = 0,
          requirements = def.requirements,
          notes = "Selling the crystal leaves more than shattering it.",
          actionable = true,
          forgoneLine = "Sell. Shattering leaves less after the cut.",
        })
      elseif quote and quote.profit > 0 then
        local craftsN = def.maxCrafts or nil
        local opp
        if craftsN == 1 then
          opp = engine:OpportunityFromQuote(quote, {
            marketCrafts = 1,
            totalProfit = quote.profit,
            totalCost = quote.cost,
            typeLabel = "Enchanting",
            name = def.name,
          })
          opp.maxCrafts = 1
        else
          opp = engine:Evaluate(def)
        end
        if opp then
          opp.type = "ENCHANTING"
          opp.typeLabel = "Enchanting"
          if def.maxCrafts then
            opp.maxCrafts = def.maxCrafts
          end
          table.insert(out, opp)
        end
      end
    end
  end
  return out
end

function Shards:Collect()
  local out = {}
  local conversions = OnyxiaGold.Data.Conversions or {}
  for i = 1, table.getn(conversions) do
    local def = conversions[i]
    if def and def.kind == "shard" then
      if OnyxiaGold.RefreshSchedule and OnyxiaGold.RefreshSchedule.Tick then
        OnyxiaGold.RefreshSchedule.Tick()
      end
      OnyxiaGold.OpportunityEngine:AppendConversionOpportunities(out, def)
    end
  end
  local extra = enchantRows()
  for i = 1, table.getn(extra) do
    if OnyxiaGold.RefreshSchedule and OnyxiaGold.RefreshSchedule.Tick then
      OnyxiaGold.RefreshSchedule.Tick()
    end
    table.insert(out, extra[i])
  end
  return out
end
