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

local COOLDOWN_GROUP = "transmute_20h"

local function cooldownOf(def)
  local req = def and def.requirements
  return req and req.cooldown or nil
end

-- unset: skill is not a number we may use.
-- unknown: profession scan has not happened.
-- locked: skill, profession, or recipe blocks the cast.
-- ready: this character can perform it.
function Transmute:RecipeGate(def)
  if not def or def.skillUnset or (def.requirements and def.requirements.skillUnset) then
    return "unset"
  end
  if not def.requirements then
    return "unset"
  end
  local capApi = OnyxiaGold.Capabilities
  if not capApi or not capApi.CanExecute then
    return "locked"
  end
  local cap = capApi:CanExecute(def.requirements)
  if cap and cap.executable then
    return "ready"
  end
  if cap and cap.skillUnset then
    return "unset"
  end
  if cap and cap.unknownRecipe then
    return "unknown"
  end
  return "locked"
end

-- One craft after a depth walk. Profit may be zero or negative.
-- Nil means the materials could not be priced, so the craft did not survive the walk.
function Transmute:QuoteFirstCraft(def)
  if not def or type(def.inputs) ~= "table" or type(def.outputs) ~= "table" then
    return nil
  end
  if def.skillUnset or (def.requirements and def.requirements.skillUnset) then
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
      return nil
    end
    firstCost = ownedCost
  end

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

  return {
    def = def,
    inputs = inputs,
    inputIDs = inputIDs,
    outputID = outputID,
    outCount = outCount,
    expectedOutput = expectedOutput,
    saleUnit = saleUnit,
    expectedGross = expectedGross,
    net = net,
    cost = firstCost,
    profit = net - firstCost,
    pricedFromMarket = pricedFromMarket and true or false,
    marketCost = marketCost,
    hasDepth = hasDepth,
    inputQty = inputQty or 0,
    outputQty = prices:GetBuyoutQuantity(outputID) or 0,
  }
end

function Transmute:OpportunityFromQuote(quote, extra)
  extra = extra or {}
  local def = quote.def
  local inputs = quote.inputs
  local inputIDs = quote.inputIDs
  local marketCrafts = extra.marketCrafts or 0
  local totalProfit = extra.totalProfit or 0
  local totalCost = extra.totalCost or quote.cost
  local avgProfit = marketCrafts > 0 and math.floor(totalProfit / marketCrafts) or quote.profit
  local outputQty = quote.outputQty or 0
  local produced = marketCrafts * quote.outCount * quote.expectedOutput
  local share
  if outputQty > 0 then
    share = produced / outputQty
  end

  local ageIDs = { quote.outputID }
  for i = 1, table.getn(inputIDs) do
    table.insert(ageIDs, inputIDs[i])
  end
  local ages = OnyxiaGold.OpportunityEngine:OldestAge(ageIDs)
  local conf, confNotes = OnyxiaGold.OpportunityEngine:ComputeConfidence({
    oldestDataAge = ages,
    outputMarketQuantity = outputQty,
    marketProfitableCrafts = marketCrafts,
    outputCount = quote.outCount,
    expectedOutput = quote.expectedOutput,
    hasDepth = quote.hasDepth,
  })

  local notes = extra.notes or def.notes or ""
  if not extra.notes then
    notes = notes .. ". Sell-side uses P25 (fallback P10/min). Output market absorption is not modelled."
  end

  local fields = {
    type = "TRANSMUTE",
    typeLabel = extra.typeLabel or def.typeLabel or "Transmute",
    name = extra.name or def.name,
    investment = quote.cost,
    grossRevenue = quote.expectedGross,
    netRevenue = quote.net,
    expectedProfit = quote.profit,
    roi = (quote.cost > 0) and (quote.profit / quote.cost) or 0,
    availableQuantity = marketCrafts,
    marketProfitableCrafts = marketCrafts,
    totalExpectedProfit = totalProfit,
    averageProfitPerCraft = avgProfit,
    inputMarketQuantity = quote.inputQty or 0,
    outputMarketQuantity = outputQty,
    marketShareAfterProduction = share,
    confidence = conf,
    confidenceNotes = confNotes,
    notes = notes,
    inputs = inputs,
    inputItemIDs = inputIDs,
    outputItemIDs = { quote.outputID },
    oldestDataAge = ages,
    expectedOutput = quote.expectedOutput,
    saleUnit = quote.saleUnit,
    requirements = def.requirements,
    inputCount = inputs[1].count,
    outputCount = quote.outCount,
    recipeId = def.id,
    isExpectedValue = quote.expectedOutput ~= 1,
    winnerName = extra.winnerName,
    runnerUpName = extra.runnerUpName,
    runnerUpProfit = extra.runnerUpProfit,
    forgoneLine = extra.forgoneLine,
    sharedCooldownRow = extra.sharedCooldownRow and true or false,
    cooldownDecision = extra.cooldownDecision,
  }
  return OnyxiaGold.OpportunityEngine:New(fields)
end

function Transmute:Evaluate(def)
  local quote = self:QuoteFirstCraft(def)
  if not quote then
    if def and (def.skillUnset or (def.requirements and def.requirements.skillUnset)) then
      OnyxiaGold.Log:Debug("Transmute", "skip " .. tostring(def.name) .. ": skill unset")
    end
    return nil
  end
  if quote.profit <= 0 then
    OnyxiaGold.Log:Debug("Transmute", string.format(
      "skip %s: first profit=%d cost=%d net=%d outputEV=%.2f",
      tostring(def.name), quote.profit, quote.cost, quote.net, quote.expectedOutput
    ))
    return nil
  end

  local inputs = quote.inputs
  local net = quote.net
  local firstCost = quote.cost
  local pricedFromMarket = quote.pricedFromMarket
  local marketCost = quote.marketCost
  local prices = OnyxiaGold.Prices

  -- Market capacity only. Owned materials are reserved later by the planner.
  -- A batch is kept while its marginal cost, across every input book, stays under net.
  -- Repeatable crafts only. A 20-hour recipe is one cast, ranked separately.
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

  OnyxiaGold.Log:Debug("Transmute", string.format(
    "hit %s first=%d total=%d marketCrafts=%d outputEV=%.2f",
    tostring(quote.def.name), quote.profit, totalProfit, marketCrafts, quote.expectedOutput
  ))

  return self:OpportunityFromQuote(quote, {
    marketCrafts = marketCrafts,
    totalProfit = totalProfit,
    totalCost = totalCost,
  })
end

function Transmute:UnknownRow(def)
  local inputs, inputIDs = copyInputs(def.inputs)
  local output = def.outputs and def.outputs[1]
  local outputID = tonumber(output and output.itemID)
  return OnyxiaGold.OpportunityEngine:New({
    type = "TRANSMUTE",
    typeLabel = "Transmute",
    name = def.name,
    notes = "Recipe state is unknown until a profession scan.",
    inputs = inputs,
    inputItemIDs = inputIDs,
    outputItemIDs = outputID and { outputID } or nil,
    requirements = def.requirements,
    inputCount = inputs and inputs[1] and inputs[1].count or 1,
    outputCount = tonumber(output and output.count) or 1,
    recipeId = def.id,
    expectedProfit = 0,
    totalExpectedProfit = 0,
    marketProfitableCrafts = 0,
    availableQuantity = 0,
  })
end

local function forgoneText(runner)
  if not runner then
    return "No other 20-hour transmute beats selling its materials."
  end
  local gold = OnyxiaGold.FormatGoldShort(runner.profit)
  return "Skipping " .. tostring(runner.def.name) .. " gives up " .. gold .. "."
end

-- One row for the shared 20-hour group. Only recipes this skill can perform.
-- Nil when none are performable. A skip row when every priced one loses to selling.
function Transmute:RankCooldown(defs)
  local ready = {}
  local passthrough = {}
  for i = 1, table.getn(defs) do
    local def = defs[i]
    local gate = self:RecipeGate(def)
    if gate == "unknown" then
      table.insert(passthrough, self:UnknownRow(def))
    elseif gate == "ready" then
      local quote = self:QuoteFirstCraft(def)
      if quote then
        table.insert(ready, quote)
      end
    end
  end

  local winners = {}
  local losers = 0
  for i = 1, table.getn(ready) do
    local quote = ready[i]
    if quote.profit > 0 then
      table.insert(winners, quote)
    else
      losers = losers + 1
    end
  end
  table.sort(winners, function(a, b)
    if a.profit == b.profit then
      return (a.cost or 0) < (b.cost or 0)
    end
    return a.profit > b.profit
  end)

  if table.getn(winners) > 0 then
    local best = winners[1]
    local runner = winners[2]
    local line = forgoneText(runner)
    local notes = (best.def.notes or "") .. " " .. line
    local row = self:OpportunityFromQuote(best, {
      marketCrafts = 1,
      totalProfit = best.profit,
      totalCost = best.cost,
      name = best.def.name,
      typeLabel = "20-hour",
      notes = notes,
      winnerName = best.def.name,
      runnerUpName = runner and runner.def.name or nil,
      runnerUpProfit = runner and runner.profit or 0,
      forgoneLine = line,
      sharedCooldownRow = true,
      cooldownDecision = "cast",
    })
    return row, passthrough
  end

  if losers > 0 then
    local skip = OnyxiaGold.OpportunityEngine:New({
      type = "TRANSMUTE",
      typeLabel = "20-hour",
      name = "Skip 20-hour transmute",
      notes = "Skip. None of these beat selling the materials.",
      expectedProfit = 0,
      totalExpectedProfit = 0,
      marketProfitableCrafts = 0,
      availableQuantity = 0,
      forgoneLine = "Skip. None of these beat selling the materials.",
      sharedCooldownRow = true,
      cooldownDecision = "skip",
    })
    return skip, passthrough
  end

  return nil, passthrough
end

function Transmute:Collect()
  local out = {}
  local cooldown = {}
  local recipes = OnyxiaGold.Data.Transmutes or {}
  for i = 1, table.getn(recipes) do
    local def = recipes[i]
    if cooldownOf(def) == COOLDOWN_GROUP then
      table.insert(cooldown, def)
    else
      local ok, opp = pcall(function()
        return self:Evaluate(def)
      end)
      if ok and opp then
        table.insert(out, opp)
      elseif not ok then
        OnyxiaGold.Log:Error("Transmute", "evaluate error: " .. tostring(opp))
      end
    end
  end
  local ok, ranked, passthrough = pcall(function()
    return self:RankCooldown(cooldown)
  end)
  if not ok then
    OnyxiaGold.Log:Error("Transmute", "cooldown rank error: " .. tostring(ranked))
    return out
  end
  if ranked then
    table.insert(out, ranked)
  end
  passthrough = passthrough or {}
  for i = 1, table.getn(passthrough) do
    table.insert(out, passthrough[i])
  end
  return out
end
