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

function Owned:GetSnapshotAge()
  local row = rec()
  if not row or not row.auctions.timestamp then
    return nil
  end
  return OnyxiaGold.AgeSeconds(row.auctions.timestamp)
end
