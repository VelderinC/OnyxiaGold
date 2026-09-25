--[[
  Quick Scan watchlist.
  Names are used as 3.3.5a QueryAuctionItems text; rows are then filtered by item ID.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Data = OnyxiaGold.Data or {}

local I = OnyxiaGold.Data.Items

local function entry(key, item, category)
  return {
    key = key,
    itemID = item.id,
    name = item.name,
    category = category,
    enabled = true,
  }
end

OnyxiaGold.Data.Watchlist = {
  entry("saronite_bar", I.SARONITE_BAR, "Transmute"),
  entry("titanium_bar", I.TITANIUM_BAR, "Transmute"),
  entry("lesser_eternal_essence", I.LESSER_ETERNAL_ESSENCE, "Essence"),
  entry("greater_eternal_essence", I.GREATER_ETERNAL_ESSENCE, "Essence"),
  entry("lesser_planar_essence", I.LESSER_PLANAR_ESSENCE, "Essence"),
  entry("greater_planar_essence", I.GREATER_PLANAR_ESSENCE, "Essence"),
  entry("lesser_cosmic_essence", I.LESSER_COSMIC_ESSENCE, "Essence"),
  entry("greater_cosmic_essence", I.GREATER_COSMIC_ESSENCE, "Essence"),
  entry("small_prismatic_shard", I.SMALL_PRISMATIC_SHARD, "Shard"),
  entry("large_prismatic_shard", I.LARGE_PRISMATIC_SHARD, "Shard"),
  entry("small_dream_shard", I.SMALL_DREAM_SHARD, "Shard"),
  entry("dream_shard", I.DREAM_SHARD, "Shard"),
  entry("netherweave_cloth", I.NETHERWEAVE_CLOTH, "Cloth"),
  entry("bolt_of_netherweave", I.BOLT_OF_NETHERWEAVE, "Cloth"),
  entry("arcane_dust", I.ARCANE_DUST, "Enchanting"),
  entry("mageweave_cloth", I.MAGEWEAVE_CLOTH, "Cloth"),
  entry("vision_dust", I.VISION_DUST, "Enchanting"),
  entry("lesser_nether_essence", I.LESSER_NETHER_ESSENCE, "Essence"),
  entry("greater_nether_essence", I.GREATER_NETHER_ESSENCE, "Essence"),
  entry("abyss_crystal", I.ABYSS_CRYSTAL, "Enchanting"),
  entry("infinite_dust", I.INFINITE_DUST, "Enchanting"),
}

function OnyxiaGold.Data.GetEnabledWatchlist()
  local src = OnyxiaGold.Data.Watchlist or {}
  local out = {}
  for i = 1, table.getn(src) do
    local e = src[i]
    if e and e.enabled ~= false and e.itemID and e.name then
      table.insert(out, e)
    end
  end
  return out
end
