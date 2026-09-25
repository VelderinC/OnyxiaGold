--[[
  OnyxiaGold.Prices
  Read aggregated scan data. All money values are integer copper.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Prices = OnyxiaGold.Prices or {}

local Prices = OnyxiaGold.Prices

local function record(itemID)
  return OnyxiaGold.Database:GetLatest(itemID)
end

function Prices:GetRecord(itemID)
  return record(itemID)
end

function Prices:GetLowest(itemID)
  local rec = record(itemID)
  if rec and rec.minUnitBuyout and rec.minUnitBuyout > 0 then
    return rec.minUnitBuyout
  end
  return nil
end

function Prices:GetMedian(itemID)
  local rec = record(itemID)
  if rec and rec.medianUnitBuyout and rec.medianUnitBuyout > 0 then
    return rec.medianUnitBuyout
  end
  return self:GetLowest(itemID)
end

function Prices:GetMean(itemID)
  local rec = record(itemID)
  if rec and rec.meanUnitBuyout and rec.meanUnitBuyout > 0 then
    return rec.meanUnitBuyout
  end
  return self:GetMedian(itemID)
end

function Prices:GetQuantity(itemID)
  local rec = record(itemID)
  if rec then
    return rec.quantity or 0
  end
  return 0
end

function Prices:GetAuctionCount(itemID)
  local rec = record(itemID)
  if rec then
    return rec.auctionCount or 0
  end
  return 0
end

-- Conservative sale estimate: median unit buyout when we have it.
-- Using the current lowest as a sell price would overstate profit.
function Prices:GetConservative(itemID)
  return self:GetMedian(itemID) or self:GetLowest(itemID)
end

function Prices:GetNetSaleValue(itemID, count)
  count = tonumber(count) or 1
  local unit = self:GetConservative(itemID)
  if not unit then
    return nil
  end
  return OnyxiaGold:ApplyAuctionHouseCut(unit * count)
end

function Prices:GetGrossSaleValue(itemID, count)
  count = tonumber(count) or 1
  local unit = self:GetConservative(itemID)
  if not unit then
    return nil
  end
  return unit * count
end

-- v0.1: cheapest unit * quantity.
-- Replace this later with depth-aware walk of the stored order book.
function Prices:GetAcquisitionCost(itemID, quantity)
  quantity = tonumber(quantity) or 1
  if quantity <= 0 then
    return 0
  end
  local unit = self:GetLowest(itemID)
  if not unit then
    return nil
  end
  return unit * quantity
end

function Prices:HasPrice(itemID)
  return self:GetLowest(itemID) ~= nil
end
