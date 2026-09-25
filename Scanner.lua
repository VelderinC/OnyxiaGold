--[[
  OnyxiaGold.Scanner
  Shared state machine for Quick Scan (watchlist name queries) and Full Scan
  (empty-name page walk). 3.3.5a QueryAuctionItems has no exact-match flag;
  Quick Scan filters returned rows by expected item ID.

  Quick Scan covers commodities. Full Scan is also the future feed for
  green/blue/purple disenchant opportunity discovery (v0.2.0).

  QueryAuctionItems(name, minLevel, maxLevel, invTypeIndex, classIndex,
                    subclassIndex, page, isUsable, qualityIndex [, getAll])
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
    return false, false
  end
  local ok, all = CanSendAuctionQuery()
  return ok and true or false, all and true or false
end

local function experimentalGetAll()
  if OnyxiaGoldDB and OnyxiaGoldDB.settings and OnyxiaGoldDB.settings.useGetAll then
    return true
  end
  return OnyxiaGold.Config.useGetAll and true or false
end

function Scanner:IsAuctionHouseOpen()
  return AuctionFrame and AuctionFrame:IsShown()
end

function Scanner:IsScanning()
  return self.state and self.state ~= STATE_IDLE
end

function Scanner:EnableScanButtons()
  if OnyxiaGold.UI then
    if OnyxiaGold.UI.quickScanButton then
      OnyxiaGold.UI.quickScanButton:Enable()
    end
    if OnyxiaGold.UI.fullScanButton then
      OnyxiaGold.UI.fullScanButton:Enable()
    end
    if OnyxiaGold.UI.scanButton then
      OnyxiaGold.UI.scanButton:Enable()
    end
  end
end

function Scanner:DisableScanButtons()
  if OnyxiaGold.UI then
    if OnyxiaGold.UI.quickScanButton then
      OnyxiaGold.UI.quickScanButton:Disable()
    end
    if OnyxiaGold.UI.fullScanButton then
      OnyxiaGold.UI.fullScanButton:Disable()
    end
    if OnyxiaGold.UI.scanButton then
      OnyxiaGold.UI.scanButton:Disable()
    end
  end
end

function Scanner:ResetRuntime()
  self.state = STATE_IDLE
  self.mode = nil
  self.page = 0
  self.pagesTotal = nil
  self.auctionsSeen = 0
  self.matchedRows = 0
  self.buyoutAuctions = 0
  self.cacheMisses = 0
  self.pageCacheMisses = 0
  self.pageUnmatched = 0
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
  self.quickQueue = nil
  self.quickIndex = 1
  self.currentWatch = nil
  self.expectedItemID = nil
  self.expectedName = nil
  self.expectedPage = nil
  self.querySequence = 0
  self.expectedSequence = nil
  self.useGetAll = false
  if self.frame then
    self.frame:SetScript("OnUpdate", nil)
  end
  self:EnableScanButtons()
end

function Scanner:SetStatus(text)
  if OnyxiaGold.UI and OnyxiaGold.UI.SetStatus then
    OnyxiaGold.UI:SetStatus(text)
  end
end

local function beginScan(self, mode)
  if self:IsScanning() then
    OnyxiaGold:Print("A scan is already running.", "Scanner")
    return false
  end
  if not self:IsAuctionHouseOpen() then
    OnyxiaGold:Print("Open the Auction House before scanning.", "Scanner")
    return false
  end
  if type(QueryAuctionItems) ~= "function" or type(GetNumAuctionItems) ~= "function" then
    OnyxiaGold:Print("Auction House API is not available. Open the Auction House and try again.", "Scanner")
    return false
  end
  local canQuery, canQueryAll = canSendQuery()
  OnyxiaGold.Log:Debug("Scanner", string.format(
    "canQuery=%s canQueryAll=%s mode=%s getAllSetting=%s",
    tostring(canQuery), tostring(canQueryAll), tostring(mode), tostring(experimentalGetAll())
  ))
  self:ResetRuntime()
  self.mode = mode
  self.state = STATE_THROTTLE
  self.startedAt = GetTime()
  self.waitElapsed = OnyxiaGold.Config.ScanDelay or 0.45
  self.frame:SetScript("OnUpdate", function(_, elapsed)
    Scanner:OnUpdate(elapsed)
  end)
  self:DisableScanButtons()
  return true
end

function Scanner:StartQuick()
  if not beginScan(self, "quick") then
    return
  end
  self.quickQueue = OnyxiaGold.Data.GetEnabledWatchlist and OnyxiaGold.Data.GetEnabledWatchlist() or {}
  self.quickIndex = 1
  if table.getn(self.quickQueue) == 0 then
    OnyxiaGold:Print("Watchlist is empty.", "Scanner")
    self:ResetRuntime()
    return
  end
  OnyxiaGold.Log:Info("Scanner", "Quick Scan started (" .. tostring(table.getn(self.quickQueue)) .. " items)")
  self:PrepareQuickItem()
  self:SetStatus("Quick Scan starting...")
end

function Scanner:StartFull()
  if not beginScan(self, "full") then
    return
  end
  self.useGetAll = false
  local _, canQueryAll = canSendQuery()
  if experimentalGetAll() then
    if canQueryAll then
      self.useGetAll = true
      OnyxiaGold.Log:Warn("Scanner", "Experimental getAll enabled for this Full Scan")
    else
      OnyxiaGold.Log:Warn("Scanner", "getAll requested but CanSendAuctionQuery() says it is not available; paging instead")
    end
  end
  OnyxiaGold.Log:Info("Scanner", "Full Scan started")
  self:SetStatus("Full Scan starting...")
end

-- /og scan defaults to Quick Scan.
function Scanner:Start()
  self:StartQuick()
end

function Scanner:PrepareQuickItem()
  local item = self.quickQueue[self.quickIndex]
  self.currentWatch = item
  self.expectedItemID = item and item.itemID or nil
  self.expectedName = item and item.name or nil
  self.page = 0
  self.pagesTotal = nil
  self.retries = 0
  self.waitElapsed = 0
  self.state = STATE_THROTTLE
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
  local canQuery = canSendQuery()
  if not canQuery then
    self.state = STATE_THROTTLE
    self.waitElapsed = 0
    return
  end

  self.querySequence = (self.querySequence or 0) + 1
  self.expectedSequence = self.querySequence
  self.expectedPage = self.page

  if self.mode == "quick" then
    local name = self.expectedName or ""
    if self.expectedItemID then
      local liveName = GetItemInfo(self.expectedItemID)
      if liveName and liveName ~= "" then
        name = liveName
        self.expectedName = liveName
      end
    end
    QueryAuctionItems(name, nil, nil, nil, nil, nil, self.page, nil, nil)
    OnyxiaGold.Log:Debug("Scanner", string.format(
      "Quick query %d/%d item=%s page=%d seq=%d",
      self.quickIndex,
      table.getn(self.quickQueue or {}),
      tostring(name),
      self.page,
      self.querySequence
    ))
    self:SetStatus(string.format(
      "Quick Scan  %d / %d   %s",
      self.quickIndex,
      table.getn(self.quickQueue or {}),
      tostring(name)
    ))
  else
    local getAll = nil
    if self.useGetAll and self.page == 0 then
      getAll = 1
    end
    QueryAuctionItems("", nil, nil, nil, nil, nil, self.page, nil, nil, getAll)
    OnyxiaGold.Log:Debug("Scanner", string.format(
      "Full page query sent page=%d/%s seq=%d getAll=%s",
      self.page,
      tostring(self.pagesTotal or "?"),
      self.querySequence,
      tostring(getAll)
    ))
    local shownPage = self.page + 1
    self:SetStatus("Full Scan  " .. shownPage .. " / " .. tostring(self.pagesTotal or "?") .. " pages")
  end

  self.state = STATE_WAITING
  self.querySentAt = GetTime()
  self.pageCacheMisses = 0
  self.pageUnmatched = 0
end

function Scanner:OnAuctionListUpdate()
  if self.state ~= STATE_WAITING then
    if self:IsScanning() then
      OnyxiaGold.Log:Debug("Scanner", "list update ignored state=" .. tostring(self.state) .. " seq=" .. tostring(self.querySequence))
    end
    return
  end

  local batch, total = GetNumAuctionItems("list")
  self.batchCount = tonumber(batch) or 0
  self.totalAuctions = tonumber(total) or 0
  self.processIndex = 1
  self.pageRows = {}
  self.pageCacheMisses = 0
  self.pageUnmatched = 0

  if not self.pagesTotal then
    local size = pageSize()
    if self.useGetAll then
      self.pagesTotal = 1
    elseif self.totalAuctions <= 0 then
      self.pagesTotal = 1
    else
      self.pagesTotal = math.ceil(self.totalAuctions / size)
    end
  end

  OnyxiaGold.Log:Debug("Scanner", string.format(
    "page received mode=%s page=%d batch=%d total=%d expectedItem=%s seq=%d",
    tostring(self.mode),
    self.page,
    self.batchCount,
    self.totalAuctions,
    tostring(self.expectedItemID),
    tostring(self.expectedSequence)
  ))

  self.state = STATE_PROCESSING
end

function Scanner:ReadAuction(index)
  local name, _, count, _, _, _, minBid, _, buyoutPrice, bidAmount = GetAuctionItemInfo("list", index)
  local link = GetAuctionItemLink("list", index)

  if not name or name == "" or not link then
    return nil, "cache"
  end

  local itemID = OnyxiaGold.ParseItemID(link)
  if not itemID then
    return nil, "cache"
  end

  count = tonumber(count) or 0
  if count <= 0 then
    return nil, "bad"
  end

  return {
    itemID = itemID,
    name = name,
    link = link,
    count = count,
    buyoutPrice = tonumber(buyoutPrice) or 0,
    minBid = tonumber(minBid) or 0,
    bidAmount = tonumber(bidAmount) or 0,
  }, nil
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
    buyoutAuctionCount = 0,
    totalQuantity = 0,
    buyoutQuantity = 0,
    bidOnlyQuantity = 0,
    minUnitBuyout = nil,
    minStackBuyout = nil,
    buyoutLevels = {},
    buyoutCopperSum = 0,
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
    rec.totalQuantity = rec.totalQuantity + row.count
    rec.name = row.name
    rec.link = row.link

    if row.buyoutPrice > 0 then
      local unit = math.floor(row.buyoutPrice / row.count)
      if unit > 0 then
        rec.buyoutAuctionCount = rec.buyoutAuctionCount + 1
        rec.buyoutQuantity = rec.buyoutQuantity + row.count
        self.buyoutAuctions = self.buyoutAuctions + 1
        if not rec.minUnitBuyout or unit < rec.minUnitBuyout then
          rec.minUnitBuyout = unit
        end
        if not rec.minStackBuyout or row.buyoutPrice < rec.minStackBuyout then
          rec.minStackBuyout = row.buyoutPrice
        end
        rec.buyoutCopperSum = rec.buyoutCopperSum + (unit * row.count)
        local bucket = rec.buyoutLevels[unit]
        if not bucket then
          rec.buyoutLevels[unit] = { p = unit, q = row.count, n = 1 }
        else
          bucket.q = bucket.q + row.count
          bucket.n = bucket.n + 1
        end
      else
        rec.bidOnlyQuantity = rec.bidOnlyQuantity + row.count
      end
    else
      rec.bidOnlyQuantity = rec.bidOnlyQuantity + row.count
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
  self.matchedRows = self.matchedRows + table.getn(rows)
end

function Scanner:ProcessSlice()
  local perFrame = OnyxiaGold.Config.AuctionsPerFrame or 25
  local last = math.min(self.processIndex + perFrame - 1, self.batchCount)
  for i = self.processIndex, last do
    local row, reason = self:ReadAuction(i)
    if row then
      if self.mode == "quick" and self.expectedItemID and row.itemID ~= self.expectedItemID then
        self.pageUnmatched = self.pageUnmatched + 1
      else
        table.insert(self.pageRows, row)
      end
    elseif reason == "cache" then
      self.pageCacheMisses = self.pageCacheMisses + 1
      if self.pageCacheMisses == 1 then
        OnyxiaGold.Log:Debug("Scanner", "item cache miss at index " .. tostring(i) .. " page=" .. tostring(self.page))
      end
    end
  end
  self.processIndex = last + 1

  if self.mode == "full" then
    local shownPage = self.page + 1
    self:SetStatus(string.format(
      "Full Scan  %d / %d pages  ·  %s auctions",
      shownPage,
      self.pagesTotal or shownPage,
      tostring(self.auctionsSeen + table.getn(self.pageRows))
    ))
  end

  if self.processIndex <= self.batchCount then
    return
  end

  if self.pageCacheMisses > 0 and self.retries < (OnyxiaGold.Config.MaxPageRetries or 3) then
    self.retries = self.retries + 1
    OnyxiaGold.Log:Debug("Scanner", string.format(
      "retrying page=%d attempt=%d cacheMisses=%d",
      self.page, self.retries, self.pageCacheMisses
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
      self.page, self.pageCacheMisses
    ))
  end

  self:MergePage(self.pageRows)
  if self.mode == "quick" then
    OnyxiaGold.Log:Debug("Scanner", string.format(
      "Quick resultRows=%d matchedRows=%d unmatched=%d item=%s",
      self.batchCount,
      table.getn(self.pageRows),
      self.pageUnmatched,
      tostring(self.expectedName)
    ))
  end
  self.pageRows = {}
  self.retries = 0

  local size = pageSize()
  local morePages = (not self.useGetAll) and self.batchCount >= size and (not self.pagesTotal or (self.page + 1) < self.pagesTotal)
  if morePages then
    self.page = self.page + 1
    self.state = STATE_THROTTLE
    self.waitElapsed = 0
    return
  end

  if self.mode == "quick" then
    self:FinishQuickItem()
  else
    self:BeginFinalize()
  end
end

function Scanner:FinishQuickItem()
  local rec = self.expectedItemID and self.aggregates[self.expectedItemID]
  if rec then
    OnyxiaGold.Log:Debug("Scanner", string.format(
      "Quick item done %s buyoutQty=%d totalQty=%d bidOnlyQty=%d auctions=%d buyoutAuctions=%d",
      tostring(self.expectedName),
      rec.buyoutQuantity or 0,
      rec.totalQuantity or 0,
      rec.bidOnlyQuantity or 0,
      rec.auctionCount or 0,
      rec.buyoutAuctionCount or 0
    ))
  else
    -- Queried, nothing matched: still record an empty snapshot for this item.
    self.aggregates[self.expectedItemID] = {
      name = self.expectedName,
      auctionCount = 0,
      buyoutAuctionCount = 0,
      totalQuantity = 0,
      buyoutQuantity = 0,
      bidOnlyQuantity = 0,
      buyoutLevels = {},
      buyoutCopperSum = 0,
    }
    OnyxiaGold.Log:Debug("Scanner", "Quick item empty " .. tostring(self.expectedName))
  end

  self.quickIndex = self.quickIndex + 1
  if self.quickIndex <= table.getn(self.quickQueue) then
    self:PrepareQuickItem()
  else
    self:BeginFinalize()
  end
end

function Scanner:CompactDepth(levelMap)
  local list = {}
  if type(levelMap) ~= "table" then
    return list
  end
  for price, bucket in pairs(levelMap) do
    if type(bucket) == "table" and bucket.p and bucket.q and bucket.q > 0 then
      table.insert(list, { p = bucket.p, q = bucket.q, n = bucket.n or 1 })
    elseif type(price) == "number" and price > 0 then
      table.insert(list, { p = price, q = bucket, n = 1 })
    end
  end
  table.sort(list, function(a, b)
    return a.p < b.p
  end)
  local cap = OnyxiaGold.Config.MaxDepthLevelsPerItem or 100
  while table.getn(list) > cap do
    table.remove(list)
  end
  return list
end

function Scanner:FinalizeItem(rec)
  rec.depth = self:CompactDepth(rec.buyoutLevels)
  rec.buyoutLevels = nil
  local nLevels = table.getn(rec.depth)
  if rec.buyoutQuantity and rec.buyoutQuantity > 0 then
    rec.meanUnitBuyout = math.floor((rec.buyoutCopperSum or 0) / rec.buyoutQuantity)
    rec.p10UnitBuyout = OnyxiaGold.Prices.PercentileFromDepth(rec.depth, rec.buyoutQuantity, 0.10)
    rec.p25UnitBuyout = OnyxiaGold.Prices.PercentileFromDepth(rec.depth, rec.buyoutQuantity, 0.25)
    rec.medianUnitBuyout = OnyxiaGold.Prices.PercentileFromDepth(rec.depth, rec.buyoutQuantity, 0.50)
    rec.p75UnitBuyout = OnyxiaGold.Prices.PercentileFromDepth(rec.depth, rec.buyoutQuantity, 0.75)
  else
    rec.meanUnitBuyout = rec.minUnitBuyout
  end
  if self.mode == "quick" then
    OnyxiaGold.Log:Debug("Scanner", string.format(
      "%s depthLevels=%d min=%s p25=%s med=%s",
      tostring(rec.name),
      nLevels,
      tostring(rec.minUnitBuyout),
      tostring(rec.p25UnitBuyout),
      tostring(rec.medianUnitBuyout)
    ))
  end
end

function Scanner:BeginFinalize()
  self.finalizeList = {}
  for itemID, rec in pairs(self.aggregates) do
    table.insert(self.finalizeList, itemID)
  end
  self.finalizeIndex = 1
  self.state = STATE_FINALIZING
  OnyxiaGold.Log:Debug("Scanner", "finalizing " .. tostring(table.getn(self.finalizeList)) .. " items")
  self:SetStatus("Calculating prices...")
end

function Scanner:FinalizeSlice()
  local perFrame = OnyxiaGold.Config.FinalizeItemsPerFrame or 30
  local list = self.finalizeList
  local last = math.min(self.finalizeIndex + perFrame - 1, table.getn(list))
  for i = self.finalizeIndex, last do
    local rec = self.aggregates[list[i]]
    if rec then
      self:FinalizeItem(rec)
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
  local meta = {
    auctionCount = self.auctionsSeen,
    pages = pages,
    duration = duration,
    cacheMisses = self.cacheMisses,
  }
  if self.mode == "quick" then
    OnyxiaGold.Database:UpdateItems(self.aggregates, meta)
  else
    OnyxiaGold.Database:WriteFullSnapshot(self.aggregates, meta)
  end

  OnyxiaGold.Log:Info("Scanner", string.format(
    "%s complete: %s auctions, %s items, %.1fs, cacheMisses=%s buyoutAuctions=%s",
    self.mode == "quick" and "Quick Scan" or "Full Scan",
    tostring(self.auctionsSeen),
    tostring(table.getn(self.finalizeList or {})),
    duration,
    tostring(self.cacheMisses),
    tostring(self.buyoutAuctions)
  ))
  if OnyxiaGold.Log.LogWatchedPrices then
    OnyxiaGold.Log:LogWatchedPrices()
  end

  self:ResetRuntime()
  self:SetStatus("Scan complete.")
  if OnyxiaGold.UI and OnyxiaGold.UI.RefreshMarketStatus then
    OnyxiaGold.UI:RefreshMarketStatus()
  end
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
    if self.waitElapsed >= (OnyxiaGold.Config.ScanDelay or 0.45) then
      local canQuery = canSendQuery()
      if canQuery then
        self:SendQuery()
      end
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
    local _, canAll = canSendQuery()
    OnyxiaGold.Log:Debug("Scanner", "Auction House opened canQueryAll=" .. tostring(canAll))
  end
end)

Scanner:ResetRuntime()
