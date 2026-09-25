--[[
  OnyxiaGold.Capital
  Liquid / claimable / pending / listed / deployable capital.
  GetSpendableNow uses GetMoney() minus the working-capital reserve.
  Pending AH invoices and listed auctions are never spendable.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Capital = OnyxiaGold.Capital or {}

local Capital = OnyxiaGold.Capital

local function rec()
  return OnyxiaGold.Database:GetCharacter()
end

function Capital:GetReservePercent()
  local pct = OnyxiaGold.Config.CapitalReservePercent or 0.10
  if OnyxiaGoldDB and OnyxiaGoldDB.settings and OnyxiaGoldDB.settings.capitalReservePercent ~= nil then
    pct = OnyxiaGoldDB.settings.capitalReservePercent
  end
  pct = tonumber(pct) or 0.10
  if pct < 0 then
    pct = 0
  elseif pct > 0.9 then
    pct = 0.9
  end
  return pct
end

function Capital:RefreshLiquid()
  local row = rec()
  local copper = tonumber(GetMoney()) or 0
  if row then
    row.capital.liquid = copper
    row.capital.timestamp = time()
    row.stateTimestamps.gold = time()
  end
  return copper
end

function Capital:GetLiquid()
  return tonumber(GetMoney()) or 0
end

function Capital:GetClaimableMail()
  if OnyxiaGold.Mail and OnyxiaGold.Mail.GetClaimableGold then
    return OnyxiaGold.Mail:GetClaimableGold()
  end
  return 0
end

function Capital:GetPendingAuctionGold()
  if OnyxiaGold.Mail and OnyxiaGold.Mail.GetPendingGold then
    return OnyxiaGold.Mail:GetPendingGold()
  end
  return 0
end

function Capital:GetListedMarketValue()
  if OnyxiaGold.OwnedAuctions and OnyxiaGold.OwnedAuctions.GetAskingValue then
    return OnyxiaGold.OwnedAuctions:GetAskingValue()
  end
  return 0
end

function Capital:GetListedExpectedNet()
  if OnyxiaGold.OwnedAuctions and OnyxiaGold.OwnedAuctions.GetExpectedNet then
    return OnyxiaGold.OwnedAuctions:GetExpectedNet()
  end
  return 0
end

function Capital:GetWorkingCapital()
  local liquid = self:GetLiquid()
  return math.floor(liquid * self:GetReservePercent() + 0.5)
end

function Capital:GetSpendableNow()
  local liquid = self:GetLiquid()
  local reserve = self:GetWorkingCapital()
  local spend = liquid - reserve
  if spend < 0 then
    spend = 0
  end
  return spend
end

function Capital:GetSpendableAfterMail()
  return self:GetSpendableNow() + self:GetClaimableMail()
end

function Capital:GetBagMarketValue()
  if OnyxiaGold.Inventory and OnyxiaGold.Inventory.GetTrackedBagValue then
    return OnyxiaGold.Inventory:GetTrackedBagValue()
  end
  return 0
end

function Capital:GetBankMarketValue()
  if OnyxiaGold.Inventory and OnyxiaGold.Inventory.GetTrackedBankValue then
    return OnyxiaGold.Inventory:GetTrackedBankValue()
  end
  return 0
end

-- High-level figure only. Never treat as spendable.
function Capital:GetEstimatedNetWorth()
  return self:GetLiquid()
    + self:GetClaimableMail()
    + self:GetPendingAuctionGold()
    + self:GetListedExpectedNet()
    + self:GetBagMarketValue()
    + self:GetBankMarketValue()
end

function Capital:GetPortfolioSummary()
  local mail = OnyxiaGold.Mail
  local auctions = OnyxiaGold.OwnedAuctions
  local inv = OnyxiaGold.Inventory
  return {
    liquid = self:GetLiquid(),
    claimableMail = self:GetClaimableMail(),
    pendingAuctionGold = self:GetPendingAuctionGold(),
    listedAsking = self:GetListedMarketValue(),
    listedExpectedNet = self:GetListedExpectedNet(),
    listedBids = auctions and auctions.GetCurrentBids and auctions:GetCurrentBids() or 0,
    bags = self:GetBagMarketValue(),
    bank = self:GetBankMarketValue(),
    reserve = self:GetWorkingCapital(),
    deployable = self:GetSpendableNow(),
    deployableAfterMail = self:GetSpendableAfterMail(),
    estimatedNetWorth = self:GetEstimatedNetWorth(),
    mailAge = mail and mail.GetSnapshotAge and mail:GetSnapshotAge() or nil,
    auctionAge = auctions and auctions.GetSnapshotAge and auctions:GetSnapshotAge() or nil,
    bankAge = inv and inv.GetBankAge and inv:GetBankAge() or nil,
    bagsLive = true,
    goldLive = true,
    reservePercent = self:GetReservePercent(),
  }
end
