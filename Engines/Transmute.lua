--[[
  Alchemy transmute engine.
  v0.1: Saronite Bar x8 → Titanium Bar x1, with optional Transmute Master EV.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Engines = OnyxiaGold.Engines or {}
OnyxiaGold.Engines.Transmute = OnyxiaGold.Engines.Transmute or {}

local Transmute = OnyxiaGold.Engines.Transmute

local function minAvailableCrafts(inputs)
  local maxCrafts
  local prices = OnyxiaGold.Prices
  for i = 1, table.getn(inputs) do
    local input = inputs[i]
    local qty = prices:GetQuantity(input.itemID)
    local crafts = math.floor(qty / input.count)
    if not maxCrafts or crafts < maxCrafts then
      maxCrafts = crafts
    end
  end
  return maxCrafts or 0
end

local function inputCost(inputs)
  local total = 0
  local prices = OnyxiaGold.Prices
  for i = 1, table.getn(inputs) do
    local input = inputs[i]
    -- GetAcquisitionCost is the extension point for depth-aware costing.
    local cost = prices:GetAcquisitionCost(input.itemID, input.count)
    if not cost then
      return nil
    end
    total = total + cost
  end
  return total
end

function Transmute:Evaluate(def)
  if not def or not def.inputs or not def.outputs then
    OnyxiaGold.Log:Debug("Transmute", "skip invalid recipe")
    return nil
  end

  local investment = inputCost(def.inputs)
  if not investment or investment <= 0 then
    OnyxiaGold.Log:Debug("Transmute", "skip " .. tostring(def.name) .. ": missing input price")
    return nil
  end

  local expectedOutput = 1.0
  if def.supportsTransmuteMastery then
    expectedOutput = OnyxiaGold:GetTransmuteMultiplier()
  end

  local prices = OnyxiaGold.Prices
  local expectedGross = 0
  for i = 1, table.getn(def.outputs) do
    local output = def.outputs[i]
    local unit = prices:GetConservative(output.itemID)
    if not unit then
      OnyxiaGold.Log:Debug("Transmute", "skip " .. tostring(def.name) .. ": missing output price item=" .. tostring(output.itemID))
      return nil
    end
    -- EV may be fractional (1.20); convert back to integer copper.
    local evCount = output.count * expectedOutput
    expectedGross = expectedGross + math.floor(unit * evCount + 0.5)
  end

  if expectedGross <= 0 then
    OnyxiaGold.Log:Debug("Transmute", "skip " .. tostring(def.name) .. ": expectedGross=0")
    return nil
  end

  local net = OnyxiaGold:ApplyAuctionHouseCut(expectedGross)
  local profit = net - investment
  if profit <= 0 then
    OnyxiaGold.Log:Debug("Transmute", string.format(
      "skip %s: profit=%d investment=%d net=%d outputEV=%.2f master=%s",
      tostring(def.name), profit, investment, net, expectedOutput, tostring(OnyxiaGold:IsTransmuteMaster())
    ))
    return nil
  end

  local confidence = 1.0
  if expectedOutput > 1.0 then
    confidence = 0.9
  end

  local available = minAvailableCrafts(def.inputs)
  OnyxiaGold.Log:Debug("Transmute", string.format(
    "hit %s profit=%d roi=%.2f avail=%d outputEV=%.2f",
    tostring(def.name), profit, profit / investment, available, expectedOutput
  ))

  return OnyxiaGold.OpportunityEngine:New({
    type = "TRANSMUTE",
    typeLabel = def.typeLabel or "Transmute",
    name = def.name,
    investment = investment,
    grossRevenue = expectedGross,
    netRevenue = net,
    expectedProfit = profit,
    roi = profit / investment,
    availableQuantity = available,
    confidence = confidence,
    notes = def.notes or "",
  })
end

function Transmute:Collect()
  local out = {}
  local recipes = OnyxiaGold.Data.Transmutes or {}
  for i = 1, table.getn(recipes) do
    local opp = self:Evaluate(recipes[i])
    if opp then
      table.insert(out, opp)
    end
  end
  return out
end
