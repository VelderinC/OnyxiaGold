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

-- Essence pairs are reversible item-use conversions. No profession and no skill,
-- so they are legal at Alchemy 1 and Enchanting 1. Dream Shard combines one way.
-- Prismatic shards stay a priced pair, not an action.
local function essencePair(id, lesser, greater, shortName)
  return {
    id = id,
    kind = "essence",
    typeLabel = "Essence",
    sourceItemID = greater.id,
    sourceCount = 1,
    targetItemID = lesser.id,
    targetCount = 3,
    reversible = true,
    nameForward = "Greater " .. shortName .. " → Lesser " .. shortName,
    nameReverse = "Lesser " .. shortName .. " → Greater " .. shortName,
    notesForward = "1 Greater converts into 3 Lesser. Item-use conversion; no profession required.",
    notesReverse = "3 Lesser convert into 1 Greater. Item-use conversion; no profession required.",
  }
end

OnyxiaGold.Data.Conversions = {
  essencePair("greater_magic_to_lesser", I.LESSER_MAGIC_ESSENCE, I.GREATER_MAGIC_ESSENCE, "Magic"),
  essencePair("greater_astral_to_lesser", I.LESSER_ASTRAL_ESSENCE, I.GREATER_ASTRAL_ESSENCE, "Astral"),
  essencePair("greater_mystic_to_lesser", I.LESSER_MYSTIC_ESSENCE, I.GREATER_MYSTIC_ESSENCE, "Mystic"),
  essencePair("greater_nether_to_lesser", I.LESSER_NETHER_ESSENCE, I.GREATER_NETHER_ESSENCE, "Nether"),
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

-- One shared 20-hour group. Skill numbers are the spell-page minimums.
-- A nil skill is unset and must not become an action. Do not encode a stored 1.
local function sharedCooldown(id, name, spell, skill, inputItem, outputItem, note)
  local req = {
    recipeSpellID = spell,
    cooldown = "transmute_20h",
  }
  local unset = skill == nil
  if unset then
    req.skillUnset = true
  else
    req.minimumSkill = skill
  end
  return {
    id = id,
    name = name,
    typeLabel = "Transmute",
    skillUnset = unset or nil,
    inputs = {
      { itemID = inputItem.id, count = 1 },
    },
    outputs = {
      { itemID = outputItem.id, count = 1 },
    },
    -- Section 2.1 applies the 1.20 expectation to transmutes. Elemental Fire
    -- is the unset mastery and is not in this list.
    supportsTransmuteMastery = true,
    requirements = alchemyTool(req),
    notes = note or "Shares the 20-hour transmute group. One cast from that group.",
  }
end

local function addShared(row)
  table.insert(OnyxiaGold.Data.Transmutes, row)
end

local cycleNote = "Shares the 20-hour transmute group. One cast. Transmute Master is expected value only."

-- Eternal cycle. Skill 400. One to one.
local eternals = {
  { "eternal_life_to_shadow", "Eternal Life to Shadow", 53771, I.ETERNAL_LIFE, I.ETERNAL_SHADOW },
  { "eternal_life_to_fire", "Eternal Life to Fire", 53773, I.ETERNAL_LIFE, I.ETERNAL_FIRE },
  { "eternal_fire_to_water", "Eternal Fire to Water", 53774, I.ETERNAL_FIRE, I.ETERNAL_WATER },
  { "eternal_fire_to_life", "Eternal Fire to Life", 53775, I.ETERNAL_FIRE, I.ETERNAL_LIFE },
  { "eternal_air_to_water", "Eternal Air to Water", 53776, I.ETERNAL_AIR, I.ETERNAL_WATER },
  { "eternal_air_to_earth", "Eternal Air to Earth", 53777, I.ETERNAL_AIR, I.ETERNAL_EARTH },
  { "eternal_shadow_to_earth", "Eternal Shadow to Earth", 53779, I.ETERNAL_SHADOW, I.ETERNAL_EARTH },
  { "eternal_shadow_to_life", "Eternal Shadow to Life", 53780, I.ETERNAL_SHADOW, I.ETERNAL_LIFE },
  { "eternal_earth_to_air", "Eternal Earth to Air", 53781, I.ETERNAL_EARTH, I.ETERNAL_AIR },
  { "eternal_earth_to_shadow", "Eternal Earth to Shadow", 53782, I.ETERNAL_EARTH, I.ETERNAL_SHADOW },
  { "eternal_water_to_air", "Eternal Water to Air", 53783, I.ETERNAL_WATER, I.ETERNAL_AIR },
  { "eternal_water_to_fire", "Eternal Water to Fire", 53784, I.ETERNAL_WATER, I.ETERNAL_FIRE },
}
for i = 1, table.getn(eternals) do
  local row = eternals[i]
  addShared(sharedCooldown(row[1], row[2], row[3], 400, row[4], row[5], cycleNote))
end

-- Old metals. Skill 225.
addShared(sharedCooldown(
  "iron_to_gold", "Iron to Gold", 11479, 225, I.IRON_BAR, I.GOLD_BAR, cycleNote
))
addShared(sharedCooldown(
  "mithril_to_truesilver", "Mithril to Truesilver", 11480, 225, I.MITHRIL_BAR, I.TRUESILVER_BAR, cycleNote
))

-- Vanilla essence cycle. Skill 275. One to one.
local essences = {
  { "essence_air_to_fire", "Essence of Air to Fire", 17559, I.ESSENCE_OF_AIR, I.ESSENCE_OF_FIRE },
  { "essence_fire_to_earth", "Essence of Fire to Earth", 17560, I.ESSENCE_OF_FIRE, I.ESSENCE_OF_EARTH },
  { "essence_earth_to_water", "Essence of Earth to Water", 17561, I.ESSENCE_OF_EARTH, I.ESSENCE_OF_WATER },
  { "essence_water_to_air", "Essence of Water to Air", 17562, I.ESSENCE_OF_WATER, I.ESSENCE_OF_AIR },
  { "essence_undeath_to_water", "Essence of Undeath to Water", 17563, I.ESSENCE_OF_UNDEATH, I.ESSENCE_OF_WATER },
  { "essence_water_to_undeath", "Essence of Water to Undeath", 17564, I.ESSENCE_OF_WATER, I.ESSENCE_OF_UNDEATH },
  { "essence_living_to_earth", "Living Essence to Earth", 17565, I.LIVING_ESSENCE, I.ESSENCE_OF_EARTH },
  { "essence_earth_to_living", "Essence of Earth to Living", 17566, I.ESSENCE_OF_EARTH, I.LIVING_ESSENCE },
}
for i = 1, table.getn(essences) do
  local row = essences[i]
  addShared(sharedCooldown(row[1], row[2], row[3], 275, row[4], row[5], cycleNote))
end

-- Trainer primals. Skill 350. One to one.
local primals = {
  { "primal_air_to_fire", "Primal Air to Fire", 28566, I.PRIMAL_AIR, I.PRIMAL_FIRE },
  { "primal_earth_to_water", "Primal Earth to Water", 28567, I.PRIMAL_EARTH, I.PRIMAL_WATER },
  { "primal_fire_to_earth", "Primal Fire to Earth", 28568, I.PRIMAL_FIRE, I.PRIMAL_EARTH },
  { "primal_water_to_air", "Primal Water to Air", 28569, I.PRIMAL_WATER, I.PRIMAL_AIR },
}
for i = 1, table.getn(primals) do
  local row = primals[i]
  addShared(sharedCooldown(row[1], row[2], row[3], 350, row[4], row[5], cycleNote))
end

-- Discovered primals store a required skill of 1. That number is unset.
local discovered = {
  { "primal_shadow_to_water", "Primal Shadow to Water", 28580, I.PRIMAL_SHADOW, I.PRIMAL_WATER },
  { "primal_water_to_shadow", "Primal Water to Shadow", 28581, I.PRIMAL_WATER, I.PRIMAL_SHADOW },
  { "primal_mana_to_fire", "Primal Mana to Fire", 28582, I.PRIMAL_MANA, I.PRIMAL_FIRE },
  { "primal_fire_to_mana", "Primal Fire to Mana", 28583, I.PRIMAL_FIRE, I.PRIMAL_MANA },
  { "primal_life_to_earth", "Primal Life to Earth", 28584, I.PRIMAL_LIFE, I.PRIMAL_EARTH },
  { "primal_earth_to_life", "Primal Earth to Life", 28585, I.PRIMAL_EARTH, I.PRIMAL_LIFE },
}
for i = 1, table.getn(discovered) do
  local row = discovered[i]
  addShared(sharedCooldown(
    row[1], row[2], row[3], nil, row[4], row[5],
    "Minimum skill is unset. Not an action."
  ))
end

-- Eternal Might's required skill is blank. Not an action. Not a one-to-one cycle.
addShared({
  id = "eternal_might",
  name = "Eternal Might",
  typeLabel = "Transmute",
  skillUnset = true,
  inputs = {
    { itemID = I.ETERNAL_AIR.id, count = 1 },
    { itemID = I.ETERNAL_EARTH.id, count = 1 },
    { itemID = I.ETERNAL_FIRE.id, count = 1 },
    { itemID = I.ETERNAL_WATER.id, count = 1 },
  },
  outputs = {
    { itemID = I.ETERNAL_MIGHT.id, count = 1 },
  },
  supportsTransmuteMastery = true,
  requirements = alchemyTool({
    recipeSpellID = 54020,
    skillUnset = true,
    cooldown = "transmute_20h",
  }),
  notes = "Minimum skill is unset. Not an action.",
})
