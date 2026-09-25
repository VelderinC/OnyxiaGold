--[[
  OnyxiaGold.Mail
  Mailbox snapshots. Claimable attached gold vs pending seller invoices.
  Do not loot mail. Do not treat stale snapshots as live cash.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Mail = OnyxiaGold.Mail or {}

local Mail = OnyxiaGold.Mail
Mail.open = false

local function rec()
  return OnyxiaGold.Database:GetCharacter()
end

local function mailRow()
  local row = rec()
  return row and row.mail or nil
end

function Mail:OnMailboxOpened()
  self.open = true
  local row = rec()
  if row then
    row.mail.mailboxLastOpened = time()
  end
  -- Inbox is populated by the client. Do not spam CheckInbox().
  self:ScanInbox()
end

function Mail:OnMailboxClosed()
  self.open = false
  local m = mailRow()
  if m then
    m.snapshotTimestamp = m.snapshotTimestamp or time()
  end
  OnyxiaGold.Log:Debug("Mail", "Mailbox closed; snapshot persisted")
end

-- 3.3.5 MailFrame: bid + deposit - consignment for seller invoices.
local function sellerInvoiceAmount(bid, deposit, consignment)
  bid = tonumber(bid) or 0
  deposit = tonumber(deposit) or 0
  consignment = tonumber(consignment) or 0
  local amount = bid + deposit - consignment
  if amount < 0 then
    amount = 0
  end
  return amount
end

function Mail:ScanInbox()
  local row = rec()
  if not row then
    return
  end

  local numItems, totalItems = GetInboxNumItems()
  numItems = tonumber(numItems) or 0
  totalItems = tonumber(totalItems) or numItems
  if totalItems > numItems then
    OnyxiaGold.Log:Debug("Mail", string.format(
      "Inbox showing %d of %d; not forcing extra CheckInbox()",
      numItems, totalItems
    ))
  end

  local claimable = 0
  local pending = 0
  local pendingEta
  local items = {}

  for i = 1, numItems do
    local _, _, _, _, money, CODAmount, _, itemCount = GetInboxHeaderInfo(i)
    money = tonumber(money) or 0
    CODAmount = tonumber(CODAmount) or 0
    itemCount = tonumber(itemCount) or 0

    -- COD is a liability, never wealth. Its attachments are not stock.
    if CODAmount > 0 then
      -- skip
    else
      if itemCount > 0 and type(GetInboxItemLink) == "function" and type(GetInboxItem) == "function" then
        for attach = 1, itemCount do
          local link = GetInboxItemLink(i, attach)
          local _, _, count = GetInboxItem(i, attach)
          local itemID = OnyxiaGold.ParseItemID(link)
          if itemID then
            items[itemID] = (items[itemID] or 0) + (tonumber(count) or 1)
          end
        end
      end
      if money > 0 then
        claimable = claimable + money
      else
        local invoiceType, _, _, bid, buyout, deposit, consignment, moneyDelay, etaHour, etaMin = GetInboxInvoiceInfo(i)
        if invoiceType == "seller_temp_invoice" then
          pending = pending + sellerInvoiceAmount(bid, deposit, consignment)
          if etaHour ~= nil or etaMin ~= nil then
            pendingEta = {
              hour = tonumber(etaHour) or 0,
              min = tonumber(etaMin) or 0,
            }
          end
          if moneyDelay then
            -- captured for later UI; 3.3.5 MailFrame often has no extra returns
          end
        elseif invoiceType and invoiceType ~= "buyer" and moneyDelay and tonumber(moneyDelay) and tonumber(moneyDelay) > 0 then
          pending = pending + sellerInvoiceAmount(bid, deposit, consignment)
        end
      end
    end
  end

  local complete = numItems >= totalItems
  row.mail.claimableGold = claimable
  row.mail.pendingGold = pending
  row.mail.pendingEta = pendingEta
  row.mail.snapshotTimestamp = time()
  row.mail.snapshotComplete = complete
  row.mail.items = items
  row.mail.visibleCount = numItems
  row.mail.totalCount = totalItems
  -- Kept so older readers still see the same counts.
  row.mail.inboxCount = numItems
  row.mail.inboxTotal = totalItems
  row.stateTimestamps.mail = time()

  OnyxiaGold.Log:Debug("Mail", string.format(
    "Inbox claimable=%d pending=%d visible=%d total=%d complete=%s",
    claimable, pending, numItems, totalItems, tostring(complete)
  ))

  -- Read sale proceeds off success mail. Do not take or delete anything.
  if OnyxiaGold.TradeLog and OnyxiaGold.TradeLog.NoteInbox then
    OnyxiaGold.TradeLog:NoteInbox()
  end
end

function Mail:IsSnapshotComplete()
  local m = mailRow()
  if not m or not m.snapshotTimestamp then
    return nil
  end
  if m.snapshotComplete ~= nil then
    return m.snapshotComplete and true or false
  end
  local visible = m.visibleCount or m.inboxCount
  local total = m.totalCount or m.inboxTotal
  if visible and total then
    return visible >= total
  end
  return nil
end

function Mail:GetVisibleCount()
  local m = mailRow()
  if not m then
    return nil
  end
  if m.visibleCount ~= nil then
    return tonumber(m.visibleCount) or 0
  end
  if m.inboxCount ~= nil then
    return tonumber(m.inboxCount) or 0
  end
  return nil
end

function Mail:GetTotalCount()
  local m = mailRow()
  if not m then
    return nil
  end
  if m.totalCount ~= nil then
    return tonumber(m.totalCount) or 0
  end
  if m.inboxTotal ~= nil then
    return tonumber(m.inboxTotal) or 0
  end
  return nil
end

function Mail:GetItemCount(itemID)
  itemID = tonumber(itemID)
  local m = mailRow()
  if not itemID or not m or type(m.items) ~= "table" then
    return 0
  end
  return tonumber(m.items[itemID]) or 0
end

function Mail:GetClaimableGold()
  local m = mailRow()
  return m and (tonumber(m.claimableGold) or 0) or 0
end

function Mail:GetPendingGold()
  local m = mailRow()
  return m and (tonumber(m.pendingGold) or 0) or 0
end

function Mail:GetSnapshotAge()
  local m = mailRow()
  if not m or not m.snapshotTimestamp then
    return nil
  end
  return OnyxiaGold.AgeSeconds(m.snapshotTimestamp)
end

function Mail:IsStale()
  local age = self:GetSnapshotAge()
  if age == nil then
    return true
  end
  return age > (OnyxiaGold.Config.MailStaleSeconds or 600)
end

function Mail:HasBeenScanned()
  local m = mailRow()
  return m and m.snapshotTimestamp ~= nil
end
