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
  -- Philosopher's Stone is a tool, not an input. Later stones are named only.
  -- Their tool-category membership is unset, so they are not valid transmute tools yet.
  PHILOSOPHERS_STONE = { id = 9149, name = "Philosopher's Stone" },
  ALCHEMISTS_STONE = { id = 35748, name = "Alchemist's Stone" },
  ASSASSINS_ALCHEMIST_STONE = { id = 35749, name = "Assassin's Alchemist Stone" },
  GUARDIANS_ALCHEMIST_STONE = { id = 35750, name = "Guardian's Alchemist Stone" },
  REDEEMERS_ALCHEMIST_STONE = { id = 35751, name = "Redeemer's Alchemist Stone" },
  MIGHTY_ALCHEMISTS_STONE = { id = 44322, name = "Mighty Alchemist's Stone" },
  INDESTRUCTIBLE_ALCHEMISTS_STONE = { id = 44323, name = "Indestructible Alchemist's Stone" },
  MERCURIAL_STONE = { id = 31080, name = "Mercurial Stone" },
  RUNED_FEL_IRON_ROD = { id = 22461, name = "Runed Fel Iron Rod" },
  RUNED_ETERNIUM_ROD = { id = 22463, name = "Runed Eternium Rod" },
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
  ETERNAL_WATER = { id = 35622, name = "Eternal Water" },
  ETERNAL_EARTH = { id = 35624, name = "Eternal Earth" },

  -- Old 20-hour alchemy cycle. Prices come from the scan, not from this file.
  ESSENCE_OF_AIR = { id = 7082, name = "Essence of Air" },
  ESSENCE_OF_EARTH = { id = 7076, name = "Essence of Earth" },
  ESSENCE_OF_FIRE = { id = 7078, name = "Essence of Fire" },
  ESSENCE_OF_WATER = { id = 7080, name = "Essence of Water" },
  ESSENCE_OF_UNDEATH = { id = 12808, name = "Essence of Undeath" },
  LIVING_ESSENCE = { id = 12803, name = "Living Essence" },
  IRON_BAR = { id = 3575, name = "Iron Bar" },
  GOLD_BAR = { id = 3577, name = "Gold Bar" },
  MITHRIL_BAR = { id = 3860, name = "Mithril Bar" },
  TRUESILVER_BAR = { id = 6037, name = "Truesilver Bar" },
  PRIMAL_AIR = { id = 22451, name = "Primal Air" },
  PRIMAL_EARTH = { id = 22452, name = "Primal Earth" },
  PRIMAL_FIRE = { id = 21884, name = "Primal Fire" },
  PRIMAL_WATER = { id = 21885, name = "Primal Water" },
  PRIMAL_SHADOW = { id = 22456, name = "Primal Shadow" },
  PRIMAL_MANA = { id = 22457, name = "Primal Mana" },
  PRIMAL_LIFE = { id = 21886, name = "Primal Life" },
  ETERNAL_MIGHT = { id = 40248, name = "Eternal Might" },

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
