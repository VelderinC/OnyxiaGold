--[[
  OnyxiaGold.BagQuality
  Thin quality rims on default bag slots. Poor and common stay plain.
  Refreshed when a bag frame updates, including after Sort.
  No timers, and this file never calls PickupContainerItem.
  Compatible with Lua 5.1 / WoW 3.3.5a.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.BagQuality = OnyxiaGold.BagQuality or {}

local BagQuality = OnyxiaGold.BagQuality

local INSET = 3
local THICK = 2
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function hideEdges(edges)
  if not edges then
    return
  end
  for i = 1, 4 do
    if edges[i] then
      edges[i]:Hide()
    end
  end
end

local function makeEdge(button)
  local tex = button:CreateTexture(nil, "OVERLAY")
  tex:SetTexture(WHITE)
  tex:Hide()
  return tex
end

-- Four strokes around the icon. The middle of the icon stays clear.
local function ensureEdges(button)
  if button.onyxiaGoldQuality then
    return button.onyxiaGoldQuality
  end
  local top = makeEdge(button)
  top:SetPoint("TOPLEFT", button, "TOPLEFT", INSET, -INSET)
  top:SetPoint("TOPRIGHT", button, "TOPRIGHT", -INSET, -INSET)
  top:SetHeight(THICK)

  local bottom = makeEdge(button)
  bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", INSET, INSET)
  bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -INSET, INSET)
  bottom:SetHeight(THICK)

  local left = makeEdge(button)
  left:SetPoint("TOPLEFT", button, "TOPLEFT", INSET, -(INSET + THICK))
  left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", INSET, INSET + THICK)
  left:SetWidth(THICK)

  local right = makeEdge(button)
  right:SetPoint("TOPRIGHT", button, "TOPRIGHT", -INSET, -(INSET + THICK))
  right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -INSET, INSET + THICK)
  right:SetWidth(THICK)

  button.onyxiaGoldQuality = { top, bottom, left, right }
  return button.onyxiaGoldQuality
end

local function paintEdges(edges, quality)
  if type(GetItemQualityColor) ~= "function" then
    hideEdges(edges)
    return
  end
  local r, g, b = GetItemQualityColor(quality)
  r = tonumber(r)
  g = tonumber(g)
  b = tonumber(b)
  if not r or not g or not b then
    hideEdges(edges)
    return
  end
  for i = 1, 4 do
    edges[i]:SetVertexColor(r, g, b, 1)
    edges[i]:Show()
  end
end

function BagQuality:UpdateButton(button, bag)
  if not button then
    return
  end
  local edges = button.onyxiaGoldQuality
  if not button.IsShown or not button:IsShown() then
    hideEdges(edges)
    return
  end
  local slot = button.GetID and button:GetID() or nil
  bag = tonumber(bag)
  slot = tonumber(slot)
  local quality = nil
  if bag and slot and type(GetContainerItemInfo) == "function" then
    local _, _, _, itemQuality = GetContainerItemInfo(bag, slot)
    quality = tonumber(itemQuality)
  end
  if (not quality or quality < 2) and bag and slot and type(GetContainerItemLink) == "function" and type(GetItemInfo) == "function" then
    local link = GetContainerItemLink(bag, slot)
    if link then
      local _, _, linkQuality = GetItemInfo(link)
      quality = tonumber(linkQuality)
    end
  end
  if not quality or quality < 2 then
    if edges then
      hideEdges(edges)
    end
    return
  end
  paintEdges(ensureEdges(button), quality)
end

function BagQuality:UpdateFrame(frame)
  if not frame or not frame.GetName or not frame.GetID then
    return
  end
  if frame.IsShown and not frame:IsShown() then
    return
  end
  local slots = tonumber(frame.size)
  if not slots or slots < 1 then
    return
  end
  local name = frame:GetName()
  local bag = frame:GetID()
  if not name then
    return
  end
  for i = 1, slots do
    local button = getglobal(name .. "Item" .. i)
    if button then
      self:UpdateButton(button, bag)
    end
  end
end

function BagQuality:Refresh()
  local frames = NUM_CONTAINER_FRAMES or 13
  for i = 1, frames do
    local frame = getglobal("ContainerFrame" .. i)
    if frame then
      self:UpdateFrame(frame)
    end
  end
end

function BagQuality:InstallHooks()
  if self.hooksInstalled or type(hooksecurefunc) ~= "function" then
    return
  end
  self.hooksInstalled = true
  if type(ContainerFrame_Update) ~= "function" then
    self.hooksInstalled = false
    return
  end
  hooksecurefunc("ContainerFrame_Update", function(frame)
    BagQuality:UpdateFrame(frame)
  end)
end

local events = CreateFrame("Frame", "OnyxiaGoldBagQualityEvents")
events:RegisterEvent("BAG_UPDATE")
events:SetScript("OnEvent", function()
  BagQuality:InstallHooks()
  BagQuality:Refresh()
end)

BagQuality:InstallHooks()
