--[[
  OnyxiaGold.TradeLog
  Per-character buys and sales inside OnyxiaGoldDB.

  A buy click, an English "auction won" / "auction sold" system line, and
  Auction House success mail are trades. Scans, snapshots, and expected
  profit are not. Mail is only read. Nothing here takes mail, deletes mail,
  posts an auction, or buys one.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.TradeLog = OnyxiaGold.TradeLog or {}

local TradeLog = OnyxiaGold.TradeLog

local BUTTON_ECHO_SECONDS = 20
local COPPER_PER_SILVER = 100
local COPPER_PER_GOLD = 10000

local function plainMoney(copper)
  if OnyxiaGold.FormatGoldShort then
    return OnyxiaGold.FormatGoldShort(copper)
  end
  copper = tonumber(copper) or 0
  local g = math.floor(copper / COPPER_PER_GOLD)
  local s = math.floor((copper % COPPER_PER_GOLD) / COPPER_PER_SILVER)
  if g > 0 and s > 0 then
    return string.format("%dg %ds", g, s)
  elseif g > 0 then
    return string.format("%dg", g)
  elseif s > 0 then
    return string.format("%ds", s)
  end
  return string.format("%dc", copper % COPPER_PER_SILVER)
end

function TradeLog.ServerStamp()
  local now = time()
  if type(date) ~= "function" then
    return ""
  end
  if type(GetGameTime) ~= "function" then
    return date("%Y-%m-%d %H:%M", now)
  end
  local hour, minute = GetGameTime()
  hour = tonumber(hour) or 0
  minute = tonumber(minute) or 0
  local localHour = tonumber(date("%H", now)) or 0
  local localMinute = tonumber(date("%M", now)) or 0
  local delta = (hour * 60 + minute) - (localHour * 60 + localMinute)
  if delta > 720 then
    delta = delta - 1440
  elseif delta < -720 then
    delta = delta + 1440
  end
  return date("%Y-%m-%d %H:%M", now + delta * 60)
end

function TradeLog:Entries()
  if not OnyxiaGold.Database or not OnyxiaGold.Database.GetCharacter then
    return nil
  end
  local rec = OnyxiaGold.Database:GetCharacter()
  if not rec then
    return nil
  end
  if type(rec.trades) ~= "table" then
    rec.trades = {}
  end
  return rec.trades
end

function TradeLog:Seen()
  if not OnyxiaGold.Database or not OnyxiaGold.Database.GetCharacter then
    return nil
  end
  local rec = OnyxiaGold.Database:GetCharacter()
  if not rec then
    return nil
  end
  if type(rec.tradeMailSeen) ~= "table" then
    rec.tradeMailSeen = {}
  end
  return rec.tradeMailSeen
end

function TradeLog.FormatLine(entry)
  entry = entry or {}
  local side = "BUY"
  if entry.side == "sale" then
    side = "SALE"
  end
  local name = entry.name or "item"
  local body = name
  local count = tonumber(entry.count)
  if count and count > 0 then
    body = string.format("%dx %s", count, name)
  end
  local money = ""
  if entry.copper ~= nil then
    money = "  " .. plainMoney(entry.copper)
  end
  local line = string.format("%s  %s  %s%s", entry.when or "", side, body, money)
  if type(entry.note) == "string" and entry.note ~= "" then
    line = line .. "  | " .. entry.note
  end
  return line
end

function TradeLog:Totals()
  local spent, received = 0, 0
  local entries = self:Entries()
  if not entries then
    return spent, received
  end
  for i = 1, table.getn(entries) do
    local entry = entries[i]
    if entry and entry.copper ~= nil then
      local copper = tonumber(entry.copper)
      if copper and copper >= 0 then
        if entry.side == "sale" then
          received = received + copper
        elseif entry.side == "buy" then
          spent = spent + copper
        end
      end
    end
  end
  return spent, received
end

function TradeLog:TotalsLine()
  local spent, received = self:Totals()
  return string.format("Spent %s    Received %s", plainMoney(spent), plainMoney(received))
end

function TradeLog:Dump()
  local lines = { self:TotalsLine() }
  local entries = self:Entries()
  if entries then
    for i = 1, table.getn(entries) do
      table.insert(lines, self.FormatLine(entries[i]))
    end
  end
  return table.concat(lines, "\n")
end

function TradeLog:Touch()
  if OnyxiaGold.UI and OnyxiaGold.UI.RefreshTrades then
    OnyxiaGold.UI:RefreshTrades()
  end
end

function TradeLog:Append(fields, quiet)
  fields = fields or {}
  if fields.side ~= "buy" and fields.side ~= "sale" then
    return nil
  end
  local name = fields.name
  if type(name) ~= "string" or name == "" then
    return nil
  end
  local entries = self:Entries()
  if not entries then
    return nil
  end
  local entry = {
    t = time(),
    when = self.ServerStamp(),
    side = fields.side,
    name = name,
    source = fields.source,
  }
  local itemID = tonumber(fields.itemID)
  if itemID and itemID > 0 then
    entry.itemID = itemID
  end
  local count = tonumber(fields.count)
  if count and count > 0 then
    entry.count = count
  end
  if fields.copper ~= nil then
    local copper = tonumber(fields.copper)
    if copper and copper >= 0 then
      entry.copper = copper
    end
  end
  if type(fields.note) == "string" and fields.note ~= "" then
    entry.note = fields.note
  end
  if type(fields.mailKey) == "string" and fields.mailKey ~= "" then
    entry.mailKey = fields.mailKey
  end
  table.insert(entries, entry)
  local cap = (OnyxiaGold.Config and OnyxiaGold.Config.MaxTradeLines) or 400
  while table.getn(entries) > cap do
    table.remove(entries, 1)
  end
  if not quiet then
    self:Touch()
  end
  return entry
end

function TradeLog.SameItem(entry, itemID, name)
  if type(entry) ~= "table" then
    return false
  end
  itemID = tonumber(itemID)
  local entryID = tonumber(entry.itemID)
  if itemID and entryID then
    return itemID == entryID
  end
  if type(name) == "string" and type(entry.name) == "string" and name ~= "" and entry.name ~= "" then
    return string.lower(name) == string.lower(entry.name)
  end
  return false
end

-- The convert sentence from the action row. Not the profit breakdown.
function TradeLog:RecordBuyClick(itemID, name, count, copper, note)
  itemID = tonumber(itemID)
  if (type(name) ~= "string" or name == "") and itemID and OnyxiaGold.Data and OnyxiaGold.Data.GetItemName then
    name = OnyxiaGold.Data.GetItemName(itemID)
  end
  if (type(name) ~= "string" or name == "") and itemID then
    name = "item:" .. tostring(itemID)
  end
  self:Append({
    side = "buy",
    name = name,
    itemID = itemID,
    count = count,
    copper = copper,
    note = note,
    source = "button",
  })
end

function TradeLog.ParseCopper(text)
  if type(text) ~= "string" then
    return nil
  end
  local work = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
  work = string.gsub(work, "|Hitem:[^|]*|h", "")
  work = string.gsub(work, "|h", "")
  work = string.gsub(work, "|r", "")
  local gold, silver, copper
  local function take(pattern)
    local n = string.match(work, pattern)
    if not n then
      return nil
    end
    return tonumber(n) or 0
  end
  gold = take("(%d+)%s*[Gg]old")
  silver = take("(%d+)%s*[Ss]ilver")
  copper = take("(%d+)%s*[Cc]opper")
  if gold == nil then
    gold = take("(%d+)%s*[gG]")
  end
  if silver == nil then
    silver = take("(%d+)%s*[sS]")
  end
  if copper == nil then
    copper = take("(%d+)%s*[cC]")
  end
  if gold == nil and silver == nil and copper == nil then
    return nil
  end
  return (gold or 0) * COPPER_PER_GOLD + (silver or 0) * COPPER_PER_SILVER + (copper or 0)
end

function TradeLog.ItemIdByName(name)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  local items = OnyxiaGold.Data and OnyxiaGold.Data.ItemsByID
  if type(items) == "table" then
    for id, def in pairs(items) do
      if type(def) == "table" and def.name == name then
        return tonumber(def.id) or tonumber(id)
      end
    end
  end
  if type(GetItemInfo) == "function" then
    local _, link = GetItemInfo(name)
    if link and OnyxiaGold.ParseItemID then
      return OnyxiaGold.ParseItemID(link)
    end
  end
  return nil
end

local function stripTrailingPrice(text)
  if type(text) ~= "string" then
    return ""
  end
  local work = text
  work = string.gsub(work, "%s+[Ss]old%s*.*$", "")
  work = string.gsub(work, "%s+[Ff]or%s+.*$", "")
  work = string.gsub(work, "%s+%d+%s*[Gg]old.*$", "")
  work = string.gsub(work, "%s+%d+%s*[Ss]ilver.*$", "")
  work = string.gsub(work, "%s+%d+%s*[Cc]opper.*$", "")
  work = string.gsub(work, "%s+%d+%s*[gG]%s*%d*%s*[sS]?%s*%d*%s*[cC]?%s*$", "")
  work = string.gsub(work, "%s+%d+%s*[sS]%s*%d*%s*[cC]?%s*$", "")
  work = string.gsub(work, "%s+%d+%s*[cC]%s*$", "")
  return work
end

function TradeLog.ItemFromMessage(msg, rest)
  local itemID = OnyxiaGold.ParseItemID and OnyxiaGold.ParseItemID(msg) or nil
  local name = type(msg) == "string" and string.match(msg, "|h%[(.-)%]|h") or nil
  if type(name) == "string" and name ~= "" then
    return name, itemID
  end
  name = stripTrailingPrice(rest or "")
  name = string.gsub(name, "^%s+", "")
  name = string.gsub(name, "%s+$", "")
  name = string.gsub(name, "[%.%!]+$", "")
  name = string.gsub(name, "^%[", "")
  name = string.gsub(name, "%]$", "")
  name = string.gsub(name, "%s+$", "")
  if not itemID then
    itemID = TradeLog.ItemIdByName(name)
  end
  if name == "" then
    return nil, itemID
  end
  return name, itemID
end

local function prefixOf(fmt, fallback)
  if type(fmt) == "string" then
    local pre = string.match(fmt, "^(.-)%%s")
    if pre and pre ~= "" then
      return pre
    end
  end
  return fallback
end

function TradeLog.ClassifySystemMessage(msg)
  if type(msg) ~= "string" or msg == "" then
    return nil
  end
  local won = prefixOf(ERR_AUCTION_WON_S, "You won an auction for ")
  local sold = prefixOf(ERR_AUCTION_SOLD_S, "A buyer has been found for your auction of ")
  local side, rest
  if string.sub(msg, 1, string.len(won)) == won then
    side = "buy"
    rest = string.sub(msg, string.len(won) + 1)
  elseif string.sub(msg, 1, string.len(sold)) == sold then
    side = "sale"
    rest = string.sub(msg, string.len(sold) + 1)
  else
    local your = "Your auction of "
    local lower = string.lower(msg)
    -- Whole words, so an item such as Soldering Iron is not a sale.
    local function word(text, token)
      return string.find(text, "%f[%a]" .. token .. "%f[%A]") ~= nil
    end
    if string.sub(msg, 1, string.len(your)) == your
      and word(lower, "sold")
      and not word(lower, "expired")
      and not string.find(lower, "%f[%a]cancel") then
      side = "sale"
      rest = string.sub(msg, string.len(your) + 1)
    end
  end
  if not side then
    return nil
  end
  local name, itemID = TradeLog.ItemFromMessage(msg, rest)
  if not name or name == "" then
    return nil
  end
  local count = string.match(rest or "", "^%s*(%d+)%s*[xX]%s+")
  count = tonumber(count)
  if count and count < 1 then
    count = nil
  end
  return {
    side = side,
    name = name,
    itemID = itemID,
    copper = TradeLog.ParseCopper(msg),
    count = count,
  }
end

function TradeLog:ConsumeButtonBuy(itemID, name)
  local entries = self:Entries()
  if not entries then
    return false
  end
  local now = time()
  for i = table.getn(entries), 1, -1 do
    local entry = entries[i]
    if entry and entry.side == "buy" and entry.source == "button" and not entry.chatMatched then
      local age = now - (tonumber(entry.t) or now)
      if age < 0 then
        age = 0
      end
      if age <= BUTTON_ECHO_SECONDS and self.SameItem(entry, itemID, name) then
        entry.chatMatched = true
        return true
      end
    end
  end
  return false
end

function TradeLog:OnSystemMessage(msg)
  local parsed = self.ClassifySystemMessage(msg)
  if not parsed then
    return
  end
  if parsed.side == "buy" and self:ConsumeButtonBuy(parsed.itemID, parsed.name) then
    return
  end
  self:Append({
    side = parsed.side,
    name = parsed.name,
    itemID = parsed.itemID,
    count = parsed.count,
    copper = parsed.copper,
    source = "chat",
  })
end

function TradeLog.ParseMailSubject(subject)
  if type(subject) ~= "string" then
    return nil
  end
  local itemID, _, _, auctionID, count = string.match(subject, "^(%d+):(%-?%d+):(%d+):(%d+):(%d+)")
  if not itemID then
    return nil
  end
  count = tonumber(count)
  if count and count < 1 then
    count = nil
  end
  auctionID = tonumber(auctionID)
  if auctionID and auctionID < 1 then
    auctionID = nil
  end
  return tonumber(itemID), auctionID, count
end

function TradeLog.PlainItemName(text)
  if type(text) ~= "string" or text == "" then
    return nil
  end
  local name = string.match(text, "|h%[(.-)%]|h")
  if not name or name == "" then
    name = string.match(text, "%[(.-)%]")
  end
  if not name or name == "" then
    name = text
  end
  name = string.gsub(name, "|c%x%x%x%x%x%x%x%x", "")
  name = string.gsub(name, "|r", "")
  name = string.gsub(name, "|h", "")
  name = string.gsub(name, "^%s+", "")
  name = string.gsub(name, "%s+$", "")
  if name == "" then
    return nil
  end
  return name
end

-- Attached copper is the received amount. If it was already taken, the
-- invoice still shows bid + deposit - consignment, and that is the same
-- amount after the house cut.
function TradeLog.MailProceeds(money, bid, deposit, consignment)
  money = tonumber(money) or 0
  if money > 0 then
    return money
  end
  bid = tonumber(bid) or 0
  deposit = tonumber(deposit) or 0
  consignment = tonumber(consignment) or 0
  local shown = bid + deposit - consignment
  if shown > 0 then
    return shown
  end
  return nil
end

function TradeLog.MailFingerprint(auctionID, itemID, name, bid, buyout, deposit, consignment, money, playerName)
  auctionID = tonumber(auctionID)
  if auctionID and auctionID > 0 then
    return "a:" .. tostring(auctionID)
  end
  return table.concat({
    "m",
    tostring(tonumber(itemID) or ""),
    name or "",
    tostring(tonumber(bid) or 0),
    tostring(tonumber(buyout) or 0),
    tostring(tonumber(deposit) or 0),
    tostring(tonumber(consignment) or 0),
    tostring(tonumber(money) or 0),
    playerName or "",
  }, "|")
end

function TradeLog.ReadSuccessMail(index)
  if type(GetInboxHeaderInfo) ~= "function" then
    return nil
  end
  local _, _, _, subject, money, codAmount = GetInboxHeaderInfo(index)
  if (tonumber(codAmount) or 0) > 0 then
    return nil
  end
  if type(GetInboxInvoiceInfo) ~= "function" then
    return nil
  end
  local invoiceType, itemName, playerName, bid, buyout, deposit, consignment = GetInboxInvoiceInfo(index)
  if invoiceType ~= "seller" then
    return nil
  end
  local itemID, auctionID, count = TradeLog.ParseMailSubject(subject)
  local name = TradeLog.PlainItemName(itemName)
  if (not name or name == "") and itemID and OnyxiaGold.Data and OnyxiaGold.Data.GetItemName then
    name = OnyxiaGold.Data.GetItemName(itemID)
  end
  if not itemID and name then
    itemID = TradeLog.ItemIdByName(name)
  end
  if (not name or name == "") and itemID then
    name = "item:" .. tostring(itemID)
  end
  if not name or name == "" then
    return nil
  end
  return {
    fingerprint = TradeLog.MailFingerprint(auctionID, itemID, name, bid, buyout, deposit, consignment, money, playerName),
    itemID = itemID,
    name = name,
    count = count,
    copper = TradeLog.MailProceeds(money, bid, deposit, consignment),
  }
end

function TradeLog:OldestOpenSale(itemID, name)
  local entries = self:Entries()
  if not entries then
    return nil
  end
  for i = 1, table.getn(entries) do
    local entry = entries[i]
    if entry and entry.side == "sale" and not entry.mailKey and self.SameItem(entry, itemID, name) then
      return entry
    end
  end
  return nil
end

function TradeLog:ApplyMail(info)
  if type(info) ~= "table" then
    return
  end
  local entry = self:OldestOpenSale(info.itemID, info.name)
  if entry then
    if info.copper ~= nil then
      entry.copper = info.copper
    end
    if info.count and (not tonumber(entry.count) or tonumber(entry.count) < 1) then
      entry.count = info.count
    end
    if info.itemID and not entry.itemID then
      entry.itemID = info.itemID
    end
    entry.mailKey = info.fingerprint
    return
  end
  self:Append({
    side = "sale",
    name = info.name,
    itemID = info.itemID,
    count = info.count,
    copper = info.copper,
    source = "mail",
    mailKey = info.fingerprint,
  }, true)
end

function TradeLog:NoteInbox()
  if type(GetInboxNumItems) ~= "function" then
    return
  end
  local seen = self:Seen()
  if not seen then
    return
  end
  local numItems, totalItems = GetInboxNumItems()
  numItems = tonumber(numItems) or 0
  totalItems = tonumber(totalItems) or numItems
  local complete = numItems >= totalItems
  local groups = {}
  local order = {}
  for i = 1, numItems do
    local info = self.ReadSuccessMail(i)
    if info and info.fingerprint then
      local group = groups[info.fingerprint]
      if not group then
        group = { count = 0, info = info }
        groups[info.fingerprint] = group
        table.insert(order, info.fingerprint)
      end
      group.count = group.count + 1
    end
  end
  local changed = false
  for i = 1, table.getn(order) do
    local fp = order[i]
    local group = groups[fp]
    local already = tonumber(seen[fp]) or 0
    local add = group.count - already
    if add < 0 then
      if complete then
        seen[fp] = group.count
      end
    elseif add > 0 then
      for _ = 1, add do
        self:ApplyMail(group.info)
      end
      seen[fp] = already + add
      changed = true
    end
  end
  if complete then
    for fp in pairs(seen) do
      if not groups[fp] then
        seen[fp] = nil
      end
    end
  end
  if changed then
    self:Touch()
  end
end

if type(CreateFrame) == "function" then
  local watch = CreateFrame("Frame")
  watch:RegisterEvent("CHAT_MSG_SYSTEM")
  watch:SetScript("OnEvent", function(_, event, message)
    if event == "CHAT_MSG_SYSTEM" then
      TradeLog:OnSystemMessage(message)
    end
  end)
end
