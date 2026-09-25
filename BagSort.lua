--[[
  OnyxiaGold.BagSort
  One backpack click stacks partial stacks, then sorts items to the back
  of the backpack and the equipped bags. Empty slots end up at the front.
  Occupied slots swap when an item belongs earlier or later.
  The Sort button is in the open backpack's title bar, just right of the portrait.

  PickupContainerItem runs inside that button click. Nothing is scheduled
  after it returns. If the client stops accepting moves, the click stops
  and the next click continues the same order.
  Bank, mail, keyring, and equipped gear are not touched.
  Compatible with Lua 5.1 / WoW 3.3.5a.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.BagSort = OnyxiaGold.BagSort or {}

local BagSort = OnyxiaGold.BagSort

local BUTTON_NAME = "OnyxiaGoldBagSortButton"
local TOOLTIP_TITLE = "Sort"
local TOOLTIP_BODY = "Stacks partial stacks, then sorts items to the back. Empty slots stay at the front. If the bags stop moving, click again."
local CONTINUE_MESSAGE = "Click Sort again to continue."
local LOCKED_MESSAGE = "A bag slot is locked. Click Sort again to continue."

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
    className = slot.className,
    subClass = slot.subClass,
    quality = slot.quality,
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
  slot.className = nil
  slot.subClass = nil
  slot.quality = nil
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

local function itemSnapshot(slot)
  return {
    itemID = slot.itemID,
    count = slot.count,
    maxStack = slot.maxStack,
    name = slot.name,
    family = slot.family,
    className = slot.className,
    subClass = slot.subClass,
    quality = slot.quality,
  }
end

local function writeItem(slot, item)
  if not item or not item.itemID then
    clearItem(slot)
    return
  end
  slot.itemID = item.itemID
  slot.count = item.count
  slot.maxStack = item.maxStack
  slot.name = item.name
  slot.family = item.family
  slot.className = item.className
  slot.subClass = item.subClass
  slot.quality = item.quality
end

local function exchangeItems(a, b)
  local tmp = itemSnapshot(a)
  writeItem(a, itemSnapshot(b))
  writeItem(b, tmp)
end

-- Higher rank sits further back. Same item id compares equal, so partial
-- stacks stay together and are never clicked onto each other.
local function ranksBehind(a, b)
  if a.itemID and not b.itemID then
    return true
  end
  if not a.itemID or not b.itemID then
    return false
  end
  local fieldsA = {
    a.className or "",
    a.subClass or "",
    tonumber(a.quality) or 0,
    a.name or "",
    tonumber(a.itemID) or 0,
  }
  local fieldsB = {
    b.className or "",
    b.subClass or "",
    tonumber(b.quality) or 0,
    b.name or "",
    tonumber(b.itemID) or 0,
  }
  for i = 1, 5 do
    if fieldsA[i] ~= fieldsB[i] then
      return fieldsA[i] > fieldsB[i]
    end
  end
  return false
end

local function canPlace(src, dest)
  if not src.itemID then
    return false
  end
  if not itemFits(src, dest) then
    return false
  end
  if dest.itemID and not itemFits(dest, src) then
    return false
  end
  return true
end

-- Share one identity across stacks of the same item so a cache miss on one
-- slot does not split them.
local function itemKeyScore(slot)
  local score = 0
  if type(slot.className) == "string" and slot.className ~= "" then
    score = score + 4
  end
  if type(slot.subClass) == "string" and slot.subClass ~= "" then
    score = score + 2
  end
  if slot.quality ~= nil then
    score = score + 1
  end
  return score
end

local function unifyItemKeys(slots)
  local known = {}
  local n = table.getn(slots)
  for i = 1, n do
    local slot = slots[i]
    if slot.itemID then
      local prev = known[slot.itemID]
      if not prev or itemKeyScore(slot) > itemKeyScore(prev) then
        known[slot.itemID] = slot
      end
    end
  end
  for i = 1, n do
    local slot = slots[i]
    local src = slot.itemID and known[slot.itemID]
    if src and src ~= slot then
      if (type(slot.className) ~= "string" or slot.className == "") and type(src.className) == "string" and src.className ~= "" then
        slot.className = src.className
      end
      if (type(slot.subClass) ~= "string" or slot.subClass == "") and type(src.subClass) == "string" and src.subClass ~= "" then
        slot.subClass = src.subClass
      end
      if slot.quality == nil and src.quality ~= nil then
        slot.quality = src.quality
      end
      if (type(slot.name) ~= "string" or slot.name == "") and type(src.name) == "string" and src.name ~= "" then
        slot.name = src.name
      end
    end
  end
end

-- Selection from the back. Each destination takes the item that belongs
-- furthest back among the slots in front of it, swapping when that slot
-- is already occupied.
local function sortSlots(slots, ops)
  unifyItemKeys(slots)
  local n = table.getn(slots)
  for destIndex = n, 1, -1 do
    local best = destIndex
    local dest = slots[destIndex]
    for srcIndex = 1, destIndex - 1 do
      local src = slots[srcIndex]
      if canPlace(src, dest) and ranksBehind(src, slots[best]) then
        best = srcIndex
      end
    end
    if best ~= destIndex then
      local src = slots[best]
      if dest.itemID then
        table.insert(ops, {
          kind = "swap",
          srcBag = src.bag,
          srcSlot = src.slot,
          dstBag = dest.bag,
          dstSlot = dest.slot,
          itemID = src.itemID,
          destItemID = dest.itemID,
          name = src.name,
          destName = dest.name,
          family = src.family,
          destFamily = dest.family,
        })
      else
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
      end
      exchangeItems(src, dest)
    end
  end
  return nil
end

-- Returns the swaps to run, then an error string if a later swap is not legal.
-- The third return is true when a locked slot should wait for the next click.
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
      return {}, nil, true
    end
  end
  local ops = {}
  local stackErr = stackSlots(work, ops)
  if stackErr then
    return ops, stackErr
  end
  local sortErr = sortSlots(work, ops)
  return ops, sortErr
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
      local className = nil
      local subClass = nil
      local quality = nil
      if link then
        itemID = parseItemID(link)
        if itemCount < 1 then
          itemCount = 1
        end
        if itemID and type(GetItemInfo) == "function" then
          local itemName, _, rarity, _, _, itemType, itemSubType, stack = GetItemInfo(itemID)
          name = itemName
          if type(itemType) == "string" and itemType ~= "" then
            className = itemType
          end
          if type(itemSubType) == "string" and itemSubType ~= "" then
            subClass = itemSubType
          end
          if rarity ~= nil then
            quality = tonumber(rarity)
          end
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
        className = className,
        subClass = subClass,
        quality = quality,
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

-- A full pickup can be put back with ClearCursor. A split stack must not.
local function releaseHeld(srcBag, srcSlot, dstBag, dstSlot, itemID, destLinkBefore, allowClear)
  if not (CursorHasItem and CursorHasItem()) then
    return true
  end
  restoreCursor(srcBag, srcSlot, dstBag, dstSlot, itemID, destLinkBefore)
  if CursorHasItem and CursorHasItem() and allowClear and type(ClearCursor) == "function" then
    ClearCursor()
  end
  return not (CursorHasItem and CursorHasItem())
end

local function cursorStuckMessage()
  return "The swap was refused, and the item is still on the cursor. Click a bag slot to put it back."
end

-- True when this place call left the same item on the cursor.
local function placeIgnored(heldBefore)
  if not (CursorHasItem and CursorHasItem()) then
    return false
  end
  local now = cursorItemID()
  if heldBefore == nil or now == nil then
    return true
  end
  return now == heldBefore
end

local function pickupIgnored(bag, slot)
  if CursorHasItem and CursorHasItem() then
    return false
  end
  return GetContainerItemLink(bag, slot) ~= nil
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
      if pickupIgnored(op.srcBag, op.srcSlot) then
        return false, nil, true
      end
      return false, pickupFailedMessage(srcLocked)
    end
    local held = cursorItemID()
    PickupContainerItem(op.dstBag, op.dstSlot)
    if CursorHasItem() then
      local ignored = placeIgnored(held)
      if not releaseHeld(op.srcBag, op.srcSlot, op.dstBag, op.dstSlot, op.itemID, destLinkBefore, true) then
        return false, cursorStuckMessage()
      end
      if ignored then
        return false, nil, true
      end
      return false, "That bag cannot hold this item, so the sort stopped."
    end
    if parseItemID(GetContainerItemLink(op.dstBag, op.dstSlot)) ~= op.itemID then
      return false, "The swap was refused, so the sort stopped."
    end
    return true
  end

  if op.kind == "swap" then
    local destID = parseItemID(destLinkBefore)
    if not destLinkBefore or destID ~= op.destItemID then
      return false, "The bag changed during the sort, so it stopped."
    end
    local probeSrc = {
      family = liveItemFamily(srcLink, op.srcBag),
      name = op.name,
    }
    local probeDst = {
      family = liveItemFamily(destLinkBefore, op.dstBag),
      name = op.destName,
    }
    local destBag = {
      bagFamily = liveBagFamily(op.dstBag),
      bagName = GetBagName and GetBagName(op.dstBag) or nil,
    }
    local srcBagInfo = {
      bagFamily = liveBagFamily(op.srcBag),
      bagName = GetBagName and GetBagName(op.srcBag) or nil,
    }
    if not itemFits(probeSrc, destBag) then
      return false, cannotHoldMessage(probeSrc, destBag)
    end
    if not itemFits(probeDst, srcBagInfo) then
      return false, cannotHoldMessage(probeDst, srcBagInfo)
    end
    PickupContainerItem(op.srcBag, op.srcSlot)
    if not CursorHasItem() then
      if pickupIgnored(op.srcBag, op.srcSlot) then
        return false, nil, true
      end
      return false, pickupFailedMessage(srcLocked)
    end
    local held = cursorItemID()
    PickupContainerItem(op.dstBag, op.dstSlot)
    if not CursorHasItem() or placeIgnored(held) or (cursorItemID() and cursorItemID() ~= op.destItemID) then
      local ignored = (not CursorHasItem()) or placeIgnored(held)
      if not releaseHeld(op.srcBag, op.srcSlot, op.dstBag, op.dstSlot, op.itemID, destLinkBefore, true) then
        return false, cursorStuckMessage()
      end
      if parseItemID(GetContainerItemLink(op.dstBag, op.dstSlot)) == op.itemID
        and parseItemID(GetContainerItemLink(op.srcBag, op.srcSlot)) == op.destItemID then
        return true
      end
      if ignored then
        return false, nil, true
      end
      return false, "The swap was refused, so the sort stopped."
    end
    held = cursorItemID()
    PickupContainerItem(op.srcBag, op.srcSlot)
    if CursorHasItem() then
      local ignored = placeIgnored(held)
      if not releaseHeld(op.srcBag, op.srcSlot, op.dstBag, op.dstSlot, op.itemID, destLinkBefore, true) then
        return false, cursorStuckMessage()
      end
      if parseItemID(GetContainerItemLink(op.dstBag, op.dstSlot)) == op.itemID
        and parseItemID(GetContainerItemLink(op.srcBag, op.srcSlot)) == op.destItemID then
        return true
      end
      if ignored then
        return false, nil, true
      end
      return false, "The swap was refused, so the sort stopped."
    end
    if parseItemID(GetContainerItemLink(op.dstBag, op.dstSlot)) ~= op.itemID
      or parseItemID(GetContainerItemLink(op.srcBag, op.srcSlot)) ~= op.destItemID then
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
  local split = amount < srcCount
  if amount >= srcCount then
    PickupContainerItem(op.srcBag, op.srcSlot)
  else
    if type(SplitContainerItem) ~= "function" then
      return false, "Could not split that stack, so the sort stopped."
    end
    SplitContainerItem(op.srcBag, op.srcSlot, amount)
  end
  if not CursorHasItem() then
    if pickupIgnored(op.srcBag, op.srcSlot) then
      return false, nil, true
    end
    return false, pickupFailedMessage(srcLocked)
  end
  local held = cursorItemID()
  PickupContainerItem(op.dstBag, op.dstSlot)
  if CursorHasItem() then
    local ignored = placeIgnored(held)
    if not releaseHeld(op.srcBag, op.srcSlot, op.dstBag, op.dstSlot, op.itemID, destLinkBefore, not split) then
      return false, cursorStuckMessage()
    end
    if ignored then
      return false, nil, true
    end
    return false, "Those items did not stack, so the sort stopped."
  end
  if parseItemID(GetContainerItemLink(op.dstBag, op.dstSlot)) ~= op.itemID then
    return false, "Those items did not stack, so the sort stopped."
  end
  return true
end

local function refreshBagQuality()
  local quality = OnyxiaGold.BagQuality
  if quality and quality.Refresh then
    quality:Refresh()
  end
end

function BagSort:Sort()
  if self:Blocked() then
    return
  end
  local slots = self:ReadSlots()
  local ops, err, paused = self:Plan(slots)
  if paused then
    self:Say(LOCKED_MESSAGE)
    refreshBagQuality()
    return
  end
  for i = 1, table.getn(ops) do
    local ok, message, again = self:RunOp(ops[i])
    if again then
      self:Say(CONTINUE_MESSAGE)
      refreshBagQuality()
      return
    end
    if not ok then
      self:Say(message)
      refreshBagQuality()
      return
    end
  end
  if err then
    self:Say(err)
    refreshBagQuality()
    return
  end
  refreshBagQuality()
  if OnyxiaGold.Log and OnyxiaGold.Log.Debug then
    OnyxiaGold.Log:Debug("Bags", "Bag sort finished (" .. tostring(table.getn(ops)) .. " swaps)")
  end
end

-- Blizzard container frames are born with id 100. The backpack id becomes 0
-- only while that bag is open, and it is not always ContainerFrame1.
local function shownBackpack()
  local frames = NUM_CONTAINER_FRAMES or 13
  for i = 1, frames do
    local frame = getglobal("ContainerFrame" .. i)
    if frame and frame.IsShown and frame:IsShown() and frame.GetID and frame:GetID() == 0 then
      return frame
    end
  end
  return nil
end

-- Title bar, just right of the portrait (40px at x=7) and left of the close button.
local function anchorButton(btn, frame)
  btn:SetParent(frame)
  btn:ClearAllPoints()
  btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 50, -6)
  local strata = "HIGH"
  if frame.GetFrameStrata then
    local parentStrata = frame:GetFrameStrata()
    if parentStrata == "DIALOG" or parentStrata == "FULLSCREEN" or parentStrata == "FULLSCREEN_DIALOG" or parentStrata == "TOOLTIP" then
      strata = parentStrata
    end
  end
  btn:SetFrameStrata(strata)
  local level = 1
  if frame.GetFrameLevel then
    level = frame:GetFrameLevel() or 1
  end
  if level < 1 then
    level = 1
  end
  btn:SetFrameLevel(level + 40)
  btn:Show()
end

local function styleSortButton(btn)
  btn:SetWidth(64)
  btn:SetHeight(22)
  btn:SetText("Sort")
  local label = getglobal(btn:GetName() .. "Text")
  if label then
    label:SetText("Sort")
    label:Show()
  end
  btn:SetScript("OnClick", function()
    -- Swaps run in this click. PickupContainerItem is not deferred.
    BagSort:Sort()
  end)
  btn:SetScript("OnEnter", function(self)
    if not GameTooltip then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(TOOLTIP_TITLE, 1, 0.82, 0)
    GameTooltip:AddLine(TOOLTIP_BODY, 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
end

function BagSort:InstallHooks()
  if self.hooksInstalled or type(hooksecurefunc) ~= "function" then
    return
  end
  self.hooksInstalled = true
  if type(ContainerFrame_OnShow) == "function" then
    hooksecurefunc("ContainerFrame_OnShow", function(frame)
      if frame and frame.GetID and frame:GetID() == 0 then
        BagSort:EnsureButton()
      end
    end)
  end
  if type(ContainerFrame_OnHide) == "function" then
    hooksecurefunc("ContainerFrame_OnHide", function(frame)
      local btn = getglobal(BUTTON_NAME)
      if btn and frame and btn.GetParent and btn:GetParent() == frame then
        btn:Hide()
      end
    end)
  end
end

function BagSort:EnsureButton()
  self:InstallHooks()
  if type(CreateFrame) ~= "function" or type(getglobal) ~= "function" then
    return
  end
  local btn = getglobal(BUTTON_NAME)
  if not btn then
    if not ContainerFrame1 then
      return
    end
    btn = CreateFrame("Button", BUTTON_NAME, ContainerFrame1, "UIPanelButtonTemplate")
    styleSortButton(btn)
    btn:Hide()
  end
  local frame = shownBackpack()
  if frame then
    anchorButton(btn, frame)
  else
    btn:Hide()
  end
end

local sortEvents = CreateFrame("Frame", "OnyxiaGoldBagSortEvents")
sortEvents:RegisterEvent("PLAYER_LOGIN")
sortEvents:RegisterEvent("BAG_UPDATE")
sortEvents:SetScript("OnEvent", function(_, event, bag)
  if event == "BAG_UPDATE" and tonumber(bag) ~= 0 then
    return
  end
  BagSort:EnsureButton()
end)

BagSort:InstallHooks()
BagSort:EnsureButton()
