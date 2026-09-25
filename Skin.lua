--[[
  OnyxiaGold.Skin
  How the window looks. UI.lua decides what a control is.
  Coordinates come from OnyxiaGold.MediaAtlas. WoW 3.3.5a, Lua 5.1.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Skin = OnyxiaGold.Skin or {}

local Skin = OnyxiaGold.Skin

local COLOR = {
  gold = { 1, 0.82, 0 },
  blue = { 0.55, 0.75, 0.95 },
  green = { 0.35, 0.85, 0.45 },
  red = { 0.85, 0.28, 0.22 },
  grey = { 0.55, 0.55, 0.55 },
}

local FRAME_REGIONS = {
  "background_dark_tile",
  "corner_tl",
  "corner_tr",
  "corner_bl",
  "edge_top",
  "edge_left",
}

local PANELS = {
  "OnyxiaGoldAuctionSection",
  "OnyxiaGoldOptionsSection",
  "OnyxiaGoldSummarySection",
  "OnyxiaGoldMailSection",
  "OnyxiaGoldTradesSection",
  "OnyxiaGoldListSection",
}

local SECONDARY_BUTTONS = {
  "OnyxiaGoldOpenLogButton",
  "OnyxiaGoldQuickScanButton",
  "OnyxiaGoldFullScanButton",
  "OnyxiaGoldRefreshButton",
  "OnyxiaGoldHeldButton",
  "OnyxiaGoldCollectGoldButton",
  "OnyxiaGoldFactorySweepButton",
  "OnyxiaGoldTradeCopyButton",
}

local BUTTON_STATES = {
  { setter = "SetNormalTexture", getter = "GetNormalTexture", suffix = "normal" },
  { setter = "SetHighlightTexture", getter = "GetHighlightTexture", suffix = "hover" },
  { setter = "SetPushedTexture", getter = "GetPushedTexture", suffix = "pressed" },
  { setter = "SetDisabledTexture", getter = "GetDisabledTexture", suffix = "disabled" },
}

local function atlas()
  local media = OnyxiaGold.MediaAtlas
  if not media or not media.regions or not media.texture or media.texture == "" then
    return nil
  end
  return media
end

local function hasRegions(names)
  local media = atlas()
  if not media then
    return false
  end
  for i = 1, table.getn(names) do
    if not media.regions[names[i]] then
      return false
    end
  end
  return true
end

-- Half a texel inset, then optional mirror. The inset is a guard against
-- neighboring atlas pixels. It has not been checked in the 3.3.5 client.
function Skin.RegionCoords(box, width, height, flipH, flipV)
  width = tonumber(width) or 256
  height = tonumber(height) or 128
  if width < 1 then
    width = 256
  end
  if height < 1 then
    height = 128
  end
  local insetX = 0.5 / width
  local insetY = 0.5 / height
  local left = (tonumber(box.left) or 0) + insetX
  local right = (tonumber(box.right) or 0) - insetX
  local top = (tonumber(box.top) or 0) + insetY
  local bottom = (tonumber(box.bottom) or 0) - insetY
  if left >= right or top >= bottom then
    left = tonumber(box.left) or 0
    right = tonumber(box.right) or 0
    top = tonumber(box.top) or 0
    bottom = tonumber(box.bottom) or 0
  end
  if flipH then
    left, right = right, left
  end
  if flipV then
    top, bottom = bottom, top
  end
  return left, right, top, bottom
end

local function applyRegion(tex, name, flipH, flipV)
  local media = atlas()
  local box = media and media.regions[name]
  if not tex or not box then
    return false
  end
  tex:SetTexture(media.texture)
  local left, right, top, bottom = Skin.RegionCoords(box, media.width, media.height, flipH, flipV)
  tex:SetTexCoord(left, right, top, bottom)
  return true
end

local function setColor(fs, color)
  if fs and fs.SetTextColor and color then
    fs:SetTextColor(color[1], color[2], color[3])
  end
end

local function clearBackdrop(panel)
  if not panel or not panel.SetBackdrop then
    return
  end
  local ok = pcall(panel.SetBackdrop, panel, nil)
  if not ok then
    pcall(panel.SetBackdropColor, panel, 0, 0, 0, 0)
    pcall(panel.SetBackdropBorderColor, panel, 0, 0, 0, 0)
  end
end

local function span(box, key, fallback)
  local n = box and tonumber(box[key])
  if n and n >= 1 then
    return n
  end
  return fallback
end

local function buildChrome(panel)
  if not panel or panel.ogChrome then
    return
  end
  if not hasRegions(FRAME_REGIONS) then
    return
  end
  local media = atlas()
  local corner = span(media.regions.corner_tl, "width", 12)
  local edgeY = span(media.regions.edge_top, "height", 6)
  local edgeX = span(media.regions.edge_left, "width", 6)

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", panel, "TOPLEFT", edgeX, -edgeY)
  bg:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -edgeX, edgeY)
  applyRegion(bg, "background_dark_tile")

  local tl = panel:CreateTexture(nil, "BORDER")
  tl:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
  tl:SetWidth(corner)
  tl:SetHeight(corner)
  applyRegion(tl, "corner_tl")

  local tr = panel:CreateTexture(nil, "BORDER")
  tr:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
  tr:SetWidth(corner)
  tr:SetHeight(corner)
  applyRegion(tr, "corner_tr")

  local bl = panel:CreateTexture(nil, "BORDER")
  bl:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
  bl:SetWidth(corner)
  bl:SetHeight(corner)
  applyRegion(bl, "corner_bl")

  local br = panel:CreateTexture(nil, "BORDER")
  br:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  br:SetWidth(corner)
  br:SetHeight(corner)
  applyRegion(br, "corner_tl", true, true)

  local top = panel:CreateTexture(nil, "BORDER")
  top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
  top:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)
  top:SetHeight(edgeY)
  applyRegion(top, "edge_top")

  local bottom = panel:CreateTexture(nil, "BORDER")
  bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0)
  bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
  bottom:SetHeight(edgeY)
  applyRegion(bottom, "edge_top", false, true)

  local left = panel:CreateTexture(nil, "BORDER")
  left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
  left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)
  left:SetWidth(edgeX)
  applyRegion(left, "edge_left")

  local right = panel:CreateTexture(nil, "BORDER")
  right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
  right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
  right:SetWidth(edgeX)
  applyRegion(right, "edge_left", true, false)

  clearBackdrop(panel)
  panel.ogChrome = true
end

local function hideTemplateChrome(button)
  local name = button.GetName and button:GetName()
  if not name or not getglobal then
    return
  end
  local pieces = { "Left", "Middle", "Right" }
  for i = 1, 3 do
    local piece = getglobal(name .. pieces[i])
    if piece then
      piece:Hide()
      if piece.SetAlpha then
        piece:SetAlpha(0)
      end
    end
  end
  local label = getglobal(name .. "Text")
  if label and label.SetDrawLayer then
    label:SetDrawLayer("OVERLAY")
  end
end

local function skinButton(button, kind)
  if not button or button.ogSkinned then
    return
  end
  local needed = {}
  for i = 1, table.getn(BUTTON_STATES) do
    needed[i] = "button_" .. kind .. "_" .. BUTTON_STATES[i].suffix
  end
  if not hasRegions(needed) then
    return
  end
  local media = atlas()
  local bound = {}
  for i = 1, table.getn(BUTTON_STATES) do
    local state = BUTTON_STATES[i]
    button[state.setter](button, media.texture)
    local tex = button[state.getter](button)
    if not tex then
      return
    end
    bound[i] = tex
    local box = media.regions[needed[i]]
    local left, right, top, bottom = Skin.RegionCoords(box, media.width, media.height, false, false)
    tex:SetTexCoord(left, right, top, bottom)
    if tex.SetBlendMode then
      tex:SetBlendMode("BLEND")
    end
    if tex.SetVertexColor then
      tex:SetVertexColor(1, 1, 1, 1)
    end
  end
  for i = 1, table.getn(BUTTON_STATES) do
    local box = media.regions[needed[i]]
    local left, right, top, bottom = Skin.RegionCoords(box, media.width, media.height, false, false)
    bound[i]:SetTexCoord(left, right, top, bottom)
  end
  hideTemplateChrome(button)
  if GameFontHighlight and button.SetNormalFontObject then
    button:SetNormalFontObject(GameFontHighlight)
  end
  if GameFontHighlight and button.SetHighlightFontObject then
    button:SetHighlightFontObject(GameFontHighlight)
  end
  if GameFontDisable and button.SetDisabledFontObject then
    button:SetDisabledFontObject(GameFontDisable)
  end
  button.ogSkinned = true
end

local function skinNamed(names, kind)
  if not getglobal then
    return
  end
  for i = 1, table.getn(names) do
    skinButton(getglobal(names[i]), kind)
  end
end

function Skin:StatusTone(text)
  text = text or ""
  local scanner = OnyxiaGold.Scanner
  if scanner and scanner.IsScanning and scanner:IsScanning() then
    return "info"
  end
  if string.sub(text, 1, 7) == "Posted " or string.sub(text, 1, 13) == "Scan complete" then
    return "success"
  end
  if string.sub(text, 1, 9) == "Could not" then
    return "error"
  end
  if string.find(text, "did not", 1, true) or string.find(text, "not live-checked", 1, true) then
    return "error"
  end
  if string.sub(text, 1, 18) == "Nothing actionable" then
    return "warning"
  end
  if string.sub(text, 1, 13) == "No sale price" then
    return "warning"
  end
  if string.sub(text, 1, 13) == "Price changed" then
    return "warning"
  end
  if string.sub(text, 1, 12) == "Need a fresh" then
    return "warning"
  end
  if string.sub(text, 1, 22) == "Open the Auction House" then
    return "warning"
  end
  if string.sub(text, 1, 16) == "That item is not" then
    return "warning"
  end
  if string.find(text, "interrupted", 1, true) then
    return "warning"
  end
  return "info"
end

local function toneRegion(tone)
  if tone == "success" then
    return "status_success"
  end
  if tone == "warning" then
    return "status_warning"
  end
  if tone == "error" then
    return "status_error"
  end
  return "status_info"
end

function Skin:Apply(ui)
  if not ui or ui.ogSkinApplied then
    return
  end
  ui.ogSkinApplied = true
  if not atlas() then
    return
  end
  ui.ogSkinLive = true

  if ui.frame then
    buildChrome(ui.frame)
  end
  for i = 1, table.getn(PANELS) do
    if getglobal then
      buildChrome(getglobal(PANELS[i]))
    end
  end

  skinNamed(SECONDARY_BUTTONS, "secondary")
  local rows = ui.rows
  if rows then
    for i = 1, table.getn(rows) do
      local row = rows[i]
      if row then
        skinButton(row.buyButton, "primary")
        skinButton(row.postButton, "primary")
      end
    end
  end

  if ui.frame and hasRegions({ "header_gold" }) then
    local band = ui.frame:CreateTexture(nil, "BACKGROUND")
    band:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", 8, -6)
    band:SetWidth(220)
    band:SetHeight(26)
    applyRegion(band, "header_gold")
    ui.ogHeaderBand = band
  end

  if ui.headerRule and hasRegions({ "divider_gold" }) then
    applyRegion(ui.headerRule, "divider_gold")
  end

  if ui.nextAction and hasRegions({ "glow_gold" }) then
    local parent = ui.nextAction:GetParent()
    if parent then
      local glow = parent:CreateTexture(nil, "BACKGROUND")
      glow:SetPoint("TOPLEFT", ui.nextAction, "TOPLEFT", -4, 2)
      glow:SetPoint("BOTTOMRIGHT", ui.nextAction, "BOTTOMRIGHT", 4, -2)
      glow:SetAlpha(0.28)
      applyRegion(glow, "glow_gold")
      glow:Hide()
      ui.ogNextGlow = glow
    end
  end

  local bar = ui.scanBar
  if bar and not bar.ogFill and hasRegions({ "progress_track", "progress_fill_blue" }) then
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(bar)
    applyRegion(track, "progress_track")
    bar.ogTrack = track
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    fill:SetWidth(1)
    applyRegion(fill, "progress_fill_blue")
    fill:Hide()
    bar.ogFill = fill
    local native = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if native and native.SetAlpha then
      native:SetAlpha(0)
    end
    setColor(ui.scanBarText, { 0.85, 0.93, 1 })
  end

  if ui.status and hasRegions({ "status_info", "status_success", "status_warning", "status_error" }) then
    local parent = ui.status:GetParent()
    if parent then
      local icon = parent:CreateTexture(nil, "ARTWORK")
      icon:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 5)
      icon:SetWidth(14)
      icon:SetHeight(14)
      applyRegion(icon, "status_info")
      ui.ogStatusIcon = icon
      ui.status:ClearAllPoints()
      ui.status:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 28, 5)
      ui.status:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 5)
      ui.status:SetHeight(14)
      ui.status:SetJustifyH("LEFT")
      ui.status:SetJustifyV("MIDDLE")
      ui.status:SetWordWrap(false)
    end
  end

  if ui.factoryLabel and hasRegions({ "status_success", "status_warning" }) then
    local parent = ui.factoryLabel:GetParent()
    if parent then
      local icon = parent:CreateTexture(nil, "ARTWORK")
      icon:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -26)
      icon:SetWidth(12)
      icon:SetHeight(12)
      icon:Hide()
      ui.ogFactoryIcon = icon
      ui.factoryLabel:ClearAllPoints()
      ui.factoryLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 26, -26)
      ui.factoryLabel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -26)
      ui.factoryLabel:SetHeight(12)
      ui.factoryLabel:SetJustifyH("LEFT")
      ui.factoryLabel:SetJustifyV("MIDDLE")
      ui.factoryLabel:SetWordWrap(false)
    end
  end

  setColor(ui.marketStatus, COLOR.blue)
end

function Skin:PaintScan(ui)
  local bar = ui and ui.scanBar
  local fill = bar and bar.ogFill
  if not fill then
    return
  end
  local native = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
  if native and native.SetAlpha then
    native:SetAlpha(0)
  end
  local minV, maxV = 0, 0
  if bar.GetMinMaxValues then
    minV, maxV = bar:GetMinMaxValues()
  end
  minV = tonumber(minV) or 0
  maxV = tonumber(maxV) or 0
  local value = 0
  if bar.GetValue then
    value = tonumber(bar:GetValue()) or 0
  end
  local frac = 0
  if maxV > minV then
    frac = (value - minV) / (maxV - minV)
  end
  if frac < 0 then
    frac = 0
  end
  if frac > 1 then
    frac = 1
  end
  local width = (tonumber(bar:GetWidth()) or 0) * frac
  if width < 1 then
    fill:Hide()
    return
  end
  fill:SetWidth(width)
  fill:Show()
end

function Skin:PaintStatus(ui)
  local icon = ui and ui.ogStatusIcon
  if not icon then
    return
  end
  local text = ""
  if ui.status and ui.status.GetText then
    text = ui.status:GetText() or ""
  end
  if applyRegion(icon, toneRegion(self:StatusTone(text))) then
    icon:Show()
  else
    icon:Hide()
  end
end

function Skin:PaintHeader(ui)
  if not ui or not ui.ogSkinLive then
    return
  end
  setColor(ui.marketStatus, COLOR.blue)
  local icon = ui.ogFactoryIcon
  if not icon then
    return
  end
  local text = ""
  if ui.factoryLabel and ui.factoryLabel.GetText then
    text = ui.factoryLabel:GetText() or ""
  end
  if text == "" then
    icon:Hide()
    return
  end
  local complete = false
  local cap = OnyxiaGold.Capabilities
  if cap and cap.GetFactoryStatus then
    local status = cap:GetFactoryStatus()
    if status and status.complete then
      complete = true
    end
  end
  local name = "status_warning"
  if complete then
    name = "status_success"
  end
  if applyRegion(icon, name) then
    icon:Show()
  else
    icon:Hide()
  end
end

function Skin:PaintNext(ui)
  local label = ui and ui.nextAction
  if not label then
    return
  end
  local text = ""
  if label.GetText then
    text = label:GetText() or ""
  end
  local glow = ui.ogNextGlow
  if text == "" then
    if glow then
      glow:Hide()
    end
    return
  end
  setColor(label, COLOR.gold)
  if glow then
    glow:Show()
    glow:SetAlpha(0.28)
  end
end

function Skin:PaintProfit(ui)
  local rows = ui and ui.rows
  if not rows then
    return
  end
  for i = 1, table.getn(rows) do
    local row = rows[i]
    local action = row and row.action
    local fs = row and row.cells and row.cells.profit
    if action and fs and fs.GetText and fs:GetText() ~= "" then
      local preview = action.kind == "SKILL_PREVIEW" or action.kind == "GOLD_PREVIEW"
      if not preview then
        local profit = tonumber(action.expectedProfit) or 0
        if profit > 0 then
          setColor(fs, COLOR.green)
        elseif profit < 0 then
          setColor(fs, COLOR.red)
        end
      end
    end
  end
end

function Skin:PaintList(ui)
  if not ui or not ui.ogSkinLive then
    return
  end
  self:PaintNext(ui)
  if ui.listMode == "inventory" then
    return
  end
  self:PaintProfit(ui)
end
