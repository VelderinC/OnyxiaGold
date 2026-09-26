--[[
  OnyxiaGold.TradeLog
  Per-character buys and sales inside OnyxiaGoldDB.

  A confirmed buy, an English "auction won" / "auction sold" system line, and
  Auction House success mail are trades. A buy click is only an attempt.
  Scans, snapshots, and expected profit are not trades. Mail is only read.
  Nothing here takes mail, deletes mail, posts an auction, or buys one.

  A sale keeps the item, the quantity, the proceeds, and the time it sold.
  The auction-house cut and the deposit returned are stored only when the
  mail states them. The time listed, a relist, and the plan that bought or
  crafted the item are stored only when that link is already known. A missing
  cut is left unset. It is not guessed.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.TradeLog = OnyxiaGold.TradeLog or {}

local TradeLog = OnyxiaGold.TradeLog
TradeLog.dirty = true

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

function TradeLog:Open()
  if not OnyxiaGold.Database or not OnyxiaGold.Database.GetCharacter then
    return nil
  end
  local rec = OnyxiaGold.Database:GetCharacter()
  if not rec then
    return nil
  end
  if type(rec.tradeOpen) ~= "table" then
    rec.tradeOpen = {}
  end
  return rec.tradeOpen
end

local function trimOpen(open)
  if type(open) ~= "table" then
    return
  end
  local cap = (OnyxiaGold.Config and OnyxiaGold.Config.MaxTradeLines) or 400
  while table.getn(open) > cap do
    table.remove(open, 1)
  end
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
  local proceeds = tonumber(entry.copper)
  if entry.side == "sale" then
    proceeds = TradeLog.RealisedProceeds(entry)
  end
  if proceeds ~= nil then
    money = "  " .. plainMoney(proceeds)
  end
  local line = string.format("%s  %s  %s%s", entry.when or "", side, body, money)
  if entry.side == "sale" then
    local parts = {}
    if type(entry.plan) == "string" and entry.plan ~= "" then
      table.insert(parts, "Plan: " .. entry.plan)
    end
    if entry.cut ~= nil then
      table.insert(parts, "Auction-house cut " .. plainMoney(entry.cut))
    end
    if entry.deposit ~= nil then
      table.insert(parts, "Deposit returned " .. plainMoney(entry.deposit))
    end
    if type(entry.listedWhen) == "string" and entry.listedWhen ~= "" then
      table.insert(parts, "Listed " .. entry.listedWhen)
    end
    if type(entry.when) == "string" and entry.when ~= "" then
      table.insert(parts, "Sold " .. entry.when)
    end
    if entry.relisted == true then
      table.insert(parts, "Relisted")
    end
    if table.getn(parts) > 0 then
      line = line .. "  | " .. table.concat(parts, " | ")
    end
  end
  if type(entry.note) == "string" and entry.note ~= "" then
    line = line .. "  | " .. entry.note
  end
  return line
end

-- Proceeds the client reported. A missing cut is not filled in at 5%.
function TradeLog.RealisedProceeds(entry)
  if type(entry) ~= "table" or entry.side ~= "sale" then
    return nil
  end
  local copper = tonumber(entry.copper)
  if not copper or copper < 0 then
    return nil
  end
  return copper
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
  local pending = self.pendingBuy
  if type(pending) == "table" and pending.name then
    local state = pending.status or "PENDING_BUY"
    if state == "PENDING_BUY" then
      state = "ATTEMPTED"
    end
    table.insert(lines, state .. " BUY " .. tostring(pending.count or "") .. " " .. tostring(pending.name))
  end
  local entries = self:Entries()
  if entries then
    for i = 1, table.getn(entries) do
      table.insert(lines, self.FormatLine(entries[i]))
    end
  end
  return table.concat(lines, "\n")
end

function TradeLog:Touch()
  self.dirty = true
  self.revision = (self.revision or 0) + 1
  local clock = OnyxiaGold.RefreshSchedule
  if clock and clock.Push then
    local now = 0
    if type(GetTime) == "function" then
      now = tonumber(GetTime()) or 0
    end
    clock:Push(now, "ui", "trade")
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
  if fields.side == "sale" then
    if fields.cut ~= nil then
      local cut = tonumber(fields.cut)
      if cut and cut >= 0 then
        entry.cut = cut
      end
    end
    if fields.deposit ~= nil then
      local returned = tonumber(fields.deposit)
      if returned and returned >= 0 then
        entry.deposit = returned
      end
    end
    local listed = tonumber(fields.listed)
    if listed and listed > 0 then
      entry.listed = listed
    end
    if type(fields.listedWhen) == "string" and fields.listedWhen ~= "" then
      entry.listedWhen = fields.listedWhen
    end
    if type(fields.plan) == "string" and fields.plan ~= "" then
      entry.plan = fields.plan
    end
    if fields.relisted == true then
      entry.relisted = true
    end
    local open = self:Open()
    if open then
      TradeLog.AttachKnown(entry, open)
    end
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

-- A click is an attempt. It is not a realised buy until the client confirms it.
function TradeLog:RecordBuyClick(itemID, name, count, copper, note)
  itemID = tonumber(itemID)
  if (type(name) ~= "string" or name == "") and itemID and OnyxiaGold.Data and OnyxiaGold.Data.GetItemName then
    name = OnyxiaGold.Data.GetItemName(itemID)
  end
  if (type(name) ~= "string" or name == "") and itemID then
    name = "item:" .. tostring(itemID)
  end
  local stamp = 0
  if type(time) == "function" then
    stamp = time()
  elseif os and os.time then
    stamp = os.time()
  end
  self.pendingBuy = {
    status = "PENDING_BUY",
    t = stamp,
    name = name,
    itemID = itemID,
    count = count,
    copper = copper,
    note = note,
  }
  self.dirty = true
  return self.pendingBuy
end

function TradeLog:ConfirmPendingBuy(itemID, name)
  local pending = self.pendingBuy
  if type(pending) ~= "table" then
    return false
  end
  if not self.SameItem(pending, itemID, name) then
    return false
  end
  local now = 0
  if type(time) == "function" then
    now = time()
  elseif os and os.time then
    now = os.time()
  end
  local age = now - (tonumber(pending.t) or now)
  if age < 0 then
    age = 0
  end
  if age > BUTTON_ECHO_SECONDS then
    pending.status = "UNKNOWN"
    self.dirty = true
    return false
  end
  local entry = self:Append({
    side = "buy",
    name = pending.name,
    itemID = pending.itemID,
    count = pending.count,
    copper = pending.copper,
    note = pending.note,
    source = "confirmed",
  }, true)
  if entry then
    self.pendingBuy = nil
  end
  self.dirty = true
  return entry ~= nil
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

function TradeLog.IsExpiry(msg)
  if type(msg) ~= "string" or msg == "" then
    return false
  end
  local fmt = "Your auction of %s has expired."
  if type(ERR_AUCTION_EXPIRED_S) == "string" and ERR_AUCTION_EXPIRED_S ~= "" then
    fmt = ERR_AUCTION_EXPIRED_S
  end
  local pre = prefixOf(fmt, "Your auction of ")
  if string.sub(msg, 1, string.len(pre)) ~= pre then
    return false
  end
  local suffix = string.match(fmt, "%%s(.*)$") or ""
  if suffix == "" then
    return false
  end
  local rest = string.sub(msg, string.len(pre) + 1)
  return string.sub(rest, -string.len(suffix)) == suffix
end

function TradeLog.ExpiryItem(msg)
  if not TradeLog.IsExpiry(msg) then
    return nil, nil
  end
  local fmt = "Your auction of %s has expired."
  if type(ERR_AUCTION_EXPIRED_S) == "string" and ERR_AUCTION_EXPIRED_S ~= "" then
    fmt = ERR_AUCTION_EXPIRED_S
  end
  local pre = prefixOf(fmt, "Your auction of ")
  local suffix = string.match(fmt, "%%s(.*)$") or ""
  local rest = string.sub(msg, string.len(pre) + 1)
  if suffix ~= "" and string.sub(rest, -string.len(suffix)) == suffix then
    rest = string.sub(rest, 1, -string.len(suffix) - 1)
  end
  return TradeLog.ItemFromMessage(msg, rest)
end

function TradeLog:OnSystemMessage(msg)
  if self.IsExpiry(msg) then
    local name, itemID = self.ExpiryItem(msg)
    if name and name ~= "" then
      self:NoteExpired(itemID, name)
    end
    return
  end
  local parsed = self.ClassifySystemMessage(msg)
  if not parsed then
    return
  end
  if parsed.side == "buy" and self:ConfirmPendingBuy(parsed.itemID, parsed.name) then
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

-- Cut and deposit are copied only when the invoice actually returned them.
-- Proceeds stay the amount the client reported. They are not reduced by a
-- house cut that the mail did not state.
function TradeLog.SaleFieldsFromInvoice(money, bid, deposit, consignment)
  local fields = {}
  local proceeds = TradeLog.MailProceeds(money, bid, deposit, consignment)
  if proceeds ~= nil then
    fields.copper = proceeds
  end
  if consignment ~= nil then
    local cut = tonumber(consignment)
    if cut and cut >= 0 then
      fields.cut = cut
    end
  end
  if deposit ~= nil then
    local returned = tonumber(deposit)
    if returned and returned >= 0 then
      fields.deposit = returned
    end
  end
  return fields
end

function TradeLog.AttachKnown(entry, openRows)
  if type(entry) ~= "table" or entry.side ~= "sale" or type(openRows) ~= "table" then
    return entry
  end
  local found, index
  for i = 1, table.getn(openRows) do
    local row = openRows[i]
    if type(row) == "table" and not row.expired and TradeLog.SameItem(row, entry.itemID, entry.name) then
      found = row
      index = i
      break
    end
  end
  if not found then
    return entry
  end
  if (type(entry.plan) ~= "string" or entry.plan == "") and type(found.plan) == "string" and found.plan ~= "" then
    entry.plan = found.plan
  end
  if entry.listed == nil and tonumber(found.listed) and tonumber(found.listed) > 0 then
    entry.listed = tonumber(found.listed)
  end
  if (type(entry.listedWhen) ~= "string" or entry.listedWhen == "")
    and type(found.listedWhen) == "string" and found.listedWhen ~= "" then
    entry.listedWhen = found.listedWhen
  end
  if entry.relisted == nil and found.relisted == true then
    entry.relisted = true
  end
  table.remove(openRows, index)
  return entry
end

function TradeLog.MarkExpired(openRows, itemID, name)
  if type(openRows) ~= "table" then
    return false
  end
  for i = 1, table.getn(openRows) do
    local row = openRows[i]
    if type(row) == "table" and not row.expired and TradeLog.SameItem(row, itemID, name) then
      row.expired = true
      return true
    end
  end
  return false
end

function TradeLog.PushBought(openRows, fields)
  fields = fields or {}
  if type(openRows) ~= "table" then
    return nil
  end
  if type(fields.plan) ~= "string" or fields.plan == "" then
    return nil
  end
  local itemID = tonumber(fields.itemID)
  local name = fields.name
  if (type(name) ~= "string" or name == "") and itemID and itemID > 0 then
    name = "item:" .. tostring(itemID)
  end
  if type(name) ~= "string" or name == "" then
    return nil
  end
  local row = {
    kind = "buy",
    name = name,
    plan = fields.plan,
  }
  if itemID and itemID > 0 then
    row.itemID = itemID
  end
  local count = tonumber(fields.count)
  if count and count > 0 then
    row.count = count
  end
  table.insert(openRows, row)
  trimOpen(openRows)
  return row
end

function TradeLog.PushListing(openRows, fields)
  fields = fields or {}
  if type(openRows) ~= "table" then
    return nil
  end
  local itemID = tonumber(fields.itemID)
  local name = fields.name
  if (type(name) ~= "string" or name == "") and itemID and itemID > 0 then
    name = "item:" .. tostring(itemID)
  end
  if type(name) ~= "string" or name == "" then
    return nil
  end
  local relisted = nil
  local boughtPlan
  local i = 1
  while i <= table.getn(openRows) do
    local row = openRows[i]
    if type(row) == "table" and TradeLog.SameItem(row, itemID, name) then
      if row.expired then
        relisted = true
        if not boughtPlan and type(row.plan) == "string" and row.plan ~= "" then
          boughtPlan = row.plan
        end
        table.remove(openRows, i)
      elseif row.kind == "buy" then
        if not boughtPlan and type(row.plan) == "string" and row.plan ~= "" then
          boughtPlan = row.plan
        end
        table.remove(openRows, i)
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  local plan = fields.plan
  if type(plan) ~= "string" or plan == "" then
    plan = boughtPlan
  end
  local row = {
    kind = "list",
    name = name,
  }
  if itemID and itemID > 0 then
    row.itemID = itemID
  end
  local count = tonumber(fields.count)
  if count and count > 0 then
    row.count = count
  end
  if type(plan) == "string" and plan ~= "" then
    row.plan = plan
  end
  local listed = tonumber(fields.listed)
  if listed and listed > 0 then
    row.listed = listed
  end
  if type(fields.listedWhen) == "string" and fields.listedWhen ~= "" then
    row.listedWhen = fields.listedWhen
  end
  if relisted == true then
    row.relisted = true
  end
  table.insert(openRows, row)
  trimOpen(openRows)
  return row
end

function TradeLog:RememberBought(fields)
  local open = self:Open()
  if not open then
    return nil
  end
  return TradeLog.PushBought(open, fields)
end

function TradeLog:RememberListed(fields)
  fields = fields or {}
  local open = self:Open()
  if not open then
    return nil
  end
  local listedWhen = fields.listedWhen
  if type(listedWhen) ~= "string" or listedWhen == "" then
    local stamp = self.ServerStamp()
    if type(stamp) == "string" and stamp ~= "" then
      listedWhen = stamp
    end
  end
  return TradeLog.PushListing(open, {
    itemID = fields.itemID,
    name = fields.name,
    count = fields.count,
    plan = fields.plan,
    listed = tonumber(fields.listed) or time(),
    listedWhen = listedWhen,
  })
end

function TradeLog:NoteExpired(itemID, name)
  local open = self:Open()
  if not open then
    return false
  end
  return TradeLog.MarkExpired(open, itemID, name)
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
  local priced = TradeLog.SaleFieldsFromInvoice(money, bid, deposit, consignment)
  return {
    fingerprint = TradeLog.MailFingerprint(auctionID, itemID, name, bid, buyout, deposit, consignment, money, playerName),
    itemID = itemID,
    name = name,
    count = count,
    copper = priced.copper,
    cut = priced.cut,
    deposit = priced.deposit,
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
    if info.cut ~= nil and entry.cut == nil then
      entry.cut = info.cut
    end
    if info.deposit ~= nil and entry.deposit == nil then
      entry.deposit = info.deposit
    end
    entry.mailKey = info.fingerprint
    local open = self:Open()
    if open and (type(entry.plan) ~= "string" or entry.plan == "") then
      TradeLog.AttachKnown(entry, open)
    end
    return
  end
  self:Append({
    side = "sale",
    name = info.name,
    itemID = info.itemID,
    count = info.count,
    copper = info.copper,
    cut = info.cut,
    deposit = info.deposit,
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
