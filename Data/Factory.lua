--[[
  Target factory configuration for the intended Alliance Druid.

  This is the IDEAL profession pair, not a claim that the character has them.
  Capabilities still detect whatever the logged-in character actually knows.

  Target:
    Alchemy 450 + Transmutation Master
    Enchanting 450

  Jewelcrafting remains a valid profession in the generic model (GLOBAL_ONLY
  on this character). Gathering professions must not be recommended as
  replacements for the two primary factory slots.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Data = OnyxiaGold.Data or {}

local Factory = {}
OnyxiaGold.Data.Factory = Factory

Factory.character = {
  class = "DRUID",
  faction = "Alliance",
  realm = "Onyxia",
  minimumLevel = 80,
}

Factory.primary = {
  {
    profession = "Alchemy",
    minimumSkill = 450,
    specialisation = "Transmutation",
    specialisationLabel = "Transmutation Master",
  },
  {
    profession = "Enchanting",
    minimumSkill = 450,
  },
}

-- Supported generically for GLOBAL market analysis. Not the factory pair.
Factory.globalProfessions = {
  Jewelcrafting = true,
  Tailoring = true,
  Blacksmithing = true,
  Leatherworking = true,
  Engineering = true,
  Inscription = true,
}

Factory.gathering = {
  Mining = true,
  Herbalism = true,
  Skinning = true,
}

function Factory:IsTargetProfession(name)
  if not name then
    return false
  end
  for i = 1, table.getn(self.primary) do
    if self.primary[i].profession == name then
      return true
    end
  end
  return false
end

function Factory:IsGatheringProfession(name)
  return name and self.gathering[name] and true or false
end

function Factory:IsGlobalProfession(name)
  return name and self.globalProfessions[name] and true or false
end

-- How a missing profession should be classified for the personal planner.
function Factory:MissingProfessionState(name)
  if self:IsGatheringProfession(name) or self:IsTargetProfession(name) then
    return "LOCKED_PROFESSION"
  end
  return "GLOBAL_ONLY"
end

function Factory:GetTargetSkill(name)
  for i = 1, table.getn(self.primary) do
    local row = self.primary[i]
    if row.profession == name then
      return row.minimumSkill, row.specialisation
    end
  end
  return nil
end
