--[[
  OnyxiaGold.UI
  Presentation only. Native 3.3.5a frames.
  Header is personal economic state. Main list is what to do now.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.UI = OnyxiaGold.UI or {}

local UI = OnyxiaGold.UI

local FRAME_WIDTH = 1080
local FRAME_HEIGHT = 884
local MIN_WIDTH = 1080
local MIN_HEIGHT = 480
local MAX_WIDTH = 1600
local MAX_HEIGHT = 1200
local NUM_ROWS = 8
local ROW_HEIGHT = 58
local COL_GAP = 12
local PAD = 14
-- Buy and a later Post button share this strip on the right of each row.
local BUTTON_GUTTER = 72
local BUTTON_HEIGHT = 22

local COL_WIDTH = {
  profit = 108,
  cash = 120,
  crafts = 56,
  type = 100,
}

local COLS = {
  { key = "name", label = "Action", width = 560, justify = "LEFT" },
  { key = "profit", label = "Profit", width = 112, justify = "RIGHT" },
  { key = "cash", label = "Cash", width = 124, justify = "RIGHT" },
  { key = "crafts", label = "Qty", width = 52, justify = "RIGHT" },
  { key = "type", label = "Type", width = 92, justify = "LEFT" },
}

local function addLabel(parent, text, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  fs:SetText(text or "")
  return fs
end

local function itemName(id)
  return OnyxiaGold.Data.GetItemName(id) or ("item:" .. tostring(id))
end

local function isBuyKind(action)
  local kind = action and action.kind
  return kind == "BUY" or kind == "BUY_AND_CRAFT"
end

-- A session step already says the one thing to do. A combined buy row
-- still names the buy, the craft, and the post.
local function actionInstruction(action)
  if not action then
    return ""
  end
  if action.sessionStep then
    return action.name or ""
  end
  if action.kind ~= "BUY_AND_CRAFT" then
    return action.name or ""
  end
  local buy = action.name or "Buy"
  local opp = action.sourceOpp
  local crafts = tonumber(action.crafts) or 0
  if crafts <= 0 or type(opp) ~= "table" then
    return buy
  end
  local per = tonumber(opp.outputCount) or 1
  if per < 1 then
    per = 1
  end
  local units = math.floor(crafts * per + 0.5)
  if units < 1 then
    return buy
  end
  local outID = opp.outputItemIDs and opp.outputItemIDs[1]
  local outName = outID and OnyxiaGold.Data.GetItemName(outID) or nil
  if not outName or outName == "" then
    if action.detail and action.detail ~= "" then
      return buy .. ", " .. action.detail
    end
    return buy
  end
  local pronoun = "them"
  if units == 1 then
    pronoun = "it"
  end
  return string.format("%s, convert into %d %s, then post %s.", buy, units, outName, pronoun)
end

-- Convert decision only. The profit breakdown stays on the row and is not a trade.
function UI:ActionNote(action)
  local text = actionInstruction(action)
  if type(text) ~= "string" or text == "" then
    return nil
  end
  if string.sub(text, -1) == "." then
    text = string.sub(text, 1, -2)
  end
  return text
end

local function formatCount(n)
  n = tonumber(n) or 0
  local nearest = math.floor(n + 0.5)
  if math.abs(n - nearest) < 0.001 then
    return tostring(nearest)
  end
  return string.format("%.2f", n)
end

-- Plain gold text. Keeps copper when it is part of the price.
local function formatPlainCash(copper)
  copper = tonumber(copper) or 0
  local negative = copper < 0
  if negative then
    copper = -copper
  end
  copper = math.floor(copper + 0.5)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local text
  if g > 0 and s > 0 and c > 0 then
    text = string.format("%dg %ds %dc", g, s, c)
  elseif g > 0 and s > 0 then
    text = string.format("%dg %ds", g, s)
  elseif g > 0 and c > 0 then
    text = string.format("%dg %dc", g, c)
  elseif g > 0 then
    text = string.format("%dg", g)
  elseif s > 0 and c > 0 then
    text = string.format("%ds %dc", s, c)
  elseif s > 0 then
    text = string.format("%ds", s)
  else
    text = string.format("%dc", c)
  end
  if negative then
    return "-" .. text
  end
  return text
end

local function profitBreakdownText(action)
  local info = action and action.breakdown
  if type(info) ~= "table" then
    return nil
  end
  local sentences = {}
  local buys = info.buys or {}
  if table.getn(buys) > 0 then
    local bits = {}
    for i = 1, table.getn(buys) do
      local row = buys[i]
      local cost = tonumber(row.cost)
      if cost then
        table.insert(bits, string.format(
          "%s %s for %s",
          formatCount(row.count),
          itemName(row.itemID),
          formatPlainCash(cost)
        ))
      end
    end
    if table.getn(bits) > 0 then
      table.insert(sentences, "Buy " .. table.concat(bits, " and "))
    end
  end
  local saleUnit = tonumber(info.saleUnit)
  local units = tonumber(info.postUnits)
  if info.outputItemID and saleUnit and saleUnit > 0 and units and units > 0 then
    local cut = "5%"
    if OnyxiaGold.GetAuctionHouseCut and OnyxiaGold.FormatPercent then
      cut = OnyxiaGold.FormatPercent(OnyxiaGold:GetAuctionHouseCut())
    end
    table.insert(sentences, string.format(
      "Expect to post %s %s at %s each, %s after the %s cut",
      formatCount(units),
      itemName(info.outputItemID),
      formatPlainCash(saleUnit),
      formatPlainCash(info.proceeds or 0),
      cut
    ))
  end
  if table.getn(sentences) == 0 then
    return nil
  end
  return table.concat(sentences, ". ") .. "."
end

local function rowTitle(action)
  if not action then
    return ""
  end
  local parts = {}
  if action.kind == "SKILL_PREVIEW" and action.skillLabel and action.skillLabel ~= "" then
    table.insert(parts, action.skillLabel)
  elseif action.kind == "GOLD_PREVIEW" then
    if action.goldLabel and action.goldLabel ~= "" then
      table.insert(parts, action.goldLabel)
    end
    if action.skillLabel and action.skillLabel ~= "" then
      table.insert(parts, action.skillLabel)
    end
  else
    local instruction = actionInstruction(action)
    if instruction and instruction ~= "" then
      table.insert(parts, instruction)
    end
  end
  local breakdown = profitBreakdownText(action)
  if breakdown and breakdown ~= "" then
    table.insert(parts, breakdown)
  end
  if table.getn(parts) == 0 then
    return action.name or ""
  end
  return table.concat(parts, " ")
end

local function setRGB(fs, r, g, b)
  if fs and fs.SetTextColor then
    fs:SetTextColor(r, g, b)
  end
end

local function paintTone(row, preview)
  local r, g, b = 1, 1, 1
  if preview then
    r, g, b = 0.55, 0.55, 0.55
  end
  setRGB(row.cells.name, r, g, b)
  setRGB(row.cells.profit, r, g, b)
  setRGB(row.cells.cash, r, g, b)
  setRGB(row.cells.crafts, r, g, b)
  setRGB(row.cells.type, r, g, b)
end

local function skillBit(cap, name)
  local skill = cap:GetProfessionSkill(name)
  if not skill then
    return name .. " —"
  end
  local text = string.format("%s %d", name, skill.rank or 0)
  if name == "Alchemy" and OnyxiaGold:IsTransmuteMaster() then
    if OnyxiaGold:IsTransmuteMasterOverride() then
      text = text .. " [TM override]"
    else
      text = text .. " [Transmute]"
    end
  end
  if not cap:HasRecipeScan(name) then
    text = text .. " · open to scan recipes"
  else
    local age = cap:RecipeScanAge(name)
    if age and age > (OnyxiaGold.Config.RecipeScanStaleSeconds or 86400) then
      text = text .. " · recipes " .. OnyxiaGold.FormatAge(age) .. " ago"
    end
  end
  return text
end

local function professionLine()
  local cap = OnyxiaGold.Capabilities
  if not cap then
    return "Professions unknown"
  end
  local parts = {
    skillBit(cap, "Alchemy"),
    skillBit(cap, "Enchanting"),
  }
  local jc = cap:GetProfessionSkill("Jewelcrafting")
  if jc and (jc.rank or 0) > 0 then
    table.insert(parts, skillBit(cap, "Jewelcrafting") .. " (global)")
  end
  return table.concat(parts, "   ")
end

local function initialWindowSize()
  local width, height = FRAME_WIDTH, FRAME_HEIGHT
  local settings = OnyxiaGoldDB and OnyxiaGoldDB.settings
  if type(settings) == "table" then
    local w = tonumber(settings.windowWidth)
    local h = tonumber(settings.windowHeight)
    if w and w >= MIN_WIDTH and w <= MAX_WIDTH then
      width = w
    end
    if h and h >= MIN_HEIGHT and h <= MAX_HEIGHT then
      height = h
    end
  end
  return width, height
end

local function identityLine()
  local id = OnyxiaGold.CharacterState and OnyxiaGold.CharacterState:GetIdentity()
  if not id or not id.name then
    return "Character unknown"
  end
  local faction = id.faction or ""
  local className = id.className or id.class or ""
  local level = id.level or 0
  return string.format("%s · %s %s · %d", id.name, faction, className, level)
end

local function applyQuietPanel(panel, list)
  panel:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  if list then
    panel:SetBackdropColor(0.04, 0.035, 0.03, 0.94)
    panel:SetBackdropBorderColor(0.78, 0.66, 0.32, 0.9)
  else
    panel:SetBackdropColor(0.06, 0.05, 0.04, 0.9)
    panel:SetBackdropBorderColor(0.55, 0.46, 0.26, 0.75)
  end
end

local function sectionLabel(parent, text)
  local fs = addLabel(parent, text, "GameFontNormalSmall")
  setRGB(fs, 1, 0.82, 0)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("MIDDLE")
  fs:SetWordWrap(false)
  return fs
end

function UI:LayoutColumns()
  if not self.rows or not self.frame then
    return
  end
  local width
  local sample = self.rows[1]
  if sample and sample.GetWidth then
    width = tonumber(sample:GetWidth())
  end
  if not width or width < 100 then
    local frameWidth = tonumber(self.frame:GetWidth()) or FRAME_WIDTH
    -- Pads, scroll insets, and the scrollbar gutter. See the list anchors in Create.
    width = frameWidth - 72
  end
  if width < 100 then
    return
  end
  local fixed = BUTTON_GUTTER + 4
  for i = 1, table.getn(COLS) do
    local key = COLS[i].key
    if key ~= "name" then
      fixed = fixed + (COL_WIDTH[key] or 80) + COL_GAP
    end
  end
  local nameW = width - fixed
  if nameW < 180 then
    nameW = 180
  end
  local x = 4
  for i = 1, table.getn(COLS) do
    local col = COLS[i]
    local w = nameW
    if col.key ~= "name" then
      w = COL_WIDTH[col.key] or 80
    end
    local headerFs = self.headerCells and self.headerCells[col.key]
    if headerFs then
      headerFs:ClearAllPoints()
      headerFs:SetPoint("LEFT", headerFs:GetParent(), "LEFT", x, 0)
      headerFs:SetWidth(w)
      headerFs:SetJustifyH(col.justify)
    end
    for r = 1, NUM_ROWS do
      local row = self.rows[r]
      local fs = row and row.cells and row.cells[col.key]
      if fs then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", row, "LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH(col.justify)
      end
    end
    x = x + w + COL_GAP
  end
  if self.tradeScroll and self.tradeEdit and self.tradeScroll.GetWidth then
    local tw = self.tradeScroll:GetWidth()
    if tw and tw > 40 then
      local nextW = math.floor(tw - 8)
      if nextW < 40 then
        nextW = 40
      end
      local current = self.tradeEdit:GetWidth() or 0
      if math.abs(current - nextW) > 1 then
        self.tradeEdit:SetWidth(nextW)
      end
    end
  end
end

function UI:Create()
  if self.frame then
    return
  end
  OnyxiaGold.Log:Debug("UI", "Creating main window")

  local frame = CreateFrame("Frame", "OnyxiaGoldFrame", UIParent)
  local width, height = initialWindowSize()
  frame:SetWidth(width)
  frame:SetHeight(height)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
  frame:SetMaxResize(MAX_WIDTH, MAX_HEIGHT)
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
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0.32, 0.27, 0.20, 1)
  frame:SetBackdropBorderColor(0.86, 0.74, 0.42, 1)
  frame:Hide()
  tinsert(UISpecialFrames, "OnyxiaGoldFrame")

  local title = addLabel(frame, "OnyxiaGold", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -12)
  setRGB(title, 1, 0.82, 0)

  local versionText = ""
  if GetAddOnMetadata then
    versionText = GetAddOnMetadata("OnyxiaGold", "Version") or ""
  end
  if versionText == "" and OnyxiaGold.Version then
    versionText = OnyxiaGold.Version
  end
  local versionLabel = addLabel(frame, versionText, "GameFontHighlightSmall")
  versionLabel:SetPoint("LEFT", title, "RIGHT", 10, -1)
  setRGB(versionLabel, 0.86, 0.74, 0.42)

  local close = CreateFrame("Button", "OnyxiaGoldCloseButton", frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

  local logBtn = CreateFrame("Button", "OnyxiaGoldOpenLogButton", frame, "UIPanelButtonTemplate")
  logBtn:SetWidth(56)
  logBtn:SetHeight(BUTTON_HEIGHT)
  logBtn:SetPoint("RIGHT", close, "LEFT", -2, -1)
  logBtn:SetText("Log")
  logBtn:SetScript("OnClick", function()
    OnyxiaGold.Log:Toggle()
  end)

  local auction = CreateFrame("Frame", "OnyxiaGoldAuctionSection", frame)
  auction:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -42)
  auction:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -42)
  auction:SetHeight(40)
  applyQuietPanel(auction, false)
  local auctionLabel = sectionLabel(auction, "Auction")
  auctionLabel:SetPoint("LEFT", auction, "LEFT", 10, 0)

  local quickBtn = CreateFrame("Button", "OnyxiaGoldQuickScanButton", auction, "UIPanelButtonTemplate")
  quickBtn:SetWidth(112)
  quickBtn:SetHeight(BUTTON_HEIGHT)
  quickBtn:SetPoint("LEFT", auction, "LEFT", 78, 0)
  quickBtn:SetText("Quick Scan")
  quickBtn:SetScript("OnClick", function()
    OnyxiaGold.Log:Debug("UI", "Quick Scan clicked")
    OnyxiaGold.Scanner:StartQuick()
  end)

  local fullBtn = CreateFrame("Button", "OnyxiaGoldFullScanButton", auction, "UIPanelButtonTemplate")
  fullBtn:SetWidth(100)
  fullBtn:SetHeight(BUTTON_HEIGHT)
  fullBtn:SetPoint("LEFT", quickBtn, "RIGHT", 8, 0)
  fullBtn:SetText("Full Scan")
  fullBtn:SetScript("OnClick", function()
    OnyxiaGold.Log:Debug("UI", "Full Scan clicked")
    OnyxiaGold.Scanner:StartFull()
  end)

  local refreshBtn = CreateFrame("Button", "OnyxiaGoldRefreshButton", auction, "UIPanelButtonTemplate")
  refreshBtn:SetWidth(96)
  refreshBtn:SetHeight(BUTTON_HEIGHT)
  refreshBtn:SetPoint("LEFT", fullBtn, "RIGHT", 8, 0)
  refreshBtn:SetText("Refresh")
  refreshBtn:SetScript("OnClick", function()
    OnyxiaGold.Log:Debug("UI", "Refresh opportunities clicked")
    OnyxiaGold.OpportunityEngine:Refresh()
  end)

  local scanBar = CreateFrame("StatusBar", "OnyxiaGoldScanBar", auction)
  scanBar:SetPoint("LEFT", refreshBtn, "RIGHT", 12, 0)
  scanBar:SetPoint("RIGHT", auction, "RIGHT", -10, 0)
  scanBar:SetHeight(16)
  scanBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  scanBar:SetStatusBarColor(0.86, 0.62, 0.12)
  scanBar:SetMinMaxValues(0, 1)
  scanBar:SetValue(0)
  local scanBarBg = scanBar:CreateTexture(nil, "BACKGROUND")
  scanBarBg:SetAllPoints(scanBar)
  scanBarBg:SetTexture(0.12, 0.1, 0.06, 0.9)
  local scanBarText = scanBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  scanBarText:SetPoint("LEFT", scanBar, "LEFT", 6, 0)
  scanBarText:SetPoint("RIGHT", scanBar, "RIGHT", -6, 0)
  scanBarText:SetJustifyH("CENTER")
  scanBarText:SetJustifyV("MIDDLE")
  scanBarText:SetTextColor(1, 0.96, 0.86)
  scanBarText:SetShadowOffset(1, -1)
  scanBarText:SetShadowColor(0, 0, 0, 1)
  scanBarText:SetText("")
  scanBar:Hide()

  local options = CreateFrame("Frame", "OnyxiaGoldOptionsSection", frame)
  options:SetPoint("TOPLEFT", auction, "BOTTOMLEFT", 0, -6)
  options:SetPoint("TOPRIGHT", auction, "BOTTOMRIGHT", 0, -6)
  options:SetHeight(40)
  applyQuietPanel(options, false)
  local optionsLabel = sectionLabel(options, "Options")
  optionsLabel:SetPoint("LEFT", options, "LEFT", 10, 0)

  local function pinCheckLabel(fs, width)
    if not fs then
      return
    end
    fs:SetWordWrap(false)
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("MIDDLE")
  end

  local master = CreateFrame("CheckButton", "OnyxiaGoldMasterCheck", options, "UICheckButtonTemplate")
  master:SetWidth(24)
  master:SetHeight(24)
  master:SetPoint("LEFT", options, "LEFT", 78, 0)
  local masterText = getglobal("OnyxiaGoldMasterCheckText")
  if masterText then
    masterText:SetText("Force TM")
    pinCheckLabel(masterText, 90)
  end
  master:SetScript("OnClick", function(self)
    OnyxiaGold.Database:Ensure()
    local on = self:GetChecked() and true or false
    OnyxiaGoldDB.settings.transmuteMasterOverride = on
    OnyxiaGoldDB.settings.transmuteMaster = on
    OnyxiaGold.Log:Info("UI", "Transmute Master override " .. tostring(on))
    OnyxiaGold.OpportunityEngine:Refresh()
  end)

  local skillPreview = CreateFrame("CheckButton", "OnyxiaGoldSkillPreviewCheck", options, "UICheckButtonTemplate")
  skillPreview:SetWidth(24)
  skillPreview:SetHeight(24)
  skillPreview:SetPoint("LEFT", options, "LEFT", 220, 0)
  local skillText = getglobal("OnyxiaGoldSkillPreviewCheckText")
  if skillText then
    skillText:SetText("Show above my skill")
    pinCheckLabel(skillText, 170)
  end
  skillPreview:SetScript("OnClick", function(self)
    OnyxiaGold.Database:Ensure()
    local on = self:GetChecked() and true or false
    OnyxiaGoldDB.settings.showAboveSkill = on
    OnyxiaGold.Log:Info("UI", "Show above my skill " .. tostring(on))
    if OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.Refresh then
      OnyxiaGold.ActionPlanner:Refresh()
    end
    OnyxiaGold.UI:Refresh()
  end)

  local goldPreview = CreateFrame("CheckButton", "OnyxiaGoldGoldPreviewCheck", options, "UICheckButtonTemplate")
  goldPreview:SetWidth(24)
  goldPreview:SetHeight(24)
  goldPreview:SetPoint("LEFT", options, "LEFT", 450, 0)
  local goldText = getglobal("OnyxiaGoldGoldPreviewCheckText")
  if goldText then
    goldText:SetText("Show beyond my gold")
    pinCheckLabel(goldText, 170)
  end
  goldPreview:SetScript("OnClick", function(self)
    OnyxiaGold.Database:Ensure()
    local on = self:GetChecked() and true or false
    OnyxiaGoldDB.settings.showBeyondGold = on
    OnyxiaGold.Log:Info("UI", "Show beyond my gold " .. tostring(on))
    if OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.Refresh then
      OnyxiaGold.ActionPlanner:Refresh()
    end
    OnyxiaGold.UI:Refresh()
  end)

  local summary = CreateFrame("Frame", "OnyxiaGoldSummarySection", frame)
  summary:SetPoint("TOPLEFT", options, "BOTTOMLEFT", 0, -6)
  summary:SetPoint("TOPRIGHT", options, "BOTTOMRIGHT", 0, -6)
  summary:SetHeight(76)
  applyQuietPanel(summary, false)

  local function stackLine(fs, y)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", summary, "TOPLEFT", 10, y)
    fs:SetPoint("TOPRIGHT", summary, "TOPRIGHT", -10, y)
    fs:SetHeight(12)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("MIDDLE")
    fs:SetWordWrap(false)
  end

  local identity = addLabel(summary, "", "GameFontHighlightSmall")
  stackLine(identity, -2)
  local professions = addLabel(summary, "", "GameFontDisableSmall")
  stackLine(professions, -14)
  local factory = addLabel(summary, "", "GameFontDisableSmall")
  stackLine(factory, -26)
  local capital = addLabel(summary, "", "GameFontHighlightSmall")
  stackLine(capital, -38)
  local deploy = addLabel(summary, "", "GameFontNormalSmall")
  stackLine(deploy, -50)
  setRGB(deploy, 0.35, 0.85, 0.45)
  local market = addLabel(summary, "Market: —", "GameFontDisableSmall")
  stackLine(market, -62)

  local capitalHit = CreateFrame("Frame", "OnyxiaGoldCapitalHit", summary)
  capitalHit:SetPoint("TOPLEFT", capital, "TOPLEFT", -2, 2)
  capitalHit:SetPoint("BOTTOMRIGHT", deploy, "BOTTOMRIGHT", 2, -2)
  capitalHit:EnableMouse(true)
  capitalHit:SetScript("OnEnter", function()
    UI:ShowCapitalTooltip(capitalHit)
  end)
  capitalHit:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  local mail = CreateFrame("Frame", "OnyxiaGoldMailSection", frame)
  mail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 20)
  mail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 20)
  mail:SetHeight(40)
  applyQuietPanel(mail, false)
  local mailLabel = sectionLabel(mail, "Mail")
  mailLabel:SetPoint("LEFT", mail, "LEFT", 10, 0)

  local heldBtn = CreateFrame("Button", "OnyxiaGoldHeldButton", mail, "UIPanelButtonTemplate")
  heldBtn:SetWidth(88)
  heldBtn:SetHeight(BUTTON_HEIGHT)
  heldBtn:SetPoint("LEFT", mail, "LEFT", 64, 0)
  heldBtn:SetText("In bags")
  heldBtn:SetScript("OnClick", function()
    if UI.listMode == "inventory" then
      UI.listMode = "actions"
    else
      UI.listMode = "inventory"
    end
    UI:Refresh()
  end)
  heldBtn:SetScript("OnEnter", function(self)
    if not GameTooltip then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("In bags", 1, 0.82, 0)
    GameTooltip:AddLine("Switches this list between What to do now and the items in your bags. Each held row shows what it is worth, where it sits, and a badge for what to do with it: use, disenchant, sell, vendor, or wait. Click again to return to What to do now.", 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  heldBtn:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)

  local goldBtn = CreateFrame("Button", "OnyxiaGoldCollectGoldButton", mail, "UIPanelButtonTemplate")
  goldBtn:SetWidth(100)
  goldBtn:SetHeight(BUTTON_HEIGHT)
  goldBtn:SetPoint("LEFT", heldBtn, "RIGHT", 12, 0)
  goldBtn:SetText("Take gold")
  goldBtn:SetScript("OnClick", function()
    if OnyxiaGold.MailProcessor then
      OnyxiaGold.MailProcessor:CollectGold(true)
    end
    OnyxiaGold.UI:ShowFactoryMail()
  end)
  goldBtn:SetScript("OnEnter", function(self)
    if not GameTooltip then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Take gold", 1, 0.82, 0)
    GameTooltip:AddLine("Stand at a mailbox. Each click takes one auction-house sale payment. It does not take items, personal mail, or cash-on-delivery. Click again for the next payment.", 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  goldBtn:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)

  local sweepBtn = CreateFrame("Button", "OnyxiaGoldFactorySweepButton", mail, "UIPanelButtonTemplate")
  sweepBtn:SetWidth(100)
  sweepBtn:SetHeight(BUTTON_HEIGHT)
  sweepBtn:SetPoint("LEFT", goldBtn, "RIGHT", 12, 0)
  sweepBtn:SetText("Take mail")
  sweepBtn:SetScript("OnClick", function()
    if OnyxiaGold.MailProcessor then
      OnyxiaGold.MailProcessor:Sweep(true)
    end
    OnyxiaGold.UI:ShowFactoryMail()
  end)
  sweepBtn:SetScript("OnEnter", function(self)
    if not GameTooltip then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Take mail", 1, 0.82, 0)
    GameTooltip:AddLine("Stand at a mailbox. Each click takes the next safe auction-house mail: sale gold first, then items this list planned to buy, then other won or purchased items, then expired and cancelled auctions. It never takes personal mail, cash-on-delivery, or unknown mail. An item needs a free bag slot.", 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  sweepBtn:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)

  local trades = CreateFrame("Frame", "OnyxiaGoldTradesSection", frame)
  trades:SetPoint("BOTTOMLEFT", mail, "TOPLEFT", 0, 6)
  trades:SetPoint("BOTTOMRIGHT", mail, "TOPRIGHT", 0, 6)
  trades:SetHeight(64)
  applyQuietPanel(trades, false)

  local tradeTitle = addLabel(trades, "Trades", "GameFontNormalSmall")
  tradeTitle:SetPoint("TOPLEFT", trades, "TOPLEFT", 10, -6)
  setRGB(tradeTitle, 1, 0.82, 0)

  local tradeCopy = CreateFrame("Button", "OnyxiaGoldTradeCopyButton", trades, "UIPanelButtonTemplate")
  tradeCopy:SetWidth(56)
  tradeCopy:SetHeight(BUTTON_HEIGHT)
  tradeCopy:SetPoint("TOPRIGHT", trades, "TOPRIGHT", -8, -4)
  tradeCopy:SetText("Copy")
  tradeCopy:SetScript("OnClick", function()
    UI:CopyTrades()
  end)
  tradeCopy:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Select the trade lines, then Ctrl+C", 1, 1, 1)
    GameTooltip:Show()
  end)
  tradeCopy:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  local tradeTotals = addLabel(trades, "", "GameFontHighlightSmall")
  tradeTotals:SetPoint("LEFT", tradeTitle, "RIGHT", 12, 0)
  tradeTotals:SetPoint("RIGHT", tradeCopy, "LEFT", -8, 0)
  tradeTotals:SetJustifyH("LEFT")
  tradeTotals:SetWordWrap(false)

  local tradeScroll = CreateFrame("ScrollFrame", "OnyxiaGoldTradeScroll", trades, "UIPanelScrollFrameTemplate")
  tradeScroll:SetPoint("TOPLEFT", trades, "TOPLEFT", 8, -28)
  tradeScroll:SetPoint("BOTTOMRIGHT", trades, "BOTTOMRIGHT", -26, 6)
  tradeScroll:EnableMouseWheel(1)
  tradeScroll:SetScript("OnMouseWheel", function(self, delta)
    local bar = getglobal(self:GetName() .. "ScrollBar")
    if not bar then
      return
    end
    local step = 28
    local value = bar:GetValue() or 0
    if delta > 0 then
      value = value - step
    else
      value = value + step
    end
    local minV, maxV = bar:GetMinMaxValues()
    if value < (minV or 0) then
      value = minV or 0
    end
    if value > (maxV or 0) then
      value = maxV or 0
    end
    bar:SetValue(value)
  end)

  local tradeEdit = CreateFrame("EditBox", "OnyxiaGoldTradeEdit", tradeScroll)
  tradeEdit:SetMultiLine(true)
  tradeEdit:SetAutoFocus(false)
  tradeEdit:SetFontObject(GameFontHighlightSmall)
  tradeEdit:SetWidth(960)
  tradeEdit:SetHeight(40)
  tradeEdit:SetMaxLetters(999999)
  tradeEdit:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  tradeEdit:SetScript("OnTextChanged", function(self)
    if self.freeze and self.frozenText and self:GetText() ~= self.frozenText then
      self:SetText(self.frozenText)
    end
  end)
  tradeScroll:SetScrollChild(tradeEdit)

  local listPanel = CreateFrame("Frame", "OnyxiaGoldListSection", frame)
  listPanel:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -6)
  listPanel:SetPoint("BOTTOMRIGHT", trades, "TOPRIGHT", 0, 6)
  applyQuietPanel(listPanel, true)

  local listTitle = sectionLabel(listPanel, "What to do now")
  listTitle:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 10, -6)
  listTitle:SetHeight(14)

  local nextAction = addLabel(listPanel, "", "GameFontHighlightSmall")
  nextAction:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 10, -20)
  nextAction:SetPoint("TOPRIGHT", listPanel, "TOPRIGHT", -12, -20)
  nextAction:SetHeight(32)
  nextAction:SetJustifyH("LEFT")
  nextAction:SetJustifyV("TOP")
  nextAction:SetWordWrap(true)
  nextAction:SetNonSpaceWrap(false)
  setRGB(nextAction, 0.95, 0.9, 0.75)

  local header = CreateFrame("Frame", "OnyxiaGoldHeader", listPanel)
  header:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 8, -52)
  header:SetPoint("TOPRIGHT", listPanel, "TOPRIGHT", -26, -52)
  header:SetHeight(16)

  local headerCells = {}
  for i = 1, table.getn(COLS) do
    local col = COLS[i]
    local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", header, "LEFT", 0, 0)
    fs:SetWidth(col.width)
    fs:SetJustifyH(col.justify)
    fs:SetJustifyV("MIDDLE")
    fs:SetWordWrap(false)
    fs:SetText(col.label)
    headerCells[col.key] = fs
    setRGB(fs, 1, 0.82, 0)
  end

  local headerRule = header:CreateTexture(nil, "ARTWORK")
  headerRule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, -1)
  headerRule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, -1)
  headerRule:SetHeight(1)
  headerRule:SetTexture(0.85, 0.68, 0.25, 0.85)

  local scroll = CreateFrame("ScrollFrame", "OnyxiaGoldListScroll", listPanel, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 4, -70)
  scroll:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -4, 24)
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
    if UI.tradeScroll and MouseIsOver and MouseIsOver(UI.tradeScroll) then
      return
    end
    local handler = scroll:GetScript("OnMouseWheel")
    if handler then
      handler(scroll, delta)
    end
  end)

  local status = addLabel(listPanel, "Open the Auction House, then Quick Scan.", "GameFontDisableSmall")
  status:SetPoint("BOTTOMLEFT", listPanel, "BOTTOMLEFT", 10, 5)
  status:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -10, 5)
  status:SetHeight(14)
  status:SetJustifyH("LEFT")
  status:SetJustifyV("MIDDLE")
  status:SetWordWrap(false)

  local rows = {}
  for i = 1, NUM_ROWS do
    local row = CreateFrame("Button", "OnyxiaGoldRow" .. i, frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("LEFT", scroll, "LEFT", 4, 0)
    row:SetPoint("RIGHT", scroll, "RIGHT", -22, 0)
    row:SetFrameLevel(frame:GetFrameLevel() + 4)
    if i == 1 then
      row:SetPoint("TOP", scroll, "TOP", 0, 0)
    else
      row:SetPoint("TOP", rows[i - 1], "BOTTOM", 0, 0)
    end

    if i % 2 == 0 then
      local bg = row:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints(row)
      bg:SetTexture(1, 1, 1, 0.06)
      row.bg = bg
    end

    row.cells = {}
    for c = 1, table.getn(COLS) do
      local col = COLS[c]
      local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("LEFT", row, "LEFT", 0, 0)
      fs:SetWidth(col.width)
      fs:SetJustifyH(col.justify)
      fs:SetJustifyV("MIDDLE")
      fs:SetText("")
      if col.key == "name" then
        fs:SetHeight(ROW_HEIGHT - 8)
        fs:SetJustifyV("TOP")
        fs:SetWordWrap(true)
        fs:SetNonSpaceWrap(false)
      else
        fs:SetWordWrap(false)
      end
      row.cells[col.key] = fs
    end

    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
      UI:OnActionClick(self)
    end)
    row:SetScript("OnEnter", function(self)
      if self.factoryItem then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        UI:FactoryInventoryTooltip(self.factoryItem)
      else
        UI:ShowActionTooltip(self)
      end
    end)
    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    local buy = CreateFrame("Button", "OnyxiaGoldRowBuy" .. i, row, "UIPanelButtonTemplate")
    buy:SetWidth(56)
    buy:SetHeight(22)
    buy:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    buy:SetText("Buy")
    buy:SetFrameLevel(row:GetFrameLevel() + 2)
    buy:SetScript("OnClick", function()
      UI:OnBuyClick(row)
    end)
    buy:Hide()
    row.buyButton = buy

    local post = CreateFrame("Button", "OnyxiaGoldRowPost" .. i, row, "UIPanelButtonTemplate")
    post:SetWidth(56)
    post:SetHeight(22)
    post:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    post:SetText("Post")
    post:SetFrameLevel(row:GetFrameLevel() + 2)
    post:SetScript("OnClick", function()
      UI:OnPostClick(row)
    end)
    post:Hide()
    row.postButton = post

    rows[i] = row
  end

  local grip = CreateFrame("Button", "OnyxiaGoldResizeGrip", frame)
  grip:SetWidth(16)
  grip:SetHeight(16)
  grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
  grip:SetFrameLevel(frame:GetFrameLevel() + 20)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function()
    frame:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    UI:SaveWindowSize()
  end)
  grip:SetScript("OnEnter", function(self)
    if not GameTooltip then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Drag to resize", 1, 1, 1)
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)

  frame:SetScript("OnSizeChanged", function()
    if UI.rows then
      UI:LayoutColumns()
      UI:UpdateList()
    end
    UI:SaveWindowSize()
  end)

  self.frame = frame
  self.quickScanButton = quickBtn
  self.fullScanButton = fullBtn
  self.scanButton = quickBtn
  self.refreshButton = refreshBtn
  self.masterCheck = master
  self.skillCheck = skillPreview
  self.goldCheck = goldPreview
  self.identityLabel = identity
  self.professionLabel = professions
  self.factoryLabel = factory
  self.capitalLabel = capital
  self.deployLabel = deploy
  self.marketStatus = market
  self.scroll = scroll
  self.rows = rows
  self.status = status
  self.scanBar = scanBar
  self.scanBarText = scanBarText
  self.tradeScroll = tradeScroll
  self.tradeEdit = tradeEdit
  self.tradeTotals = tradeTotals
  self.header = header
  self.headerCells = headerCells
  self.listTitle = listTitle
  self.nextAction = nextAction
  self.heldButton = heldBtn
  self.listMode = "actions"
  self:LayoutColumns()
end

function UI:ShowCapitalTooltip(owner)
  local cap = OnyxiaGold.Capital and OnyxiaGold.Capital:GetPortfolioSummary()
  if not cap then
    return
  end
  GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
  GameTooltip:SetText("Portfolio", 1, 0.82, 0)
  GameTooltip:AddLine("Liquid (spendable at AH): " .. OnyxiaGold.FormatMoney(cap.liquid), 1, 1, 1)
  GameTooltip:AddLine("Planner reserve (" .. OnyxiaGold.FormatPercent(cap.reservePercent) .. "): " .. OnyxiaGold.FormatMoney(cap.reserve), 0.8, 0.8, 0.8)
  GameTooltip:AddLine("Deployable now: " .. OnyxiaGold.FormatMoney(cap.deployable), 0.35, 0.85, 0.45)
  local afterText = OnyxiaGold.FormatMoney(cap.deployableAfterMail or 0)
  if cap.mailComplete == false then
    afterText = "~" .. afterText .. "+"
  end
  GameTooltip:AddLine("Deployable after mail: " .. afterText, 0.35, 0.85, 0.45)
  GameTooltip:AddLine(
    "After-mail reserve (" .. OnyxiaGold.FormatPercent(cap.reservePercent) .. " of liquid + mail): "
      .. OnyxiaGold.FormatMoney(cap.postMailReserve or 0),
    0.8, 0.8, 0.8
  )
  GameTooltip:AddLine(" ", 1, 1, 1)

  local mailAge = cap.mailAge
  local mailPrefix = "Mail ready: "
  local mailAmount = OnyxiaGold.FormatMoney(cap.claimableMail)
  if mailAge == nil then
    mailPrefix = "Mail ready (never checked): "
  elseif cap.mailComplete == false then
    mailPrefix = "Mail ready: ~"
    mailAmount = mailAmount .. "+"
  elseif OnyxiaGold.Mail and OnyxiaGold.Mail:IsStale() then
    mailPrefix = "Mail ready ~ "
  end
  GameTooltip:AddLine(mailPrefix .. mailAmount, 1, 1, 1)
  if cap.mailComplete == false then
    GameTooltip:AddLine(string.format(
      "%s shown · mailbox not fully loaded (%d/%d)",
      OnyxiaGold.FormatMoney(cap.claimableMail),
      cap.mailVisible or 0,
      cap.mailTotal or 0
    ), 1, 0.85, 0.35, 1)
  end
  local pendingText = OnyxiaGold.FormatMoney(cap.pendingAuctionGold)
  if cap.mailComplete == false then
    pendingText = "~" .. pendingText .. "+"
  end
  GameTooltip:AddLine("Pending AH invoices: " .. pendingText, 1, 0.85, 0.35)
  if mailAge then
    local r, g, b = OnyxiaGold.FreshnessRGB(mailAge, OnyxiaGold.Config.MailStaleSeconds, 3600)
    GameTooltip:AddLine("Mail checked " .. OnyxiaGold.FormatAge(mailAge) .. " ago", r, g, b)
  end
  local listedAsking = OnyxiaGold.FormatMoney(cap.listedAsking)
  local listedNet = OnyxiaGold.FormatMoney(cap.listedExpectedNet)
  if cap.auctionsComplete == false then
    listedAsking = "~" .. listedAsking
    listedNet = "~" .. listedNet
  end
  GameTooltip:AddLine("Listed asking: " .. listedAsking, 0.8, 0.8, 0.8)
  GameTooltip:AddLine("Listed expected net: " .. listedNet, 0.8, 0.8, 0.8)
  if cap.auctionsComplete == false then
    GameTooltip:AddLine(string.format(
      "Listed is approximate: %d of %d auctions shown",
      cap.auctionsShown or 0,
      cap.auctionsTotal or 0
    ), 1, 0.85, 0.35, 1)
  end
  GameTooltip:AddLine("Current bids on listings: " .. OnyxiaGold.FormatMoney(cap.listedBids), 0.8, 0.8, 0.8)
  if cap.auctionAge then
    local r, g, b = OnyxiaGold.FreshnessRGB(cap.auctionAge, OnyxiaGold.Config.AuctionStaleSeconds, 3600)
    GameTooltip:AddLine("Auctions checked " .. OnyxiaGold.FormatAge(cap.auctionAge) .. " ago", r, g, b)
  else
    GameTooltip:AddLine("Auctions: open AH to scan own listings", 0.55, 0.55, 0.55)
  end
  GameTooltip:AddLine("Bags (tracked mats): " .. OnyxiaGold.FormatMoney(cap.bags) .. "  live", 0.8, 0.8, 0.8)
  if cap.bankAge then
    local r, g, b = OnyxiaGold.FreshnessRGB(cap.bankAge, OnyxiaGold.Config.BankStaleSeconds, 86400 * 7)
    GameTooltip:AddLine("Bank (tracked mats): " .. OnyxiaGold.FormatMoney(cap.bank) .. "  " .. OnyxiaGold.FormatAge(cap.bankAge) .. " ago", r, g, b)
  else
    GameTooltip:AddLine("Bank: open bank to snapshot", 0.55, 0.55, 0.55)
  end
  GameTooltip:AddLine(" ", 1, 1, 1)
  GameTooltip:AddLine("Estimated net: " .. OnyxiaGold.FormatMoney(cap.estimatedNetWorth) .. "  (not spendable)", 0.65, 0.65, 0.65)
  GameTooltip:AddLine("Pending and listed values cannot fund a buy.", 0.7, 0.7, 0.7, 1)
  GameTooltip:Show()
end

function UI:PaintAuctionPage(page)
  local rows = page and page.rows or {}
  local offset = 0
  if type(FauxScrollFrame_GetOffset) == "function" and BrowseScrollFrame then
    offset = tonumber(FauxScrollFrame_GetOffset(BrowseScrollFrame)) or 0
  end
  local shown = NUM_BROWSE_TO_DISPLAY or 8
  for i = 1, shown do
    local button = _G["BrowseButton" .. i]
    local row = rows[i + offset]
    if button then
      if not button.ogStopLine and button.CreateFontString then
        button.ogStopLine = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      end
      if button.ogStopLine and button.ogStopLine.SetText then
        button.ogStopLine:SetText(row and row.line or "")
      end
    end
  end
end

local BADGE_COLOR = {
  USE = { 0.25, 0.75, 0.35 },
  DE = { 0.55, 0.40, 0.75 },
  SELL = { 0.85, 0.70, 0.25 },
  VENDOR = { 0.55, 0.55, 0.55 },
  WAIT = { 0.80, 0.70, 0.25 },
  LOCKED = { 0.70, 0.30, 0.25 },
  ["?"] = { 0.35, 0.35, 0.35 },
}

local INVENTORY_HEADERS = {
  name = "Item",
  profit = "Worth",
  cash = "Place",
  crafts = "Badge",
  type = "Disposition",
}

local function paintHeaders(self)
  local cells = self.headerCells
  if not cells then
    return
  end
  local inventory = self.listMode == "inventory"
  if self.listTitle then
    if inventory then
      self.listTitle:SetText("In bags")
    else
      self.listTitle:SetText("What to do now")
    end
  end
  for i = 1, table.getn(COLS) do
    local col = COLS[i]
    local fs = cells[col.key]
    if fs then
      fs:SetText(inventory and INVENTORY_HEADERS[col.key] or col.label)
    end
  end
end

local function clearRow(row)
  row.action = nil
  row.factoryItem = nil
  row.opp = nil
  if row.cells then
    for _, fs in pairs(row.cells) do
      fs:SetText("")
      setRGB(fs, 1, 1, 1)
    end
  end
  if row.buyButton then
    row.buyButton:Hide()
  end
  if row.postButton then
    row.postButton:Hide()
  end
  row:Hide()
end

function UI:PaintFactoryInventory(rows)
  rows = rows or {}
  self.factoryRows = rows
end

function UI:FactoryInventoryTooltip(row)
  if not row or not GameTooltip then
    return
  end
  local color = BADGE_COLOR[row.badge] or BADGE_COLOR["?"]
  GameTooltip:SetText((row.badge or "?") .. "  " .. tostring(row.name or ""), color[1], color[2], color[3])
  GameTooltip:AddLine(row.tooltip or "", 1, 1, 1, 1)
end

function UI:ShowFactoryMail()
  local line = "Factory mail."
  if OnyxiaGold.MailProcessor and OnyxiaGold.MailProcessor.SummaryLine then
    line = OnyxiaGold.MailProcessor:SummaryLine()
  end
  self:SetStatus(line)
end

function UI:ShowPostRow(text)
  if self.SetStatus then
    self:SetStatus(text or "")
  end
end

function UI:ApplyPostPrice(copper)
  copper = tonumber(copper) or 0
  if copper <= 0 or not BuyoutPrice then
    return
  end
  if type(MoneyInputFrame_GetCopper) ~= "function" or type(MoneyInputFrame_SetCopper) ~= "function" then
    return
  end
  local current = tonumber(MoneyInputFrame_GetCopper(BuyoutPrice)) or 0
  if current < copper then
    MoneyInputFrame_SetCopper(BuyoutPrice, copper)
  end
end

function UI:ShowActionTooltip(row)
  local action = row and row.action
  if not action then
    return
  end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(action.name or "Action", 1, 0.82, 0)
  if action.detail then
    GameTooltip:AddLine(action.detail, 0.85, 0.85, 0.85, 1)
  end
  GameTooltip:AddLine("Cash required now: " .. OnyxiaGold.FormatMoney(action.cashRequiredNow or 0), 1, 1, 1)
  if action.kind == "POST" then
    GameTooltip:AddLine("Expected revenue: " .. OnyxiaGold.FormatMoney(action.expectedRevenue or 0), 1, 1, 1)
    GameTooltip:AddLine("Cash released if it sells: " .. OnyxiaGold.FormatMoney(action.cashReleased or action.expectedRevenue or 0), 1, 1, 1)
    GameTooltip:AddLine("Inventory value: " .. OnyxiaGold.FormatMoney(action.inventoryValue or 0), 1, 1, 1)
    GameTooltip:AddLine("Expected profit: " .. OnyxiaGold.FormatMoneySigned(action.expectedProfit or 0), 0.2, 1, 0.2)
    if action.saleUnit then
      GameTooltip:AddLine("Sale unit: " .. OnyxiaGold.FormatMoney(action.saleUnit), 0.8, 0.8, 0.8)
    end
    if action.stackBuyout then
      GameTooltip:AddLine("Stack buyout: " .. OnyxiaGold.FormatMoney(action.stackBuyout), 0.8, 0.8, 0.8)
    end
  else
    GameTooltip:AddLine("Expected economic profit: " .. OnyxiaGold.FormatMoneySigned(action.expectedProfit or 0), 0.2, 1, 0.2)
  end
  if action.crafts and action.crafts > 0 then
    GameTooltip:AddLine("Planned crafts: " .. tostring(action.crafts), 1, 1, 1)
  end

  local person = action.person
  local opp = action.sourceOpp
  if person then
    GameTooltip:AddLine(" ", 1, 1, 1)
    GameTooltip:AddLine("Economic input value: " .. OnyxiaGold.FormatMoney(person.economicInputValue or 0), 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Owned material value: " .. OnyxiaGold.FormatMoney(person.ownedInputValue or 0), 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Missing materials cash: " .. OnyxiaGold.FormatMoney(person.missingInputCost or 0), 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Owned units: " .. tostring(person.ownedInputs or 0), 0.75, 0.75, 0.75)
    GameTooltip:AddLine(string.format(
      "Market profitable %s · physical %s · affordable %s",
      tostring(person.marketProfitableCrafts or 0),
      tostring(person.physicalPossibleCrafts or 0),
      tostring(person.affordableCrafts or 0)
    ), 0.75, 0.75, 0.75)
    GameTooltip:AddLine(string.format(
      "Capability %s · executable %s · sensible %s",
      tostring(person.capabilityAllowedCrafts or 0),
      tostring(person.executableCrafts or 0),
      tostring(person.sensibleCrafts or 0)
    ), 0.75, 0.75, 0.75)
    if person.outputCapNote then
      GameTooltip:AddLine(person.outputCapNote, 1, 0.82, 0.4, 1)
    end
    if person.outputStockLine then
      GameTooltip:AddLine(person.outputStockLine, 0.85, 0.85, 0.85, 1)
    end
    if person.outputHeldNote then
      GameTooltip:AddLine(person.outputHeldNote, 0.85, 0.85, 0.85, 1)
    end
  end
  if opp then
    GameTooltip:AddLine(" ", 1, 1, 1)
    GameTooltip:AddLine("Market first-craft profit: " .. OnyxiaGold.FormatMoneySigned(opp.expectedProfit or 0), 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Market potential: " .. OnyxiaGold.FormatMoneySigned(opp.totalExpectedProfit or 0), 0.7, 0.7, 0.7)
    if opp.inputItemIDs and opp.inputItemIDs[1] then
      GameTooltip:AddLine("Input: " .. tostring(itemName(opp.inputItemIDs[1])), 0.7, 0.7, 0.7)
    end
    if opp.confidenceNotes and opp.confidenceNotes ~= "" then
      GameTooltip:AddLine("Confidence " .. string.format("%.0f%%", (opp.confidence or 1) * 100)
        .. " — " .. opp.confidenceNotes, 0.7, 0.7, 0.7, 1)
    end
  end
  if action.kind == "SKILL_PREVIEW" then
    GameTooltip:AddLine((action.skillLabel or "Above your skill") .. " Not a buy.", 1, 0.82, 0.4, 1)
  elseif action.kind == "GOLD_PREVIEW" then
    GameTooltip:AddLine((action.goldLabel or "Beyond your gold") .. " Not a buy.", 1, 0.82, 0.4, 1)
    if action.skillLabel and action.skillLabel ~= "" then
      GameTooltip:AddLine(action.skillLabel, 1, 0.82, 0.4, 1)
    end
  elseif action.kind == "COLLECT_MAIL" then
    GameTooltip:AddLine("Visit a mailbox and collect gold. The addon will not loot mail.", 1, 0.85, 0.4, 1)
  elseif action.kind == "BUY" or action.kind == "BUY_AND_CRAFT" then
    GameTooltip:AddLine("Click the row to search the Auction House. Buy purchases one listing at or under the stop.", 1, 0.85, 0.4, 1)
  elseif action.kind == "CRAFT" and action.sessionStep then
    GameTooltip:AddLine("Open the profession window, then craft this yourself.", 1, 0.85, 0.4, 1)
  elseif action.kind == "POST" then
    GameTooltip:AddLine("Post lists one stack. Open the Auction House, then click Post.", 1, 0.85, 0.4, 1)
  else
    GameTooltip:AddLine("Planning only — OnyxiaGold will not buy or craft for you.", 0.55, 0.55, 0.55, 1)
  end
  GameTooltip:Show()
end

function UI:SetStatus(text)
  if not self.frame then
    self:Create()
  end
  self.status:SetText(text or "")
end

local function formatRemaining(seconds)
  seconds = tonumber(seconds) or 0
  if seconds < 0 then
    seconds = 0
  end
  seconds = math.floor(seconds + 0.5)
  if seconds >= 3600 then
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    return string.format("%dh %dm", hours, minutes)
  end
  if seconds >= 60 then
    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%dm %ds", minutes, secs)
  end
  return string.format("%ds", seconds)
end

local function setBarFill(bar, fraction)
  if fraction < 0 then
    fraction = 0
  end
  if fraction > 1 then
    fraction = 1
  end
  bar:SetMinMaxValues(0, 1000)
  bar:SetValue(math.floor(fraction * 1000 + 0.5))
end

function UI:PaintScanProgress()
  local bar = self.scanBar
  if not bar then
    return
  end
  local progress = OnyxiaGold.Scanner and OnyxiaGold.Scanner.GetProgress and OnyxiaGold.Scanner:GetProgress()
  if not progress then
    bar:Hide()
    return
  end
  bar:Show()
  local text = ""
  if progress.mode == "full" then
    local shown = (tonumber(progress.page) or 0) + 1
    local total = tonumber(progress.pagesTotal)
    if not total or total <= 0 then
      setBarFill(bar, 0)
      text = string.format("page %d · total unknown", shown)
    else
      local done = tonumber(progress.index) or 0
      if done < 0 then
        done = 0
      end
      if done > total then
        done = total
      end
      setBarFill(bar, done / total)
      text = string.format("page %d / %d", shown, total)
      local elapsed = tonumber(progress.elapsed) or 0
      if done > 0 and done < total and elapsed > 0 then
        local left = (elapsed / done) * (total - done)
        text = text .. "  ·  ~" .. formatRemaining(left)
      end
    end
  else
    local done = tonumber(progress.index) or 0
    local total = tonumber(progress.total) or 0
    local name = progress.name or ""
    if done < 0 then
      done = 0
    end
    if total > 0 and done > total then
      done = total
    end
    if total <= 0 then
      setBarFill(bar, 0)
      text = name
    else
      local fraction = done / total
      local pagesTotal = tonumber(progress.pagesTotal)
      local onItem = done < total
      if onItem and pagesTotal and pagesTotal > 1 then
        local pageDone = tonumber(progress.page) or 0
        if pageDone < 0 then
          pageDone = 0
        end
        if pageDone > pagesTotal then
          pageDone = pagesTotal
        end
        fraction = (done + (pageDone / pagesTotal)) / total
      end
      setBarFill(bar, fraction)
      if done >= total then
        text = string.format("%d / %d", total, total)
      else
        text = string.format("%d / %d   %s", done + 1, total, name)
        if onItem and pagesTotal and pagesTotal > 1 then
          local shownPage = (tonumber(progress.page) or 0) + 1
          if shownPage > pagesTotal then
            shownPage = pagesTotal
          end
          text = text .. string.format("   page %d / %d", shownPage, pagesTotal)
        end
      end
      local elapsed = tonumber(progress.elapsed) or 0
      if done > 0 and done < total and elapsed > 0 then
        local left = (elapsed / done) * (total - done)
        text = text .. "  ·  ~" .. formatRemaining(left)
      end
    end
  end
  if self.scanBarText then
    self.scanBarText:SetText(text)
  end
end

function UI:RefreshHeader()
  if not self.frame then
    return
  end
  if self.identityLabel then
    self.identityLabel:SetText(identityLine())
  end
  if self.professionLabel then
    self.professionLabel:SetText(professionLine())
  end
  if self.factoryLabel then
    local status = OnyxiaGold.Capabilities and OnyxiaGold.Capabilities.GetFactoryStatus
      and OnyxiaGold.Capabilities:GetFactoryStatus()
    if status then
      self.factoryLabel:SetText(status.message or "")
      if status.complete then
        setRGB(self.factoryLabel, 0.45, 0.7, 0.5)
      else
        setRGB(self.factoryLabel, 1, 0.85, 0.35)
      end
    else
      self.factoryLabel:SetText("")
    end
  end

  local cap = OnyxiaGold.Capital and OnyxiaGold.Capital:GetPortfolioSummary()
  if cap and self.capitalLabel then
    local mailText = OnyxiaGold.FormatGoldShort(cap.claimableMail)
    if cap.mailAge == nil then
      mailText = "—"
    elseif cap.mailComplete == false then
      mailText = "~" .. mailText .. "+"
    elseif OnyxiaGold.Mail and OnyxiaGold.Mail:IsStale() then
      mailText = "~" .. mailText
    end
    local pendingText = OnyxiaGold.FormatGoldShort(cap.pendingAuctionGold)
    if cap.mailAge == nil then
      pendingText = "—"
    elseif cap.mailComplete == false then
      pendingText = "~" .. pendingText .. "+"
    end
    local listedText = OnyxiaGold.FormatGoldShort(cap.listedAsking)
    if not cap.auctionAge then
      listedText = "—"
    elseif cap.auctionsComplete == false then
      listedText = "~" .. listedText
    end
    self.capitalLabel:SetText(string.format(
      "%s Liquid    %s Mail    %s Pending    %s Listed",
      OnyxiaGold.FormatGoldShort(cap.liquid),
      mailText,
      pendingText,
      listedText
    ))
    setRGB(self.capitalLabel, 0.85, 0.85, 0.85)
  end
  if cap and self.deployLabel then
    self.deployLabel:SetText(string.format(
      "Deployable now: %s    Reserve: %s",
      OnyxiaGold.FormatGoldShort(cap.deployable),
      OnyxiaGold.FormatGoldShort(cap.reserve)
    ))
    setRGB(self.deployLabel, 0.35, 0.85, 0.45)
  end

  if self.marketStatus then
    local label = OnyxiaGold.Database:FormatMarketLabel()
    local quick = OnyxiaGold.Database:LastScanOfType("quick")
    local full = OnyxiaGold.Database:LastScanOfType("full")
    local q = "—"
    local f = "—"
    if quick and quick.timestamp then
      q = OnyxiaGold.FormatAge(OnyxiaGold.AgeSeconds(quick.timestamp)) .. " ago"
    end
    if full and full.timestamp then
      f = OnyxiaGold.FormatAge(OnyxiaGold.AgeSeconds(full.timestamp)) .. " ago"
    end
    self.marketStatus:SetText(string.format("Market: %s    Quick %s    Full %s", label, q, f))
  end
end

function UI:RefreshMarketStatus()
  self:RefreshHeader()
end

function UI:BuyStateText(state)
  local status = state and state.status
  if status == "closed" then
    return "Open the Auction House."
  elseif status == "search" then
    local name = state.name
    if name and name ~= "" then
      return "Searching " .. name .. "."
    end
    return "Searching the Auction House."
  elseif status == "settle" then
    return "Waiting for the auction page."
  elseif status == "none" then
    return "Nothing at or under the stop."
  elseif status == "large" then
    return "No listing at or under the stop fits the remaining quantity."
  elseif status == "busy" then
    return "Auction House is busy. Click the row again."
  elseif status == "stale" then
    return "The listing changed. Click the row to search again."
  elseif status == "done" then
    return "That row has the quantity it still needs."
  elseif status == "confirm" and state.offer then
    local offer = state.offer
    local name = offer.name
    if not name or name == "" then
      name = state.name or "Item"
    end
    return string.format("%s x%d · %s", name, offer.count or 0, OnyxiaGold.FormatMoney(offer.buyout or 0))
  end
  return nil
end

local function auctionHouseOpen()
  return AuctionFrame and AuctionFrame.IsShown and AuctionFrame:IsShown() and true or false
end

function UI:PaintBuyRow(row, action)
  local button = row.buyButton
  if button then
    button:Hide()
  end
  if not isBuyKind(action) then
    return
  end
  if action.windowHint and not auctionHouseOpen() then
    return
  end
  local stop = OnyxiaGold.AuctionStop
  if not stop or not stop.RowState then
    return
  end
  local state = stop:RowState(action)
  if not state then
    return
  end
  if state.status == "closed" then
    local current = action.name or ""
    if string.find(current, "Open the Auction House.", 1, true) then
      return
    end
  end
  local text = self:BuyStateText(state)
  if text and text ~= "" then
    row.cells.name:SetText(tostring(action.index) .. ". " .. text)
  end
  if state.status == "confirm" and button then
    button:Show()
  end
end

function UI:OnActionClick(row)
  local action = row and row.action
  if not isBuyKind(action) then
    return
  end
  if OnyxiaGold.AuctionStop and OnyxiaGold.AuctionStop.RequestBuy then
    OnyxiaGold.AuctionStop:RequestBuy(action)
  end
  self:UpdateList()
end

-- Hardware click. This is the only PlaceAuctionBid in the addon.
function UI:OnBuyClick(row)
  local action = row and row.action
  local stop = OnyxiaGold.AuctionStop
  if not isBuyKind(action) or not stop or not stop.LiveBid then
    return
  end
  if stop.buyActionIndex ~= action.index then
    return
  end
  local bid = stop:LiveBid()
  if not bid then
    self:UpdateList()
    return
  end
  if not OnyxiaGold.Lots or not OnyxiaGold.Lots.AllowPlaceAuctionBid(bid, true) then
    self:UpdateList()
    return
  end
  if type(PlaceAuctionBid) ~= "function" then
    return
  end
  local itemID = stop.itemID
  local itemName = stop.queryName
  if stop.offer and type(stop.offer.name) == "string" and stop.offer.name ~= "" then
    itemName = stop.offer.name
  end
  local note = self:ActionNote(action)
  stop:BeginSettle(bid)
  if OnyxiaGold.TradeLog and OnyxiaGold.TradeLog.RecordBuyClick then
    OnyxiaGold.TradeLog:RecordBuyClick(itemID, itemName, bid.count, bid.buyout, note)
  end
  PlaceAuctionBid("list", bid.index, bid.buyout)
  if stop.NoteBidSent then
    stop:NoteBidSent()
  end
  if OnyxiaGold.Log and OnyxiaGold.Log.Debug then
    OnyxiaGold.Log:Debug("UI", string.format(
      "PlaceAuctionBid list index=%d buyout=%d count=%d",
      bid.index, bid.buyout, bid.count
    ))
  end
  self:AcceptHouseConfirm()
  self:UpdateList()
end

-- Largest unlocked bag stack of this item. Prefers a stack that covers need.
local function bagStackForPost(itemID, need)
  itemID = tonumber(itemID)
  need = tonumber(need) or 1
  if need < 1 then
    need = 1
  end
  if not itemID or type(GetContainerNumSlots) ~= "function" or type(GetContainerItemLink) ~= "function" then
    return nil
  end
  local bagSlots = NUM_BAG_SLOTS or 4
  local bestBag, bestSlot, bestCount
  for bag = 0, bagSlots do
    local slots = GetContainerNumSlots(bag)
    if slots and slots > 0 then
      for slot = 1, slots do
        local link = GetContainerItemLink(bag, slot)
        local id = OnyxiaGold.ParseItemID(link)
        if id == itemID then
          local _, count, locked = GetContainerItemInfo(bag, slot)
          count = tonumber(count) or 0
          local taken = locked == 1 or locked == true
          if not taken and count > 0 then
            if count >= need then
              return bag, slot, count
            end
            if not bestCount or count > bestCount then
              bestBag, bestSlot, bestCount = bag, slot, count
            end
          end
        end
      end
    end
  end
  return bestBag, bestSlot, bestCount
end

function UI:PaintPostRow(row, action)
  local button = row and row.postButton
  if button then
    button:Hide()
  end
  if not button or not action or action.kind ~= "POST" then
    return
  end
  if not auctionHouseOpen() then
    return
  end
  button:Show()
end

-- Hardware click. Pickup, the sell slot, and StartAuction stay in this handler.
function UI:OnPostClick(row)
  local action = row and row.action
  if not action or action.kind ~= "POST" then
    return
  end
  if not auctionHouseOpen() then
    self:SetStatus("Open the Auction House to post.")
    return
  end
  local itemID = tonumber(action.outputItemID)
  local stack = tonumber(action.stackSize) or 1
  if stack < 1 then
    stack = 1
  end
  local saleUnit = tonumber(action.saleUnit) or 0
  if not itemID or saleUnit < 1 then
    self:SetStatus("No sale price for that stack.")
    return
  end
  local age = OnyxiaGold.Prices and OnyxiaGold.Prices.GetAge and OnyxiaGold.Prices:GetAge(itemID)
  local stale = true
  if OnyxiaGold.Lots and OnyxiaGold.Lots.IsStale then
    stale = OnyxiaGold.Lots.IsStale(age, OnyxiaGold.Config and OnyxiaGold.Config.QuickScanStaleSeconds)
  end
  local record = OnyxiaGold.Prices and OnyxiaGold.Prices.GetRecord and OnyxiaGold.Prices:GetRecord(itemID)
  local external = record and record.source == "external"
  local marketMin = OnyxiaGold.Prices and OnyxiaGold.Prices.GetMarketMinimum and OnyxiaGold.Prices:GetMarketMinimum(itemID)
  local ownMin = OnyxiaGold.AuctionStop and OnyxiaGold.AuctionStop.OwnCheapestUnit
    and OnyxiaGold.AuctionStop.OwnCheapestUnit(itemID)
  local floorUnit = tonumber(action.economicFloor) or saleUnit
  local policyOwn = ownMin
  if action.flip and ownMin and saleUnit >= ownMin then
    policyOwn = nil
  end
  local policy = OnyxiaGold.Lots and OnyxiaGold.Lots.PostPolicy and OnyxiaGold.Lots.PostPolicy({
    economicFloor = floorUnit,
    marketMinimum = marketMin,
    ownMinimum = policyOwn,
    stackSize = stack,
    stale = stale,
    external = external and true or false,
    liveValidated = not stale and not external,
  })
  local buyout = policy and policy.totalBuyout or math.floor(saleUnit * stack + 0.5)
  if action.flip and ownMin and policy and policy.targetPrice and policy.targetPrice < ownMin then
    self:SetStatus("That price would undercut your auction.")
    return
  end
  local allowed = OnyxiaGold.Lots and OnyxiaGold.Lots.AllowStartAuction and OnyxiaGold.Lots.AllowStartAuction({
    validated = policy and policy.decision == "post",
    stale = stale,
    external = external and true or false,
    matches = policy and action.stackBuyout and policy.totalBuyout == action.stackBuyout,
    buyout = buyout,
  })
  if not allowed then
    if policy and policy.decision == "needs_validation" then
      self:SetStatus("Need a fresh market check before posting. Run a scan of this item, then click Post again.")
    elseif policy and action.stackBuyout and policy.totalBuyout ~= action.stackBuyout then
      self:SetStatus("Price changed. The row will refresh. Click Post again to list at the checked price.")
      if OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.Refresh then
        OnyxiaGold.ActionPlanner:Refresh()
      end
      self:Refresh()
    else
      self:SetStatus("That post is not live-checked, so it was not listed.")
    end
    return
  end
  if type(PickupContainerItem) ~= "function"
    or type(ClickAuctionSellItemButton) ~= "function"
    or type(StartAuction) ~= "function" then
    self:SetStatus("The auction house did not take that post.")
    return
  end
  local bag, slot, count = bagStackForPost(itemID, stack)
  if not bag then
    if OnyxiaGold.Inventory and OnyxiaGold.Inventory.ScanBags then
      OnyxiaGold.Inventory:ScanBags()
    end
    if OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.Refresh then
      OnyxiaGold.ActionPlanner:Refresh()
    end
    self:Refresh()
    self:SetStatus("That item is not in your bags.")
    return
  end
  local postCount = stack
  if postCount > count then
    postCount = count
  end
  if postCount < 1 then
    self:SetStatus("That item is not in your bags.")
    return
  end
  local unit = (policy and policy.targetPrice) or saleUnit
  buyout = math.floor(unit * postCount + 0.5)
  local bid = buyout
  local duration = tonumber(action.duration) or 2
  if duration ~= 1 and duration ~= 2 and duration ~= 3 then
    duration = 2
  end
  if type(GetAuctionSellItemInfo) == "function" then
    local existing = GetAuctionSellItemInfo()
    if type(existing) == "string" and existing ~= "" then
      ClickAuctionSellItemButton()
      if type(ClearCursor) == "function" then
        ClearCursor()
      end
    end
  end
  if type(CursorHasItem) == "function" and CursorHasItem() and type(ClearCursor) == "function" then
    ClearCursor()
  end
  PickupContainerItem(bag, slot)
  if type(CursorHasItem) == "function" and not CursorHasItem() then
    self:SetStatus("Could not pick up that stack.")
    return
  end
  ClickAuctionSellItemButton()
  StartAuction(bid, buyout, duration, postCount, 1)
  if OnyxiaGold.Log and OnyxiaGold.Log.Debug then
    OnyxiaGold.Log:Debug("UI", string.format(
      "StartAuction item=%d count=%d bid=%d buyout=%d duration=%d",
      itemID, postCount, bid, buyout, duration
    ))
  end
  if OnyxiaGold.Inventory and OnyxiaGold.Inventory.ScanBags then
    OnyxiaGold.Inventory:ScanBags()
  end
  if OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.Refresh then
    OnyxiaGold.ActionPlanner:Refresh()
  end
  self:Refresh()
  local postedName = itemID and OnyxiaGold.Data.GetItemName(itemID) or "item"
  self:SetStatus(string.format("Posted %d %s.", postCount, postedName))
end

function UI:AcceptHouseConfirm()
  local names = {
    BUYOUT_AUCTION = true,
    CONFIRM_BUYOUT = true,
    CONFIRM_AUCTION_BUYOUT = true,
  }
  local n = STATICPOPUP_NUMDIALOGS or 4
  for i = 1, n do
    local popup = _G["StaticPopup" .. i]
    if popup and popup.IsShown and popup:IsShown() and names[popup.which] then
      local button = _G["StaticPopup" .. i .. "Button1"]
      if button and button.Click then
        local enabled = true
        if button.IsEnabled then
          local flag = button:IsEnabled()
          enabled = flag == 1 or flag == true
        end
        if enabled then
          pcall(button.Click, button)
        end
      end
      return
    end
  end
end

function UI:VisibleRowCount()
  local height
  local scroll = self.scroll
  if scroll and scroll.GetHeight then
    height = tonumber(scroll:GetHeight())
  end
  if not height or height <= 0 then
    local frame = self.frame
    local frameHeight = frame and frame.GetHeight and tonumber(frame:GetHeight())
    if frameHeight and frameHeight > 0 then
      -- Title, auction, options, summary, list chrome, trades, and mail.
      height = frameHeight - 418
    end
  end
  if not height or height <= 0 then
    return 1
  end
  local count = math.floor(height / ROW_HEIGHT)
  if count < 1 then
    count = 1
  end
  if count > NUM_ROWS then
    count = NUM_ROWS
  end
  return count
end

function UI:SaveWindowSize()
  local frame = self.frame
  if not frame or not frame.GetWidth then
    return
  end
  local width = tonumber(frame:GetWidth())
  local height = tonumber(frame:GetHeight())
  if not width or not height or width < (MIN_WIDTH - 1) or height < (MIN_HEIGHT - 1) then
    return
  end
  width = math.floor(width + 0.5)
  height = math.floor(height + 0.5)
  if width < MIN_WIDTH then
    width = MIN_WIDTH
  end
  if height < MIN_HEIGHT then
    height = MIN_HEIGHT
  end
  if width > MAX_WIDTH then
    width = MAX_WIDTH
  end
  if height > MAX_HEIGHT then
    height = MAX_HEIGHT
  end
  if OnyxiaGold.Database and OnyxiaGold.Database.Ensure then
    OnyxiaGold.Database:Ensure()
  end
  if type(OnyxiaGoldDB) ~= "table" then
    return
  end
  if type(OnyxiaGoldDB.settings) ~= "table" then
    OnyxiaGoldDB.settings = {}
  end
  OnyxiaGoldDB.settings.windowWidth = width
  OnyxiaGoldDB.settings.windowHeight = height
end

function UI:UpdateInventoryList()
  local results = self.factoryRows or {}
  local n = table.getn(results)
  local visible = self:VisibleRowCount()
  FauxScrollFrame_Update(self.scroll, n, visible, ROW_HEIGHT)
  local offset = FauxScrollFrame_GetOffset(self.scroll) or 0
  for i = 1, NUM_ROWS do
    local row = self.rows[i]
    local item = results[offset + i]
    if i > visible or not item then
      clearRow(row)
    else
      row.action = nil
      row.factoryItem = item
      row:Show()
      if row.buyButton then
        row.buyButton:Hide()
      end
      if row.postButton then
        row.postButton:Hide()
      end
      row.cells.name:SetText(tostring(item.name or item.itemID) .. " x" .. tostring(item.count or 0))
      setRGB(row.cells.name, 1, 1, 1)
      if item.worth then
        row.cells.profit:SetText(OnyxiaGold.FormatMoney(item.worth))
      else
        row.cells.profit:SetText("")
      end
      setRGB(row.cells.profit, 1, 1, 1)
      row.cells.cash:SetText(item.place or "")
      setRGB(row.cells.cash, 1, 1, 1)
      row.cells.crafts:SetText(item.badge or "?")
      local color = BADGE_COLOR[item.badge] or BADGE_COLOR["?"]
      setRGB(row.cells.crafts, color[1], color[2], color[3])
      row.cells.type:SetText(item.label or "")
      setRGB(row.cells.type, color[1], color[2], color[3])
    end
  end
end

function UI:PaintSessionLine()
  local label = self.nextAction
  if not label then
    return
  end
  if self.listMode == "inventory" then
    label:SetText("")
    return
  end
  local session
  if OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.GetSession then
    session = OnyxiaGold.ActionPlanner:GetSession()
  end
  local line = session and session.nextLine or ""
  local summary = session and session.summaryLine or ""
  if line ~= "" and summary ~= "" then
    label:SetText(line .. " " .. summary)
  else
    label:SetText(line or "")
  end
end

function UI:UpdateList()
  if not self.rows then
    return
  end
  self:PaintSessionLine()
  self:LayoutColumns()
  paintHeaders(self)
  if self.listMode == "inventory" then
    self:UpdateInventoryList()
    return
  end
  local results = {}
  if OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.GetActions then
    results = OnyxiaGold.ActionPlanner:GetActions()
  end
  local n = table.getn(results)
  local visible = self:VisibleRowCount()
  FauxScrollFrame_Update(self.scroll, n, visible, ROW_HEIGHT)
  local offset = FauxScrollFrame_GetOffset(self.scroll) or 0

  for i = 1, NUM_ROWS do
    local row = self.rows[i]
    if i > visible then
      clearRow(row)
    else
    local action = results[offset + i]
    row.action = action
    row.opp = action and action.sourceOpp or nil
    if action then
      row.factoryItem = nil
      row:Show()
      local label = tostring(offset + i) .. ". " .. rowTitle(action)
      row.cells.name:SetText(label)
      local previewRow = action.kind == "SKILL_PREVIEW" or action.kind == "GOLD_PREVIEW"
      paintTone(row, previewRow)
      if action.kind == "COLLECT_MAIL" then
        row.cells.profit:SetText("")
        local ready = OnyxiaGold.FormatGoldShort(action.claimable or 0)
        if action.mailPartial then
          ready = "~" .. ready .. "+"
        end
        row.cells.cash:SetText(ready .. " ready")
        row.cells.crafts:SetText("")
      else
        row.cells.profit:SetText(OnyxiaGold.FormatMoneySigned(action.expectedProfit or 0))
        row.cells.cash:SetText(OnyxiaGold.FormatMoney(action.cashRequiredNow or 0))
        row.cells.crafts:SetText(tostring(action.crafts or 0))
      end
      row.cells.type:SetText(action.typeLabel or action.kind or "")
      if previewRow and row.buyButton then
        row.buyButton:Hide()
      end
      if previewRow and row.postButton then
        row.postButton:Hide()
      end
      self:PaintBuyRow(row, action)
      self:PaintPostRow(row, action)
    else
      if row.buyButton then
        row.buyButton:Hide()
      end
      if row.postButton then
        row.postButton:Hide()
      end
      clearRow(row)
    end
    end
  end
end

function UI:Refresh()
  if not self.frame then
    self:Create()
  end
  if self.masterCheck then
    if OnyxiaGold:IsTransmuteMasterOverride() then
      self.masterCheck:SetChecked(1)
    else
      self.masterCheck:SetChecked(0)
    end
  end
  if self.skillCheck then
    local on = OnyxiaGoldDB and OnyxiaGoldDB.settings and OnyxiaGoldDB.settings.showAboveSkill
    if on then
      self.skillCheck:SetChecked(1)
    else
      self.skillCheck:SetChecked(0)
    end
  end
  if self.goldCheck then
    local on = OnyxiaGoldDB and OnyxiaGoldDB.settings and OnyxiaGoldDB.settings.showBeyondGold
    if on then
      self.goldCheck:SetChecked(1)
    else
      self.goldCheck:SetChecked(0)
    end
  end

  self:RefreshHeader()

  if self.listMode == "inventory" then
    local held = {}
    if OnyxiaGold.FactoryInventory and OnyxiaGold.FactoryInventory.Rows then
      held = OnyxiaGold.FactoryInventory:Rows()
    end
    self:PaintFactoryInventory(held)
    if not OnyxiaGold.Scanner:IsScanning() then
      self:SetStatus(tostring(table.getn(held)) .. " held items. Badge and tooltip say worth and why.")
    end
    self:UpdateList()
    self:PaintScanProgress()
    self:RefreshTrades()
    return
  end

  local actions = {}
  if OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.GetActions then
    actions = OnyxiaGold.ActionPlanner:GetActions()
  end
  local real = 0
  local preview = 0
  local beyond = 0
  for i = 1, table.getn(actions) do
    if actions[i].kind == "SKILL_PREVIEW" then
      preview = preview + 1
    elseif actions[i].kind == "GOLD_PREVIEW" then
      beyond = beyond + 1
    else
      real = real + 1
    end
  end

  if OnyxiaGold.Scanner:IsScanning() then
    -- Scanner owns the status line while a scan is in progress.
  else
    local hint = OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner:UnknownRecipeHint()
    if real == 0 and preview == 0 and beyond == 0 then
      local market = OnyxiaGold.Database:GetMarket()
      if not market or not market.latest or not next(market.latest) then
        self:SetStatus("No price data yet. Open the Auction House and click Quick Scan.")
      elseif hint then
        self:SetStatus(hint)
      else
        self:SetStatus("Nothing actionable with current gold, bags, and professions.")
      end
    else
      local extra = hint and ("  " .. hint) or ""
      if preview > 0 then
        extra = extra .. "  " .. tostring(preview) .. " above your skill."
      end
      if beyond > 0 then
        extra = extra .. "  " .. tostring(beyond) .. " beyond your gold."
      end
      if real == 0 then
        local bits = {}
        if preview > 0 then
          table.insert(bits, tostring(preview) .. " above your skill")
        end
        if beyond > 0 then
          table.insert(bits, tostring(beyond) .. " beyond your gold")
        end
        self:SetStatus(table.concat(bits, ". ") .. "." .. (hint and ("  " .. hint) or ""))
      else
        local session = OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.GetSession and OnyxiaGold.ActionPlanner:GetSession()
        local steps = session and tonumber(session.activeSteps) or 0
        if steps > 0 then
          local word = "steps"
          if steps == 1 then
            word = "step"
          end
          self:SetStatus(tostring(steps) .. " " .. word .. " in this session." .. extra)
        else
          self:SetStatus(tostring(real) .. " personal actions from current capital." .. extra)
        end
      end
    end
  end

  self:UpdateList()
  self:PaintScanProgress()
  self:RefreshTrades()
end

function UI:RefreshTrades()
  if not self.tradeEdit then
    return
  end
  local text = ""
  local totals = "Spent 0c    Received 0c"
  if OnyxiaGold.TradeLog and OnyxiaGold.TradeLog.Dump then
    text = OnyxiaGold.TradeLog:Dump() or ""
  end
  if OnyxiaGold.TradeLog and OnyxiaGold.TradeLog.TotalsLine then
    totals = OnyxiaGold.TradeLog:TotalsLine()
  end
  if self.tradeTotals then
    self.tradeTotals:SetText(totals)
  end
  local edit = self.tradeEdit
  edit.freeze = false
  edit:SetText(text)
  edit.frozenText = text
  edit.freeze = true
  local _, breaks = string.gsub(text, "\n", "\n")
  local lines = (breaks or 0) + 1
  if text == "" then
    lines = 1
  end
  local minH = 36
  if self.tradeScroll and self.tradeScroll.GetHeight then
    local scrollH = tonumber(self.tradeScroll:GetHeight())
    if scrollH and scrollH > 20 then
      minH = scrollH
    end
  end
  edit:SetHeight(math.max(minH, lines * 14 + 8))
  if self.tradeScroll and self.tradeScroll.UpdateScrollChildRect then
    self.tradeScroll:UpdateScrollChildRect()
  end
end

function UI:CopyTrades()
  if not self.tradeEdit then
    return
  end
  self:RefreshTrades()
  self.tradeEdit:SetFocus()
  self.tradeEdit:HighlightText()
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

function UI:EnsureAuctionHouseButton()
  if getglobal("OnyxiaGoldAuctionButton") or not AuctionFrame then
    return
  end
  local btn = CreateFrame("Button", "OnyxiaGoldAuctionButton", AuctionFrame, "UIPanelButtonTemplate")
  btn:SetWidth(110)
  btn:SetHeight(22)
  btn:SetText("OnyxiaGold")
  local function raiseButton(self)
    local parent = self:GetParent()
    if not parent then
      return
    end
    self:SetFrameStrata(parent:GetFrameStrata())
    local level = parent:GetFrameLevel() or 1
    if level < 1 then
      level = 1
    end
    self:SetFrameLevel(level + 5)
  end
  raiseButton(btn)
  btn:HookScript("OnShow", raiseButton)
  if AuctionFrameCloseButton then
    btn:SetPoint("TOPRIGHT", AuctionFrameCloseButton, "TOPLEFT", -8, -5)
  else
    btn:SetPoint("TOPRIGHT", AuctionFrame, "TOPRIGHT", -36, -13)
  end
  btn:SetScript("OnClick", function()
    OnyxiaGold.UI:Toggle()
  end)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Open OnyxiaGold", 1, 1, 1)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  self.auctionButton = btn
end

local auctionWatcher = CreateFrame("Frame", "OnyxiaGoldAuctionWatcher", UIParent)
auctionWatcher:RegisterEvent("ADDON_LOADED")
auctionWatcher:RegisterEvent("AUCTION_HOUSE_SHOW")
auctionWatcher:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name ~= "Blizzard_AuctionUI" then
    return
  end
  OnyxiaGold.UI:EnsureAuctionHouseButton()
end)

if AuctionFrame then
  UI:EnsureAuctionHouseButton()
end
