--[[
  OnyxiaGold.Database
  SavedVariables, realm/faction markets, character snapshots, migrations.

  DB_VERSION 2 partitions latest/history/scans by market key "Realm|Faction".
  DB_VERSION 3 adds characters["Realm|Faction|Name"] observation snapshots.
  DB_VERSION 4 scopes knownRecipes by profession and replaces each set on scan.
  Depth lives only on current latest records. History stores compact stats.
  Latest records keep buyoutQuantity (full book) and depthCoveredQuantity
  (units still represented after acquisition-depth truncation).
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
    transmuteMasterOverride = false,
    auctionHouseCut = nil,
    useGetAll = false,
    capitalReservePercent = 0.10,
    showAboveSkill = false,
  }
end

function DB:EmptyRoot()
  return {
    version = OnyxiaGold.DB_VERSION,
    markets = {},
    characters = {},
    itemMeta = {},
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
  if type(db.characters) ~= "table" then
    db.characters = {}
  end
  if type(db.itemMeta) ~= "table" then
    db.itemMeta = {}
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

function DB:EmptyCharacter()
  return {
    identity = {},
    professions = {},
    -- knownRecipes[profession][spellID] = true. _legacy holds unscoped pre-v4 spells.
    knownRecipes = {},
    recipeScans = {},
    specialisations = {},
    inventory = {
      bags = {},
      equipped = {},
      timestamp = nil,
      stackSize = {},
      partialRoom = {},
    },
    bank = { items = {}, timestamp = nil },
    mail = {
      claimableGold = 0,
      pendingGold = 0,
      snapshotTimestamp = nil,
      mailboxLastOpened = nil,
      snapshotComplete = nil,
      visibleCount = nil,
      totalCount = nil,
      items = {},
    },
    auctions = {
      listings = {},
      askingValue = 0,
      expectedNet = 0,
      currentBids = 0,
      timestamp = nil,
      shown = nil,
      total = nil,
      complete = nil,
    },
    capital = {
      liquid = 0,
      timestamp = nil,
    },
    stateTimestamps = {},
  }
end

function DB:EnsureCharacterShape(rec)
  local empty = self:EmptyCharacter()
  if type(rec) ~= "table" then
    return empty
  end
  rec.identity = type(rec.identity) == "table" and rec.identity or {}
  rec.professions = type(rec.professions) == "table" and rec.professions or {}
  rec.knownRecipes = type(rec.knownRecipes) == "table" and rec.knownRecipes or {}
  rec.recipeScans = type(rec.recipeScans) == "table" and rec.recipeScans or {}
  self:MigrateKnownRecipes(rec)
  rec.specialisations = type(rec.specialisations) == "table" and rec.specialisations or {}
  rec.inventory = type(rec.inventory) == "table" and rec.inventory or empty.inventory
  if type(rec.inventory.bags) ~= "table" then
    rec.inventory.bags = {}
  end
  if type(rec.inventory.equipped) ~= "table" then
    rec.inventory.equipped = {}
  end
  if type(rec.inventory.stackSize) ~= "table" then
    rec.inventory.stackSize = {}
  end
  if type(rec.inventory.partialRoom) ~= "table" then
    rec.inventory.partialRoom = {}
  end
  rec.bank = type(rec.bank) == "table" and rec.bank or empty.bank
  if type(rec.bank.items) ~= "table" then
    rec.bank.items = {}
  end
  rec.mail = type(rec.mail) == "table" and rec.mail or empty.mail
  if type(rec.mail.items) ~= "table" then
    rec.mail.items = {}
  end
  rec.auctions = type(rec.auctions) == "table" and rec.auctions or empty.auctions
  if type(rec.auctions.listings) ~= "table" then
    rec.auctions.listings = {}
  end
  rec.capital = type(rec.capital) == "table" and rec.capital or empty.capital
  rec.stateTimestamps = type(rec.stateTimestamps) == "table" and rec.stateTimestamps or {}
  return rec
end

-- "Onyxia|Alliance|CharacterName". Nil until name/realm/faction exist.
function DB:GetCharacterKey()
  local realm = GetRealmName()
  local name = UnitName("player")
  if not realm or realm == "" or not name or name == "" then
    return nil
  end
  local faction = UnitFactionGroup("player")
  if faction ~= "Alliance" and faction ~= "Horde" then
    faction = "Unknown"
  end
  return realm .. "|" .. faction .. "|" .. name
end

function DB:GetCharacter(key)
  self:Ensure()
  key = key or self:GetCharacterKey()
  if not key then
    return nil
  end
  if type(OnyxiaGoldDB.characters[key]) ~= "table" then
    OnyxiaGoldDB.characters[key] = self:EmptyCharacter()
  end
  return self:EnsureCharacterShape(OnyxiaGoldDB.characters[key])
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

local function numericKey(k)
  if type(k) == "number" then
    return k
  end
  if type(k) == "string" then
    return tonumber(k)
  end
  return nil
end

-- spellID -> profession, from static recipe definitions loaded with the addon.
function DB:SpellProfessionMap()
  local map = {}
  local transmutes = OnyxiaGold.Data and OnyxiaGold.Data.Transmutes
  if type(transmutes) == "table" then
    for i = 1, table.getn(transmutes) do
      local def = transmutes[i]
      local req = def and def.requirements
      local spell = req and tonumber(req.recipeSpellID)
      local profession = req and req.profession
      if spell and profession then
        map[spell] = profession
      end
    end
  end
  return map
end

--[[
  Old shape: knownRecipes[spellID] = true  (one flat set, appended forever)
  New shape: knownRecipes[profession][spellID] = true
  Unscoped leftovers sit in knownRecipes._legacy until that profession is
  replaced by a complete scan. Idempotent once the flat keys are gone.
]]
function DB:MigrateKnownRecipes(rec)
  if type(rec) ~= "table" then
    return
  end
  if type(rec.knownRecipes) ~= "table" then
    rec.knownRecipes = {}
    return
  end
  local known = rec.knownRecipes
  local flat = {}
  local nested = {}
  local legacy = {}
  local sawFlat = false
  for k, v in pairs(known) do
    local spell = numericKey(k)
    if spell and type(v) ~= "table" then
      sawFlat = true
      if v then
        flat[spell] = true
      end
    elseif k == "_legacy" and type(v) == "table" then
      for lk, lv in pairs(v) do
        local ls = numericKey(lk)
        if ls and lv and type(lv) ~= "table" then
          legacy[ls] = true
        end
      end
    elseif type(k) == "string" and type(v) == "table" then
      nested[k] = v
    end
  end
  if not sawFlat then
    return
  end

  local map = self:SpellProfessionMap()
  local scans = type(rec.recipeScans) == "table" and rec.recipeScans or {}
  local scanNames = {}
  for name, scan in pairs(scans) do
    if type(name) == "string" and type(scan) == "table" and scan.timestamp then
      table.insert(scanNames, name)
    end
  end

  local function bucket(profession)
    if type(nested[profession]) ~= "table" then
      nested[profession] = {}
    end
    return nested[profession]
  end

  if table.getn(scanNames) == 1 then
    local only = scanNames[1]
    for spell, _ in pairs(flat) do
      local mapped = map[spell]
      if mapped then
        bucket(mapped)[spell] = true
      else
        bucket(only)[spell] = true
      end
    end
  else
    for spell, _ in pairs(flat) do
      local mapped = map[spell]
      if mapped then
        bucket(mapped)[spell] = true
      else
        legacy[spell] = true
      end
    end
  end

  local out = {}
  for profession, set in pairs(nested) do
    out[profession] = set
  end
  if next(legacy) then
    out._legacy = legacy
  end
  rec.knownRecipes = out
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
  [3] = function(db)
    db.characters = db.characters or {}
    OnyxiaGold:Debug("v3 character snapshots enabled", "Database")
  end,
  [4] = function(db)
    db.characters = db.characters or {}
    local n = 0
    for _, rec in pairs(db.characters) do
      if type(rec) == "table" then
        DB:MigrateKnownRecipes(rec)
        n = n + 1
      end
    end
    OnyxiaGold:Debug("v4 profession-scoped recipe snapshots on " .. tostring(n) .. " characters", "Database")
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
  local preservedChars = OnyxiaGoldDB and OnyxiaGoldDB.characters
  local preservedSettings = OnyxiaGoldDB and OnyxiaGoldDB.settings
  local preservedMeta = OnyxiaGoldDB and OnyxiaGoldDB.itemMeta
  OnyxiaGoldDB = self:EmptyRoot()
  if preservedLog then
    OnyxiaGoldDB.log = preservedLog
  end
  if type(preservedChars) == "table" then
    OnyxiaGoldDB.characters = preservedChars
  end
  if type(preservedSettings) == "table" then
    OnyxiaGoldDB.settings = copyDefaults(preservedSettings, self:DefaultSettings())
  end
  if type(preservedMeta) == "table" then
    OnyxiaGoldDB.itemMeta = preservedMeta
  end
  OnyxiaGold:Warn("Price database reset; log, settings, character snapshots, and item metadata retained", "Database")
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
    depthCoveredQuantity = rec.depthCoveredQuantity,
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
