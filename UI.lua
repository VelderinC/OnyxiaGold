--[[
  OnyxiaGold.UI
  Native 3.3.5a frames. No Ace3 or other addon dependencies.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.UI = OnyxiaGold.UI or {}

local UI = OnyxiaGold.UI

local FRAME_WIDTH = 760
local FRAME_HEIGHT = 480
local NUM_ROWS = 14
local ROW_HEIGHT = 18
local HEADER_Y = -78
local LIST_TOP = HEADER_Y - 22

local COLS = {
  { key = "name", label = "Opportunity", width = 230, justify = "LEFT" },
  { key = "investment", label = "Investment", width = 120, justify = "RIGHT" },
  { key = "profit", label = "Expected Profit", width = 130, justify = "RIGHT" },
  { key = "roi", label = "ROI", width = 60, justify = "RIGHT" },
  { key = "available", label = "Available", width = 80, justify = "RIGHT" },
  { key = "type", label = "Type", width = 80, justify = "LEFT" },
}

local function addLabel(parent, text, template, x, y, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  if justify then
    fs:SetJustifyH(justify)
  end
  fs:SetText(text or "")
  return fs
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

  local title = addLabel(frame, "OnyxiaGold", "GameFontNormalLarge", 20, -16)
  title:SetPoint("TOP", frame, "TOP", 0, -16)
  title:SetPoint("LEFT", frame, "LEFT", 20, 0)

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

  local scanBtn = CreateFrame("Button", "OnyxiaGoldScanButton", frame, "UIPanelButtonTemplate")
  scanBtn:SetWidth(160)
  scanBtn:SetHeight(24)
  scanBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -44)
  scanBtn:SetText("Scan Auction House")
  scanBtn:SetScript("OnClick", function()
    OnyxiaGold.Log:Debug("UI", "Scan button clicked")
    OnyxiaGold.Scanner:Start()
  end)

  local refreshBtn = CreateFrame("Button", "OnyxiaGoldRefreshButton", frame, "UIPanelButtonTemplate")
  refreshBtn:SetWidth(160)
  refreshBtn:SetHeight(24)
  refreshBtn:SetPoint("LEFT", scanBtn, "RIGHT", 8, 0)
  refreshBtn:SetText("Refresh Opportunities")
  refreshBtn:SetScript("OnClick", function()
    OnyxiaGold.Log:Debug("UI", "Refresh opportunities clicked")
    OnyxiaGold.OpportunityEngine:Refresh()
  end)

  local master = CreateFrame("CheckButton", "OnyxiaGoldMasterCheck", frame, "UICheckButtonTemplate")
  master:SetWidth(24)
  master:SetHeight(24)
  master:SetPoint("LEFT", refreshBtn, "RIGHT", 12, 0)
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

  local header = CreateFrame("Frame", "OnyxiaGoldHeader", frame)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, HEADER_Y)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, HEADER_Y)
  header:SetHeight(18)

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
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 48)
  scroll.offset = 0
  scroll:EnableMouseWheel(1)
  scroll:SetScript("OnVerticalScroll", function(self, value)
    -- 3.3.5a FauxScrollFrame_OnVerticalScroll still reads globals this/arg1.
    this = self
    arg1 = value
    FauxScrollFrame_OnVerticalScroll(ROW_HEIGHT, function()
      OnyxiaGold.UI:UpdateList()
    end)
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
      bg:SetTexture(1, 1, 1, 0.04)
      row.bg = bg
    end

    row.cells = {}
    local cx = 0
    for c = 1, table.getn(COLS) do
      local col = COLS[c]
      local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("LEFT", row, "LEFT", cx, 0)
      fs:SetWidth(col.width)
      fs:SetJustifyH(col.justify)
      fs:SetText("")
      row.cells[col.key] = fs
      cx = cx + col.width
    end

    row:SetScript("OnEnter", function(self)
      if not self.opp then
        return
      end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.opp.name, 1, 0.82, 0)
      if self.opp.notes and self.opp.notes ~= "" then
        GameTooltip:AddLine(self.opp.notes, 0.9, 0.9, 0.9, 1)
      end
      GameTooltip:AddLine("Investment: " .. OnyxiaGold.FormatMoney(self.opp.investment), 1, 1, 1)
      GameTooltip:AddLine("Gross: " .. OnyxiaGold.FormatMoney(self.opp.grossRevenue), 1, 1, 1)
      GameTooltip:AddLine("Net after AH cut: " .. OnyxiaGold.FormatMoney(self.opp.netRevenue), 1, 1, 1)
      GameTooltip:AddLine("Expected profit: " .. OnyxiaGold.FormatMoneySigned(self.opp.expectedProfit), 1, 1, 1)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    rows[i] = row
  end

  local status = addLabel(frame, "Open the Auction House, then scan.", "GameFontDisable", 20, 0)
  status:ClearAllPoints()
  status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 18)
  status:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 18)
  status:SetJustifyH("LEFT")

  self.frame = frame
  self.scanButton = scanBtn
  self.refreshButton = refreshBtn
  self.masterCheck = master
  self.scroll = scroll
  self.rows = rows
  self.status = status
end

function UI:SetStatus(text)
  if not self.frame then
    self:Create()
  end
  self.status:SetText(text or "")
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
      row.cells.investment:SetText(OnyxiaGold.FormatMoney(opp.investment))
      row.cells.profit:SetText(OnyxiaGold.FormatMoneySigned(opp.expectedProfit))
      row.cells.roi:SetText(OnyxiaGold.FormatPercent(opp.roi))
      row.cells.available:SetText(tostring(opp.availableQuantity or 0))
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

  local results = OnyxiaGold.OpportunityEngine:GetResults()
  local n = table.getn(results)
  local scanInfo = ""
  if OnyxiaGoldDB and OnyxiaGoldDB.scans and table.getn(OnyxiaGoldDB.scans) > 0 then
    local last = OnyxiaGoldDB.scans[table.getn(OnyxiaGoldDB.scans)]
    if last and last.timestamp then
      scanInfo = "Last scan " .. date("%H:%M:%S", last.timestamp) .. " · "
    end
  end

  if OnyxiaGold.Scanner:IsScanning() then
    -- Scanner owns the status line while a scan is in progress.
  elseif n == 0 then
    if not OnyxiaGoldDB or not OnyxiaGoldDB.latest or not next(OnyxiaGoldDB.latest) then
      self:SetStatus("No price data yet. Open the Auction House and click Scan Auction House.")
    else
      self:SetStatus(scanInfo .. "No positive opportunities on the current scan.")
    end
  else
    self:SetStatus(scanInfo .. tostring(n) .. " opportunities ranked by expected profit.")
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
