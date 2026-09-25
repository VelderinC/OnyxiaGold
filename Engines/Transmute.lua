--[[
  Alchemy transmute engine.
  Recipes carry an input array. Each input is walked on its own buyout book.
  Sell side uses P25 (thin-market fallbacks).
  Output absorption is not modelled; total potential is input-depth capped.
  Transmute Master is the existing 1.20 expectation, and only when the recipe supports it.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Engines = OnyxiaGold.Engines or {}
OnyxiaGold.Engines.Transmute = OnyxiaGold.Engines.Transmute or {}

local Transmute = OnyxiaGold.Engines.Transmute

local function copyInputs(raw)
  local inputs = {}
  local ids = {}
  if type(raw) ~= "table" then
    return nil
  end
  for i = 1, table.getn(raw) do
    local row = raw[i]
    local itemID = tonumber(row and row.itemID)
    local count = tonumber(row and row.count) or 0
    if not itemID or count <= 0 then
      return nil
    end
    table.insert(inputs, { itemID = itemID, count = count })
    table.insert(ids, itemID)
  end
  if table.getn(inputs) < 1 then
    return nil
  end
  return inputs, ids
end

function Transmute:Evaluate(def)
  if not def or type(def.inputs) ~= "table" or type(def.outputs) ~= "table" then
    OnyxiaGold.Log:Debug("Transmute", "skip invalid recipe")
    return nil
  end
  if def.skillUnset or (def.requirements and def.requirements.skillUnset) then
    OnyxiaGold.Log:Debug("Transmute", "skip " .. tostring(def.name) .. ": skill unset")
    return nil
  end
  if table.getn(def.inputs) < 1 or table.getn(def.outputs) < 1 then
    return nil
  end

  local inputs, inputIDs = copyInputs(def.inputs)
  local output = def.outputs[1]
  local outputID = tonumber(output and output.itemID)
  local outCount = tonumber(output and output.count) or 0
  if not inputs or not outputID or outCount <= 0 then
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

  local function marketCost(crafts)
    local total = 0
    for i = 1, table.getn(inputs) do
      local row = inputs[i]
      local part = prices:GetAcquisitionCost(row.itemID, crafts * row.count)
      if not part then
        return nil
      end
      total = total + part
    end
    return total
  end

  local firstCost = marketCost(1)
  local pricedFromMarket = firstCost and firstCost > 0
  if not pricedFromMarket then
    local ownedCost = 0
    local ownedComplete = true
    for i = 1, table.getn(inputs) do
      local row = inputs[i]
      local owned = 0
      if OnyxiaGold.Inventory and OnyxiaGold.Inventory.GetImmediatelyAvailableCount then
        owned = OnyxiaGold.Inventory:GetImmediatelyAvailableCount(row.itemID) or 0
      end
      if owned < row.count then
        ownedComplete = false
        break
      end
      local unit = prices:GetLiquidationPrice(row.itemID)
      if not unit or unit <= 0 then
        ownedComplete = false
        break
      end
      ownedCost = ownedCost + unit * row.count
    end
    if not ownedComplete then
      OnyxiaGold.Log:Debug("Transmute", "skip " .. tostring(def.name) .. ": cannot fill first craft")
      return nil
    end
    firstCost = ownedCost
  end

  local firstProfit = net - firstCost
  if firstProfit <= 0 then
    OnyxiaGold.Log:Debug("Transmute", string.format(
      "skip %s: first profit=%d cost=%d net=%d outputEV=%.2f",
      tostring(def.name), firstProfit, firstCost, net, expectedOutput
    ))
    return nil
  end

  -- Market capacity only. Owned materials are reserved later by the planner.
  -- A batch is kept while its marginal cost, across every input book, stays under net.
  local marketCrafts = 0
  local totalCost = firstCost
  if pricedFromMarket then
    local hi = nil
    for i = 1, table.getn(inputs) do
      local row = inputs[i]
      local covered = prices:GetDepthCoveredQuantity(row.itemID) or 0
      local n = math.floor(covered / row.count)
      if not hi or n < hi then
        hi = n
      end
    end
    hi = hi or 0
    local function marginalOK(n)
      if n <= 0 then
        return false
      end
      local costN = marketCost(n)
      if not costN then
        return false
      end
      local prev = 0
      if n > 1 then
        prev = marketCost(n - 1)
        if not prev then
          return false
        end
      end
      return (costN - prev) < net
    end
    local lo = 0
    while lo < hi do
      local mid = math.floor((lo + hi + 1) / 2)
      if marginalOK(mid) then
        lo = mid
      else
        hi = mid - 1
      end
    end
    marketCrafts = lo
    if marketCrafts > 0 then
      totalCost = marketCost(marketCrafts) or firstCost
    end
  end
  local totalProfit = 0
  if marketCrafts > 0 then
    totalProfit = marketCrafts * net - totalCost
  end
  local avgProfit = marketCrafts > 0 and math.floor(totalProfit / marketCrafts) or firstProfit

  local inputQty = nil
  local hasDepth = true
  for i = 1, table.getn(inputs) do
    local qty = prices:GetBuyoutQuantity(inputs[i].itemID) or 0
    if not inputQty or qty < inputQty then
      inputQty = qty
    end
    if prices:GetDepth(inputs[i].itemID) == nil then
      hasDepth = false
    end
  end
  local outputQty = prices:GetBuyoutQuantity(outputID)
  local produced = marketCrafts * outCount * expectedOutput
  local share
  if outputQty > 0 then
    share = produced / outputQty
  end

  local ageIDs = { outputID }
  for i = 1, table.getn(inputIDs) do
    table.insert(ageIDs, inputIDs[i])
  end
  local ages = OnyxiaGold.OpportunityEngine:OldestAge(ageIDs)
  local conf, confNotes = OnyxiaGold.OpportunityEngine:ComputeConfidence({
    oldestDataAge = ages,
    outputMarketQuantity = outputQty,
    marketProfitableCrafts = marketCrafts,
    outputCount = outCount,
    expectedOutput = expectedOutput,
    hasDepth = hasDepth,
  })

  local notes = def.notes or ""
  notes = notes .. ". Sell-side uses P25 (fallback P10/min). Output market absorption is not modelled."

  OnyxiaGold.Log:Debug("Transmute", string.format(
    "hit %s first=%d total=%d marketCrafts=%d outputEV=%.2f",
    tostring(def.name), firstProfit, totalProfit, marketCrafts, expectedOutput
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
    inputMarketQuantity = inputQty or 0,
    outputMarketQuantity = outputQty,
    marketShareAfterProduction = share,
    confidence = conf,
    confidenceNotes = confNotes,
    notes = notes,
    inputs = inputs,
    inputItemIDs = inputIDs,
    outputItemIDs = { outputID },
    oldestDataAge = ages,
    expectedOutput = expectedOutput,
    saleUnit = saleUnit,
    requirements = def.requirements,
    inputCount = inputs[1].count,
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
