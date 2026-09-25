--[[
  Canonical item IDs used by OnyxiaGold.
  Always key economic logic by ID, never by localised name.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Data = OnyxiaGold.Data or {}

local Items = {
  -- Enchanting essences (1 Greater <-> 3 Lesser)
  LESSER_MAGIC_ESSENCE = { id = 10938, name = "Lesser Magic Essence" },
  GREATER_MAGIC_ESSENCE = { id = 10939, name = "Greater Magic Essence" },
  LESSER_ASTRAL_ESSENCE = { id = 10998, name = "Lesser Astral Essence" },
  GREATER_ASTRAL_ESSENCE = { id = 11082, name = "Greater Astral Essence" },
  LESSER_MYSTIC_ESSENCE = { id = 11134, name = "Lesser Mystic Essence" },
  GREATER_MYSTIC_ESSENCE = { id = 11135, name = "Greater Mystic Essence" },
  LESSER_NETHER_ESSENCE = { id = 11174, name = "Lesser Nether Essence" },
  GREATER_NETHER_ESSENCE = { id = 11175, name = "Greater Nether Essence" },
  LESSER_ETERNAL_ESSENCE = { id = 16202, name = "Lesser Eternal Essence" },
  GREATER_ETERNAL_ESSENCE = { id = 16203, name = "Greater Eternal Essence" },
  LESSER_PLANAR_ESSENCE = { id = 22447, name = "Lesser Planar Essence" },
  GREATER_PLANAR_ESSENCE = { id = 22446, name = "Greater Planar Essence" },
  LESSER_COSMIC_ESSENCE = { id = 34056, name = "Lesser Cosmic Essence" },
  GREATER_COSMIC_ESSENCE = { id = 34055, name = "Greater Cosmic Essence" },

  -- Shards (3 Small <-> 1 Large)
  SMALL_PRISMATIC_SHARD = { id = 22448, name = "Small Prismatic Shard" },
  LARGE_PRISMATIC_SHARD = { id = 22449, name = "Large Prismatic Shard" },
  SMALL_DREAM_SHARD = { id = 34053, name = "Small Dream Shard" },
  DREAM_SHARD = { id = 34052, name = "Dream Shard" },

  -- WotLK bars
  SARONITE_BAR = { id = 36913, name = "Saronite Bar" },
  TITANIUM_BAR = { id = 41163, name = "Titanium Bar" },

  -- Upcoming economic materials (watchlist / later engines)
  NETHERWEAVE_CLOTH = { id = 21877, name = "Netherweave Cloth" },
  BOLT_OF_NETHERWEAVE = { id = 21840, name = "Bolt of Netherweave" },
  ARCANE_DUST = { id = 22445, name = "Arcane Dust" },
  MAGEWEAVE_CLOTH = { id = 4338, name = "Mageweave Cloth" },
  VISION_DUST = { id = 11137, name = "Vision Dust" },
  INFINITE_DUST = { id = 34054, name = "Infinite Dust" },
  ABYSS_CRYSTAL = { id = 34057, name = "Abyss Crystal" },
}

OnyxiaGold.Data.Items = Items

local byID = {}
for _, def in pairs(Items) do
  byID[def.id] = def
end
OnyxiaGold.Data.ItemsByID = byID

function OnyxiaGold.Data.GetItemName(itemID)
  itemID = tonumber(itemID)
  if not itemID then
    return nil
  end
  local def = byID[itemID]
  if def then
    return def.name
  end
  local latest = OnyxiaGold.Database and OnyxiaGold.Database:GetLatest(itemID)
  if latest and latest.name then
    return latest.name
  end
  local name = GetItemInfo(itemID)
  return name
end
