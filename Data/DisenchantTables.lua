--[[
  Disenchant yields and the Enchanting skill each item level needs.

  Skill and quantity come from wotlk-335-mechanics.md. A gap in that
  skill table returns nil. Northrend uncommon rates are unset and are
  not listed. Item levels 166 and 167 are omitted. The 0.5% crystal on
  older rares is not an outcome. A quantity range is priced at its minimum.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Data = OnyxiaGold.Data or {}

local function skillBand(itemLevel, rows)
  for i = 1, table.getn(rows) do
    local row = rows[i]
    if itemLevel >= row[1] and itemLevel <= row[2] then
      return row[3]
    end
  end
  return nil
end

local UNCOMMON_SKILL = {
  { 1, 20, 1 },
  { 21, 25, 25 },
  { 26, 30, 50 },
  { 31, 35, 75 },
  { 36, 40, 100 },
  { 41, 45, 125 },
  { 46, 50, 150 },
  { 51, 55, 175 },
  { 56, 60, 200 },
  { 61, 99, 225 },
  { 102, 120, 275 },
  { 130, 150, 325 },
  { 154, 182, 350 },
}

local RARE_SKILL = {
  { 10, 25, 25 },
  { 26, 30, 50 },
  { 31, 35, 75 },
  { 36, 40, 100 },
  { 41, 45, 125 },
  { 46, 50, 150 },
  { 51, 55, 175 },
  { 56, 60, 200 },
  { 61, 97, 225 },
  { 100, 115, 275 },
  { 130, 200, 325 },
}

local EPIC_SKILL = {
  { 61, 95, 225 },
  { 100, 164, 300 },
  { 200, 277, 375 },
}

-- Nil means the skill is unset. Do not invent a number for the holes.
function OnyxiaGold.Data.GetDisenchantSkillRequired(itemLevel, quality)
  itemLevel = tonumber(itemLevel)
  quality = tonumber(quality)
  if not itemLevel or not quality then
    return nil
  end
  if quality == 2 then
    return skillBand(itemLevel, UNCOMMON_SKILL)
  end
  if quality == 3 then
    return skillBand(itemLevel, RARE_SKILL)
  end
  if quality == 4 then
    return skillBand(itemLevel, EPIC_SKILL)
  end
  return nil
end

-- bps is probability in basis points. minQty is the low end of a range.
local function outcomesFor(itemLevel, rows)
  for i = 1, table.getn(rows) do
    local row = rows[i]
    if itemLevel >= row.min and itemLevel <= row.max then
      return row.outcomes
    end
  end
  return nil
end

local function line(itemID, bps, minQty)
  return { itemID = itemID, bps = bps, minQty = minQty }
end

local ARMOR_GREEN = {
  { min = 5, max = 15, outcomes = { line(10940, 8000, 1), line(10938, 2000, 1) } },
  { min = 16, max = 20, outcomes = { line(10940, 7500, 2), line(10939, 2000, 1), line(10978, 500, 1) } },
  { min = 21, max = 25, outcomes = { line(10940, 7500, 4), line(10998, 1500, 1), line(10978, 1000, 1) } },
  { min = 26, max = 30, outcomes = { line(11083, 7500, 1), line(11082, 2000, 1), line(11084, 500, 1) } },
  { min = 31, max = 35, outcomes = { line(11083, 7500, 2), line(11134, 2000, 1), line(11138, 500, 1) } },
  { min = 36, max = 40, outcomes = { line(11137, 7500, 1), line(11135, 2000, 1), line(11139, 500, 1) } },
  { min = 41, max = 45, outcomes = { line(11137, 7500, 2), line(11174, 2000, 1), line(11177, 500, 1) } },
  { min = 46, max = 50, outcomes = { line(11176, 7500, 1), line(11175, 2000, 1), line(11178, 500, 1) } },
  { min = 51, max = 55, outcomes = { line(11176, 7500, 2), line(16202, 2000, 1), line(14343, 500, 1) } },
  { min = 56, max = 60, outcomes = { line(16204, 7500, 1), line(16203, 2000, 1), line(14344, 500, 1) } },
  { min = 61, max = 65, outcomes = { line(16204, 7500, 2), line(16203, 2000, 2), line(14344, 500, 1) } },
  { min = 79, max = 79, outcomes = { line(22445, 7500, 1), line(22447, 2200, 1), line(22448, 300, 1) } },
  { min = 80, max = 99, outcomes = { line(22445, 7500, 2), line(22447, 2200, 2), line(22448, 300, 1) } },
  { min = 100, max = 120, outcomes = { line(22445, 7500, 2), line(22446, 2200, 1), line(22449, 300, 1) } },
}

local WEAPON_GREEN = {
  { min = 6, max = 15, outcomes = { line(10940, 2000, 1), line(10938, 8000, 1) } },
  { min = 16, max = 20, outcomes = { line(10940, 2000, 2), line(10939, 7500, 1), line(10978, 500, 1) } },
  { min = 21, max = 25, outcomes = { line(10940, 1500, 4), line(10998, 7500, 1), line(10978, 1000, 1) } },
  { min = 26, max = 30, outcomes = { line(11083, 2000, 1), line(11082, 7500, 1), line(11084, 500, 1) } },
  { min = 31, max = 35, outcomes = { line(11083, 2000, 2), line(11134, 7500, 1), line(11138, 500, 1) } },
  { min = 36, max = 40, outcomes = { line(11137, 2000, 1), line(11135, 7500, 1), line(11139, 500, 1) } },
  { min = 41, max = 45, outcomes = { line(11137, 2000, 2), line(11174, 7500, 1), line(11177, 500, 1) } },
  { min = 46, max = 50, outcomes = { line(11176, 2000, 1), line(11175, 7500, 1), line(11178, 500, 1) } },
  { min = 51, max = 55, outcomes = { line(11176, 2200, 2), line(16202, 7500, 1), line(14343, 300, 1) } },
  { min = 56, max = 60, outcomes = { line(16204, 2200, 1), line(16203, 7500, 1), line(14344, 300, 1) } },
  { min = 61, max = 65, outcomes = { line(16204, 2200, 2), line(16203, 7500, 2), line(14344, 300, 1) } },
  { min = 80, max = 99, outcomes = { line(22445, 2200, 2), line(22447, 7500, 2), line(22448, 300, 1) } },
  { min = 100, max = 120, outcomes = { line(22445, 2200, 2), line(22446, 7500, 1), line(22449, 300, 1) } },
}

local function rareOutcomes(itemLevel)
  if itemLevel == 166 or itemLevel == 167 then
    return nil
  end
  if itemLevel >= 1 and itemLevel <= 25 then
    return { line(10978, 10000, 1) }
  elseif itemLevel >= 26 and itemLevel <= 30 then
    return { line(11084, 10000, 1) }
  elseif itemLevel >= 31 and itemLevel <= 35 then
    return { line(11138, 10000, 1) }
  elseif itemLevel >= 36 and itemLevel <= 40 then
    return { line(11139, 10000, 1) }
  elseif itemLevel >= 41 and itemLevel <= 45 then
    return { line(11177, 10000, 1) }
  elseif itemLevel >= 46 and itemLevel <= 50 then
    return { line(11178, 10000, 1) }
  elseif itemLevel >= 51 and itemLevel <= 55 then
    return { line(14343, 10000, 1) }
  elseif itemLevel >= 56 and itemLevel <= 65 then
    return { line(14344, 9950, 1) }
  elseif itemLevel >= 66 and itemLevel <= 99 then
    return { line(22448, 9950, 1) }
  elseif itemLevel >= 100 and itemLevel <= 115 then
    return { line(22449, 9950, 1) }
  elseif itemLevel >= 130 and itemLevel <= 165 then
    return { line(34053, 10000, 1) }
  elseif itemLevel >= 168 and itemLevel <= 200 then
    return { line(34052, 10000, 1) }
  end
  return nil
end

-- itemClass is "Armor" or "Weapon" from item info. Shields are armor. Wands are weapons.
function OnyxiaGold.Data.GetDisenchantOutcomes(itemLevel, quality, itemClass)
  itemLevel = tonumber(itemLevel)
  quality = tonumber(quality)
  if not itemLevel or not quality then
    return nil
  end
  if itemLevel == 166 or itemLevel == 167 then
    return nil
  end
  if quality == 2 then
    if itemClass == "Armor" then
      return outcomesFor(itemLevel, ARMOR_GREEN)
    end
    if itemClass == "Weapon" then
      return outcomesFor(itemLevel, WEAPON_GREEN)
    end
    return nil
  end
  if quality == 3 then
    return rareOutcomes(itemLevel)
  end
  if quality == 4 and itemLevel >= 200 and itemLevel <= 277 then
    return { line(34057, 10000, 1) }
  end
  return nil
end
