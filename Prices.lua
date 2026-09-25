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
    depth = { { p = copper, q = units, n = auctions, s = stack }, ... }

  A level is n whole auctions of stack s. GetAcquisitionQuote buys whole
  auctions. cashRequired is the copper that leaves the purse.
  economicConsumedCost is the cost of the units the recipe uses.
  Leftover units keep leftoverAssetValue. The quote does not price past
  depthCoveredQuantity, and it does not split a stack.
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

function Prices:SumDepthQuantity(depth)
  local sum = 0
  if type(depth) ~= "table" then
    return 0
  end
  for i = 1, table.getn(depth) do
    local lvl = depth[i]
    local q = lvl and (lvl.q or lvl.quantity)
    if q and q > 0 then
      sum = sum + q
    end
  end
  return sum
end

-- Units the persisted book can actually price. Not the full buyout count.
function Prices:GetDepthCoveredQuantity(itemID)
  local rec = record(itemID)
  if not rec then
    return 0
  end
  if rec.depthCoveredQuantity ~= nil then
    return tonumber(rec.depthCoveredQuantity) or 0
  end
  if type(rec.depth) == "table" then
    return self:SumDepthQuantity(rec.depth)
  end
  return 0
end

-- Cheapest persisted levels, stopped at depthCoveredQuantity.
-- Whole auctions only. Stack size s is kept.
local function depthWithinCoverage(depth, covered)
  if OnyxiaGold.Lots and OnyxiaGold.Lots.WholeLevels then
    return OnyxiaGold.Lots.WholeLevels(depth, covered)
  end
  return {}, 0
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

-- Stack size already stored on the buyout book, at the P25 band.
-- Nil when that scan did not keep a stack size.
function Prices:GetPlannedStackSize(itemID)
  local depth = self:GetDepth(itemID)
  if type(depth) ~= "table" then
    return nil
  end
  local qty = 0
  local n = table.getn(depth)
  for i = 1, n do
    local lvl = depth[i]
    local q = lvl and tonumber(lvl.q or lvl.quantity) or 0
    if q > 0 then
      qty = qty + q
    end
  end
  if qty <= 0 then
    return nil
  end
  local target = qty * 0.25
  if target < 1 then
    target = 1
  end
  local cumulative = 0
  local stack
  for i = 1, n do
    local lvl = depth[i]
    local q = lvl and tonumber(lvl.q or lvl.quantity) or 0
    local s = lvl and tonumber(lvl.s) or nil
    if q > 0 then
      if s and s > 0 then
        stack = s
      end
      cumulative = cumulative + q
      if cumulative >= target then
        if s and s > 0 then
          return math.floor(s)
        end
        if stack and stack > 0 then
          return math.floor(stack)
        end
        return nil
      end
    end
  end
  if stack and stack > 0 then
    return math.floor(stack)
  end
  return nil
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
  Quantity-weighted percentile over a depth book.
  Pass the full runtime book and its full quantity. Do not pass a truncated
  book together with the uncapped buyout count.
  target = quantity * percentile. Walk cumulative q; do not expand units.

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

local function emptyQuote(quantity)
  return {
    requestedQuantity = quantity,
    requestedUnits = quantity,
    filledQuantity = 0,
    purchasedUnits = 0,
    consumedUnits = 0,
    excessUnits = 0,
    totalCost = 0,
    cashRequired = 0,
    economicConsumedCost = 0,
    leftoverAssetValue = 0,
    averageUnitCost = nil,
    marginalUnitCost = nil,
    levelsConsumed = 0,
    selectedLots = {},
    complete = false,
    depthCoveredQuantity = 0,
  }
end

function Prices:GetAcquisitionQuote(itemID, quantity, constraints)
  quantity = math.floor(tonumber(quantity) or 0)
  local live = record(itemID)
  if live and live.source == "external" then
    return emptyQuote(quantity)
  end
  local covered = self:GetDepthCoveredQuantity(itemID)
  if quantity <= 0 then
    local quote = emptyQuote(quantity)
    quote.complete = true
    quote.averageUnitCost = 0
    quote.depthCoveredQuantity = covered
    return quote
  end
  local depth = depthWithinCoverage(self:GetDepth(itemID), covered)
  local quote
  if OnyxiaGold.Lots and OnyxiaGold.Lots.Quote then
    quote = OnyxiaGold.Lots.Quote(depth, quantity, constraints)
  else
    quote = emptyQuote(quantity)
  end
  quote.depthCoveredQuantity = covered
  quote.requestedQuantity = quantity
  if OnyxiaGold.Log and OnyxiaGold.Log.Trace then
    OnyxiaGold.Log:Trace("Prices", string.format(
      "quote item=%s qty=%d bought=%s consumed=%s cash=%s economic=%s complete=%s",
      tostring(itemID), quantity, tostring(quote.purchasedUnits),
      tostring(quote.consumedUnits), tostring(quote.cashRequired),
      tostring(quote.economicConsumedCost), tostring(quote.complete)
    ))
  end
  return quote
end

-- Copper that actually leaves the purse. Nil when the lots cannot cover.
function Prices:GetAcquisitionCost(itemID, quantity)
  quantity = tonumber(quantity) or 1
  if quantity <= 0 then
    return 0
  end
  local quote = self:GetAcquisitionQuote(itemID, quantity)
  if not quote or not quote.complete then
    return nil
  end
  return quote.cashRequired or quote.totalCost
end

-- Cost of the units a recipe would consume. Leftover lots stay an asset.
function Prices:GetEconomicAcquisitionCost(itemID, quantity)
  quantity = tonumber(quantity) or 1
  if quantity <= 0 then
    return 0
  end
  local quote = self:GetAcquisitionQuote(itemID, quantity)
  if not quote or not quote.complete then
    return nil
  end
  return quote.economicConsumedCost
end

-- Stop at the first batch whose marginal economic cost is not under the net.
-- Whole lots. Independent quotes from the full book, so leftover is not
-- charged twice and is not discarded.
function Prices:GetMaxProfitableBatches(itemID, unitsPerBatch, netPerBatch)
  unitsPerBatch = math.floor(tonumber(unitsPerBatch) or 0)
  netPerBatch = tonumber(netPerBatch) or 0
  if unitsPerBatch <= 0 or netPerBatch <= 0 then
    return nil
  end

  local covered = self:GetDepthCoveredQuantity(itemID)
  if covered < unitsPerBatch then
    return nil
  end

  local batches = 0
  local previous = 0
  local guard = 0
  while guard < 200 do
    guard = guard + 1
    local qty = (batches + 1) * unitsPerBatch
    if qty > covered then
      break
    end
    local economic = self:GetEconomicAcquisitionCost(itemID, qty)
    if not economic then
      break
    end
    local marginal = economic - previous
    if marginal >= netPerBatch then
      break
    end
    batches = batches + 1
    previous = economic
  end

  if batches <= 0 then
    return nil
  end
  return {
    batches = batches,
    firstCost = self:GetEconomicAcquisitionCost(itemID, unitsPerBatch),
    firstProfit = netPerBatch - (self:GetEconomicAcquisitionCost(itemID, unitsPerBatch) or 0),
    totalCost = previous,
    totalProfit = batches * netPerBatch - previous,
    averageUnitCost = math.floor(previous / (batches * unitsPerBatch)),
  }
end
