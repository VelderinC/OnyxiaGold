--[[
  OnyxiaGold.Database
  SavedVariables, realm/faction markets, migrations, full vs partial writes.

  DB_VERSION 2 partitions latest/history/scans by market key "Realm|Faction".
  Depth lives only on current latest records. History stores compact stats.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Database = OnyxiaGold.Database or {}

local DB = OnyxiaGold.Database

local function copyDefaults(dst, src)
  if type(dst) ~= "table" then
    dst = {}
  end
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = copyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end

local function emptyMarket()
  return {
    latest = {},
    history = {},
    scans = {},
  }
end

function DB:DefaultSettings()
  return {
    debug = false,
    transmuteMaster = false,
    auctionHouseCut = nil,
    useGetAll = false,
  }
end

function DB:EmptyRoot()
  return {
    version = OnyxiaGold.DB_VERSION,
    markets = {},
    settings = self:DefaultSettings(),
    log = { session = 0, lines = {} },
  }
end

function DB:EnsureMarketShape(market)
  if type(market) ~= "table" then
    return emptyMarket()
  end
  if type(market.latest) ~= "table" then
    market.latest = {}
  end
  if type(market.history) ~= "table" then
    market.history = {}
  end
  if type(market.scans) ~= "table" then
    market.scans = {}
  end
  return market
end

function DB:EnsureShape(db)
  db = db or OnyxiaGoldDB
  if type(db) ~= "table" then
    return self:EmptyRoot()
  end
  if type(db.markets) ~= "table" then
    db.markets = {}
  end
  for key, market in pairs(db.markets) do
    db.markets[key] = self:EnsureMarketShape(market)
  end
  if type(db.log) ~= "table" then
    db.log = { session = 0, lines = {} }
  end
  if type(db.log.lines) ~= "table" then
    db.log.lines = {}
  end
  db.settings = copyDefaults(db.settings, self:DefaultSettings())
  if not db.version then
    db.version = OnyxiaGold.DB_VERSION
  end
  return db
end

-- "Onyxia|Horde". Nil until realm/faction exist (ADDON_LOADED can be too early).
function DB:GetCurrentMarketKey()
  local realm = GetRealmName()
  if not realm or realm == "" then
    return nil
  end
  local faction = UnitFactionGroup("player")
  if faction ~= "Alliance" and faction ~= "Horde" then
    faction = "Unknown"
  end
  return realm .. "|" .. faction
end

function DB:FormatMarketLabel(key)
  key = key or self:GetCurrentMarketKey()
  if not key then
    return "Unknown market"
  end
  local realm, faction = string.match(key, "^(.*)|(.*)$")
  if realm and faction then
    return realm .. " · " .. faction
  end
  return key
end

function DB:GetMarket(key)
  self:Ensure()
  key = key or self:GetCurrentMarketKey() or "legacy"
  if type(OnyxiaGoldDB.markets[key]) ~= "table" then
    OnyxiaGoldDB.markets[key] = emptyMarket()
  end
  return self:EnsureMarketShape(OnyxiaGoldDB.markets[key])
end

local function snapshotLegacy(db)
  local latest = db.latest
  local history = db.history
  local scans = db.scans
  local hasLatest = type(latest) == "table" and next(latest)
  local hasHistory = type(history) == "table" and next(history)
  local hasScans = type(scans) == "table" and table.getn(scans) > 0
  if not hasLatest and not hasHistory and not hasScans then
    return nil
  end
  return {
    latest = type(latest) == "table" and latest or {},
    history = type(history) == "table" and history or {},
    scans = type(scans) == "table" and scans or {},
  }
end

local migrations = {
  [2] = function(db)
    -- Preserve unpartitioned v1 tables until PLAYER_LOGIN can name the market.
    db.pendingLegacy = snapshotLegacy(db)
    db.markets = db.markets or {}
    db.latest = nil
    db.history = nil
    db.scans = nil
    if db.pendingLegacy then
      OnyxiaGold:Debug("v1 market data preserved as pendingLegacy", "Database")
    else
      OnyxiaGold:Debug("v1 had no market data to migrate", "Database")
    end
  end,
}

function DB:Migrate(fromVersion, toVersion)
  local v = fromVersion
  while v < toVersion do
    local nextVersion = v + 1
    local fn = migrations[nextVersion]
    if fn then
      fn(OnyxiaGoldDB)
    end
    v = nextVersion
    OnyxiaGoldDB.version = v
    OnyxiaGold:Debug("Migrated saved variables to version " .. tostring(v), "Database")
  end
  self:EnsureShape(OnyxiaGoldDB)
end

function DB:Init()
  local preservedLog
  if type(OnyxiaGoldDB) == "table" then
    preservedLog = OnyxiaGoldDB.log
  end

  if type(OnyxiaGoldDB) ~= "table" then
    OnyxiaGoldDB = self:EmptyRoot()
    if preservedLog then
      OnyxiaGoldDB.log = preservedLog
    end
    OnyxiaGold:Debug("Created new saved variables", "Database")
    return
  end
  if not OnyxiaGoldDB.version then
    local existing = OnyxiaGoldDB
    OnyxiaGoldDB = self:EmptyRoot()
    OnyxiaGoldDB.settings = copyDefaults(existing.settings, self:DefaultSettings())
    OnyxiaGoldDB.log = existing.log or preservedLog or OnyxiaGoldDB.log
    OnyxiaGoldDB.pendingLegacy = snapshotLegacy(existing)
    OnyxiaGold:Debug("Initialised unversioned saved variables into v" .. tostring(OnyxiaGold.DB_VERSION), "Database")
  elseif OnyxiaGoldDB.version < OnyxiaGold.DB_VERSION then
    self:Migrate(OnyxiaGoldDB.version, OnyxiaGold.DB_VERSION)
  end
  self:EnsureShape(OnyxiaGoldDB)
  if preservedLog and (not OnyxiaGoldDB.log or not OnyxiaGoldDB.log.lines) then
    OnyxiaGoldDB.log = preservedLog
  end
end

function DB:Ensure()
  if type(OnyxiaGoldDB) ~= "table" then
    OnyxiaGoldDB = self:EmptyRoot()
  else
    self:EnsureShape(OnyxiaGoldDB)
  end
end

-- Assign pending v1 data once realm/faction are known. Never destroy it.
function DB:BindCurrentMarket()
  self:Ensure()
  local key = self:GetCurrentMarketKey()
  if not key then
    OnyxiaGold:Debug("BindCurrentMarket skipped; realm/faction not ready", "Database")
    return
  end
  local pending = OnyxiaGoldDB.pendingLegacy
  if type(pending) ~= "table" then
    self:GetMarket(key)
    return
  end
  local dest = self:GetMarket(key)
  if not next(dest.latest) then
    dest.latest = pending.latest or {}
    dest.history = pending.history or dest.history
    dest.scans = pending.scans or dest.scans
    OnyxiaGold:Debug("Migrated pendingLegacy into " .. key, "Database")
  else
    OnyxiaGoldDB.markets["legacy"] = self:EnsureMarketShape(pending)
    OnyxiaGold:Debug("Current market already had data; pendingLegacy kept as markets.legacy", "Database")
  end
  OnyxiaGoldDB.pendingLegacy = nil
end

function DB:Reset()
  local preservedLog = OnyxiaGoldDB and OnyxiaGoldDB.log
  OnyxiaGoldDB = self:EmptyRoot()
  if preservedLog then
    OnyxiaGoldDB.log = preservedLog
  end
  OnyxiaGold:Warn("Price database reset; log retained", "Database")
end

local function compactRecord(itemID, rec, timestamp)
  local totalQuantity = rec.totalQuantity or rec.quantity or 0
  local buyoutQuantity = rec.buyoutQuantity or 0
  local out = {
    itemID = itemID,
    name = rec.name,
    timestamp = timestamp,
    -- quantity is a compatibility alias for totalQuantity (all listed units).
    -- Instant-buy math must use buyoutQuantity, not quantity.
    quantity = totalQuantity,
    totalQuantity = totalQuantity,
    buyoutQuantity = buyoutQuantity,
    bidOnlyQuantity = rec.bidOnlyQuantity or 0,
    auctionCount = rec.auctionCount or 0,
    buyoutAuctionCount = rec.buyoutAuctionCount or 0,
    minUnitBuyout = rec.minUnitBuyout,
    minStackBuyout = rec.minStackBuyout,
    p10UnitBuyout = rec.p10UnitBuyout,
    p25UnitBuyout = rec.p25UnitBuyout,
    medianUnitBuyout = rec.medianUnitBuyout,
    p75UnitBuyout = rec.p75UnitBuyout,
    meanUnitBuyout = rec.meanUnitBuyout,
    minBidUnit = rec.minBidUnit,
    depth = rec.depth,
  }
  return out
end

local function historyPoint(rec)
  return {
    t = rec.timestamp,
    min = rec.minUnitBuyout,
    p10 = rec.p10UnitBuyout,
    p25 = rec.p25UnitBuyout,
    med = rec.medianUnitBuyout,
    p75 = rec.p75UnitBuyout,
    mean = rec.meanUnitBuyout,
    qty = rec.totalQuantity or rec.quantity,
    buyoutQty = rec.buyoutQuantity,
  }
end

function DB:AppendHistory(itemID, rec)
  if not rec then
    return
  end
  local market = self:GetMarket()
  local history = market.history[itemID]
  if type(history) ~= "table" then
    history = {}
    market.history[itemID] = history
  end
  table.insert(history, historyPoint(rec))
  local cap = OnyxiaGold.Config.MaxHistoryPoints or 30
  while table.getn(history) > cap do
    table.remove(history, 1)
  end
end

function DB:AppendScanSummary(market, summary)
  table.insert(market.scans, summary)
  local maxSummaries = OnyxiaGold.Config.MaxScanSummaries or 20
  while table.getn(market.scans) > maxSummaries do
    table.remove(market.scans, 1)
  end
end

-- Full Scan: replace this market's latest snapshot entirely.
function DB:WriteFullSnapshot(aggregates, scanMeta)
  self:Ensure()
  local market = self:GetMarket()
  local timestamp = time()
  local latest = {}
  local itemCount = 0
  for itemID, rec in pairs(aggregates) do
    itemCount = itemCount + 1
    latest[itemID] = compactRecord(itemID, rec, timestamp)
    self:AppendHistory(itemID, latest[itemID])
  end
  market.latest = latest
  self:AppendScanSummary(market, {
    timestamp = timestamp,
    scanType = "full",
    auctionCount = scanMeta and scanMeta.auctionCount or 0,
    itemCount = itemCount,
    queriedItems = itemCount,
    pages = scanMeta and scanMeta.pages or 0,
    duration = scanMeta and scanMeta.duration or 0,
    cacheMisses = scanMeta and scanMeta.cacheMisses or 0,
  })
  OnyxiaGold:Debug(string.format(
    "Full snapshot items=%d auctions=%s duration=%.1fs",
    itemCount,
    tostring(scanMeta and scanMeta.auctionCount),
    tonumber(scanMeta and scanMeta.duration) or 0
  ), "Database")
end

-- Quick Scan: update only queried item IDs; leave the rest of latest intact.
function DB:UpdateItems(aggregates, scanMeta)
  self:Ensure()
  local market = self:GetMarket()
  if type(market.latest) ~= "table" then
    market.latest = {}
  end
  local timestamp = time()
  local itemCount = 0
  for itemID, rec in pairs(aggregates) do
    itemCount = itemCount + 1
    market.latest[itemID] = compactRecord(itemID, rec, timestamp)
    self:AppendHistory(itemID, market.latest[itemID])
  end
  self:AppendScanSummary(market, {
    timestamp = timestamp,
    scanType = "quick",
    auctionCount = scanMeta and scanMeta.auctionCount or 0,
    itemCount = itemCount,
    queriedItems = itemCount,
    pages = scanMeta and scanMeta.pages or 0,
    duration = scanMeta and scanMeta.duration or 0,
    cacheMisses = scanMeta and scanMeta.cacheMisses or 0,
  })
  OnyxiaGold:Debug(string.format(
    "Quick update items=%d auctions=%s duration=%.1fs",
    itemCount,
    tostring(scanMeta and scanMeta.auctionCount),
    tonumber(scanMeta and scanMeta.duration) or 0
  ), "Database")
end

-- Back-compat name used by older scanner complete path.
function DB:WriteLatest(aggregates, scanMeta)
  self:WriteFullSnapshot(aggregates, scanMeta)
end

function DB:GetLatest(itemID)
  self:Ensure()
  itemID = tonumber(itemID)
  if not itemID then
    return nil
  end
  local market = self:GetMarket()
  return market.latest[itemID]
end

function DB:GetHistory(itemID)
  self:Ensure()
  itemID = tonumber(itemID)
  if not itemID then
    return nil
  end
  local market = self:GetMarket()
  return market.history[itemID]
end

function DB:LastScanOfType(scanType)
  local market = self:GetMarket()
  local scans = market.scans
  for i = table.getn(scans), 1, -1 do
    if scans[i] and scans[i].scanType == scanType then
      return scans[i]
    end
  end
  return nil
end
