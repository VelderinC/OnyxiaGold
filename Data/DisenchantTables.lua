--[[
  Disenchant expected-value tables and Enchanting skill floors.

  v0.2.0 will populate outcomes by quality, item level, and weapon vs armour.
  Do not scatter DE skill thresholds through the scanner; use GetDisenchantSkillRequired.

  EDV (future) =
    sum(probability × expected quantity × conservative material liquidation)
  Then apply AH cut once, on sale of the produced materials. Disenchanting itself
  has no AH cut.

  Until tables are filled, Collect() returns nothing.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Data = OnyxiaGold.Data or {}

OnyxiaGold.Data.DisenchantTables = {
  -- Example future shape (not evaluated until v0.2.0):
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

-- 3.3.5 Enchanting skill required to disenchant an item.
-- Brackets follow the common WotLK client table (uncommon / rare / epic).
-- Confirm on Warmane Onyxia before using this to authorise AH buys.
function OnyxiaGold.Data.GetDisenchantSkillRequired(itemLevel, quality)
  itemLevel = tonumber(itemLevel)
  quality = tonumber(quality)
  if not itemLevel or not quality then
    return nil
  end
  if quality < 2 or quality > 4 then
    return nil
  end

  local function uncommonSkill(ilvl)
    if ilvl <= 20 then
      return 1
    elseif ilvl <= 25 then
      return 25
    elseif ilvl <= 30 then
      return 50
    elseif ilvl <= 35 then
      return 75
    elseif ilvl <= 40 then
      return 100
    elseif ilvl <= 45 then
      return 125
    elseif ilvl <= 50 then
      return 150
    elseif ilvl <= 55 then
      return 175
    elseif ilvl <= 60 then
      return 200
    elseif ilvl <= 99 then
      return 225
    elseif ilvl <= 120 then
      return 225
    elseif ilvl <= 151 then
      return 275
    elseif ilvl <= 200 then
      return 325
    end
    return 350
  end

  if quality == 2 then
    return uncommonSkill(itemLevel)
  end
  if quality == 3 then
    -- Rare: typically 25 above the uncommon bracket of the same iLevel.
    local need = uncommonSkill(itemLevel) + 25
    if need < 1 then
      need = 1
    end
    return need
  end
  -- Epic
  if itemLevel <= 95 then
    return 225
  elseif itemLevel <= 164 then
    return 275
  elseif itemLevel <= 200 then
    return 325
  end
  return 350
end
