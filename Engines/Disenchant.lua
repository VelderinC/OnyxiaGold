--[[
  Owned-item disenchant calculator.

  Bags only. Equipped gear is not a row. Nothing is bought.
  A bracket with an unset yield or an unset skill is skipped.
  Item levels 166 and 167 are skipped. Northrend uncommon rates are not priced.
  A range uses its minimum quantity. The 0.5% crystal is not added.
  Sale of the gear is unknown until bind is known, so the alternative is vendor.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Engines = OnyxiaGold.Engines or {}
OnyxiaGold.Engines.Disenchant = OnyxiaGold.Engines.Disenchant or {}

local Disenchant = OnyxiaGold.Engines.Disenchant

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
  local gross = expectedGross(outcomes)
  if not gross or gross <= 0 then
    return nil
  end
  local net = OnyxiaGold:ApplyAuctionHouseCut(gross)
  local vendor = tonumber(meta.vendorPrice) or 0
  if vendor < 0 then
    vendor = 0
  end
  local profit = net - vendor
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
    investment = vendor,
    grossRevenue = gross,
    netRevenue = net,
    expectedProfit = profit,
    roi = (vendor > 0) and (profit / vendor) or 0,
    availableQuantity = count,
    marketProfitableCrafts = count,
    totalExpectedProfit = profit * count,
    averageProfitPerCraft = profit,
    outputMarketQuantity = outputQty,
    notes = "Owned item. Vendor versus disenchant. Sale of the gear is unknown. No buy.",
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
    saleExitUnknown = true,
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
