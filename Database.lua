--[[
  OnyxiaGold.Database
  SavedVariables initialisation, shape guarantees, and version migrations.
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

function DB:DefaultSettings()
  return {
    debug = false,
    transmuteMaster = false,
    auctionHouseCut = nil,
  }
end

function DB:EmptyRoot()
  return {
    version = OnyxiaGold.DB_VERSION,
    scans = {},
    latest = {},
    history = {},
    settings = self:DefaultSettings(),
    log = { session = 0, lines = {} },
  }
end

function DB:EnsureShape(db)
  db = db or OnyxiaGoldDB
  if type(db) ~= "table" then
    return self:EmptyRoot()
  end
  if type(db.scans) ~= "table" then
    db.scans = {}
  end
  if type(db.latest) ~= "table" then
    db.latest = {}
  end
  if type(db.history) ~= "table" then
    db.history = {}
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

-- Migrations run in order from (fromVersion + 1) through toVersion.
-- Version 1 is the initial schema; add [2] = function(db) ... end when it changes.
local migrations = {
  -- [2] = function(db)
  --   db.history = db.history or {}
  -- end,
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
    if type(existing.latest) == "table" then
      OnyxiaGoldDB.latest = existing.latest
    end
    if type(existing.scans) == "table" then
      OnyxiaGoldDB.scans = existing.scans
    end
    if type(existing.settings) == "table" then
      OnyxiaGoldDB.settings = copyDefaults(existing.settings, self:DefaultSettings())
    end
    OnyxiaGoldDB.log = existing.log or preservedLog or OnyxiaGoldDB.log
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

function DB:Reset()
  local preservedLog = OnyxiaGoldDB and OnyxiaGoldDB.log
  OnyxiaGoldDB = self:EmptyRoot()
  if preservedLog then
    OnyxiaGoldDB.log = preservedLog
  end
  OnyxiaGold:Warn("Price database reset; log retained", "Database")
end

-- Compact per-item snapshot written after a successful full scan.
-- Raw auction rows are discarded; only aggregates survive.
function DB:WriteLatest(aggregates, scanMeta)
  self:Ensure()
  local timestamp = time()
  local latest = {}
  local itemCount = 0

  for itemID, rec in pairs(aggregates) do
    itemCount = itemCount + 1
    latest[itemID] = {
      itemID = itemID,
      name = rec.name,
      timestamp = timestamp,
      quantity = rec.quantity or 0,
      auctionCount = rec.auctionCount or 0,
      minUnitBuyout = rec.minUnitBuyout,
      minStackBuyout = rec.minStackBuyout,
      medianUnitBuyout = rec.medianUnitBuyout,
      meanUnitBuyout = rec.meanUnitBuyout,
      minBidUnit = rec.minBidUnit,
    }
    self:AppendHistory(itemID, latest[itemID])
  end

  OnyxiaGoldDB.latest = latest

  local summary = {
    timestamp = timestamp,
    auctionCount = scanMeta and scanMeta.auctionCount or 0,
    itemCount = itemCount,
    pages = scanMeta and scanMeta.pages or 0,
    duration = scanMeta and scanMeta.duration or 0,
    cacheMisses = scanMeta and scanMeta.cacheMisses or 0,
  }
  table.insert(OnyxiaGoldDB.scans, summary)

  local maxSummaries = OnyxiaGold.Config.MaxScanSummaries or 20
  while table.getn(OnyxiaGoldDB.scans) > maxSummaries do
    table.remove(OnyxiaGoldDB.scans, 1)
  end
  OnyxiaGold:Debug(string.format(
    "Wrote latest snapshot items=%d auctions=%s pages=%s duration=%.1fs cacheMisses=%s",
    itemCount,
    tostring(scanMeta and scanMeta.auctionCount),
    tostring(scanMeta and scanMeta.pages),
    tonumber(scanMeta and scanMeta.duration) or 0,
    tostring(scanMeta and scanMeta.cacheMisses)
  ), "Database")
end

function DB:AppendHistory(itemID, rec)
  if not rec or not rec.minUnitBuyout then
    return
  end
  local history = OnyxiaGoldDB.history[itemID]
  if type(history) ~= "table" then
    history = {}
    OnyxiaGoldDB.history[itemID] = history
  end
  table.insert(history, {
    t = rec.timestamp,
    min = rec.minUnitBuyout,
    med = rec.medianUnitBuyout,
    mean = rec.meanUnitBuyout,
    qty = rec.quantity,
  })
  local cap = OnyxiaGold.Config.MaxHistoryPoints or 30
  while table.getn(history) > cap do
    table.remove(history, 1)
  end
end

function DB:GetLatest(itemID)
  self:Ensure()
  itemID = tonumber(itemID)
  if not itemID then
    return nil
  end
  return OnyxiaGoldDB.latest[itemID]
end

function DB:GetHistory(itemID)
  self:Ensure()
  itemID = tonumber(itemID)
  if not itemID then
    return nil
  end
  return OnyxiaGoldDB.history[itemID]
end
