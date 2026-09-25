--[[
  Data-driven transformations.
  Economic relationships live here, not in the UI.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Data = OnyxiaGold.Data or {}

local I = OnyxiaGold.Data.Items

-- Reversible 1 Greater <-> 3 Lesser (and 3 Small <-> 1 Large) conversions.
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
    notesForward = "1 Greater converts into 3 Lesser",
    notesReverse = "3 Lesser convert into 1 Greater",
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
    notesForward = "1 Greater converts into 3 Lesser",
    notesReverse = "3 Lesser convert into 1 Greater",
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
    notesForward = "1 Greater converts into 3 Lesser",
    notesReverse = "3 Lesser convert into 1 Greater",
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
    nameForward = "Small Prismatic → Large Prismatic",
    nameReverse = "Large Prismatic → Small Prismatic",
    notesForward = "3 Small convert into 1 Large",
    notesReverse = "1 Large converts into 3 Small",
  },
  {
    id = "small_dream_to_dream",
    kind = "shard",
    typeLabel = "Shard",
    sourceItemID = I.SMALL_DREAM_SHARD.id,
    sourceCount = 3,
    targetItemID = I.DREAM_SHARD.id,
    targetCount = 1,
    reversible = true,
    nameForward = "Small Dream Shard → Dream Shard",
    nameReverse = "Dream Shard → Small Dream Shard",
    notesForward = "3 Small convert into 1 Dream Shard",
    notesReverse = "1 Dream Shard converts into 3 Small",
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
    notes = "Expected output is not guaranteed; Transmute Master uses a 1.20 EV multiplier",
  },
}
