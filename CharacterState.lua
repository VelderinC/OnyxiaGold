--[[
  OnyxiaGold.CharacterState
  Identity, profession snapshot coordination, and 3.3.5 personal events.
  Character observations are keyed by realm|faction|name.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.CharacterState = OnyxiaGold.CharacterState or {}

local State = OnyxiaGold.CharacterState

local BAG_THROTTLE = 0.25
local TRADE_THROTTLE = 0.35
local bagDirty = false
local bagElapsed = 0
local tradeDirty = false
local tradeElapsed = 0

local function rec()
  return OnyxiaGold.Database:GetCharacter()
end

function State:GetKey()
  return OnyxiaGold.Database:GetCharacterKey()
end

function State:GetRecord()
  return rec()
end

function State:RefreshIdentity()
  local row = rec()
  if not row then
    return nil
  end
  local name = UnitName("player")
  local realm = GetRealmName()
  local faction = UnitFactionGroup("player")
  local className, classFile = UnitClass("player")
  local level = UnitLevel("player")
  row.identity = {
    name = name,
    realm = realm,
    faction = faction,
    class = classFile,
    className = className,
    level = level,
    key = self:GetKey(),
    englishLocale = GetLocale and GetLocale() or "enUS",
  }
  row.stateTimestamps.identity = time()
  return row.identity
end

function State:GetIdentity()
  local row = rec()
  if row and row.identity and row.identity.name then
    return row.identity
  end
  return self:RefreshIdentity()
end

function State:ClassFile()
  local id = self:GetIdentity()
  return id and id.class or nil
end

function State:Level()
  local id = self:GetIdentity()
  return id and id.level or 0
end

local opportunitiesRebuilt = false

local function marketHasData()
  local db = OnyxiaGold.Database
  if not db or not db.GetMarket then
    return false
  end
  local market = db:GetMarket()
  return type(market) == "table" and type(market.latest) == "table" and next(market.latest) ~= nil
end

local function nowSeconds()
  if type(GetTime) == "function" then
    return tonumber(GetTime()) or 0
  end
  return 0
end

-- Queue one domain job. Event handlers must not run it on the UI thread.
-- market rebuilds candidates. plan reallocates them. ui only paints.
local function scheduleRefresh(kind, reason)
  kind = kind or "plan"
  if kind == "engine" then
    kind = "market"
  elseif kind == "planner" then
    kind = "plan"
  end
  if kind ~= "market" then
    if OnyxiaGold.Scanner and OnyxiaGold.Scanner.IsScanning and OnyxiaGold.Scanner:IsScanning() then
      if OnyxiaGold.UI and OnyxiaGold.UI.frame and OnyxiaGold.UI.RefreshHeader then
        OnyxiaGold.UI:RefreshHeader()
      end
      return
    end
  end
  local clock = OnyxiaGold.RefreshSchedule
  if clock and clock.Push then
    clock:Push(nowSeconds(), kind, reason)
    return
  end
  if kind == "market" and OnyxiaGold.CandidateCache and OnyxiaGold.CandidateCache.Build then
    OnyxiaGold.CandidateCache:Build()
  elseif kind == "market" and OnyxiaGold.OpportunityEngine and OnyxiaGold.OpportunityEngine.Refresh then
    OnyxiaGold.OpportunityEngine:Refresh()
  end
  if kind ~= "ui" and OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.Refresh then
    OnyxiaGold.ActionPlanner:Refresh()
  end
  if OnyxiaGold.UI and OnyxiaGold.UI.frame and OnyxiaGold.UI.Refresh then
    OnyxiaGold.UI:Refresh()
  end
end

local function pumpRefresh()
  local clock = OnyxiaGold.RefreshSchedule
  if clock and clock.Begin then
    clock:Begin(nowSeconds())
  end
end

-- One rebuild after login or /reload. Later bag and money events stay on the planner.
local function tryRebuildOpportunities()
  local Lots = OnyxiaGold.Lots
  if not Lots or not Lots.ShouldRebuildOpportunities then
    return false
  end
  local row = rec()
  local ready = Lots.ShouldRebuildOpportunities({
    alreadyRan = opportunitiesRebuilt,
    database = type(OnyxiaGoldDB) == "table" and OnyxiaGoldDB.version and true or false,
    character = row and row.identity and row.identity.name and true or false,
    inventory = row and row.inventory and row.inventory.timestamp and true or false,
    capabilities = row and type(row.professions) == "table" and true or false,
    hasMarket = marketHasData(),
  })
  if not ready then
    return false
  end
  opportunitiesRebuilt = true
  scheduleRefresh("market", "login")
  return true
end

local function refreshPlannerSoon(reason)
  scheduleRefresh("plan", reason)
end

local function refreshWindow(reason)
  scheduleRefresh("ui", reason)
end

local function noteOwnedChange(reason)
  local owned = OnyxiaGold.OwnedAuctions
  if not owned or not owned.Scan then
    refreshWindow(reason)
    return
  end
  local before = owned.Fingerprint and owned:Fingerprint() or ""
  owned:Scan()
  local after = owned.Fingerprint and owned:Fingerprint() or before
  if before ~= after then
    refreshPlannerSoon(reason)
  else
    refreshWindow(reason)
  end
end

function State:OnLogin()
  self:RefreshIdentity()
  if OnyxiaGold.Capital then
    OnyxiaGold.Capital:RefreshLiquid()
  end
  if OnyxiaGold.Inventory then
    OnyxiaGold.Inventory:ScanBags()
    if OnyxiaGold.Inventory.ScanEquipment then
      OnyxiaGold.Inventory:ScanEquipment()
    end
  end
  if OnyxiaGold.Capabilities then
    OnyxiaGold.Capabilities:ScanProfessions()
    OnyxiaGold.Capabilities:ScanSpecialisations()
  end
  OnyxiaGold.Log:Info("Character", "Bound " .. tostring(self:GetKey()))
  if not tryRebuildOpportunities() then
    refreshPlannerSoon()
  end
end

function State:OnEvent(event, arg1)
  if type(OnyxiaGoldDB) ~= "table" or not OnyxiaGoldDB.version then
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then
    self:RefreshIdentity()
    if OnyxiaGold.Capital then
      OnyxiaGold.Capital:RefreshLiquid()
    end
    if OnyxiaGold.Inventory then
      OnyxiaGold.Inventory:ScanBags()
      if OnyxiaGold.Inventory.ScanEquipment then
        OnyxiaGold.Inventory:ScanEquipment()
      end
    end
    if OnyxiaGold.Capabilities then
      OnyxiaGold.Capabilities:ScanProfessions()
      OnyxiaGold.Capabilities:ScanSpecialisations()
    end
    if not tryRebuildOpportunities() then
      refreshPlannerSoon("enter")
    end
  elseif event == "PLAYER_LEVEL_UP" then
    self:RefreshIdentity()
    refreshPlannerSoon("level")
  elseif event == "PLAYER_MONEY" then
    if OnyxiaGold.Capital then
      OnyxiaGold.Capital:RefreshLiquid()
    end
    refreshPlannerSoon("money")
  elseif event == "BAG_UPDATE" then
    bagDirty = true
    bagElapsed = 0
  elseif event == "SKILL_LINES_CHANGED" then
    if OnyxiaGold.Capabilities then
      OnyxiaGold.Capabilities:ScanProfessions()
    end
    refreshPlannerSoon("skill")
  elseif event == "TRADE_SKILL_SHOW" then
    tradeDirty = true
    tradeElapsed = 0
  elseif event == "TRADE_SKILL_UPDATE" then
    if OnyxiaGold.Capabilities and OnyxiaGold.Capabilities.scanInProgress then
      return
    end
    if GetTime and OnyxiaGold.Capabilities and OnyxiaGold.Capabilities.suppressTradeUntil
      and GetTime() < OnyxiaGold.Capabilities.suppressTradeUntil then
      return
    end
    tradeDirty = true
    tradeElapsed = 0
  elseif event == "TRADE_SKILL_CLOSE" then
    tradeDirty = false
  elseif event == "MAIL_SHOW" then
    if OnyxiaGold.Mail then
      OnyxiaGold.Mail:OnMailboxOpened()
    end
  elseif event == "MAIL_INBOX_UPDATE" then
    if OnyxiaGold.Mail then
      OnyxiaGold.Mail:ScanInbox()
    end
    refreshPlannerSoon("mail")
  elseif event == "MAIL_CLOSED" then
    if OnyxiaGold.Mail then
      OnyxiaGold.Mail:OnMailboxClosed()
    end
    refreshWindow("mail-closed")
  elseif event == "AUCTION_HOUSE_SHOW" then
    noteOwnedChange("ah-show")
  elseif event == "AUCTION_OWNED_LIST_UPDATE" then
    noteOwnedChange("owned")
  elseif event == "AUCTION_HOUSE_CLOSED" then
    if OnyxiaGold.OwnedAuctions then
      OnyxiaGold.OwnedAuctions:OnClosed()
    end
    refreshWindow("ah-closed")
  elseif event == "BANKFRAME_OPENED" then
    if OnyxiaGold.Inventory then
      OnyxiaGold.Inventory:ScanBank()
    end
    refreshPlannerSoon("bank")
  elseif event == "BANKFRAME_CLOSED" then
    -- last bank snapshot already persisted on open/scan
  end
end

local eventFrame = CreateFrame("Frame")
local EVENTS = {
  "PLAYER_ENTERING_WORLD",
  "PLAYER_MONEY",
  "BAG_UPDATE",
  "SKILL_LINES_CHANGED",
  "TRADE_SKILL_SHOW",
  "TRADE_SKILL_UPDATE",
  "TRADE_SKILL_CLOSE",
  "MAIL_SHOW",
  "MAIL_INBOX_UPDATE",
  "MAIL_CLOSED",
  "AUCTION_HOUSE_SHOW",
  "AUCTION_OWNED_LIST_UPDATE",
  "AUCTION_HOUSE_CLOSED",
  "PLAYER_LEVEL_UP",
  "BANKFRAME_OPENED",
  "BANKFRAME_CLOSED",
}
for i = 1, table.getn(EVENTS) do
  eventFrame:RegisterEvent(EVENTS[i])
end
eventFrame:SetScript("OnEvent", function(self, event, arg1)
  OnyxiaGold.CharacterState:OnEvent(event, arg1)
end)
eventFrame:SetScript("OnUpdate", function(self, elapsed)
  if type(OnyxiaGoldDB) ~= "table" or not OnyxiaGoldDB.version then
    return
  end
  elapsed = tonumber(elapsed) or 0
  if bagDirty then
    bagElapsed = bagElapsed + elapsed
    if bagElapsed >= BAG_THROTTLE then
      bagDirty = false
      bagElapsed = 0
      if OnyxiaGold.Inventory then
        OnyxiaGold.Inventory:ScanBags()
        if BankFrame and BankFrame:IsShown() then
          OnyxiaGold.Inventory:ScanBank()
        end
      end
      refreshPlannerSoon("bags")
    end
  end
  if tradeDirty then
    tradeElapsed = tradeElapsed + elapsed
    if tradeElapsed >= TRADE_THROTTLE then
      tradeDirty = false
      tradeElapsed = 0
      local replaced = false
      if OnyxiaGold.Capabilities then
        replaced = OnyxiaGold.Capabilities:ScanOpenTradeSkill() and true or false
      end
      if replaced then
        if OnyxiaGold.Revisions and OnyxiaGold.Revisions.Bump then
          OnyxiaGold.Revisions:Bump("recipe")
        end
        scheduleRefresh("market", "recipes")
      else
        refreshWindow("profession")
      end
    end
  end
  pumpRefresh()
end)
