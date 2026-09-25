--[[
  OnyxiaGold.UI
  Presentation only. Native 3.3.5a frames.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.UI = OnyxiaGold.UI or {}

local UI = OnyxiaGold.UI

local FRAME_WIDTH = 760
local FRAME_HEIGHT = 500
local NUM_ROWS = 14
local ROW_HEIGHT = 18
local HEADER_Y = -108
local LIST_TOP = HEADER_Y - 20

local COLS = {
  { key = "name", label = "Opportunity", width = 220, justify = "LEFT" },
  { key = "profit", label = "Profit", width = 110, justify = "RIGHT" },
  { key = "total", label = "Potential", width = 110, justify = "RIGHT" },
  { key = "roi", label = "ROI", width = 55, justify = "RIGHT" },
  { key = "crafts", label = "Crafts", width = 70, justify = "RIGHT" },
  { key = "type", label = "Type", width = 80, justify = "LEFT" },
}

local function addLabel(parent, text, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  fs:SetText(text or "")
  return fs
end

local function itemName(id)
  return OnyxiaGold.Data.GetItemName(id) or ("item:" .. tostring(id))
end

function UI:Create()
  if self.frame then
    return
  end
  OnyxiaGold.Log:Debug("UI", "Creating main window")

  local frame = CreateFrame("Frame", "OnyxiaGoldFrame", UIParent)
  frame:SetWidth(FRAME_WIDTH)
  frame:SetHeight(FRAME_HEIGHT)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetFrameStrata("HIGH")
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
  tinsert(UISpecialFrames, "OnyxiaGoldFrame")

  local title = addLabel(frame, "OnyxiaGold", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -16)

  local close = CreateFrame("Button", "OnyxiaGoldCloseButton", frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

  local logBtn = CreateFrame("Button", "OnyxiaGoldOpenLogButton", frame, "UIPanelButtonTemplate")
  logBtn:SetWidth(56)
  logBtn:SetHeight(22)
  logBtn:SetPoint("RIGHT", close, "LEFT", -4, 0)
  logBtn:SetText("Log")
  logBtn:SetScript("OnClick", function()
    OnyxiaGold.Log:Toggle()
  end)

  local quickBtn = CreateFrame("Button", "OnyxiaGoldQuickScanButton", frame, "UIPanelButtonTemplate")
  quickBtn:SetWidth(110)
  quickBtn:SetHeight(24)
  quickBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -44)
  quickBtn:SetText("Quick Scan")
  quickBtn:SetScript("OnClick", function()
    OnyxiaGold.Log:Debug("UI", "Quick Scan clicked")
    OnyxiaGold.Scanner:StartQuick()
  end)

  local fullBtn = CreateFrame("Button", "OnyxiaGoldFullScanButton", frame, "UIPanelButtonTemplate")
  fullBtn:SetWidth(90)
  fullBtn:SetHeight(24)
  fullBtn:SetPoint("LEFT", quickBtn, "RIGHT", 6, 0)
  fullBtn:SetText("Full Scan")
  fullBtn:SetScript("OnClick", function()
    OnyxiaGold.Log:Debug("UI", "Full Scan clicked")
    OnyxiaGold.Scanner:StartFull()
  end)

  local refreshBtn = CreateFrame("Button", "OnyxiaGoldRefreshButton", frame, "UIPanelButtonTemplate")
  refreshBtn:SetWidth(130)
  refreshBtn:SetHeight(24)
  refreshBtn:SetPoint("LEFT", fullBtn, "RIGHT", 6, 0)
  refreshBtn:SetText("Refresh")
  refreshBtn:SetScript("OnClick", function()
    OnyxiaGold.Log:Debug("UI", "Refresh opportunities clicked")
    OnyxiaGold.OpportunityEngine:Refresh()
  end)

  local master = CreateFrame("CheckButton", "OnyxiaGoldMasterCheck", frame, "UICheckButtonTemplate")
  master:SetWidth(24)
  master:SetHeight(24)
  master:SetPoint("LEFT", refreshBtn, "RIGHT", 10, 0)
  local masterText = getglobal("OnyxiaGoldMasterCheckText")
  if masterText then
    masterText:SetText("Transmute Master")
  end
  master:SetScript("OnClick", function(self)
    OnyxiaGold.Database:Ensure()
    OnyxiaGoldDB.settings.transmuteMaster = self:GetChecked() and true or false
    OnyxiaGold.Log:Info("UI", "Transmute Master set to " .. tostring(OnyxiaGoldDB.settings.transmuteMaster))
    OnyxiaGold.OpportunityEngine:Refresh()
  end)

  local market = addLabel(frame, "Market: —", "GameFontDisableSmall")
  market:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -74)
  market:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -74)
  market:SetJustifyH("LEFT")

  local header = CreateFrame("Frame", "OnyxiaGoldHeader", frame)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, HEADER_Y)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, HEADER_Y)
  header:SetHeight(16)

  local x = 0
  for i = 1, table.getn(COLS) do
    local col = COLS[i]
    local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", header, "LEFT", x, 0)
    fs:SetWidth(col.width)
    fs:SetJustifyH(col.justify)
    fs:SetText(col.label)
    x = x + col.width
  end

  local scroll = CreateFrame("ScrollFrame", "OnyxiaGoldListScroll", frame, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, LIST_TOP)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 42)
  scroll.offset = 0
  scroll:EnableMouseWheel(1)
  scroll:SetScript("OnVerticalScroll", function(self, value)
    value = tonumber(value) or 0
    self.offset = math.floor((value / ROW_HEIGHT) + 0.5)
    if self.offset < 0 then
      self.offset = 0
    end
    OnyxiaGold.UI:UpdateList()
  end)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local scrollbar = getglobal(self:GetName() .. "ScrollBar")
    if not scrollbar then
      return
    end
    local current = scrollbar:GetValue() or 0
    local minV, maxV = scrollbar:GetMinMaxValues()
    minV = minV or 0
    maxV = maxV or 0
    local step = ROW_HEIGHT * 3
    local newValue = current
    if delta > 0 then
      newValue = current - step
    else
      newValue = current + step
    end
    if newValue < minV then
      newValue = minV
    end
    if newValue > maxV then
      newValue = maxV
    end
    scrollbar:SetValue(newValue)
  end)
  frame:EnableMouseWheel(1)
  frame:SetScript("OnMouseWheel", function(_, delta)
    local handler = scroll:GetScript("OnMouseWheel")
    if handler then
      handler(scroll, delta)
    end
  end)

  local rows = {}
  for i = 1, NUM_ROWS do
    local row = CreateFrame("Button", "OnyxiaGoldRow" .. i, frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("LEFT", scroll, "LEFT", 4, 0)
    row:SetPoint("RIGHT", scroll, "RIGHT", -4, 0)
    if i == 1 then
      row:SetPoint("TOP", scroll, "TOP", 0, 0)
    else
      row:SetPoint("TOP", rows[i - 1], "BOTTOM", 0, 0)
    end

    if math.mod(i, 2) == 0 then
      local bg = row:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints(row)
      bg:SetTexture(1, 1, 1, 0.035)
      row.bg = bg
    end

    row.cells = {}
    local cx = 0
    for c = 1, table.getn(COLS) do
      local col = COLS[c]
      local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("LEFT", row, "LEFT", cx, 0)
      fs:SetWidth(col.width - 4)
      fs:SetJustifyH(col.justify)
      fs:SetText("")
      row.cells[col.key] = fs
      cx = cx + col.width
    end

    row:SetScript("OnEnter", function(self)
      UI:ShowOpportunityTooltip(self)
    end)
    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    rows[i] = row
  end

  local status = addLabel(frame, "Open the Auction House, then Quick Scan.", "GameFontDisable")
  status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 16)
  status:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 16)
  status:SetJustifyH("LEFT")

  self.frame = frame
  self.quickScanButton = quickBtn
  self.fullScanButton = fullBtn
  self.scanButton = quickBtn
  self.refreshButton = refreshBtn
  self.masterCheck = master
  self.marketStatus = market
  self.scroll = scroll
  self.rows = rows
  self.status = status
end

function UI:ShowOpportunityTooltip(row)
  local opp = row and row.opp
  if not opp then
    return
  end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(opp.name or "Opportunity", 1, 0.82, 0)

  if opp.inputItemIDs and opp.inputItemIDs[1] then
    GameTooltip:AddLine("Input: " .. tostring(itemName(opp.inputItemIDs[1])), 0.8, 0.8, 0.8)
  end
  GameTooltip:AddLine("First craft acquisition: " .. OnyxiaGold.FormatMoney(opp.investment), 1, 1, 1)
  if opp.expectedOutput and opp.expectedOutput ~= 1 then
    GameTooltip:AddLine(string.format("Expected output: %.2f (EV, not guaranteed)", opp.expectedOutput), 1, 0.85, 0.4)
  end
  GameTooltip:AddLine("Expected net revenue: " .. OnyxiaGold.FormatMoney(opp.netRevenue), 1, 1, 1)
  GameTooltip:AddLine("Profit / craft: " .. OnyxiaGold.FormatMoneySigned(opp.expectedProfit), 0.2, 1, 0.2)
  GameTooltip:AddLine("Maximum profitable crafts: " .. tostring(opp.maxProfitableCrafts or 0), 1, 1, 1)
  GameTooltip:AddLine("Estimated total potential: " .. OnyxiaGold.FormatMoneySigned(opp.totalExpectedProfit or 0), 0.2, 1, 0.2)
  GameTooltip:AddLine("Potential is input-depth capped, not guaranteed sales.", 0.7, 0.7, 0.7)

  GameTooltip:AddLine(" ", 1, 1, 1)
  GameTooltip:AddLine("Input stock: " .. tostring(opp.inputMarketQuantity or 0) .. " buyout units", 0.8, 0.8, 0.8)
  GameTooltip:AddLine("Output market: " .. tostring(opp.outputMarketQuantity or 0) .. " buyout units", 0.8, 0.8, 0.8)

  if opp.inputItemIDs and opp.inputItemIDs[1] then
    local id = opp.inputItemIDs[1]
    GameTooltip:AddLine("Input P10 " .. OnyxiaGold.FormatMoney(OnyxiaGold.Prices:GetP10(id) or 0)
      .. "  median " .. OnyxiaGold.FormatMoney(OnyxiaGold.Prices:GetMedian(id) or 0), 0.75, 0.75, 0.75)
  end
  if opp.outputItemIDs and opp.outputItemIDs[1] then
    local id = opp.outputItemIDs[1]
    GameTooltip:AddLine("Output P25 " .. OnyxiaGold.FormatMoney(OnyxiaGold.Prices:GetP25(id) or 0)
      .. "  median " .. OnyxiaGold.FormatMoney(OnyxiaGold.Prices:GetMedian(id) or 0), 0.75, 0.75, 0.75)
  end

  if opp.oldestDataAge then
    local stale = opp.oldestDataAge > (OnyxiaGold.Config.QuickScanStaleSeconds or 600)
    local r, g, b = 0.7, 0.7, 0.7
    if stale then
      r, g, b = 1, 0.75, 0.2
    end
    GameTooltip:AddLine("Data age: " .. OnyxiaGold.FormatAge(opp.oldestDataAge), r, g, b)
  end
  if OnyxiaGold:IsTransmuteMaster() and opp.type == "TRANSMUTE" then
    GameTooltip:AddLine("Transmute Master EV enabled", 1, 0.85, 0.4)
  end
  if opp.confidenceNotes and opp.confidenceNotes ~= "" then
    GameTooltip:AddLine("Confidence " .. string.format("%.0f%%", (opp.confidence or 1) * 100)
      .. " — " .. opp.confidenceNotes, 0.7, 0.7, 0.7, 1)
  end
  if opp.notes and opp.notes ~= "" then
    GameTooltip:AddLine(opp.notes, 0.65, 0.65, 0.65, 1)
  end
  GameTooltip:Show()
end

function UI:SetStatus(text)
  if not self.frame then
    self:Create()
  end
  self.status:SetText(text or "")
end

function UI:RefreshMarketStatus()
  if not self.marketStatus then
    return
  end
  local label = OnyxiaGold.Database:FormatMarketLabel()
  local quick = OnyxiaGold.Database:LastScanOfType("quick")
  local full = OnyxiaGold.Database:LastScanOfType("full")
  local q = quick and date("%H:%M:%S", quick.timestamp) or "—"
  local f = full and date("%H:%M:%S", full.timestamp) or "—"
  self.marketStatus:SetText(string.format("Market: %s    Quick: %s    Full: %s", label, q, f))
end

function UI:UpdateList()
  if not self.rows then
    return
  end
  local results = OnyxiaGold.OpportunityEngine:GetResults()
  local n = table.getn(results)
  FauxScrollFrame_Update(self.scroll, n, NUM_ROWS, ROW_HEIGHT)
  local offset = FauxScrollFrame_GetOffset(self.scroll) or 0

  for i = 1, NUM_ROWS do
    local row = self.rows[i]
    local opp = results[offset + i]
    row.opp = opp
    if opp then
      row:Show()
      row.cells.name:SetText(opp.name or "")
      row.cells.profit:SetText(OnyxiaGold.FormatMoneySigned(opp.expectedProfit))
      row.cells.total:SetText(OnyxiaGold.FormatMoneySigned(opp.totalExpectedProfit or opp.expectedProfit))
      row.cells.roi:SetText(OnyxiaGold.FormatPercent(opp.roi))
      row.cells.crafts:SetText(tostring(opp.maxProfitableCrafts or opp.availableQuantity or 0))
      row.cells.type:SetText(opp.typeLabel or opp.type or "")
    else
      row:Hide()
    end
  end
end

function UI:Refresh()
  if not self.frame then
    self:Create()
  end
  if self.masterCheck then
    if OnyxiaGold:IsTransmuteMaster() then
      self.masterCheck:SetChecked(1)
    else
      self.masterCheck:SetChecked(0)
    end
  end

  self:RefreshMarketStatus()

  local results = OnyxiaGold.OpportunityEngine:GetResults()
  local n = table.getn(results)

  if OnyxiaGold.Scanner:IsScanning() then
    -- Scanner owns the status line while a scan is in progress.
  elseif n == 0 then
    local market = OnyxiaGold.Database:GetMarket()
    if not market or not market.latest or not next(market.latest) then
      self:SetStatus("No price data yet. Open the Auction House and click Quick Scan.")
    else
      self:SetStatus("No positive opportunities on current market data.")
    end
  else
    self:SetStatus(tostring(n) .. " opportunities ranked by potential profit (input-depth cap).")
  end

  self:UpdateList()
end

function UI:Show()
  if not self.frame then
    self:Create()
  end
  self:Refresh()
  self.frame:Show()
  OnyxiaGold.Log:Debug("UI", "Main window shown")
end

function UI:Hide()
  if self.frame then
    self.frame:Hide()
  end
end

function UI:Toggle()
  if not self.frame then
    self:Create()
  end
  if self.frame:IsShown() then
    self:Hide()
  else
    self:Show()
  end
end
