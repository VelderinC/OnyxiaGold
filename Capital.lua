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

-- Reserve against a liquid total. Rounded to the nearest copper.
function Capital:GetReserveOn(amount)
  amount = tonumber(amount) or 0
  if amount < 0 then
    amount = 0
  end
  return math.floor(amount * self:GetReservePercent() + 0.5)
end

function Capital:GetWorkingCapital()
  return self:GetReserveOn(self:GetLiquid())
end

function Capital:GetSpendableNow()
  local liquid = self:GetLiquid()
  local spend = liquid - self:GetWorkingCapital()
  if spend < 0 then
    spend = 0
  end
  return spend
end

-- Liquid that would be on the character after collecting claimable mail.
function Capital:GetPostMailLiquid()
  return self:GetLiquid() + self:GetClaimableMail()
end

-- Reserve recalculated on post-collection liquid, not on current deployable.
function Capital:GetPostMailReserve()
  return self:GetReserveOn(self:GetPostMailLiquid())
end

--[[
  Spendable after mail collection.

  Reserve applies to (liquid + claimable), not to current deployable plus mail.
  Example: liquid 100g, reserve 10%, mail 900g.
  Current deployable is 90g. Post-collection liquid is 1000g,
  post-collection reserve is 100g, post-collection deployable is 900g.
  Adding mail on top of current deployable (990g) is wrong.
  A partial mailbox snapshot understates claimable gold; this figure is then
  a lower bound, not an exact post-collection budget.
]]
function Capital:GetSpendableAfterMail()
  local liquid = self:GetPostMailLiquid()
  local spend = liquid - self:GetPostMailReserve()
  if spend < 0 then
    spend = 0
  end
  return spend
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
  local mailComplete, mailVisible, mailTotal
  if mail and mail.IsSnapshotComplete then
    mailComplete = mail:IsSnapshotComplete()
    mailVisible = mail:GetVisibleCount()
    mailTotal = mail:GetTotalCount()
  end
  local auctionsComplete, auctionsShown, auctionsTotal
  if auctions and auctions.IsSnapshotComplete then
    auctionsComplete = auctions:IsSnapshotComplete()
    auctionsShown = auctions:GetShownCount()
    auctionsTotal = auctions:GetTotalCount()
  end
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
    postMailLiquid = self:GetPostMailLiquid(),
    postMailReserve = self:GetPostMailReserve(),
    deployable = self:GetSpendableNow(),
    deployableAfterMail = self:GetSpendableAfterMail(),
    mailComplete = mailComplete,
    mailVisible = mailVisible,
    mailTotal = mailTotal,
    auctionsComplete = auctionsComplete,
    auctionsShown = auctionsShown,
    auctionsTotal = auctionsTotal,
    estimatedNetWorth = self:GetEstimatedNetWorth(),
    mailAge = mail and mail.GetSnapshotAge and mail:GetSnapshotAge() or nil,
    auctionAge = auctions and auctions.GetSnapshotAge and auctions:GetSnapshotAge() or nil,
    bankAge = inv and inv.GetBankAge and inv:GetBankAge() or nil,
    bagsLive = true,
    goldLive = true,
    reservePercent = self:GetReservePercent(),
  }
end
