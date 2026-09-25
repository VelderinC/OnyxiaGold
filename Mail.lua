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

local function subjectMatches(subject, fmt)
  if type(subject) ~= "string" or type(fmt) ~= "string" then
    return false
  end
  local prefix = string.match(fmt, "^(.*)%%s")
  if not prefix then
    return false
  end
  if prefix == "" then
    return true
  end
  return string.sub(subject, 1, string.len(prefix)) == prefix
end

-- Invoice metadata first. Subject text is used only against the client's own
-- localized format globals, and only when those globals exist.
function Mail:Classify(info)
  info = info or {}
  local cod = tonumber(info.cod) or 0
  local money = tonumber(info.money) or 0
  local items = tonumber(info.itemCount) or 0
  local invoice = info.invoiceType
  if cod > 0 then
    return "COD_MAIL", "BLOCKED"
  end
  if invoice == "seller" and money > 0 then
    return "AH_SALE_GOLD", "SAFE_AUTO_PROCESS"
  end
  if invoice == "seller_temp_invoice" then
    return "AH_PENDING_SALE", "MANUAL_ONLY"
  end
  if invoice == "buyer" and items > 0 then
    if subjectMatches(info.subject, AUCTION_WON_MAIL_SUBJECT) then
      return "AH_WON_ITEM", "SAFE_AUTO_PROCESS"
    end
    return "AH_PURCHASE_ITEM", "SAFE_AUTO_PROCESS"
  end
  if items > 0 and subjectMatches(info.subject, AUCTION_EXPIRED_MAIL_SUBJECT) then
    return "AH_EXPIRED_ITEM", "SAFE_AUTO_PROCESS"
  end
  if items > 0 and subjectMatches(info.subject, AUCTION_REMOVED_MAIL_SUBJECT) then
    return "AH_CANCELLED_ITEM", "SAFE_AUTO_PROCESS"
  end
  if info.canReply then
    return "PERSONAL_MAIL", "MANUAL_ONLY"
  end
  if invoice or items > 0 or money > 0 then
    return "SYSTEM_OTHER", "MANUAL_ONLY"
  end
  return "UNKNOWN", "MANUAL_ONLY"
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

  local messages = {}
  for i = 1, numItems do
    local _, _, sender, subject, money, CODAmount, _, itemCount, _, _, _, canReply = GetInboxHeaderInfo(i)
    money = tonumber(money) or 0
    CODAmount = tonumber(CODAmount) or 0
    itemCount = tonumber(itemCount) or 0
    local invoiceType, _, _, bid, buyout, deposit, consignment, moneyDelay, etaHour, etaMin
    if type(GetInboxInvoiceInfo) == "function" then
      invoiceType, _, _, bid, buyout, deposit, consignment, moneyDelay, etaHour, etaMin = GetInboxInvoiceInfo(i)
    end
    local class, safety = self:Classify({
      cod = CODAmount,
      money = money,
      itemCount = itemCount,
      invoiceType = invoiceType,
      subject = subject,
      canReply = canReply and true or false,
    })
    local attached = {}
    table.insert(messages, {
      index = i,
      sender = sender,
      subject = subject,
      money = money,
      cod = CODAmount,
      itemCount = itemCount,
      invoiceType = invoiceType,
      class = class,
      safety = safety,
      items = attached,
      bid = tonumber(bid),
      buyout = tonumber(buyout),
      deposit = tonumber(deposit),
      consignment = tonumber(consignment),
      timestamp = time(),
    })

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
            local n = tonumber(count) or 1
            items[itemID] = (items[itemID] or 0) + n
            table.insert(attached, { itemID = itemID, count = n })
          end
        end
      end
      if money > 0 then
        claimable = claimable + money
      else
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
  row.mail.messages = messages
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

-- Sale payments only. Personal mail and cash-on-delivery are not gold to take.
function Mail:GetSaleGold()
  local m = mailRow()
  local list = m and m.messages
  if type(list) ~= "table" then
    return 0
  end
  local total = 0
  for i = 1, table.getn(list) do
    local message = list[i]
    if message and message.class == "AH_SALE_GOLD" and (tonumber(message.cod) or 0) == 0 then
      total = total + (tonumber(message.money) or 0)
    end
  end
  return total
end

local function purchaseClass(message)
  if not message then
    return false
  end
  if (tonumber(message.cod) or 0) > 0 then
    return false
  end
  if message.safety ~= "SAFE_AUTO_PROCESS" then
    return false
  end
  return message.class == "AH_PURCHASE_ITEM" or message.class == "AH_WON_ITEM"
end

-- Purchased and won auction items. Personal mail and cash-on-delivery stay out.
function Mail:GetPurchaseCount(itemID)
  itemID = tonumber(itemID)
  local m = mailRow()
  local list = m and m.messages
  if not itemID or type(list) ~= "table" then
    return 0
  end
  local total = 0
  for i = 1, table.getn(list) do
    local message = list[i]
    if purchaseClass(message) then
      local attached = message.items or {}
      for j = 1, table.getn(attached) do
        local row = attached[j]
        if row and tonumber(row.itemID) == itemID then
          total = total + (tonumber(row.count) or 0)
        end
      end
    end
  end
  return total
end

function Mail:PurchaseItems()
  local map = {}
  local m = mailRow()
  local list = m and m.messages
  if type(list) ~= "table" then
    return map
  end
  for i = 1, table.getn(list) do
    local message = list[i]
    if purchaseClass(message) then
      local attached = message.items or {}
      for j = 1, table.getn(attached) do
        local row = attached[j]
        local id = row and tonumber(row.itemID)
        local n = row and tonumber(row.count) or 0
        if id and n > 0 then
          map[id] = (map[id] or 0) + n
        end
      end
    end
  end
  return map
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
