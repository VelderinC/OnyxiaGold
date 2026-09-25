--[[
  Disenchant expected-value tables.
  Phase 2: populate by item level, armour vs weapon, and quality.
  Weapons typically favour essences; armour typically favours dust.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Data = OnyxiaGold.Data or {}

OnyxiaGold.Data.DisenchantTables = {
  -- Example future shape (not evaluated in v0.1):
  -- {
  --   quality = 2,
  --   slot = "armor",
  --   iLevelMin = 80,
  --   iLevelMax = 99,
  --   outcomes = {
  --     { itemID = 34054, chance = 0.75, min = 2, max = 4 },
  --     { itemID = 34056, chance = 0.20, min = 1, max = 2 },
  --     { itemID = 34053, chance = 0.05, min = 1, max = 1 },
  --   },
  -- },
}
