--[[
  Owned-item disenchant calculator.

  Bags only. Equipped gear is not a row. Nothing is bought.
  A bracket with an unset yield or an unset skill is skipped.
  Item levels 166 and 167 are skipped. Northrend uncommon rates are not priced.
  A range uses its minimum quantity. The 0.5% crystal is not added.
  An unknown intact sale is not a disenchant. Soulbound gear can be
  disenchanted when the floor beats vendor. A known auction value must
  lose to the floor before DISENCHANT is actionable.
  Floor and expected value stay separate. The action uses the floor.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Engines = OnyxiaGold.Engines or {}
OnyxiaGold.Engines.Disenchant = OnyxiaGold.Engines.Disenchant or {}

local Disenchant = OnyxiaGold.Engines.Disenchant

local function sliceTick()
  local schedule = OnyxiaGold.RefreshSchedule
  if schedule and schedule.Tick then
    schedule.Tick()
  end
end

local function expectedGross(outcomes)
  local prices = OnyxiaGold.Prices
  local total = 0
  for i = 1, table.getn(outcomes) do
    local row = outcomes[i]
    local sale = prices:GetOpportunitySaleUnit(row.itemID)
    if not sale then
      return nil
    end
    total = total + math.floor(sale * row.minQty * row.bps / 10000 + 0.5)
  end
  return total
end

local function primaryOutput(outcomes)
  local best
  local bestValue = -1
  for i = 1, table.getn(outcomes) do
    local row = outcomes[i]
    local value = row.minQty * row.bps
    if value > bestValue then
      bestValue = value
      best = row
    end
  end
  return best
end

function Disenchant:IsDestructionStock(itemID)
  itemID = tonumber(itemID)
  local settings = OnyxiaGoldDB and OnyxiaGoldDB.settings
  local marked = settings and settings.destructionStock
  return itemID and type(marked) == "table" and marked[itemID] and true or false
end

function Disenchant:Exits(itemID, count, meta)
  itemID = tonumber(itemID)
  count = tonumber(count) or 0
  if not itemID or count < 1 or type(meta) ~= "table" then
    return nil
  end
  local quality = tonumber(meta.quality)
  local itemLevel = tonumber(meta.itemLevel)
  if not OnyxiaGold.ItemInfo:CanDisenchantQuality(quality) then
    return nil
  end
  local outcomes = OnyxiaGold.Data.GetDisenchantOutcomes(itemLevel, quality, meta.itemType)
  if not outcomes or table.getn(outcomes) < 1 then
    return nil
  end
  local floorGross = expectedGross(outcomes)
  if not floorGross or floorGross <= 0 then
    return {
      state = "UNKNOWN_EXIT",
      floor = nil,
      expected = nil,
      vendor = tonumber(meta.vendorPrice) or 0,
      intact = nil,
    }
  end
  local floorNet = OnyxiaGold:ApplyAuctionHouseCut(floorGross)
  local expectedNet = floorNet
  local vendor = tonumber(meta.vendorPrice) or 0
  local intact = nil
  local intactKnown = false
  if OnyxiaGold.Prices and OnyxiaGold.Prices.GetOpportunitySaleUnit then
    local sale = OnyxiaGold.Prices:GetOpportunitySaleUnit(itemID)
    local record = OnyxiaGold.Prices.GetRecord and OnyxiaGold.Prices:GetRecord(itemID)
    local external = record and record.source == "external"
    local stale = OnyxiaGold.Prices.IsStale and OnyxiaGold.Prices:IsStale(itemID)
    if sale and sale > 0 and not external and not stale then
      intact = OnyxiaGold:ApplyAuctionHouseCut(sale)
      intactKnown = true
    end
  end
  local bind = meta.bind or meta.bindType
  local soulbound = bind == "BoP" or bind == "Soulbound" or meta.soulbound
  if not OnyxiaGold.Lots or not OnyxiaGold.Lots.DisenchantExit then
    return nil
  end
  local exit = OnyxiaGold.Lots.DisenchantExit({
    floorNet = floorNet,
    expectedNet = expectedNet,
    vendor = vendor,
    intactNet = intact,
    intactKnown = intactKnown,
    soulbound = soulbound and true or false,
    destruction = self:IsDestructionStock(itemID),
  })
  exit.outcomes = outcomes
  exit.itemLevel = itemLevel
  exit.quality = quality
  exit.count = count
  return exit
end

function Disenchant:EvaluateOwned(itemID, count, meta)
  itemID = tonumber(itemID)
  count = tonumber(count) or 0
  if not itemID or count < 1 or type(meta) ~= "table" then
    return nil
  end
  local quality = tonumber(meta.quality)
  local itemLevel = tonumber(meta.itemLevel)
  if not OnyxiaGold.ItemInfo:CanDisenchantQuality(quality) then
    return nil
  end
  local need = OnyxiaGold.Data.GetDisenchantSkillRequired(itemLevel, quality)
  if not need then
    return nil
  end
  local outcomes = OnyxiaGold.Data.GetDisenchantOutcomes(itemLevel, quality, meta.itemType)
  if not outcomes or table.getn(outcomes) < 1 then
    return nil
  end
  local exit = self:Exits(itemID, count, meta)
  if not exit or not OnyxiaGold.Lots or not OnyxiaGold.Lots.AllowDisenchant(exit.state) then
    return nil
  end
  local gross = exit.floor
  local net = exit.floor
  local vendor = exit.vendor or 0
  local rival = vendor
  if exit.intact and exit.intact > rival then
    rival = exit.intact
  end
  local profit = (net or 0) - rival
  if profit <= 0 then
    return nil
  end
  local primary = primaryOutput(outcomes)
  local outputQty = OnyxiaGold.Prices:GetBuyoutQuantity(primary.itemID) or 0
  local certain = table.getn(outcomes) == 1 and outcomes[1].bps == 10000 and outcomes[1].minQty == 1
  local name = "Disenchant " .. tostring(meta.name or itemID)
  return OnyxiaGold.OpportunityEngine:New({
    type = "DISENCHANT",
    typeLabel = "Disenchant",
    name = name,
    investment = rival,
    grossRevenue = gross,
    netRevenue = net,
    expectedProfit = profit,
    roi = (rival > 0) and (profit / rival) or 0,
    availableQuantity = count,
    marketProfitableCrafts = count,
    totalExpectedProfit = profit * count,
    averageProfitPerCraft = profit,
    outputMarketQuantity = outputQty,
    notes = "Owned item. Disenchant floor beats the known intact exit. No buy.",
    inputs = { { itemID = itemID, count = 1 } },
    inputItemIDs = { itemID },
    outputItemIDs = { primary.itemID },
    outputCount = primary.minQty,
    expectedOutput = primary.bps / 10000,
    requirements = {
      profession = "Enchanting",
      minimumSkill = need,
    },
    inputCount = 1,
    recipeId = "de:" .. tostring(itemID),
    isExpectedValue = not certain,
    ownedOnly = true,
    saleExitUnknown = false,
    deFloor = exit.floor,
    deExpected = exit.expected,
    intactNet = exit.intact,
    vendorUnit = vendor,
    itemLevel = itemLevel,
    quality = quality,
  })
end

function Disenchant:Collect()
  local out = {}
  local row = OnyxiaGold.Database and OnyxiaGold.Database:GetCharacter()
  local bags = row and row.inventory and row.inventory.bags
  if type(bags) ~= "table" then
    return out
  end
  for itemID, count in pairs(bags) do
    sliceTick()
    local meta = OnyxiaGold.ItemInfo:Get(itemID)
    local ok, opp = pcall(function()
      return self:EvaluateOwned(itemID, count, meta)
    end)
    if ok and opp then
      table.insert(out, opp)
    elseif not ok then
      OnyxiaGold.Log:Error("Disenchant", "evaluate error: " .. tostring(opp))
    end
  end
  return out
end
