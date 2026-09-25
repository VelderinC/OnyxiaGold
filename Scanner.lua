--[[
  OnyxiaGold.Scanner
  Page-by-page Auction House scan for WoW 3.3.5a.

  QueryAuctionItems(name, minLevel, maxLevel, invTypeIndex, classIndex,
                    subclassIndex, page, isUsable, qualityIndex [, getAll])

  GetAuctionItemInfo in 3.3.5a does NOT return itemId. Item IDs are parsed
  from GetAuctionItemLink. Queries do nothing unless the AH window is open.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Scanner = OnyxiaGold.Scanner or {}

local Scanner = OnyxiaGold.Scanner

local STATE_IDLE = "idle"
local STATE_THROTTLE = "throttle"
local STATE_WAITING = "waiting"
local STATE_PROCESSING = "processing"
local STATE_FINALIZING = "finalizing"

local function pageSize()
  if NUM_AUCTION_ITEMS_PER_PAGE and NUM_AUCTION_ITEMS_PER_PAGE > 0 then
    return NUM_AUCTION_ITEMS_PER_PAGE
  end
  return OnyxiaGold.Config.PageSize or 50
end

local function canSendQuery()
  if type(CanSendAuctionQuery) ~= "function" then
    return false
  end
  local ok = CanSendAuctionQuery()
  return ok and true or false
end

function Scanner:IsAuctionHouseOpen()
  return AuctionFrame and AuctionFrame:IsShown()
end

function Scanner:IsScanning()
  return self.state and self.state ~= STATE_IDLE
end

function Scanner:ResetRuntime()
  self.state = STATE_IDLE
  self.page = 0
  self.pagesTotal = nil
  self.auctionsSeen = 0
  self.buyoutAuctions = 0
  self.cacheMisses = 0
  self.pageCacheMisses = 0
  self.retries = 0
  self.aggregates = {}
  self.pageRows = {}
  self.processIndex = 1
  self.batchCount = 0
  self.totalAuctions = 0
  self.waitElapsed = 0
  self.querySentAt = 0
  self.startedAt = 0
  self.finalizeList = nil
  self.finalizeIndex = 1
  if self.frame then
    self.frame:SetScript("OnUpdate", nil)
  end
  if OnyxiaGold.UI and OnyxiaGold.UI.scanButton then
    OnyxiaGold.UI.scanButton:Enable()
  end
end

function Scanner:SetStatus(text)
  if OnyxiaGold.UI and OnyxiaGold.UI.SetStatus then
    OnyxiaGold.UI:SetStatus(text)
  end
end

function Scanner:Start()
  if self:IsScanning() then
    OnyxiaGold:Print("A scan is already running.", "Scanner")
    return
  end
  if not self:IsAuctionHouseOpen() then
    OnyxiaGold:Print("Open the Auction House before scanning.", "Scanner")
    return
  end
  if type(QueryAuctionItems) ~= "function" or type(GetNumAuctionItems) ~= "function" then
    OnyxiaGold:Print("Auction House API is not available. Open the Auction House and try again.", "Scanner")
    return
  end

  local canQuery, canQueryAll
  if type(CanSendAuctionQuery) == "function" then
    canQuery, canQueryAll = CanSendAuctionQuery()
  end

  self:ResetRuntime()
  self.state = STATE_THROTTLE
  self.startedAt = GetTime()
  self.waitElapsed = OnyxiaGold.Config.ScanDelay or 0.45

  self.frame:SetScript("OnUpdate", function(_, elapsed)
    Scanner:OnUpdate(elapsed)
  end)

  OnyxiaGold.Log:Info("Scanner", "Scan started")
  OnyxiaGold.Log:Debug("Scanner", string.format(
    "canQuery=%s canQueryAll=%s pageSize=%d delay=%.2f timeout=%.1f",
    tostring(canQuery),
    tostring(canQueryAll),
    pageSize(),
    OnyxiaGold.Config.ScanDelay or 0.45,
    OnyxiaGold.Config.ScanPageTimeout or 12
  ))
  self:SetStatus("Starting scan...")
  if OnyxiaGold.UI and OnyxiaGold.UI.scanButton then
    OnyxiaGold.UI.scanButton:Disable()
  end
end

function Scanner:Abort(reason)
  if not self:IsScanning() then
    return
  end
  OnyxiaGold.Log:Warn("Scanner", "Scan interrupted (" .. tostring(reason) .. "). Previous price data was kept.")
  self:ResetRuntime()
  self:SetStatus("Scan interrupted. Previous prices kept.")
end

function Scanner:SendQuery()
  if not self:IsAuctionHouseOpen() then
    self:Abort("auction house closed")
    return
  end
  if not canSendQuery() then
    self.state = STATE_THROTTLE
    self.waitElapsed = 0
    return
  end

  -- Page index is 0-based. getAll is intentionally omitted (nil/false).
  QueryAuctionItems("", nil, nil, nil, nil, nil, self.page, nil, nil)
  self.state = STATE_WAITING
  self.querySentAt = GetTime()
  self.pageCacheMisses = 0
  OnyxiaGold.Log:Debug("Scanner", string.format(
    "page query sent page=%d/%s",
    self.page,
    tostring(self.pagesTotal or "?")
  ))
  local shownPage = self.page + 1
  local total = self.pagesTotal or "?"
  self:SetStatus("Scanning " .. shownPage .. " / " .. tostring(total) .. " pages")
end

function Scanner:OnAuctionListUpdate()
  if self.state ~= STATE_WAITING then
    if self:IsScanning() then
      OnyxiaGold.Log:Debug("Scanner", "list update ignored state=" .. tostring(self.state))
    end
    return
  end

  local batch, total = GetNumAuctionItems("list")
  self.batchCount = tonumber(batch) or 0
  self.totalAuctions = tonumber(total) or 0
  self.processIndex = 1
  self.pageRows = {}
  self.pageCacheMisses = 0

  if not self.pagesTotal then
    local size = pageSize()
    if self.totalAuctions <= 0 then
      self.pagesTotal = 1
    else
      self.pagesTotal = math.ceil(self.totalAuctions / size)
    end
  end

  OnyxiaGold.Log:Debug("Scanner", string.format(
    "page received page=%d batch=%d total=%d pagesTotal=%s wait=%.2fs",
    self.page,
    self.batchCount,
    self.totalAuctions,
    tostring(self.pagesTotal),
    GetTime() - (self.querySentAt or GetTime())
  ))

  self.state = STATE_PROCESSING
end

local function medianOf(list)
  if type(list) ~= "table" then
    return nil
  end
  local n = table.getn(list)
  if n == 0 then
    return nil
  end
  table.sort(list)
  if math.mod(n, 2) == 1 then
    return list[(n + 1) / 2]
  end
  local a = list[n / 2]
  local b = list[n / 2 + 1]
  return math.floor((a + b) / 2)
end

function Scanner:ReadAuction(index)
  -- 3.3.5a return order: no levelColHeader, no itemId, no hasAllInfo.
  local name, _, count, _, _, _, minBid, _, buyoutPrice, bidAmount = GetAuctionItemInfo("list", index)
  local link = GetAuctionItemLink("list", index)

  if not name or name == "" or not link then
    return nil
  end

  local itemID = OnyxiaGold.ParseItemID(link)
  if not itemID then
    return nil
  end

  count = tonumber(count) or 0
  if count <= 0 then
    return nil
  end

  return {
    itemID = itemID,
    name = name,
    link = link,
    count = count,
    buyoutPrice = tonumber(buyoutPrice) or 0,
    minBid = tonumber(minBid) or 0,
    bidAmount = tonumber(bidAmount) or 0,
  }
end

function Scanner:EnsureAggregate(row)
  local rec = self.aggregates[row.itemID]
  if rec then
    return rec
  end
  rec = {
    name = row.name,
    link = row.link,
    auctionCount = 0,
    quantity = 0,
    minUnitBuyout = nil,
    minStackBuyout = nil,
    unitPrices = {},
    buyoutCopperSum = 0,
    buyoutQuantity = 0,
    minBidUnit = nil,
  }
  self.aggregates[row.itemID] = rec
  return rec
end

function Scanner:MergePage(rows)
  for i = 1, table.getn(rows) do
    local row = rows[i]
    local rec = self:EnsureAggregate(row)
    rec.auctionCount = rec.auctionCount + 1
    rec.quantity = rec.quantity + row.count
    rec.name = row.name
    rec.link = row.link

    -- Instant-buy math ignores bid-only auctions (buyout 0).
    if row.buyoutPrice > 0 then
      self.buyoutAuctions = self.buyoutAuctions + 1
      local unit = math.floor(row.buyoutPrice / row.count)
      if unit > 0 then
        if not rec.minUnitBuyout or unit < rec.minUnitBuyout then
          rec.minUnitBuyout = unit
        end
        if not rec.minStackBuyout or row.buyoutPrice < rec.minStackBuyout then
          rec.minStackBuyout = row.buyoutPrice
        end
        table.insert(rec.unitPrices, unit)
        rec.buyoutCopperSum = rec.buyoutCopperSum + (unit * row.count)
        rec.buyoutQuantity = rec.buyoutQuantity + row.count
      end
    end

    local bidCopper = 0
    if row.bidAmount > 0 then
      bidCopper = row.bidAmount
    elseif row.minBid > 0 then
      bidCopper = row.minBid
    end
    if bidCopper > 0 then
      local bidUnit = math.floor(bidCopper / row.count)
      if bidUnit > 0 and (not rec.minBidUnit or bidUnit < rec.minBidUnit) then
        rec.minBidUnit = bidUnit
      end
    end
  end
  self.auctionsSeen = self.auctionsSeen + table.getn(rows)
end

function Scanner:ProcessSlice()
  local perFrame = OnyxiaGold.Config.AuctionsPerFrame or 25
  local last = math.min(self.processIndex + perFrame - 1, self.batchCount)
  for i = self.processIndex, last do
    local row = self:ReadAuction(i)
    if row then
      table.insert(self.pageRows, row)
    else
      self.pageCacheMisses = self.pageCacheMisses + 1
      if self.pageCacheMisses == 1 then
        OnyxiaGold.Log:Debug("Scanner", "item cache miss at index " .. tostring(i) .. " page=" .. tostring(self.page))
      end
    end
  end
  self.processIndex = last + 1

  local shownPage = self.page + 1
  self:SetStatus(string.format(
    "Scanning %d / %d pages  ·  Scanned %s auctions",
    shownPage,
    self.pagesTotal or shownPage,
    tostring(self.auctionsSeen + table.getn(self.pageRows))
  ))

  if self.processIndex <= self.batchCount then
    return
  end

  if self.pageCacheMisses > 0 and self.retries < (OnyxiaGold.Config.MaxPageRetries or 3) then
    self.retries = self.retries + 1
    OnyxiaGold.Log:Debug("Scanner", string.format(
      "retrying page=%d attempt=%d cacheMisses=%d",
      self.page,
      self.retries,
      self.pageCacheMisses
    ))
    self.pageRows = {}
    self.state = STATE_THROTTLE
    self.waitElapsed = 0
    return
  end

  if self.pageCacheMisses > 0 then
    self.cacheMisses = self.cacheMisses + self.pageCacheMisses
    OnyxiaGold.Log:Warn("Scanner", string.format(
      "accepting page=%d with %d unresolved cache misses",
      self.page,
      self.pageCacheMisses
    ))
  end

  self:MergePage(self.pageRows)
  self.pageRows = {}
  self.retries = 0

  local size = pageSize()
  local morePages = self.batchCount >= size and (not self.pagesTotal or (self.page + 1) < self.pagesTotal)
  if morePages then
    self.page = self.page + 1
    self.state = STATE_THROTTLE
    self.waitElapsed = 0
  else
    self:BeginFinalize()
  end
end

function Scanner:BeginFinalize()
  self.finalizeList = {}
  for itemID, rec in pairs(self.aggregates) do
    table.insert(self.finalizeList, itemID)
  end
  self.finalizeIndex = 1
  self.state = STATE_FINALIZING
  OnyxiaGold.Log:Debug("Scanner", "pages complete, finalizing " .. tostring(table.getn(self.finalizeList)) .. " items")
  self:SetStatus("Calculating prices...")
end

function Scanner:FinalizeSlice()
  local perFrame = OnyxiaGold.Config.FinalizeItemsPerFrame or 30
  local list = self.finalizeList
  local last = math.min(self.finalizeIndex + perFrame - 1, table.getn(list))
  for i = self.finalizeIndex, last do
    local rec = self.aggregates[list[i]]
    if rec then
      rec.medianUnitBuyout = medianOf(rec.unitPrices)
      rec.unitPrices = nil
      if rec.buyoutQuantity > 0 then
        rec.meanUnitBuyout = math.floor(rec.buyoutCopperSum / rec.buyoutQuantity)
      else
        rec.meanUnitBuyout = rec.minUnitBuyout
      end
    end
  end
  self.finalizeIndex = last + 1
  if self.finalizeIndex <= table.getn(list) then
    return
  end
  self:Complete()
end

function Scanner:Complete()
  local duration = GetTime() - (self.startedAt or GetTime())
  local pages = (self.page or 0) + 1
  OnyxiaGold.Database:WriteLatest(self.aggregates, {
    auctionCount = self.auctionsSeen,
    pages = pages,
    duration = duration,
    cacheMisses = self.cacheMisses,
  })

  OnyxiaGold.Log:Info("Scanner", string.format(
    "Scan complete: %s auctions, %s items, %d pages, %.1fs, cacheMisses=%s buyoutAuctions=%s",
    tostring(self.auctionsSeen),
    tostring(table.getn(self.finalizeList or {})),
    pages,
    duration,
    tostring(self.cacheMisses),
    tostring(self.buyoutAuctions)
  ))
  if OnyxiaGold.Log.LogWatchedPrices then
    OnyxiaGold.Log:LogWatchedPrices()
  end

  self:ResetRuntime()
  self:SetStatus("Scan complete.")
  OnyxiaGold.OpportunityEngine:Refresh()
end

function Scanner:OnUpdate(elapsed)
  if self.state == STATE_IDLE then
    return
  end

  if not self:IsAuctionHouseOpen() then
    self:Abort("auction house closed")
    return
  end

  if self.state == STATE_THROTTLE then
    self.waitElapsed = (self.waitElapsed or 0) + elapsed
    if self.waitElapsed >= (OnyxiaGold.Config.ScanDelay or 0.45) and canSendQuery() then
      self:SendQuery()
    end
  elseif self.state == STATE_WAITING then
    if (GetTime() - (self.querySentAt or 0)) > (OnyxiaGold.Config.ScanPageTimeout or 12) then
      if self.retries < (OnyxiaGold.Config.MaxPageRetries or 3) then
        self.retries = self.retries + 1
        OnyxiaGold.Log:Warn("Scanner", "page timeout, retry " .. tostring(self.retries) .. " page=" .. tostring(self.page))
        self.state = STATE_THROTTLE
        self.waitElapsed = 0
      else
        self:Abort("query timeout")
      end
    end
  elseif self.state == STATE_PROCESSING then
    self:ProcessSlice()
  elseif self.state == STATE_FINALIZING then
    self:FinalizeSlice()
  end
end

local eventFrame = CreateFrame("Frame")
Scanner.frame = eventFrame
eventFrame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:SetScript("OnEvent", function(_, event)
  if event == "AUCTION_ITEM_LIST_UPDATE" then
    Scanner:OnAuctionListUpdate()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    if Scanner:IsScanning() then
      Scanner:Abort("auction house closed")
    end
  elseif event == "AUCTION_HOUSE_SHOW" then
    OnyxiaGold.Log:Debug("Scanner", "Auction House opened")
  end
end)

Scanner:ResetRuntime()
