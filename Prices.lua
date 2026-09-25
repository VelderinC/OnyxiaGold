--[[
  OnyxiaGold.Prices
  Query API over the current realm/faction snapshot.

  Quantity:
    GetBuyoutQuantity  = units with a buyout (instant-buy stock)
    GetTotalQuantity   = all listed units including bid-only
    GetQuantity        = GetBuyoutQuantity (acquisition-safe)

  Sale:
    GetMarketReferencePrice = quantity-weighted median
    GetLiquidationPrice     = P10, else P25, else min
    GetOpportunitySaleUnit  = P25 if present, else P10, else min
      Used by deterministic engines. Conservative vs raw median.

  Depth lives on latest records only as:
    depth = { { p = copper, q = units, n = auctions }, ... } cheapest first
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

function Prices:GetDepth(itemID)
  local rec = record(itemID)
  if rec and type(rec.depth) == "table" then
    return rec.depth
  end
  return nil
end

function Prices:GetTotalQuantity(itemID)
  local rec = record(itemID)
  if not rec then
    return 0
  end
  return rec.totalQuantity or rec.quantity or 0
end

-- Instant-buy stock. Opportunity engines must use this, not total listings.
function Prices:GetBuyoutQuantity(itemID)
  local rec = record(itemID)
  if not rec then
    return 0
  end
  if rec.buyoutQuantity ~= nil then
    return rec.buyoutQuantity
  end
  return rec.quantity or 0
end

function Prices:GetQuantity(itemID)
  return self:GetBuyoutQuantity(itemID)
end

function Prices:GetAuctionCount(itemID)
  local rec = record(itemID)
  if rec then
    return rec.auctionCount or 0
  end
  return 0
end

function Prices:GetBuyoutAuctionCount(itemID)
  local rec = record(itemID)
  if rec then
    return rec.buyoutAuctionCount or rec.auctionCount or 0
  end
  return 0
end

function Prices:GetMarketMinimum(itemID)
  local rec = record(itemID)
  if rec and rec.minUnitBuyout and rec.minUnitBuyout > 0 then
    return rec.minUnitBuyout
  end
  return nil
end

function Prices:GetLowest(itemID)
  return self:GetMarketMinimum(itemID)
end

local function positive(n)
  n = tonumber(n)
  if n and n > 0 then
    return n
  end
  return nil
end

function Prices:GetP10(itemID)
  local rec = record(itemID)
  return rec and positive(rec.p10UnitBuyout) or self:GetMarketMinimum(itemID)
end

function Prices:GetP25(itemID)
  local rec = record(itemID)
  return rec and positive(rec.p25UnitBuyout) or self:GetP10(itemID)
end

function Prices:GetMedian(itemID)
  local rec = record(itemID)
  if rec and positive(rec.medianUnitBuyout) then
    return rec.medianUnitBuyout
  end
  return self:GetP25(itemID)
end

function Prices:GetP75(itemID)
  local rec = record(itemID)
  return rec and positive(rec.p75UnitBuyout) or self:GetMedian(itemID)
end

function Prices:GetMean(itemID)
  local rec = record(itemID)
  if rec and positive(rec.meanUnitBuyout) then
    return rec.meanUnitBuyout
  end
  return self:GetMedian(itemID)
end

function Prices:GetMarketReferencePrice(itemID)
  return self:GetMedian(itemID)
end

function Prices:GetLiquidationPrice(itemID)
  return self:GetP10(itemID) or self:GetP25(itemID) or self:GetMarketMinimum(itemID)
end

-- Deterministic opportunity sell unit: P25, thin-market fallbacks.
function Prices:GetOpportunitySaleUnit(itemID)
  local rec = record(itemID)
  if rec and positive(rec.p25UnitBuyout) then
    return rec.p25UnitBuyout
  end
  return self:GetLiquidationPrice(itemID)
end

function Prices:GetConservative(itemID)
  return self:GetOpportunitySaleUnit(itemID)
end

function Prices:GetGrossSaleValue(itemID, count)
  count = tonumber(count) or 1
  local unit = self:GetOpportunitySaleUnit(itemID)
  if not unit then
    return nil
  end
  return unit * count
end

function Prices:GetNetSaleValue(itemID, count)
  local gross = self:GetGrossSaleValue(itemID, count)
  if not gross then
    return nil
  end
  return OnyxiaGold:ApplyAuctionHouseCut(gross)
end

function Prices:GetAge(itemID)
  local rec = record(itemID)
  if not rec or not rec.timestamp then
    return nil
  end
  local now = time()
  local age = now - rec.timestamp
  if age < 0 then
    age = 0
  end
  return age
end

function Prices:IsStale(itemID, thresholdSeconds)
  local age = self:GetAge(itemID)
  if age == nil then
    return true
  end
  thresholdSeconds = tonumber(thresholdSeconds) or OnyxiaGold.Config.QuickScanStaleSeconds or 600
  return age > thresholdSeconds
end

function Prices:HasPrice(itemID)
  return self:GetMarketMinimum(itemID) ~= nil
end

--[[
  Quantity-weighted percentile over compact depth levels.
  target = buyoutQuantity * percentile. Walk cumulative q; do not expand units.

  Example: levels (p=10000,q=20), (p=14000,q=100), (p=18000,q=500)
  buyoutQty=620
  P10 target=62  -> 20 at 1g, then into 1.4g band -> 14000
  median target=310 -> 18000
]]
function Prices.PercentileFromDepth(depth, buyoutQuantity, percentile)
  buyoutQuantity = tonumber(buyoutQuantity) or 0
  percentile = tonumber(percentile) or 0
  if type(depth) ~= "table" or buyoutQuantity <= 0 then
    return nil
  end
  local target = buyoutQuantity * percentile
  if target <= 0 then
    target = 1
  end
  local cumulative = 0
  local lastPrice
  for i = 1, table.getn(depth) do
    local lvl = depth[i]
    local p = lvl and (lvl.p or lvl.unitPrice)
    local q = lvl and (lvl.q or lvl.quantity)
    if p and p > 0 and q and q > 0 then
      lastPrice = p
      cumulative = cumulative + q
      if cumulative >= target then
        return p
      end
    end
  end
  return lastPrice
end

function Prices:GetAcquisitionQuote(itemID, quantity)
  quantity = math.floor(tonumber(quantity) or 0)
  local quote = {
    requestedQuantity = quantity,
    filledQuantity = 0,
    totalCost = 0,
    averageUnitCost = nil,
    marginalUnitCost = nil,
    levelsConsumed = 0,
    complete = false,
  }
  if quantity <= 0 then
    quote.complete = true
    quote.averageUnitCost = 0
    quote.totalCost = 0
    return quote
  end

  local depth = self:GetDepth(itemID)
  if type(depth) ~= "table" or table.getn(depth) == 0 then
    local min = self:GetMarketMinimum(itemID)
    local stock = self:GetBuyoutQuantity(itemID)
    if min and min > 0 and stock > 0 then
      depth = { { p = min, q = stock, n = 1 } }
    else
      return quote
    end
  end

  local need = quantity
  for i = 1, table.getn(depth) do
    if need <= 0 then
      break
    end
    local lvl = depth[i]
    local p = lvl and (lvl.p or lvl.unitPrice)
    local q = lvl and (lvl.q or lvl.quantity)
    if p and p > 0 and q and q > 0 then
      local take = q
      if take > need then
        take = need
      end
      quote.totalCost = quote.totalCost + take * p
      quote.filledQuantity = quote.filledQuantity + take
      quote.marginalUnitCost = p
      quote.levelsConsumed = quote.levelsConsumed + 1
      need = need - take
    end
  end

  if quote.filledQuantity > 0 then
    quote.averageUnitCost = math.floor(quote.totalCost / quote.filledQuantity)
  end
  quote.complete = (quote.filledQuantity >= quantity)
  if OnyxiaGold.Log and OnyxiaGold.Log.Trace then
    OnyxiaGold.Log:Trace("Prices", string.format(
      "quote item=%s qty=%d filled=%d cost=%s avg=%s marg=%s levels=%d complete=%s",
      tostring(itemID), quantity, quote.filledQuantity,
      tostring(quote.totalCost), tostring(quote.averageUnitCost),
      tostring(quote.marginalUnitCost), quote.levelsConsumed, tostring(quote.complete)
    ))
  end
  return quote
end

function Prices:GetAcquisitionCost(itemID, quantity)
  quantity = tonumber(quantity) or 1
  if quantity <= 0 then
    return 0
  end
  local quote = self:GetAcquisitionQuote(itemID, quantity)
  if not quote or not quote.complete then
    return nil
  end
  return quote.totalCost
end

-- Walk the buyout book in batch-sized chunks. O(depth levels), not O(units).
function Prices:GetMaxProfitableBatches(itemID, unitsPerBatch, netPerBatch)
  unitsPerBatch = math.floor(tonumber(unitsPerBatch) or 0)
  netPerBatch = tonumber(netPerBatch) or 0
  if unitsPerBatch <= 0 or netPerBatch <= 0 then
    return nil
  end

  local depth = self:GetDepth(itemID)
  if type(depth) ~= "table" or table.getn(depth) == 0 then
    local min = self:GetMarketMinimum(itemID)
    local stock = self:GetBuyoutQuantity(itemID)
    if not min or min <= 0 or stock < unitsPerBatch then
      return nil
    end
    if min * unitsPerBatch >= netPerBatch then
      return nil
    end
    local n = math.floor(stock / unitsPerBatch)
    local first = min * unitsPerBatch
    return {
      batches = n,
      firstCost = first,
      firstProfit = netPerBatch - first,
      totalCost = first * n,
      totalProfit = (netPerBatch - first) * n,
      averageUnitCost = min,
    }
  end

  local leftoverUnits = 0
  local leftoverCost = 0
  local batches = 0
  local totalCost = 0
  local firstCost

  local function takeBatch(cost)
    if cost >= netPerBatch then
      return false
    end
    if not firstCost then
      firstCost = cost
    end
    batches = batches + 1
    totalCost = totalCost + cost
    return true
  end

  for i = 1, table.getn(depth) do
    local lvl = depth[i]
    local p = lvl and (lvl.p or lvl.unitPrice)
    local q = lvl and (lvl.q or lvl.quantity)
    if p and p > 0 and q and q > 0 then
      if leftoverUnits > 0 then
        local need = unitsPerBatch - leftoverUnits
        if q >= need then
          local cost = leftoverCost + need * p
          q = q - need
          leftoverUnits = 0
          leftoverCost = 0
          if not takeBatch(cost) then
            break
          end
        else
          leftoverUnits = leftoverUnits + q
          leftoverCost = leftoverCost + q * p
          q = 0
        end
      end

      if leftoverUnits == 0 and q > 0 then
        local costPerBatch = p * unitsPerBatch
        if costPerBatch >= netPerBatch then
          break
        end
        local n = math.floor(q / unitsPerBatch)
        if n > 0 then
          if not firstCost then
            firstCost = costPerBatch
          end
          batches = batches + n
          totalCost = totalCost + n * costPerBatch
          q = q - n * unitsPerBatch
        end
        leftoverUnits = q
        leftoverCost = q * p
      end
    end
  end

  if batches <= 0 or not firstCost then
    return nil
  end
  return {
    batches = batches,
    firstCost = firstCost,
    firstProfit = netPerBatch - firstCost,
    totalCost = totalCost,
    totalProfit = batches * netPerBatch - totalCost,
    averageUnitCost = math.floor(totalCost / (batches * unitsPerBatch)),
  }
end
