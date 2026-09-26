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
    showBeyondGold = false,
    -- /og window size. Matches the UI defaults; a resize overwrites these.
    windowWidth = 1080,
    windowHeight = 884,
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
  local resolved = self:ResolveMarketKey(key)
  if self.currentMarket and resolved == self.currentMarketKey then
    return self.currentMarket
  end
  return self:EnsureMarketForWrite(resolved)
end

function DB:EmptyCharacter()
  return {
    identity = {},
    professions = {},
    -- knownRecipes[profession][spellID] = true. _legacy holds unscoped pre-v4 spells.
    knownRecipes = {},
    -- recipeBook[profession] = { scannedAt, recipes[spellID] = row }
    -- Written when Alchemy or Enchanting is open. Kept until that window opens again.
    recipeBook = {},
    recipeScans = {},
    specialisations = {},
    cooldowns = {},
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
    -- Real buys and sales only. Scans and expected profit are not trades.
    trades = {},
    tradeMailSeen = {},
    -- Open buys and listings that can still be tied to a later sale.
    tradeOpen = {},
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
  rec.recipeBook = type(rec.recipeBook) == "table" and rec.recipeBook or {}
  rec.recipeScans = type(rec.recipeScans) == "table" and rec.recipeScans or {}
  self:MigrateKnownRecipes(rec)
  rec.specialisations = type(rec.specialisations) == "table" and rec.specialisations or {}
  rec.cooldowns = type(rec.cooldowns) == "table" and rec.cooldowns or {}
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
  if type(rec.trades) ~= "table" then
    rec.trades = {}
  end
  if type(rec.tradeMailSeen) ~= "table" then
    rec.tradeMailSeen = {}
  end
  if type(rec.tradeOpen) ~= "table" then
    rec.tradeOpen = {}
  end
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
  local current = self:GetCharacterKey()
  local resolved = key or current
  if self.currentCharacter and resolved and resolved == self.currentCharacterKey then
    return self.currentCharacter
  end
  return self:EnsureCharacterForWrite(resolved)
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
  local perf = OnyxiaGold.Performance
  if perf and perf.Add then
    perf:Add("dbEnsure", 1)
  end
  if perf and perf.Begin then
    perf:Begin("database")
  end
  if type(OnyxiaGoldDB) ~= "table" then
    OnyxiaGoldDB = self:EmptyRoot()
  else
    self:EnsureShape(OnyxiaGoldDB)
  end
  if perf and perf.End then
    perf:End("database")
  end
end

function DB:ResolveMarketKey(key)
  return key or self:GetCurrentMarketKey() or "legacy"
end

-- Shape work stays on the mutation boundary. Hot reads use the cache.
function DB:EnsureMarketForWrite(key)
  self:Ensure()
  key = self:ResolveMarketKey(key)
  if type(OnyxiaGoldDB.markets[key]) ~= "table" then
    OnyxiaGoldDB.markets[key] = emptyMarket()
  end
  local market = self:EnsureMarketShape(OnyxiaGoldDB.markets[key])
  OnyxiaGoldDB.markets[key] = market
  if key == self:ResolveMarketKey(nil) then
    self.currentMarketKey = key
    self.currentMarket = market
  end
  return market
end

function DB:EnsureCharacterForWrite(key)
  self:Ensure()
  key = key or self:GetCharacterKey()
  if not key then
    return nil
  end
  if type(OnyxiaGoldDB.characters[key]) ~= "table" then
    OnyxiaGoldDB.characters[key] = self:EmptyCharacter()
  end
  local rec = self:EnsureCharacterShape(OnyxiaGoldDB.characters[key])
  OnyxiaGoldDB.characters[key] = rec
  local current = self:GetCharacterKey()
  if not current or key == current then
    self.currentCharacterKey = key
    self.currentCharacter = rec
  end
  return rec
end

function DB:InvalidateCaches()
  self.currentMarket = nil
  self.currentMarketKey = nil
  self.currentCharacter = nil
  self.currentCharacterKey = nil
  self.batch = nil
end

-- Assign pending v1 data once realm/faction are known. Never destroy it.
function DB:BindCurrentMarket()
  self:InvalidateCaches()
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
  self:InvalidateCaches()
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

local function appendPoint(history, itemID, rec)
  if type(history) ~= "table" or not rec then
    return
  end
  local list = history[itemID]
  if type(list) ~= "table" then
    list = {}
    history[itemID] = list
  end
  list[table.getn(list) + 1] = historyPoint(rec)
  local cap = OnyxiaGold.Config.MaxHistoryPoints or 30
  local n = table.getn(list)
  if n > cap then
    local fresh = {}
    local startAt = n - cap + 1
    for i = startAt, n do
      fresh[table.getn(fresh) + 1] = list[i]
    end
    history[itemID] = fresh
  end
end

function DB:AppendHistory(itemID, rec)
  if not rec then
    return
  end
  local market = self.currentMarket or self:EnsureMarketForWrite()
  if type(market.history) ~= "table" then
    market.history = {}
  end
  appendPoint(market.history, itemID, rec)
end

local function snapshotNow()
  if type(time) == "function" then
    return time()
  end
  if os and os.time then
    return os.time()
  end
  return 0
end

function DB:BeginSnapshot(mode)
  local market = self:EnsureMarketForWrite()
  if type(market.history) ~= "table" then
    market.history = {}
  end
  if type(market.latest) ~= "table" then
    market.latest = {}
  end
  local full = mode ~= "quick"
  self.batch = {
    mode = full and "full" or "quick",
    latest = full and {} or market.latest,
    history = market.history,
    count = 0,
    timestamp = snapshotNow(),
  }
  return self.batch
end

function DB:WriteSnapshotItem(itemID, rec)
  if not rec then
    return
  end
  local batch = self.batch
  if not batch then
    self:BeginSnapshot("quick")
    batch = self.batch
  end
  local row = compactRecord(itemID, rec, batch.timestamp)
  batch.latest[itemID] = row
  appendPoint(batch.history, itemID, row)
  batch.count = (batch.count or 0) + 1
end

function DB:CommitSnapshot(scanMeta, scanType)
  local batch = self.batch
  local market = self.currentMarket or self:EnsureMarketForWrite()
  if batch and batch.latest then
    market.latest = batch.latest
  end
  self.currentMarket = market
  local kind = scanType or (batch and batch.mode) or "full"
  self:AppendScanSummary(market, {
    timestamp = batch and batch.timestamp or snapshotNow(),
    scanType = kind,
    auctionCount = scanMeta and scanMeta.auctionCount or 0,
    itemCount = batch and batch.count or 0,
    queriedItems = batch and batch.count or 0,
    pages = scanMeta and scanMeta.pages or 0,
    duration = scanMeta and scanMeta.duration or 0,
    cacheMisses = scanMeta and scanMeta.cacheMisses or 0,
  })
  self.batch = nil
  if OnyxiaGold.Lots and OnyxiaGold.Lots.ClearQuoteCache then
    OnyxiaGold.Lots.ClearQuoteCache()
  end
  if OnyxiaGold.Revisions and OnyxiaGold.Revisions.Bump then
    OnyxiaGold.Revisions:Bump("market")
  end
  OnyxiaGold:Debug(string.format(
    "%s snapshot items=%d auctions=%s",
    kind,
    batch and batch.count or 0,
    tostring(scanMeta and scanMeta.auctionCount)
  ), "Database")
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
  self:BeginSnapshot("full")
  for itemID, rec in pairs(aggregates or {}) do
    self:WriteSnapshotItem(itemID, rec)
  end
  self:CommitSnapshot(scanMeta, "full")
end

-- Quick Scan: update only queried item IDs; leave the rest of latest intact.
function DB:UpdateItems(aggregates, scanMeta)
  self:BeginSnapshot("quick")
  for itemID, rec in pairs(aggregates or {}) do
    self:WriteSnapshotItem(itemID, rec)
  end
  self:CommitSnapshot(scanMeta, "quick")
end

-- Back-compat name used by older scanner complete path.
function DB:WriteLatest(aggregates, scanMeta)
  self:WriteFullSnapshot(aggregates, scanMeta)
end

function DB:GetLatest(itemID)
  local market = self.currentMarket
  if not market then
    market = self:EnsureMarketForWrite()
  end
  itemID = tonumber(itemID)
  if not itemID or not market or type(market.latest) ~= "table" then
    return nil
  end
  return market.latest[itemID]
end

function DB:GetHistory(itemID)
  local market = self.currentMarket
  if not market then
    market = self:EnsureMarketForWrite()
  end
  itemID = tonumber(itemID)
  if not itemID or not market or type(market.history) ~= "table" then
    return nil
  end
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
