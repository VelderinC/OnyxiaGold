--[[
  OnyxiaGold.OwnedAuctions
  Snapshot of the current owner listing page. Asking value is not cash.
  Does not page the owner list (avoids hijacking the AH browse query).
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.OwnedAuctions = OnyxiaGold.OwnedAuctions or {}

local Owned = OnyxiaGold.OwnedAuctions

local TIME_LABELS = {
  [1] = "SHORT",
  [2] = "MEDIUM",
  [3] = "LONG",
  [4] = "VERY_LONG",
}

local function rec()
  return OnyxiaGold.Database:GetCharacter()
end

function Owned:Scan()
  local row = rec()
  if not row then
    return
  end
  if not (AuctionFrame and AuctionFrame:IsShown()) then
    return
  end

  local numBatch, total = GetNumAuctionItems("owner")
  numBatch = tonumber(numBatch) or 0
  total = tonumber(total) or numBatch
  if total > numBatch then
    OnyxiaGold.Log:Debug("Auctions", string.format(
      "Owner list showing %d of %d; not paging",
      numBatch, total
    ))
  end

  local listings = {}
  local asking = 0
  local expectedNet = 0
  local bids = 0
  local listedCount = {}
  local cheapestUnit = {}
  local listingCount = {}
  local bidState = {}

  for i = 1, numBatch do
    local name, _, count, _, _, _, minBid, _, buyoutPrice, bidAmount = GetAuctionItemInfo("owner", i)
    local link = GetAuctionItemLink("owner", i)
    local itemID = OnyxiaGold.ParseItemID(link)
    count = tonumber(count) or 1
    buyoutPrice = tonumber(buyoutPrice) or 0
    bidAmount = tonumber(bidAmount) or 0
    minBid = tonumber(minBid) or 0
    local timeLeft
    if GetAuctionItemTimeLeft then
      timeLeft = GetAuctionItemTimeLeft("owner", i)
    end
    table.insert(listings, {
      itemID = itemID,
      name = name,
      count = count,
      buyout = buyoutPrice,
      bid = bidAmount,
      minBid = minBid,
      timeLeft = timeLeft,
      timeLeftLabel = TIME_LABELS[timeLeft],
    })
    if buyoutPrice > 0 then
      asking = asking + buyoutPrice
      expectedNet = expectedNet + OnyxiaGold:ApplyAuctionHouseCut(buyoutPrice)
    end
    if bidAmount > 0 then
      bids = bids + bidAmount
    end
    if itemID and count > 0 then
      listedCount[itemID] = (listedCount[itemID] or 0) + count
      listingCount[itemID] = (listingCount[itemID] or 0) + 1
      if buyoutPrice > 0 then
        local unit = math.floor(buyoutPrice / count)
        if unit > 0 and (not cheapestUnit[itemID] or unit < cheapestUnit[itemID]) then
          cheapestUnit[itemID] = unit
        end
      end
      if bidAmount > 0 then
        bidState[itemID] = 1
      elseif bidState[itemID] == nil then
        bidState[itemID] = 0
      end
    end
  end

  local complete = numBatch >= total
  row.auctions.listings = listings
  row.auctions.askingValue = asking
  row.auctions.expectedNet = expectedNet
  row.auctions.currentBids = bids
  row.auctions.timestamp = time()
  row.auctions.shown = numBatch
  row.auctions.total = total
  row.auctions.complete = complete
  row.auctions.listedCountByItemID = listedCount
  row.auctions.cheapestUnitByItemID = cheapestUnit
  row.auctions.listingCountByItemID = listingCount
  row.auctions.bidStateByItemID = bidState
  row.stateTimestamps.auctions = time()
  if not complete then
    OnyxiaGold.Log:Debug("Auctions", string.format(
      "Owner snapshot incomplete shown=%d total=%d; listed value is approximate",
      numBatch, total
    ))
  end
end

function Owned:IsSnapshotComplete()
  local row = rec()
  if not row or not row.auctions or not row.auctions.timestamp then
    return nil
  end
  if row.auctions.complete ~= nil then
    return row.auctions.complete and true or false
  end
  if row.auctions.shown ~= nil and row.auctions.total ~= nil then
    return row.auctions.shown >= row.auctions.total
  end
  return nil
end

function Owned:GetShownCount()
  local row = rec()
  if not row or not row.auctions or row.auctions.shown == nil then
    return nil
  end
  return tonumber(row.auctions.shown) or 0
end

function Owned:GetTotalCount()
  local row = rec()
  if not row or not row.auctions or row.auctions.total == nil then
    return nil
  end
  return tonumber(row.auctions.total) or 0
end

function Owned:OnClosed()
  -- Keep last snapshot; age is derived from timestamp.
end

function Owned:GetListedCount(itemID)
  itemID = tonumber(itemID)
  local row = rec()
  if not itemID or not row or not row.auctions then
    return 0
  end
  local indexed = row.auctions.listedCountByItemID
  if type(indexed) == "table" then
    return tonumber(indexed[itemID]) or 0
  end
  if type(row.auctions.listings) ~= "table" then
    return 0
  end
  local n = 0
  local listings = row.auctions.listings
  for i = 1, table.getn(listings) do
    local listing = listings[i]
    if listing and tonumber(listing.itemID) == itemID then
      n = n + (tonumber(listing.count) or 0)
    end
  end
  return n
end

function Owned:GetCheapestUnit(itemID)
  itemID = tonumber(itemID)
  local row = rec()
  local indexed = row and row.auctions and row.auctions.cheapestUnitByItemID
  if not itemID or type(indexed) ~= "table" then
    return nil
  end
  local unit = tonumber(indexed[itemID])
  if unit and unit > 0 then
    return unit
  end
  return nil
end

function Owned:GetAskingValue()
  local row = rec()
  return row and (tonumber(row.auctions.askingValue) or 0) or 0
end

function Owned:GetExpectedNet()
  local row = rec()
  return row and (tonumber(row.auctions.expectedNet) or 0) or 0
end

function Owned:GetCurrentBids()
  local row = rec()
  return row and (tonumber(row.auctions.currentBids) or 0) or 0
end

-- Per item: listed count, cheapest unit, and whether any listing has a bid.
-- An additive sum of those fields can collide. This key cannot.
function Owned.FingerprintMaps(listed, cheapest, bidState)
  local ids = {}
  local function add(map)
    if type(map) ~= "table" then
      return
    end
    for itemID in pairs(map) do
      ids[itemID] = true
    end
  end
  add(listed)
  add(cheapest)
  add(bidState)
  local ordered = {}
  for itemID in pairs(ids) do
    table.insert(ordered, itemID)
  end
  table.sort(ordered)
  local parts = {}
  for i = 1, table.getn(ordered) do
    local itemID = ordered[i]
    local count = listed and listed[itemID] or 0
    local unit = cheapest and cheapest[itemID] or 0
    local bid = bidState and bidState[itemID] or 0
    parts[i] = tostring(itemID) .. ":" .. tostring(count) .. ":" .. tostring(unit) .. ":" .. tostring(bid)
  end
  return table.concat(parts, "|")
end

function Owned:Fingerprint()
  local row = rec()
  local auctions = row and row.auctions
  if not auctions then
    return ""
  end
  if type(auctions.listedCountByItemID) == "table" then
    return Owned.FingerprintMaps(
      auctions.listedCountByItemID,
      auctions.cheapestUnitByItemID,
      auctions.bidStateByItemID
    )
  end
  return ""
end

function Owned:GetSnapshotAge()
  local row = rec()
  if not row or not row.auctions.timestamp then
    return nil
  end
  return OnyxiaGold.AgeSeconds(row.auctions.timestamp)
end
