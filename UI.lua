--[[
  OnyxiaGold.UI
  Presentation only. Native 3.3.5a frames.
  Header is personal economic state. Main list is what to do now.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.UI = OnyxiaGold.UI or {}

local UI = OnyxiaGold.UI

local FRAME_WIDTH = 760
local FRAME_HEIGHT = 572
local NUM_ROWS = 10
local ROW_HEIGHT = 32
local HEADER_Y = -170
local LIST_TOP = HEADER_Y - 18

local COLS = {
  { key = "name", label = "What to do now", width = 360, justify = "LEFT" },
  { key = "profit", label = "EV", width = 110, justify = "RIGHT" },
  { key = "cash", label = "Cash", width = 110, justify = "RIGHT" },
  { key = "crafts", label = "Qty", width = 50, justify = "RIGHT" },
  { key = "type", label = "Type", width = 70, justify = "LEFT" },
}

local function addLabel(parent, text, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  fs:SetText(text or "")
  return fs
end

local function itemName(id)
  return OnyxiaGold.Data.GetItemName(id) or ("item:" .. tostring(id))
end

-- Buy, convert, and post stay one action. The row says all three.
local function actionInstruction(action)
  if not action or action.kind ~= "BUY_AND_CRAFT" then
    return action and action.name or ""
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

local function setRGB(fs, r, g, b)
  if fs and fs.SetTextColor then
    fs:SetTextColor(r, g, b)
  end
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
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -14)

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
  quickBtn:SetHeight(22)
  quickBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -38)
  quickBtn:SetText("Quick Scan")
  quickBtn:SetScript("OnClick", function()
    OnyxiaGold.Log:Debug("UI", "Quick Scan clicked")
    OnyxiaGold.Scanner:StartQuick()
  end)

  local fullBtn = CreateFrame("Button", "OnyxiaGoldFullScanButton", frame, "UIPanelButtonTemplate")
  fullBtn:SetWidth(90)
  fullBtn:SetHeight(22)
  fullBtn:SetPoint("LEFT", quickBtn, "RIGHT", 6, 0)
  fullBtn:SetText("Full Scan")
  fullBtn:SetScript("OnClick", function()
    OnyxiaGold.Log:Debug("UI", "Full Scan clicked")
    OnyxiaGold.Scanner:StartFull()
  end)

  local refreshBtn = CreateFrame("Button", "OnyxiaGoldRefreshButton", frame, "UIPanelButtonTemplate")
  refreshBtn:SetWidth(90)
  refreshBtn:SetHeight(22)
  refreshBtn:SetPoint("LEFT", fullBtn, "RIGHT", 6, 0)
  refreshBtn:SetText("Refresh")
  refreshBtn:SetScript("OnClick", function()
    OnyxiaGold.Log:Debug("UI", "Refresh opportunities clicked")
    OnyxiaGold.OpportunityEngine:Refresh()
  end)

  local master = CreateFrame("CheckButton", "OnyxiaGoldMasterCheck", frame, "UICheckButtonTemplate")
  master:SetWidth(24)
  master:SetHeight(24)
  master:SetPoint("LEFT", refreshBtn, "RIGHT", 8, 0)
  local masterText = getglobal("OnyxiaGoldMasterCheckText")
  if masterText then
    masterText:SetText("Force TM")
  end
  master:SetScript("OnClick", function(self)
    OnyxiaGold.Database:Ensure()
    local on = self:GetChecked() and true or false
    OnyxiaGoldDB.settings.transmuteMasterOverride = on
    OnyxiaGoldDB.settings.transmuteMaster = on
    OnyxiaGold.Log:Info("UI", "Transmute Master override " .. tostring(on))
    OnyxiaGold.OpportunityEngine:Refresh()
  end)

  local identity = addLabel(frame, "", "GameFontHighlightSmall")
  identity:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -64)
  identity:SetJustifyH("LEFT")

  local professions = addLabel(frame, "", "GameFontDisableSmall")
  professions:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -80)
  professions:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -80)
  professions:SetJustifyH("LEFT")

  local factory = addLabel(frame, "", "GameFontDisableSmall")
  factory:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -94)
  factory:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -94)
  factory:SetJustifyH("LEFT")

  local capital = addLabel(frame, "", "GameFontHighlightSmall")
  capital:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -112)
  capital:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -112)
  capital:SetJustifyH("LEFT")

  local deploy = addLabel(frame, "", "GameFontNormalSmall")
  deploy:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -128)
  deploy:SetJustifyH("LEFT")
  setRGB(deploy, 0.35, 0.85, 0.45)

  local market = addLabel(frame, "Market: —", "GameFontDisableSmall")
  market:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -144)
  market:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -144)
  market:SetJustifyH("LEFT")

  local capitalHit = CreateFrame("Frame", "OnyxiaGoldCapitalHit", frame)
  capitalHit:SetPoint("TOPLEFT", capital, "TOPLEFT", 0, 4)
  capitalHit:SetPoint("BOTTOMRIGHT", deploy, "BOTTOMRIGHT", 280, -4)
  capitalHit:EnableMouse(true)
  capitalHit:SetScript("OnEnter", function()
    UI:ShowCapitalTooltip(capitalHit)
  end)
  capitalHit:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

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
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 58)
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

    if i % 2 == 0 then
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
      fs:SetWidth(col.width - 6)
      fs:SetJustifyH(col.justify)
      fs:SetJustifyV("MIDDLE")
      fs:SetText("")
      if col.key == "name" then
        fs:SetHeight(ROW_HEIGHT - 2)
        fs:SetWordWrap(true)
        fs:SetNonSpaceWrap(false)
      end
      row.cells[col.key] = fs
      cx = cx + col.width
    end

    row:SetScript("OnEnter", function(self)
      UI:ShowActionTooltip(self)
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

  local scanBar = CreateFrame("StatusBar", "OnyxiaGoldScanBar", frame)
  scanBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 36)
  scanBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 36)
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

  self.frame = frame
  self.quickScanButton = quickBtn
  self.fullScanButton = fullBtn
  self.scanButton = quickBtn
  self.refreshButton = refreshBtn
  self.masterCheck = master
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
  GameTooltip:AddLine("Expected economic profit: " .. OnyxiaGold.FormatMoneySigned(action.expectedProfit or 0), 0.2, 1, 0.2)
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
  if action.kind == "COLLECT_MAIL" then
    GameTooltip:AddLine("Visit a mailbox and collect gold. The addon will not loot mail.", 1, 0.85, 0.4, 1)
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

function UI:UpdateList()
  if not self.rows then
    return
  end
  local results = {}
  if OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.GetActions then
    results = OnyxiaGold.ActionPlanner:GetActions()
  end
  local n = table.getn(results)
  FauxScrollFrame_Update(self.scroll, n, NUM_ROWS, ROW_HEIGHT)
  local offset = FauxScrollFrame_GetOffset(self.scroll) or 0

  for i = 1, NUM_ROWS do
    local row = self.rows[i]
    local action = results[offset + i]
    row.action = action
    row.opp = action and action.sourceOpp or nil
    if action then
      row:Show()
      local label = tostring(offset + i) .. ". " .. actionInstruction(action)
      row.cells.name:SetText(label)
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
    if OnyxiaGold:IsTransmuteMasterOverride() then
      self.masterCheck:SetChecked(1)
    else
      self.masterCheck:SetChecked(0)
    end
  end

  self:RefreshHeader()

  local actions = {}
  if OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.GetActions then
    actions = OnyxiaGold.ActionPlanner:GetActions()
  end
  local n = table.getn(actions)

  if OnyxiaGold.Scanner:IsScanning() then
    -- Scanner owns the status line while a scan is in progress.
  else
    local hint = OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner:UnknownRecipeHint()
    if n == 0 then
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
      self:SetStatus(tostring(n) .. " personal actions from current capital." .. extra)
    end
  end

  self:UpdateList()
  self:PaintScanProgress()
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
