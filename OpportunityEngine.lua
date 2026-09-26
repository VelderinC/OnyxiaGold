--[[
  OnyxiaGold.OpportunityEngine
  Common opportunity model, conversion evaluation, collection and ranking.

  Ranking (v0.1.1): totalExpectedProfit (input-depth cap only), then expectedProfit.
  expectedProfit remains first-craft / first-conversion profit.
  totalExpectedProfit is labelled "Potential Profit" in the UI — not guaranteed.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.OpportunityEngine = OnyxiaGold.OpportunityEngine or {}

local Engine = OnyxiaGold.OpportunityEngine
Engine.results = {}

local function newOpportunity(fields)
  fields = fields or {}
  return {
    type = fields.type,
    typeLabel = fields.typeLabel or fields.type,
    name = fields.name,
    investment = fields.investment or 0,
    grossRevenue = fields.grossRevenue or 0,
    netRevenue = fields.netRevenue or 0,
    expectedProfit = fields.expectedProfit or 0,
    roi = fields.roi or 0,
    availableQuantity = fields.availableQuantity or fields.marketProfitableCrafts or fields.maxProfitableCrafts or 0,
    -- Market-only. Not physical, affordable, or executable capacity.
    marketProfitableCrafts = fields.marketProfitableCrafts or fields.maxProfitableCrafts or 0,
    maxProfitableCrafts = fields.marketProfitableCrafts or fields.maxProfitableCrafts or 0,
    totalExpectedProfit = fields.totalExpectedProfit or 0,
    averageProfitPerCraft = fields.averageProfitPerCraft or fields.expectedProfit or 0,
    averageUnitCost = fields.averageUnitCost,
    inputMarketQuantity = fields.inputMarketQuantity or 0,
    outputMarketQuantity = fields.outputMarketQuantity or 0,
    marketShareAfterProduction = fields.marketShareAfterProduction,
    confidence = fields.confidence or 1.0,
    confidenceNotes = fields.confidenceNotes or "",
    notes = fields.notes or "",
    inputs = fields.inputs,
    inputItemIDs = fields.inputItemIDs,
    outputItemIDs = fields.outputItemIDs,
    dataTimestamp = fields.dataTimestamp,
    oldestDataAge = fields.oldestDataAge,
    expectedOutput = fields.expectedOutput,
    saleUnit = fields.saleUnit,
    requirements = fields.requirements,
    inputCount = fields.inputCount,
    outputCount = fields.outputCount,
    recipeId = fields.recipeId,
    isExpectedValue = fields.isExpectedValue and true or false,
    -- false means the relationship is priced and must not become an action.
    actionable = fields.actionable ~= false,
    winnerName = fields.winnerName,
    runnerUpName = fields.runnerUpName,
    runnerUpProfit = fields.runnerUpProfit,
    forgoneLine = fields.forgoneLine,
    sharedCooldownRow = fields.sharedCooldownRow and true or false,
    cooldownDecision = fields.cooldownDecision,
    benchRow = fields.benchRow and true or false,
    castSeconds = tonumber(fields.castSeconds),
    maxCrafts = tonumber(fields.maxCrafts),
    ownedOnly = fields.ownedOnly and true or false,
    saleExitUnknown = fields.saleExitUnknown and true or false,
    vendorUnit = fields.vendorUnit,
    itemLevel = fields.itemLevel,
    quality = fields.quality,
  }
end

function Engine:New(fields)
  return newOpportunity(fields)
end

function Engine:OldestAge(itemIDs)
  local oldest
  if type(itemIDs) ~= "table" then
    return nil
  end
  for i = 1, table.getn(itemIDs) do
    local age = OnyxiaGold.Prices:GetAge(itemIDs[i])
    if age ~= nil then
      if not oldest or age > oldest then
        oldest = age
      end
    end
  end
  return oldest
end

function Engine:ComputeConfidence(fields)
  local conf = 1.0
  local notes = {}
  local age = fields.oldestDataAge
  local quick = OnyxiaGold.Config.QuickScanStaleSeconds or 600
  local full = OnyxiaGold.Config.FullScanStaleSeconds or 3600
  if age then
    if age > full then
      conf = conf - 0.2
      table.insert(notes, "data older than 1h")
    elseif age > quick then
      conf = conf - 0.1
      table.insert(notes, "data older than 10m")
    end
  else
    conf = conf - 0.2
    table.insert(notes, "missing timestamps")
  end

  local outQty = fields.outputMarketQuantity or 0
  local produced = fields.marketProfitableCrafts or fields.maxProfitableCrafts or 0
  if fields.outputCount then
    produced = produced * fields.outputCount
  end
  if outQty < 20 or (produced > 0 and outQty > 0 and produced > outQty) then
    conf = conf - 0.1
    table.insert(notes, "thin output market")
  end

  if (fields.expectedOutput or 1) > 1.0 then
    conf = conf - 0.1
    table.insert(notes, "Transmute Master EV is probabilistic")
  end

  if not fields.hasDepth then
    conf = conf - 0.1
    table.insert(notes, "no buyout depth; using min price")
  end

  if conf < 0 then
    conf = 0
  elseif conf > 1 then
    conf = 1
  end
  return conf, table.concat(notes, "; ")
end

function Engine:EvaluateConversionDirection(name, typeName, typeLabel, sourceID, sourceCount, targetID, targetCount, notes, extra)
  sourceID = tonumber(sourceID)
  targetID = tonumber(targetID)
  sourceCount = tonumber(sourceCount) or 0
  targetCount = tonumber(targetCount) or 0
  if not sourceID or not targetID or sourceCount <= 0 or targetCount <= 0 then
    return nil
  end

  local prices = OnyxiaGold.Prices
  local saleUnit = prices:GetOpportunitySaleUnit(targetID)
  if not saleUnit then
    OnyxiaGold.Log:Debug("Engine", "skip " .. tostring(name) .. ": no target sale price")
    return nil
  end

  local gross = saleUnit * targetCount
  local net = OnyxiaGold:ApplyAuctionHouseCut(gross)
  if net <= 0 then
    return nil
  end

  local marketCost = prices.GetEconomicAcquisitionCost and prices:GetEconomicAcquisitionCost(sourceID, sourceCount)
    or prices:GetAcquisitionCost(sourceID, sourceCount)
  local firstCost = marketCost
  local pricedFromMarket = marketCost and marketCost > 0
  local owned = 0
  if OnyxiaGold.Inventory and OnyxiaGold.Inventory.GetImmediatelyAvailableCount then
    owned = OnyxiaGold.Inventory:GetImmediatelyAvailableCount(sourceID)
  end
  if not pricedFromMarket then
    if owned >= sourceCount then
      local unit = prices:GetLiquidationPrice(sourceID)
      if not unit or unit <= 0 then
        OnyxiaGold.Log:Debug("Engine", "skip " .. tostring(name) .. ": no AH fill and no liquidation value")
        return nil
      end
      firstCost = unit * sourceCount
    else
      OnyxiaGold.Log:Debug("Engine", string.format(
        "skip %s: cannot fill first conversion item=%s count=%s",
        tostring(name), tostring(sourceID), tostring(sourceCount)
      ))
      return nil
    end
  end

  local firstProfit = net - firstCost
  if firstProfit <= 0 then
    OnyxiaGold.Log:Debug("Engine", string.format(
      "skip %s: first profit=%d investment=%d net=%d",
      tostring(name), firstProfit, firstCost, net
    ))
    return nil
  end

  -- Market capacity only. Owned stock must not inflate this count.
  local batch = nil
  if pricedFromMarket then
    batch = prices:GetMaxProfitableBatches(sourceID, sourceCount, net)
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
  local inputQty = prices:GetBuyoutQuantity(sourceID)
  local outputQty = prices:GetBuyoutQuantity(targetID)
  local produced = marketCrafts * targetCount
  local share
  if outputQty > 0 then
    share = produced / outputQty
  end

  local ages = self:OldestAge({ sourceID, targetID })
  local hasDepth = prices:GetDepth(sourceID) ~= nil
  local conf, confNotes = self:ComputeConfidence({
    oldestDataAge = ages,
    outputMarketQuantity = outputQty,
    marketProfitableCrafts = marketCrafts,
    outputCount = targetCount,
    expectedOutput = 1.0,
    hasDepth = hasDepth,
  })

  OnyxiaGold.Log:Debug("Engine", string.format(
    "hit %s first=%d total=%d marketCrafts=%d roi=%.2f conf=%.2f",
    tostring(name), firstProfit, totalProfit, marketCrafts, firstProfit / firstCost, conf
  ))

  return newOpportunity({
    type = typeName,
    typeLabel = typeLabel,
    name = name,
    investment = firstCost,
    grossRevenue = gross,
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
    inputItemIDs = { sourceID },
    outputItemIDs = { targetID },
    oldestDataAge = ages,
    saleUnit = saleUnit,
    requirements = extra and extra.requirements or nil,
    actionable = extra and extra.actionable,
    inputCount = sourceCount,
    outputCount = targetCount,
    recipeId = extra and extra.recipeId or nil,
  })
end

function Engine:AppendConversionOpportunities(out, def)
  if not def or not def.sourceItemID or not def.targetItemID then
    return
  end
  if not def.sourceCount or not def.targetCount then
    return
  end
  local kindName = string.upper(def.kind or "item") .. "_CONVERSION"
  local ok, opp = pcall(function()
    return self:EvaluateConversionDirection(
      def.nameForward,
      kindName,
      def.typeLabel,
      def.sourceItemID,
      def.sourceCount,
      def.targetItemID,
      def.targetCount,
      def.notesForward,
      { requirements = def.requirements, recipeId = def.id, actionable = def.actionable }
    )
  end)
  if ok and opp then
    table.insert(out, opp)
  elseif not ok then
    OnyxiaGold.Log:Error("Engine", "conversion error " .. tostring(def.id) .. ": " .. tostring(opp))
  end

  if def.reversible then
    local ok2, reverse = pcall(function()
      return self:EvaluateConversionDirection(
        def.nameReverse,
        kindName,
        def.typeLabel,
        def.targetItemID,
        def.targetCount,
        def.sourceItemID,
        def.sourceCount,
        def.notesReverse,
        { requirements = def.requirements, recipeId = def.id, actionable = def.actionable }
      )
    end)
    if ok2 and reverse then
      table.insert(out, reverse)
    elseif not ok2 then
      OnyxiaGold.Log:Error("Engine", "reverse conversion error " .. tostring(def.id) .. ": " .. tostring(reverse))
    end
  end
end

function Engine:CollectFrom(engine, name)
  if not engine or type(engine.Collect) ~= "function" then
    OnyxiaGold.Log:Debug("Engine", tostring(name or "?") .. " missing Collect()")
    return
  end
  local schedule = OnyxiaGold.RefreshSchedule
  if schedule and schedule.Tick then
    schedule.Tick()
  end
  -- A sliced refresh must be able to yield. Lua 5.1 cannot yield through pcall.
  local ok, list
  if schedule and schedule.activeSlice then
    ok = true
    list = engine:Collect()
  else
    ok, list = pcall(function()
      return engine:Collect()
    end)
  end
  if not ok then
    OnyxiaGold.Log:Error("Engine", tostring(name) .. " Collect() error: " .. tostring(list))
    return
  end
  if type(list) ~= "table" then
    OnyxiaGold.Log:Debug("Engine", tostring(name or "?") .. " Collect() returned non-table")
    return
  end
  local n = table.getn(list)
  OnyxiaGold.Log:Debug("Engine", tostring(name or "?") .. " returned " .. tostring(n))
  for i = 1, n do
    table.insert(self.results, list[i])
  end
end

function Engine:Rank(list)
  table.sort(list, function(a, b)
    local ta = a.totalExpectedProfit or 0
    local tb = b.totalExpectedProfit or 0
    if ta == tb then
      local pa = a.expectedProfit or 0
      local pb = b.expectedProfit or 0
      if pa == pb then
        return (a.roi or 0) > (b.roi or 0)
      end
      return pa > pb
    end
    return ta > tb
  end)
  return list
end

function Engine:Refresh()
  local perf = OnyxiaGold.Performance
  if perf and perf.Add then
    perf:Add("engineRebuilds", 1)
  end
  if perf and perf.Begin then
    perf:Begin("opportunity")
  end
  OnyxiaGold.Log:Debug("Engine", "Refreshing opportunities")
  self.published = self.results
  if type(self.published) ~= "table" then
    self.published = {}
  end
  self.building = true
  self.results = {}
  self:CollectFrom(OnyxiaGold.Engines.Essence, "Essence")
  self:CollectFrom(OnyxiaGold.Engines.Shards, "Shards")
  self:CollectFrom(OnyxiaGold.Engines.Transmute, "Transmute")
  self:CollectFrom(OnyxiaGold.Engines.Disenchant, "Disenchant")
  self:CollectFrom(OnyxiaGold.Engines.Crafting, "Crafting")
  self:CollectFrom(OnyxiaGold.Engines.Farming, "Farming")
  self:Rank(self.results)
  self.published = self.results
  self.building = false
  local n = table.getn(self.results)
  local top
  for i = 1, n do
    if self.results[i].actionable ~= false then
      top = self.results[i]
      break
    end
  end
  if top then
    OnyxiaGold.Log:Info("Engine", string.format(
      "%d opportunities. Top: %s first=%+d potential=%+d crafts=%s",
      n,
      tostring(top.name),
      top.expectedProfit or 0,
      top.totalExpectedProfit or 0,
      tostring(top.marketProfitableCrafts or top.maxProfitableCrafts)
    ))
  elseif n == 0 then
    OnyxiaGold.Log:Debug("Engine", "0 opportunities found")
  end
  if perf and perf.Add then
    perf:Add("opportunities", n)
  end
  if perf and perf.End then
    perf:End("opportunity")
  end
  return self.results
end

function Engine:GetResults()
  if self.building and type(self.published) == "table" then
    return self.published
  end
  return self.results or {}
end
