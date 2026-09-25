--[[
  OnyxiaGold.ItemInfo
  Cached GetItemInfo metadata for future disenchant classification.
  3.3.5 GetItemInfo may return nil until the item is in the local cache.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.ItemInfo = OnyxiaGold.ItemInfo or {}

local ItemInfo = OnyxiaGold.ItemInfo

local function metaRoot()
  if type(OnyxiaGoldDB) ~= "table" then
    return nil
  end
  if type(OnyxiaGoldDB.itemMeta) ~= "table" then
    OnyxiaGoldDB.itemMeta = {}
  end
  return OnyxiaGoldDB.itemMeta
end

-- 3.3.5: name, link, quality, iLevel, minLevel, itemType, itemSubType,
-- maxStack, equipLoc, texture, vendorPrice
function ItemInfo:Capture(itemID)
  itemID = tonumber(itemID)
  if not itemID or not GetItemInfo then
    return nil
  end
  local name, link, quality, iLevel, minLevel, itemType, itemSubType, maxStack, equipLoc, texture, vendorPrice = GetItemInfo(itemID)
  if not name then
    return nil
  end
  local rec = {
    itemID = itemID,
    name = name,
    quality = tonumber(quality),
    itemLevel = tonumber(iLevel),
    minLevel = tonumber(minLevel),
    itemType = itemType,
    itemSubType = itemSubType,
    maxStack = tonumber(maxStack),
    equipLoc = equipLoc,
    vendorPrice = tonumber(vendorPrice) or 0,
    timestamp = time(),
  }
  local root = metaRoot()
  if root then
    root[itemID] = rec
  end
  return rec
end

function ItemInfo:Get(itemID)
  itemID = tonumber(itemID)
  if not itemID then
    return nil
  end
  local root = metaRoot()
  local cached = root and root[itemID]
  if cached and cached.quality and cached.itemLevel then
    return cached
  end
  return self:Capture(itemID)
end

function ItemInfo:IsWeapon(rec)
  if not rec or not rec.itemType then
    return false
  end
  return rec.itemType == "Weapon"
end

function ItemInfo:IsArmor(rec)
  if not rec or not rec.itemType then
    return false
  end
  return rec.itemType == "Armor"
end

function ItemInfo:CanDisenchantQuality(quality)
  quality = tonumber(quality)
  return quality == 2 or quality == 3 or quality == 4
end
