--[[
  OnyxiaGold.Inventory
  Bag counts are live. Bank counts are last-opened snapshots with timestamps.
  Immediately available materials for AH crafting = bags only.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Inventory = OnyxiaGold.Inventory or {}

local Inventory = OnyxiaGold.Inventory

local BACKPACK_CONTAINER = 0
local BANK_CONTAINER = -1

local function rec()
  return OnyxiaGold.Database:GetCharacter()
end

local function addCount(map, itemID, count)
  itemID = tonumber(itemID)
  count = tonumber(count) or 0
  if not itemID or count <= 0 then
    return
  end
  map[itemID] = (map[itemID] or 0) + count
end

local function scanContainer(map, bag)
  local slots = GetContainerNumSlots(bag)
  if not slots or slots <= 0 then
    return
  end
  for slot = 1, slots do
    local link = GetContainerItemLink(bag, slot)
    local itemID = OnyxiaGold.ParseItemID(link)
    if itemID then
      local _, count = GetContainerItemInfo(bag, slot)
      addCount(map, itemID, count or 1)
    end
  end
end

local trackedCache
local function trackedSet()
  if trackedCache then
    return trackedCache
  end
  local set = {}
  local watch = OnyxiaGold.Data.Watchlist or {}
  for i = 1, table.getn(watch) do
    local e = watch[i]
    if e and e.itemID then
      set[e.itemID] = true
    end
  end
  local transmutes = OnyxiaGold.Data.Transmutes or {}
  for i = 1, table.getn(transmutes) do
    local def = transmutes[i]
    if def then
      if def.inputs then
        for j = 1, table.getn(def.inputs) do
          if def.inputs[j] and def.inputs[j].itemID then
            set[def.inputs[j].itemID] = true
          end
        end
      end
      if def.outputs then
        for j = 1, table.getn(def.outputs) do
          if def.outputs[j] and def.outputs[j].itemID then
            set[def.outputs[j].itemID] = true
          end
        end
      end
    end
  end
  local conv = OnyxiaGold.Data.Conversions or {}
  for i = 1, table.getn(conv) do
    local def = conv[i]
    if def then
      if def.sourceItemID then
        set[def.sourceItemID] = true
      end
      if def.targetItemID then
        set[def.targetItemID] = true
      end
    end
  end
  trackedCache = set
  return set
end

local function valueMap(map)
  local prices = OnyxiaGold.Prices
  if not prices or not map then
    return 0
  end
  local tracked = trackedSet()
  local total = 0
  for itemID, count in pairs(map) do
    if tracked[itemID] then
      local unit = prices:GetLiquidationPrice(itemID)
      if unit and count then
        total = total + unit * count
      end
    end
  end
  return total
end

function Inventory:ScanBags()
  local row = rec()
  if not row then
    return {}
  end
  local bags = {}
  local partial = {}
  local stacks = {}
  local freeKnown = type(GetContainerNumFreeSlots) == "function"
  local free = 0
  local bagSlots = NUM_BAG_SLOTS or 4
  for bag = BACKPACK_CONTAINER, bagSlots do
    local bagType = 0
    if freeKnown then
      local freeSlots, kind = GetContainerNumFreeSlots(bag)
      bagType = tonumber(kind) or 0
      if bag == 0 or bagType == 0 then
        free = free + (tonumber(freeSlots) or 0)
      end
    end
    local general = bag == 0 or bagType == 0
    local slots = GetContainerNumSlots(bag)
    if slots and slots > 0 then
      for slot = 1, slots do
        local link = GetContainerItemLink(bag, slot)
        local itemID = OnyxiaGold.ParseItemID(link)
        if itemID then
          local _, count = GetContainerItemInfo(bag, slot)
          count = tonumber(count) or 1
          if count < 1 then
            count = 1
          end
          addCount(bags, itemID, count)
          if general and type(GetItemInfo) == "function" then
            local _, _, _, _, _, _, _, maxStack = GetItemInfo(itemID)
            maxStack = tonumber(maxStack)
            if maxStack and maxStack > 0 then
              stacks[itemID] = maxStack
              if count < maxStack then
                partial[itemID] = (partial[itemID] or 0) + (maxStack - count)
              end
            end
          end
        end
      end
    end
  end
  row.inventory.bags = bags
  row.inventory.stackSize = stacks
  row.inventory.partialRoom = partial
  if freeKnown then
    row.inventory.freeSlots = free
  end
  row.inventory.timestamp = time()
  row.stateTimestamps.bags = time()
  return bags
end

function Inventory:ScanBank()
  local row = rec()
  if not row then
    return {}
  end
  if not (BankFrame and BankFrame:IsShown()) then
    return row.bank.items or {}
  end
  local items = {}
  scanContainer(items, BANK_CONTAINER)
  local bagSlots = NUM_BAG_SLOTS or 4
  local bankBags = NUM_BANKBAGSLOTS or 7
  for bag = bagSlots + 1, bagSlots + bankBags do
    scanContainer(items, bag)
  end
  row.bank.items = items
  row.bank.timestamp = time()
  row.stateTimestamps.bank = time()
  OnyxiaGold.Log:Debug("Inventory", "Bank snapshot stored")
  return items
end

function Inventory:GetBagCount(itemID)
  itemID = tonumber(itemID)
  local row = rec()
  if not itemID or not row then
    return 0
  end
  return tonumber(row.inventory.bags[itemID]) or 0
end

function Inventory:GetBankCount(itemID)
  itemID = tonumber(itemID)
  local row = rec()
  if not itemID or not row then
    return 0
  end
  return tonumber(row.bank.items[itemID]) or 0
end

function Inventory:GetOwnedCount(itemID)
  return self:GetBagCount(itemID) + self:GetBankCount(itemID)
end

function Inventory:GetImmediatelyAvailableCount(itemID)
  return self:GetBagCount(itemID)
end

function Inventory:GetTrackedBagValue()
  local row = rec()
  if not row then
    return 0
  end
  return valueMap(row.inventory.bags)
end

function Inventory:GetTrackedBankValue()
  local row = rec()
  if not row then
    return 0
  end
  return valueMap(row.bank.items)
end

function Inventory:GetBankAge()
  local row = rec()
  if not row or not row.bank.timestamp then
    return nil
  end
  return OnyxiaGold.AgeSeconds(row.bank.timestamp)
end

function Inventory:GetBagAge()
  return 0
end

-- Equipped gear is recorded so a tool on him counts. It is not bag stock
-- and it is not a disenchant or vendor row.
function Inventory:ScanEquipment()
  local row = rec()
  if not row then
    return {}
  end
  if type(row.inventory.equipped) ~= "table" then
    row.inventory.equipped = {}
  end
  local equipped = {}
  if type(GetInventoryItemLink) == "function" then
    for slot = 1, 19 do
      local link = GetInventoryItemLink("player", slot)
      local itemID = OnyxiaGold.ParseItemID(link)
      if itemID then
        addCount(equipped, itemID, 1)
      end
    end
  end
  row.inventory.equipped = equipped
  return equipped
end

function Inventory:GetEquippedCount(itemID)
  itemID = tonumber(itemID)
  local row = rec()
  if not itemID or not row or type(row.inventory.equipped) ~= "table" then
    return 0
  end
  return tonumber(row.inventory.equipped[itemID]) or 0
end

function Inventory:GetOnPersonCount(itemID)
  return self:GetBagCount(itemID) + self:GetEquippedCount(itemID)
end

local LATER_STONE_KEYS = {
  "ALCHEMISTS_STONE",
  "ASSASSINS_ALCHEMIST_STONE",
  "GUARDIANS_ALCHEMIST_STONE",
  "REDEEMERS_ALCHEMIST_STONE",
  "MIGHTY_ALCHEMISTS_STONE",
  "INDESTRUCTIBLE_ALCHEMISTS_STONE",
}

function Inventory:UnconfirmedStoneOnPerson()
  local items = OnyxiaGold.Data and OnyxiaGold.Data.Items
  if not items then
    return false
  end
  for i = 1, table.getn(LATER_STONE_KEYS) do
    local def = items[LATER_STONE_KEYS[i]]
    if def and def.id and self:GetOnPersonCount(def.id) > 0 then
      return true
    end
  end
  return false
end

-- Nil means the bag limit is unknown and must not cut a buy.
function Inventory:GetFreeGeneralSlots()
  if type(GetContainerNumFreeSlots) == "function" then
    local total = 0
    local bagSlots = NUM_BAG_SLOTS or 4
    for bag = 0, bagSlots do
      local freeSlots, bagType = GetContainerNumFreeSlots(bag)
      if bag == 0 or bagType == 0 then
        total = total + (tonumber(freeSlots) or 0)
      end
    end
    return total
  end
  local row = rec()
  if row and row.inventory and row.inventory.freeSlots ~= nil then
    return tonumber(row.inventory.freeSlots) or 0
  end
  return nil
end

function Inventory:GetStackSize(itemID)
  itemID = tonumber(itemID)
  local row = rec()
  if row and row.inventory and type(row.inventory.stackSize) == "table" and itemID then
    local stored = tonumber(row.inventory.stackSize[itemID])
    if stored and stored > 0 then
      return stored
    end
  end
  if itemID and type(GetItemInfo) == "function" then
    local _, _, _, _, _, _, _, stack = GetItemInfo(itemID)
    stack = tonumber(stack)
    if stack and stack > 0 then
      return stack
    end
  end
  return nil
end

function Inventory:GetPartialRoom(itemID)
  itemID = tonumber(itemID)
  local row = rec()
  if not itemID or not row or type(row.inventory.partialRoom) ~= "table" then
    return 0
  end
  local room = tonumber(row.inventory.partialRoom[itemID]) or 0
  if room < 0 then
    room = 0
  end
  return room
end
