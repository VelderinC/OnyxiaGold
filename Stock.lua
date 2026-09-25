--[[
  OnyxiaGold.Stock
  How many of an item he already holds. Counts only.

  Bags are live. Bank, mailbox attachments, and his own listings are the
  last snapshots. Partial and stale snapshots stay marked and still count.
  Pending sale-mail gold is not item stock. Asking price is not a count.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Stock = OnyxiaGold.Stock or {}

local Stock = OnyxiaGold.Stock

function Stock:Describe(itemID)
  itemID = tonumber(itemID)
  local bags = 0
  local bank = 0
  local mailItems = 0
  local listings = 0
  local inv = OnyxiaGold.Inventory
  if itemID and inv then
    if inv.GetBagCount then
      bags = inv:GetBagCount(itemID) or 0
    end
    if inv.GetBankCount then
      bank = inv:GetBankCount(itemID) or 0
    end
  end
  local mail = OnyxiaGold.Mail
  if itemID and mail and mail.GetItemCount then
    mailItems = mail:GetItemCount(itemID) or 0
  end
  local owned = OnyxiaGold.OwnedAuctions
  if itemID and owned and owned.GetListedCount then
    listings = owned:GetListedCount(itemID) or 0
  end

  local partial = false
  local stale = false
  if mail and mail.IsSnapshotComplete and mail:IsSnapshotComplete() == false then
    partial = true
  end
  if owned and owned.IsSnapshotComplete and owned:IsSnapshotComplete() == false then
    partial = true
  end
  if mail and mail.IsStale and mail:IsStale() then
    stale = true
  end
  if inv and inv.GetBankAge then
    local age = inv:GetBankAge()
    local limit = OnyxiaGold.Config and OnyxiaGold.Config.BankStaleSeconds or 86400
    if age == nil or age > limit then
      stale = true
    end
  end
  if owned and owned.GetSnapshotAge then
    local age = owned:GetSnapshotAge()
    local limit = OnyxiaGold.Config and OnyxiaGold.Config.AuctionStaleSeconds or 600
    if age == nil or age > limit then
      stale = true
    end
  end

  return {
    bags = bags,
    bank = bank,
    mail = mailItems,
    listings = listings,
    total = bags + bank + mailItems + listings,
    partial = partial and true or false,
    stale = stale and true or false,
  }
end
