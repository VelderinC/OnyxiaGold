--[[
  OnyxiaGold.OpportunityEngine
  Collects opportunities from engines, ranks them, and builds conversion objects.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.OpportunityEngine = OnyxiaGold.OpportunityEngine or {}

local Engine = OnyxiaGold.OpportunityEngine
Engine.results = {}

local function newOpportunity(fields)
  return {
    type = fields.type,
    typeLabel = fields.typeLabel or fields.type,
    name = fields.name,
    investment = fields.investment or 0,
    grossRevenue = fields.grossRevenue or 0,
    netRevenue = fields.netRevenue or 0,
    expectedProfit = fields.expectedProfit or 0,
    roi = fields.roi or 0,
    availableQuantity = fields.availableQuantity or 0,
    confidence = fields.confidence or 1.0,
    notes = fields.notes or "",
    -- Reserved for later ranking:
    -- profitPerActiveMinute, liquidity, marketCapacity, historicalConfidence
  }
end

function Engine:New(fields)
  return newOpportunity(fields)
end

-- Evaluate one direction of a data-driven conversion.
function Engine:EvaluateConversionDirection(name, typeName, typeLabel, sourceID, sourceCount, targetID, targetCount, notes)
  local prices = OnyxiaGold.Prices
  local investment = prices:GetAcquisitionCost(sourceID, sourceCount)
  local gross = prices:GetGrossSaleValue(targetID, targetCount)
  if not investment or investment <= 0 then
    OnyxiaGold.Log:Debug("Engine", string.format(
      "skip %s: no source price item=%s count=%s",
      tostring(name), tostring(sourceID), tostring(sourceCount)
    ))
    return nil
  end
  if not gross or gross <= 0 then
    OnyxiaGold.Log:Debug("Engine", string.format(
      "skip %s: no target price item=%s count=%s",
      tostring(name), tostring(targetID), tostring(targetCount)
    ))
    return nil
  end

  local net = OnyxiaGold:ApplyAuctionHouseCut(gross)
  local profit = net - investment
  if profit <= 0 then
    OnyxiaGold.Log:Debug("Engine", string.format(
      "skip %s: profit=%d investment=%d net=%d",
      tostring(name), profit, investment, net
    ))
    return nil
  end

  local sourceQty = prices:GetQuantity(sourceID)
  local available = math.floor(sourceQty / sourceCount)
  if available < 1 then
    available = 0
  end

  OnyxiaGold.Log:Debug("Engine", string.format(
    "hit %s profit=%d roi=%.2f avail=%d investment=%d net=%d",
    tostring(name), profit, profit / investment, available, investment, net
  ))

  return newOpportunity({
    type = typeName,
    typeLabel = typeLabel,
    name = name,
    investment = investment,
    grossRevenue = gross,
    netRevenue = net,
    expectedProfit = profit,
    roi = profit / investment,
    availableQuantity = available,
    confidence = 1.0,
    notes = notes,
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
  local opp = self:EvaluateConversionDirection(
    def.nameForward,
    kindName,
    def.typeLabel,
    def.sourceItemID,
    def.sourceCount,
    def.targetItemID,
    def.targetCount,
    def.notesForward
  )
  if opp then
    table.insert(out, opp)
  end

  if def.reversible then
    local reverse = self:EvaluateConversionDirection(
      def.nameReverse,
      kindName,
      def.typeLabel,
      def.targetItemID,
      def.targetCount,
      def.sourceItemID,
      def.sourceCount,
      def.notesReverse
    )
    if reverse then
      table.insert(out, reverse)
    end
  end
end

function Engine:CollectFrom(engine, name)
  if not engine or type(engine.Collect) ~= "function" then
    OnyxiaGold.Log:Debug("Engine", tostring(name or "?") .. " missing Collect()")
    return
  end
  local list = engine:Collect()
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
    local pa = a.expectedProfit or 0
    local pb = b.expectedProfit or 0
    if pa == pb then
      local ra = a.roi or 0
      local rb = b.roi or 0
      return ra > rb
    end
    return pa > pb
  end)
  return list
end

function Engine:Refresh()
  OnyxiaGold.Log:Debug("Engine", "Refreshing opportunities")
  self.results = {}
  self:CollectFrom(OnyxiaGold.Engines.Essence, "Essence")
  self:CollectFrom(OnyxiaGold.Engines.Shards, "Shards")
  self:CollectFrom(OnyxiaGold.Engines.Transmute, "Transmute")
  self:CollectFrom(OnyxiaGold.Engines.Disenchant, "Disenchant")
  self:CollectFrom(OnyxiaGold.Engines.Crafting, "Crafting")
  self:CollectFrom(OnyxiaGold.Engines.Farming, "Farming")
  self:Rank(self.results)
  local n = table.getn(self.results)
  if n > 0 then
    local top = self.results[1]
    OnyxiaGold.Log:Info("Engine", string.format(
      "%d opportunities found. Top: %s %+d copper (%.0f%% ROI)",
      n,
      tostring(top.name),
      top.expectedProfit or 0,
      (top.roi or 0) * 100
    ))
  else
    OnyxiaGold.Log:Debug("Engine", "0 opportunities found")
  end
  if OnyxiaGold.UI and OnyxiaGold.UI.Refresh then
    OnyxiaGold.UI:Refresh()
  end
  return self.results
end

function Engine:GetResults()
  return self.results or {}
end
