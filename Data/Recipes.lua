--[[
  Data-driven transformations.
  Economic relationships live here, not in the UI.

  Factory target pair: Alchemy + Enchanting.
  Jewelcrafting recipes may be added for GLOBAL analysis; they are not
  personally executable on the intended Druid.

  Essence/shard item-use conversions do not require Enchanting.
  Abyssal Shatter, Void Shatter, and vellum scrolls are Enchanting-gated
  and belong in v0.2.1+ once 3.3.5 outputs are confirmed.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Data = OnyxiaGold.Data or {}

local I = OnyxiaGold.Data.Items

-- Essence pairs are reversible item-use conversions.
-- Dream Shard combines one way. Prismatic shards stay a priced pair, not an action.
OnyxiaGold.Data.Conversions = {
  {
    id = "greater_eternal_to_lesser",
    kind = "essence",
    typeLabel = "Essence",
    sourceItemID = I.GREATER_ETERNAL_ESSENCE.id,
    sourceCount = 1,
    targetItemID = I.LESSER_ETERNAL_ESSENCE.id,
    targetCount = 3,
    reversible = true,
    nameForward = "Greater Eternal → Lesser Eternal",
    nameReverse = "Lesser Eternal → Greater Eternal",
    notesForward = "1 Greater converts into 3 Lesser. Item-use conversion; no profession required.",
    notesReverse = "3 Lesser convert into 1 Greater. Item-use conversion; no profession required.",
  },
  {
    id = "greater_planar_to_lesser",
    kind = "essence",
    typeLabel = "Essence",
    sourceItemID = I.GREATER_PLANAR_ESSENCE.id,
    sourceCount = 1,
    targetItemID = I.LESSER_PLANAR_ESSENCE.id,
    targetCount = 3,
    reversible = true,
    nameForward = "Greater Planar → Lesser Planar",
    nameReverse = "Lesser Planar → Greater Planar",
    notesForward = "1 Greater converts into 3 Lesser. Item-use conversion; no profession required.",
    notesReverse = "3 Lesser convert into 1 Greater. Item-use conversion; no profession required.",
  },
  {
    id = "greater_cosmic_to_lesser",
    kind = "essence",
    typeLabel = "Essence",
    sourceItemID = I.GREATER_COSMIC_ESSENCE.id,
    sourceCount = 1,
    targetItemID = I.LESSER_COSMIC_ESSENCE.id,
    targetCount = 3,
    reversible = true,
    nameForward = "Greater Cosmic → Lesser Cosmic",
    nameReverse = "Lesser Cosmic → Greater Cosmic",
    notesForward = "1 Greater converts into 3 Lesser. Item-use conversion; no profession required.",
    notesReverse = "3 Lesser convert into 1 Greater. Item-use conversion; no profession required.",
  },
  {
    id = "small_prismatic_to_large",
    kind = "shard",
    typeLabel = "Shard",
    sourceItemID = I.SMALL_PRISMATIC_SHARD.id,
    sourceCount = 3,
    targetItemID = I.LARGE_PRISMATIC_SHARD.id,
    targetCount = 1,
    reversible = true,
    -- Both directions stay priced. Neither is an action until the Enchanting
    -- spell and the Runed Fel Iron Rod are represented.
    actionable = false,
    nameForward = "Small Prismatic → Large Prismatic",
    nameReverse = "Large Prismatic → Small Prismatic",
    notesForward = "Market relationship only. Enchanting recipe; needs a Runed Fel Iron Rod. Not an action until that recipe and the rod are represented.",
    notesReverse = "Market relationship only. Enchanting recipe; needs a Runed Fel Iron Rod. Not an action until that recipe and the rod are represented.",
  },
  {
    id = "small_dream_to_dream",
    kind = "shard",
    typeLabel = "Shard",
    sourceItemID = I.SMALL_DREAM_SHARD.id,
    sourceCount = 3,
    targetItemID = I.DREAM_SHARD.id,
    targetCount = 1,
    reversible = false,
    nameForward = "Small Dream Shard → Dream Shard",
    notesForward = "3 Small Dream Shards combine into 1 Dream Shard. Item-use. A Dream Shard does not split.",
  },
}

OnyxiaGold.Data.Transmutes = {
  {
    id = "saronite_to_titanium",
    name = "Saronite → Titanium",
    typeLabel = "Transmute",
    inputs = {
      { itemID = I.SARONITE_BAR.id, count = 8 },
    },
    outputs = {
      { itemID = I.TITANIUM_BAR.id, count = 1 },
    },
    supportsTransmuteMastery = true,
    requirements = {
      profession = "Alchemy",
      -- 395 is the skill required to perform Transmute: Titanium (spell 60350).
      -- 440 is the difficulty colour (orange through grey), not the requirement.
      minimumSkill = 395,
      recipeSpellID = 60350,
      specialisationOptional = "Transmutation",
    },
    notes = "Expected output is not guaranteed; Transmute Master is an EV modifier, not a craft gate",
  },
}
