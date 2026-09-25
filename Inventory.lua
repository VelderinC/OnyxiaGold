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
  local bagSlots = NUM_BAG_SLOTS or 4
  for bag = BACKPACK_CONTAINER, bagSlots do
    scanContainer(bags, bag)
  end
  row.inventory.bags = bags
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
