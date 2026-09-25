--[[
  Alchemy transmute engine.
  Depth-aware Saronite → Titanium. Sell side uses P25 (thin-market fallbacks).
  Output absorption is not modelled; total potential is input-depth capped.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Engines = OnyxiaGold.Engines or {}
OnyxiaGold.Engines.Transmute = OnyxiaGold.Engines.Transmute or {}

local Transmute = OnyxiaGold.Engines.Transmute

function Transmute:Evaluate(def)
  if not def or type(def.inputs) ~= "table" or type(def.outputs) ~= "table" then
    OnyxiaGold.Log:Debug("Transmute", "skip invalid recipe")
    return nil
  end
  if table.getn(def.inputs) < 1 or table.getn(def.outputs) < 1 then
    return nil
  end

  -- v0.1.1: single-input transmutes. Multi-input depth walk comes later.
  local input = def.inputs[1]
  local output = def.outputs[1]
  local inputID = tonumber(input and input.itemID)
  local outputID = tonumber(output and output.itemID)
  local inCount = tonumber(input and input.count) or 0
  local outCount = tonumber(output and output.count) or 0
  if not inputID or not outputID or inCount <= 0 or outCount <= 0 then
    return nil
  end

  local expectedOutput = 1.0
  if def.supportsTransmuteMastery then
    expectedOutput = OnyxiaGold:GetTransmuteMultiplier()
  end

  local prices = OnyxiaGold.Prices
  local saleUnit = prices:GetOpportunitySaleUnit(outputID)
  if not saleUnit then
    OnyxiaGold.Log:Debug("Transmute", "skip " .. tostring(def.name) .. ": missing output price")
    return nil
  end

  local expectedGross = math.floor(saleUnit * outCount * expectedOutput + 0.5)
  if expectedGross <= 0 then
    return nil
  end
  local net = OnyxiaGold:ApplyAuctionHouseCut(expectedGross)

  local firstCost = prices:GetAcquisitionCost(inputID, inCount)
  if not firstCost or firstCost <= 0 then
    OnyxiaGold.Log:Debug("Transmute", "skip " .. tostring(def.name) .. ": cannot fill first craft")
    return nil
  end

  local firstProfit = net - firstCost
  if firstProfit <= 0 then
    OnyxiaGold.Log:Debug("Transmute", string.format(
      "skip %s: first profit=%d cost=%d net=%d outputEV=%.2f",
      tostring(def.name), firstProfit, firstCost, net, expectedOutput
    ))
    return nil
  end

  local batch = prices:GetMaxProfitableBatches(inputID, inCount, net)
  local crafts = batch and batch.batches or 1
  local totalProfit = batch and batch.totalProfit or firstProfit
  local avgProfit = crafts > 0 and math.floor(totalProfit / crafts) or firstProfit
  local inputQty = prices:GetBuyoutQuantity(inputID)
  local outputQty = prices:GetBuyoutQuantity(outputID)
  local produced = crafts * outCount * expectedOutput
  local share
  if outputQty > 0 then
    share = produced / outputQty
  end

  local ages = OnyxiaGold.OpportunityEngine:OldestAge({ inputID, outputID })
  local conf, confNotes = OnyxiaGold.OpportunityEngine:ComputeConfidence({
    oldestDataAge = ages,
    outputMarketQuantity = outputQty,
    maxProfitableCrafts = crafts,
    outputCount = outCount,
    expectedOutput = expectedOutput,
    hasDepth = prices:GetDepth(inputID) ~= nil,
  })

  local notes = def.notes or ""
  notes = notes .. ". Sell-side uses P25 (fallback P10/min). Output market absorption is not modelled."

  OnyxiaGold.Log:Debug("Transmute", string.format(
    "hit %s first=%d total=%d crafts=%d avgIn=%s outputEV=%.2f",
    tostring(def.name), firstProfit, totalProfit, crafts,
    tostring(batch and batch.averageUnitCost), expectedOutput
  ))

  return OnyxiaGold.OpportunityEngine:New({
    type = "TRANSMUTE",
    typeLabel = def.typeLabel or "Transmute",
    name = def.name,
    investment = firstCost,
    grossRevenue = expectedGross,
    netRevenue = net,
    expectedProfit = firstProfit,
    roi = firstProfit / firstCost,
    availableQuantity = crafts,
    maxProfitableCrafts = crafts,
    totalExpectedProfit = totalProfit,
    averageProfitPerCraft = avgProfit,
    averageUnitCost = batch and batch.averageUnitCost,
    inputMarketQuantity = inputQty,
    outputMarketQuantity = outputQty,
    marketShareAfterProduction = share,
    confidence = conf,
    confidenceNotes = confNotes,
    notes = notes,
    inputItemIDs = { inputID },
    outputItemIDs = { outputID },
    oldestDataAge = ages,
    expectedOutput = expectedOutput,
    saleUnit = saleUnit,
  })
end

function Transmute:Collect()
  local out = {}
  local recipes = OnyxiaGold.Data.Transmutes or {}
  for i = 1, table.getn(recipes) do
    local ok, opp = pcall(function()
      return self:Evaluate(recipes[i])
    end)
    if ok and opp then
      table.insert(out, opp)
    elseif not ok then
      OnyxiaGold.Log:Error("Transmute", "evaluate error: " .. tostring(opp))
    end
  end
  return out
end
