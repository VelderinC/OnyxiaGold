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
    -- Both directions stay priced. The rod is recorded. The Enchanting spell
    -- is not an action in this slice, so neither direction is a craft row.
    actionable = false,
    requirements = {
      profession = "Enchanting",
      tool = "Runed Fel Iron Rod",
      toolItemID = I.RUNED_FEL_IRON_ROD.id,
      toolConsumed = false,
    },
    nameForward = "Small Prismatic → Large Prismatic",
    nameReverse = "Large Prismatic → Small Prismatic",
    notesForward = "Market relationship only. Runed Fel Iron Rod is required on the character. Not an action until the Enchanting recipe is added.",
    notesReverse = "Market relationship only. Runed Fel Iron Rod is required on the character. Not an action until the Enchanting recipe is added.",
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

-- Philosopher's Stone (item 9149) is a tool on every transmute. It is not
-- consumed and it is not an input. The planner requires it in bags or equipped.
-- Later stones stay unconfirmed until one transmute with that item is recorded.
local function alchemyTool(requirements)
  requirements.profession = "Alchemy"
  requirements.tool = "Philosopher's Stone"
  requirements.toolItemID = I.PHILOSOPHERS_STONE.id
  requirements.toolConsumed = false
  requirements.specialisationOptional = "Transmutation"
  return requirements
end

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
    requirements = alchemyTool({
      -- 395 is the skill required to perform Transmute: Titanium (spell 60350).
      -- 440 is the difficulty colour (orange through grey), not the requirement.
      -- Spell data shows no cooldown. Not part of transmute_20h.
      minimumSkill = 395,
      recipeSpellID = 60350,
    }),
    notes = "Expected output is not guaranteed; Transmute Master is an EV modifier, not a craft gate",
  },
  {
    id = "earthsiege_diamond",
    name = "Earthsiege Diamond",
    typeLabel = "Transmute",
    inputs = {
      { itemID = I.DARK_JADE.id, count = 1 },
      { itemID = I.HUGE_CITRINE.id, count = 1 },
      { itemID = I.ETERNAL_FIRE.id, count = 1 },
    },
    outputs = {
      { itemID = I.EARTHSIEGE_DIAMOND.id, count = 1 },
    },
    supportsTransmuteMastery = true,
    requirements = alchemyTool({
      minimumSkill = 425,
      recipeSpellID = 57427,
    }),
    notes = "No cooldown in the 3.3.5 spell data. Transmute Master is expected value only.",
  },
  {
    id = "skyflare_diamond",
    name = "Skyflare Diamond",
    typeLabel = "Transmute",
    inputs = {
      { itemID = I.BLOODSTONE.id, count = 1 },
      { itemID = I.CHALCEDONY.id, count = 1 },
      { itemID = I.ETERNAL_AIR.id, count = 1 },
    },
    outputs = {
      { itemID = I.SKYFLARE_DIAMOND.id, count = 1 },
    },
    supportsTransmuteMastery = true,
    requirements = alchemyTool({
      minimumSkill = 430,
      recipeSpellID = 57425,
    }),
    notes = "Reagents are the verified 3.3.5 list. No cooldown in that spell data.",
  },
  {
    id = "ametrine",
    name = "Ametrine",
    typeLabel = "Transmute",
    inputs = {
      { itemID = I.MONARCH_TOPAZ.id, count = 1 },
      { itemID = I.ETERNAL_SHADOW.id, count = 1 },
    },
    outputs = {
      { itemID = I.AMETRINE.id, count = 1 },
    },
    supportsTransmuteMastery = true,
    requirements = alchemyTool({
      minimumSkill = 450,
      recipeSpellID = 66658,
      cooldown = "transmute_20h",
    }),
    notes = "Shares the 20-hour transmute group. One cast from that group per plan.",
  },
  {
    id = "kings_amber",
    name = "King's Amber",
    typeLabel = "Transmute",
    inputs = {
      { itemID = I.AUTUMNS_GLOW.id, count = 1 },
      { itemID = I.ETERNAL_LIFE.id, count = 1 },
    },
    outputs = {
      { itemID = I.KINGS_AMBER.id, count = 1 },
    },
    supportsTransmuteMastery = true,
    requirements = alchemyTool({
      minimumSkill = 450,
      recipeSpellID = 66660,
      cooldown = "transmute_20h",
    }),
    notes = "Shares the 20-hour transmute group. One cast from that group per plan.",
  },
  {
    id = "dreadstone",
    name = "Dreadstone",
    typeLabel = "Transmute",
    inputs = {
      { itemID = I.TWILIGHT_OPAL.id, count = 1 },
      { itemID = I.ETERNAL_SHADOW.id, count = 1 },
    },
    outputs = {
      { itemID = I.DREADSTONE.id, count = 1 },
    },
    supportsTransmuteMastery = true,
    requirements = alchemyTool({
      minimumSkill = 450,
      recipeSpellID = 66662,
      cooldown = "transmute_20h",
    }),
    notes = "Shares the 20-hour transmute group. One cast from that group per plan.",
  },
  {
    id = "majestic_zircon",
    name = "Majestic Zircon",
    typeLabel = "Transmute",
    inputs = {
      { itemID = I.SKY_SAPPHIRE.id, count = 1 },
      { itemID = I.ETERNAL_AIR.id, count = 1 },
    },
    outputs = {
      { itemID = I.MAJESTIC_ZIRCON.id, count = 1 },
    },
    supportsTransmuteMastery = true,
    requirements = alchemyTool({
      minimumSkill = 450,
      recipeSpellID = 66663,
      cooldown = "transmute_20h",
    }),
    notes = "Shares the 20-hour transmute group. One cast from that group per plan.",
  },
  {
    id = "eye_of_zul",
    name = "Eye of Zul",
    typeLabel = "Transmute",
    inputs = {
      { itemID = I.FOREST_EMERALD.id, count = 3 },
    },
    outputs = {
      { itemID = I.EYE_OF_ZUL.id, count = 1 },
    },
    supportsTransmuteMastery = true,
    requirements = alchemyTool({
      minimumSkill = 450,
      recipeSpellID = 66664,
      cooldown = "transmute_20h",
    }),
    notes = "Three Forest Emeralds. Shares the 20-hour transmute group.",
  },
  {
    -- Minimum skill is unset (yellow 440 versus the 450 quest tier). Do not guess.
    id = "cardinal_ruby",
    name = "Cardinal Ruby",
    typeLabel = "Transmute",
    skillUnset = true,
    inputs = {
      { itemID = I.SCARLET_RUBY.id, count = 1 },
      { itemID = I.ETERNAL_FIRE.id, count = 1 },
    },
    outputs = {
      { itemID = I.CARDINAL_RUBY.id, count = 1 },
    },
    supportsTransmuteMastery = true,
    requirements = alchemyTool({
      recipeSpellID = 66659,
      skillUnset = true,
      cooldown = "transmute_20h",
    }),
    notes = "Minimum skill is unset. Not an action.",
  },
}
