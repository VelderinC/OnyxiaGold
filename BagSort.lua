--[[
  OnyxiaGold.BagSort
  One backpack click stacks partial stacks, then packs items to the back
  of the backpack and the equipped bags. Empty slots end up at the front.

  Swaps run inside that button click. Nothing is scheduled after it returns.
  Bank, mail, keyring, and equipped gear are not touched.
  Compatible with Lua 5.1 / WoW 3.3.5a.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.BagSort = OnyxiaGold.BagSort or {}

local BagSort = OnyxiaGold.BagSort

local BUTTON_NAME = "OnyxiaGoldBagSortButton"
local TOOLTIP = "Stack items and pack them to the back."

local function carriedBagLimit()
  return NUM_BAG_SLOTS or 4
end

local function isCarriedBag(bag)
  bag = tonumber(bag)
  if not bag or bag < 0 then
    return false
  end
  return bag <= carriedBagLimit()
end

local function parseItemID(link)
  if OnyxiaGold.ParseItemID then
    return OnyxiaGold.ParseItemID(link)
  end
  if type(link) ~= "string" then
    return nil
  end
  return tonumber(string.match(link, "item:(%d+)"))
end

local function isLockedFlag(locked)
  if locked == true then
    return true
  end
  return type(locked) == "number" and locked > 0
end

local function copySlot(slot)
  return {
    bag = slot.bag,
    slot = slot.slot,
    itemID = slot.itemID,
    count = slot.count,
    maxStack = slot.maxStack,
    name = slot.name,
    family = slot.family,
    bagFamily = slot.bagFamily,
    bagName = slot.bagName,
    locked = slot.locked,
  }
end

local function clearItem(slot)
  slot.itemID = nil
  slot.count = 0
  slot.maxStack = nil
  slot.name = nil
  slot.family = nil
end

-- A normal bag holds every item. A specialty bag holds only a matching family.
local function itemFits(item, dest)
  local bagFamily = dest.bagFamily or 0
  if bagFamily == 0 then
    return true
  end
  if bagFamily < 0 then
    return false
  end
  local family = item.family or 0
  if family == 0 then
    return false
  end
  if type(bit) ~= "table" or type(bit.band) ~= "function" then
    return false
  end
  if bit.band(family, bagFamily) == 0 then
    return false
  end
  return true
end

local function cannotHoldMessage(item, dest)
  local bagName = dest.bagName
  if type(bagName) ~= "string" or bagName == "" then
    bagName = "That bag"
  end
  local itemName = item.name
  if type(itemName) ~= "string" or itemName == "" then
    itemName = "this item"
  end
  return bagName .. " cannot hold " .. itemName .. ", so the sort stopped."
end

local function stackSlots(slots, ops)
  local seen = {}
  local ids = {}
  local n = table.getn(slots)
  for i = 1, n do
    local itemID = slots[i].itemID
    if itemID and not seen[itemID] then
      seen[itemID] = true
      table.insert(ids, itemID)
    end
  end
  for idIndex = 1, table.getn(ids) do
    local itemID = ids[idIndex]
    local guard = 0
    while true do
      guard = guard + 1
      if guard > 1000 then
        return "Could not finish stacking, so the sort stopped."
      end
      local destIndex = nil
      for i = n, 1, -1 do
        local dest = slots[i]
        if dest.itemID == itemID and dest.maxStack and dest.count < dest.maxStack then
          destIndex = i
          break
        end
      end
      if not destIndex then
        break
      end
      local srcIndex = nil
      for i = 1, destIndex - 1 do
        local src = slots[i]
        if src.itemID == itemID and src.count and src.count > 0 then
          srcIndex = i
          break
        end
      end
      if not srcIndex then
        break
      end
      local dest = slots[destIndex]
      local src = slots[srcIndex]
      local room = dest.maxStack - dest.count
      local amount = src.count
      if amount > room then
        amount = room
      end
      if amount < 1 then
        break
      end
      table.insert(ops, {
        kind = "pour",
        srcBag = src.bag,
        srcSlot = src.slot,
        dstBag = dest.bag,
        dstSlot = dest.slot,
        amount = amount,
        itemID = itemID,
      })
      dest.count = dest.count + amount
      src.count = src.count - amount
      if src.count < 1 then
        clearItem(src)
      end
    end
  end
  return nil
end

local function packSlots(slots, ops)
  local n = table.getn(slots)
  local writeIndex = n
  for readIndex = n, 1, -1 do
    local src = slots[readIndex]
    if src.itemID then
      if readIndex ~= writeIndex then
        local dest = slots[writeIndex]
        if dest.itemID then
          return "Could not pack into an occupied slot, so the sort stopped."
        end
        if not itemFits(src, dest) then
          return cannotHoldMessage(src, dest)
        end
        table.insert(ops, {
          kind = "move",
          srcBag = src.bag,
          srcSlot = src.slot,
          dstBag = dest.bag,
          dstSlot = dest.slot,
          itemID = src.itemID,
          name = src.name,
          family = src.family,
        })
        dest.itemID = src.itemID
        dest.count = src.count
        dest.maxStack = src.maxStack
        dest.name = src.name
        dest.family = src.family
        clearItem(src)
      end
      writeIndex = writeIndex - 1
    end
  end
  return nil
end

-- Returns the swaps to run, then an error string if a later swap is not legal.
-- Locked slots produce no swaps.
function BagSort:Plan(slots)
  local work = {}
  for i = 1, table.getn(slots) do
    local slot = slots[i]
    if not isCarriedBag(slot.bag) then
      return {}, "Cannot move items outside the backpack and equipped bags, so the sort stopped."
    end
    work[i] = copySlot(slot)
  end
  for i = 1, table.getn(work) do
    if work[i].locked then
      return {}, "A bag slot is locked, so the sort stopped."
    end
  end
  local ops = {}
  local stackErr = stackSlots(work, ops)
  if stackErr then
    return ops, stackErr
  end
  local packErr = packSlots(work, ops)
  return ops, packErr
end

function BagSort:Say(message)
  if OnyxiaGold.Print then
    OnyxiaGold:Print(message, "Bags")
  elseif DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99OnyxiaGold:|r " .. tostring(message))
  end
end

function BagSort:Blocked()
  if InCombatLockdown and InCombatLockdown() then
    self:Say("Cannot sort bags in combat.")
    return true
  end
  if CursorHasItem and CursorHasItem() then
    self:Say("Cannot sort bags while the cursor is holding an item.")
    return true
  end
  if TradeFrame and TradeFrame.IsShown and TradeFrame:IsShown() then
    self:Say("Cannot sort bags while a trade is open.")
    return true
  end
  return false
end

function BagSort:ReadSlots()
  local slots = {}
  for bag = 0, carriedBagLimit() do
    local count = 0
    if GetContainerNumSlots then
      count = GetContainerNumSlots(bag) or 0
    end
    local bagFamily = 0
    if bag ~= 0 then
      if type(GetContainerNumFreeSlots) == "function" then
        local _, family = GetContainerNumFreeSlots(bag)
        bagFamily = tonumber(family) or 0
      else
        bagFamily = -1
      end
    end
    local bagName = nil
    if type(GetBagName) == "function" then
      bagName = GetBagName(bag)
    end
    if bag == 0 and (type(bagName) ~= "string" or bagName == "") then
      bagName = "Backpack"
    end
    for slot = 1, count do
      local link = nil
      if GetContainerItemLink then
        link = GetContainerItemLink(bag, slot)
      end
      local _, itemCount, locked = nil, nil, nil
      if GetContainerItemInfo then
        _, itemCount, locked = GetContainerItemInfo(bag, slot)
      end
      itemCount = tonumber(itemCount) or 0
      local itemID = nil
      local name = nil
      local maxStack = nil
      local family = 0
      if link then
        itemID = parseItemID(link)
        if itemCount < 1 then
          itemCount = 1
        end
        if itemID and type(GetItemInfo) == "function" then
          local itemName, _, _, _, _, _, _, stack = GetItemInfo(itemID)
          name = itemName
          maxStack = tonumber(stack)
          if maxStack and maxStack < 1 then
            maxStack = nil
          end
        end
        if type(name) ~= "string" or name == "" then
          name = string.match(link, "%[(.-)%]")
        end
        if type(GetItemFamily) == "function" then
          family = tonumber(GetItemFamily(link)) or 0
        end
        if family == 0 and bagFamily > 0 then
          family = bagFamily
        end
      else
        itemCount = 0
      end
      table.insert(slots, {
        bag = bag,
        slot = slot,
        itemID = itemID,
        count = itemCount,
        maxStack = maxStack,
        name = name,
        family = family,
        bagFamily = bagFamily,
        bagName = bagName,
        locked = isLockedFlag(locked),
      })
    end
  end
  return slots
end

local function liveBagFamily(bag)
  if bag == 0 then
    return 0
  end
  if type(GetContainerNumFreeSlots) ~= "function" then
    return -1
  end
  local _, family = GetContainerNumFreeSlots(bag)
  return tonumber(family) or 0
end

local function liveItemFamily(link, bag)
  local family = 0
  if type(GetItemFamily) == "function" then
    family = tonumber(GetItemFamily(link)) or 0
  end
  local bagFamily = liveBagFamily(bag)
  if family == 0 and bagFamily > 0 then
    family = bagFamily
  end
  return family
end

local function cursorItemID()
  if type(GetCursorInfo) ~= "function" or not CursorHasItem() then
    return nil
  end
  local kind, itemID = GetCursorInfo()
  if kind == "item" then
    return tonumber(itemID)
  end
  return nil
end

-- Put the cursor back. A refused place can swap instead of merging, so undo that first.
local function restoreCursor(srcBag, srcSlot, dstBag, dstSlot, itemID, destLinkBefore)
  if not (CursorHasItem and CursorHasItem()) then
    return true
  end
  local holding = cursorItemID()
  local destNowID = parseItemID(GetContainerItemLink(dstBag, dstSlot))
  local destBeforeID = parseItemID(destLinkBefore)
  local swapped = false
  if holding and itemID and holding ~= itemID then
    swapped = true
  elseif destNowID == itemID and destBeforeID ~= itemID then
    swapped = true
  end
  if swapped then
    PickupContainerItem(dstBag, dstSlot)
  end
  if CursorHasItem and CursorHasItem() then
    PickupContainerItem(srcBag, srcSlot)
  end
  return not (CursorHasItem and CursorHasItem())
end

local function pickupFailedMessage(locked)
  if isLockedFlag(locked) then
    return "A bag slot is locked, so the sort stopped."
  end
  return "Could not pick up that item, so the sort stopped."
end

function BagSort:RunOp(op)
  if InCombatLockdown and InCombatLockdown() then
    return false, "Cannot sort bags in combat."
  end
  if TradeFrame and TradeFrame.IsShown and TradeFrame:IsShown() then
    return false, "Cannot sort bags while a trade is open."
  end
  if CursorHasItem and CursorHasItem() then
    return false, "Cannot sort bags while the cursor is holding an item."
  end
  if not isCarriedBag(op.srcBag) or not isCarriedBag(op.dstBag) then
    return false, "Cannot move items outside the backpack and equipped bags, so the sort stopped."
  end

  local _, srcCount, srcLocked = GetContainerItemInfo(op.srcBag, op.srcSlot)
  local srcLink = GetContainerItemLink(op.srcBag, op.srcSlot)
  local srcID = parseItemID(srcLink)
  srcCount = tonumber(srcCount) or 0
  if not srcLink or not srcID or srcCount < 1 then
    return false, "Could not pick up that item, so the sort stopped."
  end
  if srcID ~= op.itemID then
    return false, "The bag changed during the sort, so it stopped."
  end

  local destLinkBefore = GetContainerItemLink(op.dstBag, op.dstSlot)

  if op.kind == "move" then
    if destLinkBefore then
      return false, "That slot is not empty, so the sort stopped."
    end
    local probe = {
      family = liveItemFamily(srcLink, op.srcBag),
      name = op.name,
    }
    local dest = {
      bagFamily = liveBagFamily(op.dstBag),
      bagName = GetBagName and GetBagName(op.dstBag) or nil,
    }
    if not itemFits(probe, dest) then
      return false, cannotHoldMessage(probe, dest)
    end
    PickupContainerItem(op.srcBag, op.srcSlot)
    if not CursorHasItem() then
      return false, pickupFailedMessage(srcLocked)
    end
    PickupContainerItem(op.dstBag, op.dstSlot)
    if CursorHasItem() then
      if not restoreCursor(op.srcBag, op.srcSlot, op.dstBag, op.dstSlot, op.itemID, destLinkBefore) then
        return false, "The swap was refused, and the item is still on the cursor. Click a bag slot to put it back."
      end
      return false, "That bag cannot hold this item, so the sort stopped."
    end
    if parseItemID(GetContainerItemLink(op.dstBag, op.dstSlot)) ~= op.itemID then
      return false, "The swap was refused, so the sort stopped."
    end
    return true
  end

  local amount = tonumber(op.amount) or srcCount
  if amount > srcCount then
    amount = srcCount
  end
  amount = math.floor(amount)
  if amount < 1 then
    return false, "Could not pick up that stack, so the sort stopped."
  end
  if amount >= srcCount then
    PickupContainerItem(op.srcBag, op.srcSlot)
  else
    if type(SplitContainerItem) ~= "function" then
      return false, "Could not split that stack, so the sort stopped."
    end
    SplitContainerItem(op.srcBag, op.srcSlot, amount)
  end
  if not CursorHasItem() then
    return false, pickupFailedMessage(srcLocked)
  end
  PickupContainerItem(op.dstBag, op.dstSlot)
  if CursorHasItem() then
    if not restoreCursor(op.srcBag, op.srcSlot, op.dstBag, op.dstSlot, op.itemID, destLinkBefore) then
      return false, "The swap was refused, and the item is still on the cursor. Click a bag slot to put it back."
    end
    return false, "Those items did not stack, so the sort stopped."
  end
  if parseItemID(GetContainerItemLink(op.dstBag, op.dstSlot)) ~= op.itemID then
    return false, "Those items did not stack, so the sort stopped."
  end
  return true
end

function BagSort:Sort()
  if self:Blocked() then
    return
  end
  local slots = self:ReadSlots()
  local ops, err = self:Plan(slots)
  for i = 1, table.getn(ops) do
    local ok, message = self:RunOp(ops[i])
    if not ok then
      self:Say(message)
      return
    end
  end
  if err then
    self:Say(err)
    return
  end
  if OnyxiaGold.Log and OnyxiaGold.Log.Debug then
    OnyxiaGold.Log:Debug("Bags", "Bag sort finished (" .. tostring(table.getn(ops)) .. " swaps)")
  end
end

local function raiseButton(btn)
  local parent = btn:GetParent()
  if not parent then
    return
  end
  if parent.GetFrameStrata and btn.SetFrameStrata then
    local strata = parent:GetFrameStrata()
    if strata then
      btn:SetFrameStrata(strata)
    end
  end
  local level = 1
  if parent.GetFrameLevel then
    level = parent:GetFrameLevel() or 1
  end
  if level < 1 then
    level = 1
  end
  if btn.SetFrameLevel then
    btn:SetFrameLevel(level + 10)
  end
end

-- Sits on the gold row, left of the coin frame, so the close button stays clear.
local function anchorButton(btn, frame)
  btn:SetParent(frame)
  btn:ClearAllPoints()
  local money = getglobal(frame:GetName() .. "MoneyFrame")
  if money then
    btn:SetPoint("RIGHT", money, "LEFT", -6, 0)
  else
    btn:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 10, -228)
  end
  raiseButton(btn)
  if frame.GetID and frame:GetID() == 0 then
    btn:Show()
  else
    btn:Hide()
  end
end

local function watchFrame(btn, frame)
  if not frame or not frame.HookScript or frame.onyxiaGoldSortWatch then
    return
  end
  frame.onyxiaGoldSortWatch = true
  frame:HookScript("OnShow", function(self)
    if self:GetID() == 0 then
      anchorButton(btn, self)
    elseif btn:GetParent() == self then
      btn:Hide()
    end
  end)
end

function BagSort:EnsureButton()
  if type(getglobal) == "function" and getglobal(BUTTON_NAME) then
    return
  end
  if type(CreateFrame) ~= "function" or not ContainerFrame1 then
    return
  end
  local btn = CreateFrame("Button", BUTTON_NAME, ContainerFrame1, "UIPanelButtonTemplate")
  btn:SetWidth(48)
  btn:SetHeight(22)
  btn:SetText("Sort")
  btn:SetScript("OnClick", function()
    BagSort:Sort()
  end)
  btn:SetScript("OnEnter", function(self)
    if not GameTooltip then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(TOOLTIP, 1, 1, 1)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  local frames = NUM_CONTAINER_FRAMES or 13
  local shownBackpack = nil
  for i = 1, frames do
    local frame = getglobal("ContainerFrame" .. i)
    watchFrame(btn, frame)
    if frame and frame.GetID and frame:GetID() == 0 and frame.IsShown and frame:IsShown() then
      shownBackpack = frame
    end
  end
  anchorButton(btn, shownBackpack or ContainerFrame1)
end

BagSort:EnsureButton()
