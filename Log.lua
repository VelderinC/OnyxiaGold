--[[
  OnyxiaGold.Log
  Persistent ring-buffer logging for development and in-game diagnosis.

  Chat stays quiet during scans. Every DEBUG+ line is still stored so it can
  be copied from the log window and pasted back for debugging.

  /og log         toggle log window
  /og log copy    open and select all (Ctrl+C)
  /og log clear   wipe the buffer
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Log = OnyxiaGold.Log or {}

local Log = OnyxiaGold.Log

local LEVEL = {
  TRACE = 1,
  DEBUG = 2,
  INFO = 3,
  WARN = 4,
  ERROR = 5,
}

local LEVEL_COLOR = {
  TRACE = "|cff888888",
  DEBUG = "|cff66ccff",
  INFO = "|cff33ff99",
  WARN = "|cffffcc00",
  ERROR = "|cffff4040",
}

local writing = false
local window

local function maxLines()
  return (OnyxiaGold.Config and OnyxiaGold.Config.MaxLogLines) or 800
end

local lastClock
local lastFrac = -1

-- GetTime's tenth can move backwards against date() inside one wall second.
local function clockStamp()
  local clock = date("%H:%M:%S")
  local frac = 0
  if GetTime then
    frac = math.floor((GetTime() * 10) % 10)
  end
  if clock ~= lastClock then
    lastClock = clock
    lastFrac = frac
  elseif frac < lastFrac then
    frac = lastFrac
  else
    lastFrac = frac
  end
  return string.format("%s.%d", clock, frac)
end

function Log:EnsureDB()
  if type(OnyxiaGoldDB) ~= "table" then
    return nil
  end
  if type(OnyxiaGoldDB.log) ~= "table" then
    OnyxiaGoldDB.log = { session = 0, lines = {} }
  end
  if type(OnyxiaGoldDB.log.lines) ~= "table" then
    OnyxiaGoldDB.log.lines = {}
  end
  if not OnyxiaGoldDB.log.session then
    OnyxiaGoldDB.log.session = 0
  end
  return OnyxiaGoldDB.log
end

function Log:Count()
  local db = self:EnsureDB()
  if not db then
    return 0
  end
  return table.getn(db.lines)
end

function Log:ShouldEcho(levelName)
  local n = LEVEL[levelName] or LEVEL.DEBUG
  if n >= LEVEL.INFO then
    return true
  end
  if n >= LEVEL.DEBUG and OnyxiaGold.IsDebug and OnyxiaGold:IsDebug() then
    return true
  end
  return false
end

function Log:ShouldStore(levelName)
  local n = LEVEL[levelName] or LEVEL.DEBUG
  if n >= LEVEL.DEBUG then
    return true
  end
  -- TRACE is stored only while debug chat is on, so SavedVariables stay bounded.
  return OnyxiaGold.IsDebug and OnyxiaGold:IsDebug()
end

function Log:Write(levelName, module, message)
  if writing then
    return
  end
  writing = true

  levelName = string.upper(tostring(levelName or "DEBUG"))
  if not LEVEL[levelName] then
    levelName = "DEBUG"
  end
  module = tostring(module or "Core")
  message = tostring(message or "")

  local line = string.format("%s [%s] %s: %s", clockStamp(), levelName, module, message)

  if self:ShouldStore(levelName) then
    local db = self:EnsureDB()
    if db then
      table.insert(db.lines, line)
      local cap = maxLines()
      while table.getn(db.lines) > cap do
        table.remove(db.lines, 1)
      end
    end
  end

  if self:ShouldEcho(levelName) then
    local color = LEVEL_COLOR[levelName] or "|cff33ff99"
    DEFAULT_CHAT_FRAME:AddMessage(color .. "OnyxiaGold|r |cffaaaaaa" .. module .. ":|r " .. message)
  end

  if window and window:IsShown() and window.autoRefresh then
    self:RefreshWindow()
  end

  writing = false
end

function Log:Trace(module, message)
  self:Write("TRACE", module, message)
end

function Log:Debug(module, message)
  self:Write("DEBUG", module, message)
end

function Log:Info(module, message)
  self:Write("INFO", module, message)
end

function Log:Warn(module, message)
  self:Write("WARN", module, message)
end

function Log:Error(module, message)
  self:Write("ERROR", module, message)
end

function Log:Dump()
  local db = self:EnsureDB()
  if not db or table.getn(db.lines) == 0 then
    return "(OnyxiaGold log is empty)"
  end
  return table.concat(db.lines, "\n")
end

function Log:Clear()
  local db = self:EnsureDB()
  if db then
    db.lines = {}
  end
  self:Write("INFO", "Log", "Log buffer cleared")
  self:RefreshWindow()
end

function Log:StartSession()
  local db = self:EnsureDB()
  if db then
    db.session = (db.session or 0) + 1
  end

  local version, build, buildDate, toc = GetBuildInfo()
  local player = UnitName("player") or "?"
  local realm = GetRealmName() or "?"
  local locale = GetLocale() or "?"
  local session = db and db.session or 0

  self:Info("Core", "Session " .. tostring(session) .. " start v" .. tostring(OnyxiaGold.Version))
  self:Debug("Core", string.format(
    "client=%s build=%s toc=%s locale=%s realm=%s player=%s",
    tostring(version), tostring(build), tostring(toc), locale, realm, player
  ))

  if OnyxiaGoldDB then
    local latestCount = 0
    local scanCount = 0
    local marketKey = OnyxiaGold.Database and OnyxiaGold.Database:GetCurrentMarketKey() or "?"
    if OnyxiaGold.Database then
      local market = OnyxiaGold.Database:GetMarket()
      if market and type(market.latest) == "table" then
        for _ in pairs(market.latest) do
          latestCount = latestCount + 1
        end
      end
      if market and type(market.scans) == "table" then
        scanCount = table.getn(market.scans)
      end
    end
    self:Debug("Database", string.format(
      "version=%s market=%s latestItems=%d scanSummaries=%d debug=%s transmuteMaster=%s ahCut=%.4f",
      tostring(OnyxiaGoldDB.version),
      tostring(marketKey),
      latestCount,
      scanCount,
      tostring(OnyxiaGoldDB.settings and OnyxiaGoldDB.settings.debug),
      tostring(OnyxiaGold:IsTransmuteMaster()),
      OnyxiaGold:GetAuctionHouseCut()
    ))
  end

  local conversions = OnyxiaGold.Data and OnyxiaGold.Data.Conversions
  local transmutes = OnyxiaGold.Data and OnyxiaGold.Data.Transmutes
  self:Debug("Data", string.format(
    "conversions=%d transmutes=%d",
    conversions and table.getn(conversions) or 0,
    transmutes and table.getn(transmutes) or 0
  ))
end

function Log:LogWatchedPrices()
  local items = OnyxiaGold.Data and OnyxiaGold.Data.Items
  if not items or not OnyxiaGold.Prices then
    return
  end
  local keys = {
    "SARONITE_BAR", "TITANIUM_BAR",
    "GREATER_COSMIC_ESSENCE", "LESSER_COSMIC_ESSENCE",
    "GREATER_PLANAR_ESSENCE", "LESSER_PLANAR_ESSENCE",
    "GREATER_ETERNAL_ESSENCE", "LESSER_ETERNAL_ESSENCE",
    "SMALL_PRISMATIC_SHARD", "LARGE_PRISMATIC_SHARD",
    "SMALL_DREAM_SHARD", "DREAM_SHARD",
  }
  for i = 1, table.getn(keys) do
    local def = items[keys[i]]
    if def then
      local rec = OnyxiaGold.Prices:GetRecord(def.id)
      if rec then
        self:Debug("Prices", string.format(
          "%s id=%d min=%s p25=%s med=%s totalQty=%s buyoutQty=%s covered=%s bidOnlyQty=%s auctions=%s buyoutAuctions=%s depth=%s",
          def.name,
          def.id,
          tostring(rec.minUnitBuyout),
          tostring(rec.p25UnitBuyout),
          tostring(rec.medianUnitBuyout),
          tostring(rec.totalQuantity or rec.quantity),
          tostring(rec.buyoutQuantity),
          tostring(rec.depthCoveredQuantity),
          tostring(rec.bidOnlyQuantity),
          tostring(rec.auctionCount),
          tostring(rec.buyoutAuctionCount),
          tostring(rec.depth and table.getn(rec.depth) or 0)
        ))
      else
        self:Debug("Prices", def.name .. " id=" .. tostring(def.id) .. " missing from latest scan")
      end
    end
  end
end

function Log:CreateWindow()
  if window then
    return window
  end

  local frame = CreateFrame("Frame", "OnyxiaGoldLogFrame", UIParent)
  frame:SetWidth(640)
  frame:SetHeight(420)
  frame:SetPoint("CENTER", UIParent, "CENTER", 40, -20)
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function()
    frame:StartMoving()
  end)
  frame:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
  end)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  frame:Hide()
  tinsert(UISpecialFrames, "OnyxiaGoldLogFrame")
  frame.autoRefresh = true

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -16)
  title:SetText("OnyxiaGold Log")

  local close = CreateFrame("Button", "OnyxiaGoldLogClose", frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -38)
  hint:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, -38)
  hint:SetJustifyH("LEFT")
  hint:SetText("Click the text, then Ctrl+A and Ctrl+C. Paste the dump in Discord/chat with me.")

  local scroll = CreateFrame("ScrollFrame", "OnyxiaGoldLogScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -58)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 48)

  local edit = CreateFrame("EditBox", "OnyxiaGoldLogEdit", scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(GameFontHighlightSmall)
  edit:SetWidth(560)
  edit:SetHeight(300)
  edit:SetMaxLetters(999999)
  edit:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  edit:SetScript("OnEditFocusGained", function(self)
    -- Keep the dump selectable; do not treat it as a live editor.
  end)
  edit:SetScript("OnTextChanged", function(self)
    if self.freeze and self.frozenText and self:GetText() ~= self.frozenText then
      self:SetText(self.frozenText)
    end
  end)
  scroll:SetScrollChild(edit)

  local function makeButton(name, text, x)
    local btn = CreateFrame("Button", name, frame, "UIPanelButtonTemplate")
    btn:SetWidth(90)
    btn:SetHeight(22)
    btn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, 16)
    btn:SetText(text)
    return btn
  end

  local refreshBtn = makeButton("OnyxiaGoldLogRefresh", "Refresh", 20)
  refreshBtn:SetScript("OnClick", function()
    Log:RefreshWindow()
  end)

  local copyBtn = makeButton("OnyxiaGoldLogCopy", "Select All", 118)
  copyBtn:SetScript("OnClick", function()
    Log:SelectAll()
  end)

  local clearBtn = makeButton("OnyxiaGoldLogClear", "Clear", 216)
  clearBtn:SetScript("OnClick", function()
    Log:Clear()
  end)

  window = frame
  window.edit = edit
  window.scroll = scroll
  return frame
end

function Log:RefreshWindow()
  if not window or not window.edit then
    return
  end
  local text = self:Dump()
  local edit = window.edit
  edit.freeze = false
  edit:SetText(text)
  edit.frozenText = text
  edit.freeze = true
  local lines = self:Count()
  if lines < 1 then
    lines = 1
  end
  edit:SetHeight(math.max(320, lines * 14 + 20))
  if window.scroll and window.scroll.UpdateScrollChildRect then
    window.scroll:UpdateScrollChildRect()
  end
end

function Log:SelectAll()
  self:Show()
  if window and window.edit then
    window.edit:SetFocus()
    window.edit:HighlightText()
  end
  self:Debug("Log", "Log text selected for copy")
end

function Log:Show()
  self:CreateWindow()
  self:RefreshWindow()
  window:Show()
end

function Log:Hide()
  if window then
    window:Hide()
  end
end

function Log:Toggle()
  self:CreateWindow()
  if window:IsShown() then
    self:Hide()
  else
    self:Show()
  end
end

function Log:HandleSlash(rest)
  rest = string.lower(strtrim(rest or ""))
  if rest == "" then
    self:Toggle()
  elseif rest == "copy" then
    self:SelectAll()
  elseif rest == "clear" then
    self:Clear()
  elseif rest == "dump" then
    self:Show()
    self:Info("Log", "Opened log window (" .. tostring(self:Count()) .. " lines). Use Select All then Ctrl+C.")
  else
    self:Info("Log", "Commands: /og log, /og log copy, /og log clear")
  end
end

local originalErrorHandler
local hooked = false

function Log:HookErrors()
  if hooked then
    return
  end
  hooked = true
  if type(geterrorhandler) == "function" then
    originalErrorHandler = geterrorhandler()
  end
  if type(seterrorhandler) == "function" then
    seterrorhandler(function(err)
      Log:Error("Lua", tostring(err))
      if originalErrorHandler then
        originalErrorHandler(err)
      end
    end)
    self:Debug("Log", "Lua error handler hooked")
  else
    self:Warn("Log", "seterrorhandler is not available")
  end
end
