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

  -- Prismatic shards are a priced pair. Dream Shards combine one way.
  SMALL_PRISMATIC_SHARD = { id = 22448, name = "Small Prismatic Shard" },
  LARGE_PRISMATIC_SHARD = { id = 22449, name = "Large Prismatic Shard" },
  SMALL_DREAM_SHARD = { id = 34053, name = "Small Dream Shard" },
  DREAM_SHARD = { id = 34052, name = "Dream Shard" },

  -- WotLK bars
  SARONITE_BAR = { id = 36913, name = "Saronite Bar" },
  TITANIUM_BAR = { id = 41163, name = "Titanium Bar" },

  -- Alchemy transmute reagents and outputs. Names only; prices come from the scan.
  -- Philosopher's Stone is a tool, not an input.
  PHILOSOPHERS_STONE = { id = 9149, name = "Philosopher's Stone" },
  DARK_JADE = { id = 36932, name = "Dark Jade" },
  HUGE_CITRINE = { id = 36929, name = "Huge Citrine" },
  ETERNAL_FIRE = { id = 36860, name = "Eternal Fire" },
  EARTHSIEGE_DIAMOND = { id = 41334, name = "Earthsiege Diamond" },
  BLOODSTONE = { id = 36917, name = "Bloodstone" },
  CHALCEDONY = { id = 36923, name = "Chalcedony" },
  ETERNAL_AIR = { id = 35623, name = "Eternal Air" },
  SKYFLARE_DIAMOND = { id = 41266, name = "Skyflare Diamond" },
  MONARCH_TOPAZ = { id = 36930, name = "Monarch Topaz" },
  ETERNAL_SHADOW = { id = 35627, name = "Eternal Shadow" },
  AMETRINE = { id = 36931, name = "Ametrine" },
  AUTUMNS_GLOW = { id = 36921, name = "Autumn's Glow" },
  ETERNAL_LIFE = { id = 35625, name = "Eternal Life" },
  KINGS_AMBER = { id = 36922, name = "King's Amber" },
  TWILIGHT_OPAL = { id = 36927, name = "Twilight Opal" },
  DREADSTONE = { id = 36928, name = "Dreadstone" },
  SKY_SAPPHIRE = { id = 36924, name = "Sky Sapphire" },
  MAJESTIC_ZIRCON = { id = 36925, name = "Majestic Zircon" },
  FOREST_EMERALD = { id = 36933, name = "Forest Emerald" },
  EYE_OF_ZUL = { id = 36934, name = "Eye of Zul" },
  SCARLET_RUBY = { id = 36918, name = "Scarlet Ruby" },
  CARDINAL_RUBY = { id = 36919, name = "Cardinal Ruby" },

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
