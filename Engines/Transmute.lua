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

  local marketCost = prices:GetAcquisitionCost(inputID, inCount)
  local firstCost = marketCost
  local pricedFromMarket = marketCost and marketCost > 0
  local owned = 0
  if OnyxiaGold.Inventory and OnyxiaGold.Inventory.GetImmediatelyAvailableCount then
    owned = OnyxiaGold.Inventory:GetImmediatelyAvailableCount(inputID)
  end
  if not pricedFromMarket then
    if owned >= inCount then
      local unit = prices:GetLiquidationPrice(inputID)
      if not unit or unit <= 0 then
        OnyxiaGold.Log:Debug("Transmute", "skip " .. tostring(def.name) .. ": no AH fill and no liquidation value")
        return nil
      end
      firstCost = unit * inCount
    else
      OnyxiaGold.Log:Debug("Transmute", "skip " .. tostring(def.name) .. ": cannot fill first craft")
      return nil
    end
  end

  local firstProfit = net - firstCost
  if firstProfit <= 0 then
    OnyxiaGold.Log:Debug("Transmute", string.format(
      "skip %s: first profit=%d cost=%d net=%d outputEV=%.2f",
      tostring(def.name), firstProfit, firstCost, net, expectedOutput
    ))
    return nil
  end

  -- Market capacity only. Owned bars are reserved later by the planner.
  local batch = nil
  if pricedFromMarket then
    batch = prices:GetMaxProfitableBatches(inputID, inCount, net)
  end
  local marketCrafts = 0
  if batch and batch.batches and batch.batches > 0 then
    marketCrafts = batch.batches
  elseif pricedFromMarket then
    marketCrafts = 1
  end
  local totalProfit = 0
  if batch and batch.totalProfit then
    totalProfit = batch.totalProfit
  elseif marketCrafts > 0 then
    totalProfit = firstProfit * marketCrafts
  end
  local avgProfit = marketCrafts > 0 and math.floor(totalProfit / marketCrafts) or firstProfit
  local inputQty = prices:GetBuyoutQuantity(inputID)
  local outputQty = prices:GetBuyoutQuantity(outputID)
  local produced = marketCrafts * outCount * expectedOutput
  local share
  if outputQty > 0 then
    share = produced / outputQty
  end

  local ages = OnyxiaGold.OpportunityEngine:OldestAge({ inputID, outputID })
  local conf, confNotes = OnyxiaGold.OpportunityEngine:ComputeConfidence({
    oldestDataAge = ages,
    outputMarketQuantity = outputQty,
    marketProfitableCrafts = marketCrafts,
    outputCount = outCount,
    expectedOutput = expectedOutput,
    hasDepth = prices:GetDepth(inputID) ~= nil,
  })

  local notes = def.notes or ""
  notes = notes .. ". Sell-side uses P25 (fallback P10/min). Output market absorption is not modelled."

  OnyxiaGold.Log:Debug("Transmute", string.format(
    "hit %s first=%d total=%d marketCrafts=%d avgIn=%s outputEV=%.2f",
    tostring(def.name), firstProfit, totalProfit, marketCrafts,
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
    availableQuantity = marketCrafts,
    marketProfitableCrafts = marketCrafts,
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
    requirements = def.requirements,
    inputCount = inCount,
    outputCount = outCount,
    recipeId = def.id,
    isExpectedValue = expectedOutput ~= 1,
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
