--[[
  OnyxiaGold.CandidateCache
  Market-level opportunities and direct flips.

  Rebuilt when the market revision or the recipe revision changes.
  A bag, gold, mail, or bank change does not walk market.latest again.
  The personal planner only allocates the candidates stored here.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.CandidateCache = OnyxiaGold.CandidateCache or {}

local Cache = OnyxiaGold.CandidateCache

Cache.flips = {}
Cache.marketRevision = -1
Cache.recipeRevision = -1
Cache.candidateRevision = 0

local function nitems(t)
  if type(t) ~= "table" then
    return 0
  end
  return table.getn(t)
end

local function tick()
  local schedule = OnyxiaGold.RefreshSchedule
  if schedule and schedule.Tick then
    schedule.Tick()
  end
end

local function perfAdd(name, n)
  local perf = OnyxiaGold.Performance
  if perf and perf.Add then
    perf:Add(name, n)
  end
end

function Cache:IsCurrent()
  local rev = OnyxiaGold.Revisions
  if not rev then
    return self.marketRevision ~= -1
  end
  return self.marketRevision == rev:Get("market") and self.recipeRevision == rev:Get("recipe")
end

function Cache:Flips()
  if not self:IsCurrent() then
    return {}
  end
  return self.flips or {}
end

-- One walk of the saved market. Session reservations are applied later,
-- and only to these item ids.
function Cache:DiscoverFlips()
  local perf = OnyxiaGold.Performance
  if perf and perf.Begin then
    perf:Begin("flips")
  end
  local flips = {}
  local LotsApi = OnyxiaGold.Lots
  local db = OnyxiaGold.Database
  local prices = OnyxiaGold.Prices
  if not LotsApi or not LotsApi.FlipMargin or not db or not db.GetMarket then
    self.flips = flips
    if perf and perf.End then
      perf:End("flips")
    end
    return flips
  end
  local market = db.currentMarket
  if not market and db.GetMarket then
    market = db:GetMarket()
  end
  local latest = market and market.latest
  if type(latest) ~= "table" then
    self.flips = flips
    if perf and perf.End then
      perf:End("flips")
    end
    return flips
  end
  local rows = {}
  for key, rec in pairs(latest) do
    local itemID = tonumber(key) or tonumber(rec and rec.itemID)
    if itemID and type(rec) == "table" and rec.source ~= "external" then
      rows[table.getn(rows) + 1] = { itemID = itemID, rec = rec }
    end
  end
  table.sort(rows, function(a, b)
    return a.itemID < b.itemID
  end)
  local cutBPS = 500
  if OnyxiaGold.GetAuctionHouseCutBPS then
    cutBPS = OnyxiaGold:GetAuctionHouseCutBPS()
  end
  local staleAfter = OnyxiaGold.Config and OnyxiaGold.Config.QuickScanStaleSeconds
  for i = 1, nitems(rows) do
    if i % 8 == 0 then
      tick()
    end
    local itemID = rows[i].itemID
    local rec = rows[i].rec
    perfAdd("flipItems", 1)
    local info = OnyxiaGold.ItemInfo
    local meta = info and info.Get and info:Get(itemID)
    local gear = meta and info and (info:IsWeapon(meta) or info:IsArmor(meta))
    local age = prices and prices.GetAge and prices:GetAge(itemID)
    local stale = true
    if LotsApi.IsStale then
      stale = LotsApi.IsStale(age, staleAfter)
    end
    local name = rec.name
    if type(name) ~= "string" or name == "" then
      if OnyxiaGold.Data and OnyxiaGold.Data.GetItemName then
        name = OnyxiaGold.Data.GetItemName(itemID)
      end
    end
    if not gear and not stale and meta and meta.vendorPrice ~= nil and type(name) == "string" and name ~= "" then
      local depth = prices and prices.GetDepth and prices:GetDepth(itemID)
      local covered = prices and prices.GetDepthCoveredQuantity and prices:GetDepthCoveredQuantity(itemID)
      local own = OnyxiaGold.AuctionStop and OnyxiaGold.AuctionStop.OwnCheapestUnit
        and OnyxiaGold.AuctionStop.OwnCheapestUnit(itemID)
      local found = LotsApi.FlipMargin({
        levels = depth,
        covered = covered,
        vendorUnit = meta.vendorPrice,
        hours = 24,
        cutBPS = cutBPS,
        ownMinimum = own,
        name = name,
        itemID = itemID,
      })
      if found and (tonumber(found.profit) or 0) > 0 then
        local confidence = 0.5
        if LotsApi.FlipConfidence then
          confidence = LotsApi.FlipConfidence({
            auctions = rec.buyoutAuctionCount or rec.auctionCount,
            quantity = rec.buyoutQuantity or rec.totalQuantity,
            sale = found.saleUnit,
            unit = found.unit,
            age = age,
          })
        end
        found.confidence = confidence
        found.itemID = itemID
        found.name = name
        found.vendorPrice = meta.vendorPrice
        flips[table.getn(flips) + 1] = found
      end
    end
  end
  table.sort(flips, function(a, b)
    local sa = (tonumber(a.profit) or 0) * (tonumber(a.confidence) or 0)
    local sb = (tonumber(b.profit) or 0) * (tonumber(b.confidence) or 0)
    if sa ~= sb then
      return sa > sb
    end
    return (a.itemID or 0) < (b.itemID or 0)
  end)
  self.flips = flips
  if perf and perf.End then
    perf:End("flips")
  end
  return flips
end

function Cache:Build()
  local rev = OnyxiaGold.Revisions
  local marketRev = rev and rev:Get("market") or 0
  local recipeRev = rev and rev:Get("recipe") or 0
  local engine = OnyxiaGold.OpportunityEngine
  if engine and engine.Refresh then
    engine:Refresh()
  end
  tick()
  self:DiscoverFlips()
  if rev and (rev:Get("market") ~= marketRev or rev:Get("recipe") ~= recipeRev) then
    return false
  end
  self.marketRevision = marketRev
  self.recipeRevision = recipeRev
  if rev and rev.Bump then
    self.candidateRevision = rev:Bump("candidate")
  else
    self.candidateRevision = (self.candidateRevision or 0) + 1
  end
  local oppCount = 0
  if engine and engine.GetResults then
    oppCount = nitems(engine:GetResults() or {})
  end
  perfAdd("candidates", oppCount + nitems(self.flips))
  return true
end
