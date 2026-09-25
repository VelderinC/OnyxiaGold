--[[
  OnyxiaGold.Capabilities
  Legacy 3.3.5 profession / recipe / specialisation detection.
  Do not use C_TradeSkillUI or GetProfessions.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Capabilities = OnyxiaGold.Capabilities or {}

local Cap = OnyxiaGold.Capabilities

-- Primary-profession trainer spells. GetSpellInfo localises the skill-line name.
local PROFESSION_SPELLS = {
  Alchemy = 2259,
  Jewelcrafting = 25229,
  Enchanting = 7411,
  Blacksmithing = 2018,
  Engineering = 4036,
  Leatherworking = 2108,
  Tailoring = 3908,
  Inscription = 45357,
  Herbalism = 2366,
  Mining = 2575,
  Skinning = 8613,
  Cooking = 2550,
  Fishing = 7620,
  FirstAid = 3273,
}

local SPEC_SPELLS = {
  Transmutation = 28672,
  Elixir = 28677,
  Potion = 28675,
}

local function rec()
  return OnyxiaGold.Database:GetCharacter()
end

local function localizedProfessionName(key)
  local spellID = PROFESSION_SPELLS[key]
  if spellID and GetSpellInfo then
    local name = GetSpellInfo(spellID)
    if name and name ~= "" then
      return name
    end
  end
  if key == "FirstAid" then
    return "First Aid"
  end
  return key
end

local function professionKeyFromSkillName(skillName)
  if not skillName then
    return nil
  end
  for key, _ in pairs(PROFESSION_SPELLS) do
    if skillName == localizedProfessionName(key) or skillName == key then
      return key
    end
  end
  if skillName == "First Aid" then
    return "FirstAid"
  end
  return nil
end

local function truthy(v)
  return v and v ~= 0
end

function Cap:ScanProfessions()
  local row = rec()
  if not row then
    return
  end
  local professions = {}
  local n = GetNumSkillLines and GetNumSkillLines() or 0
  for i = 1, n do
    local skillName, header, _, skillRank, _, skillModifier, skillMaxRank, isAbandonable = GetSkillLineInfo(i)
    if not truthy(header) then
      local key = professionKeyFromSkillName(skillName)
      if key then
        professions[key] = {
          key = key,
          name = skillName,
          rank = tonumber(skillRank) or 0,
          modifier = tonumber(skillModifier) or 0,
          maxRank = tonumber(skillMaxRank) or 0,
          abandonable = truthy(isAbandonable),
        }
      end
    end
  end
  row.professions = professions
  row.stateTimestamps.professions = time()
end

local function spellLinkID(link)
  if type(link) ~= "string" then
    return nil
  end
  local id = string.match(link, "spell:(%d+)")
  return tonumber(id)
end

function Cap:IsSpellInBook(spellID)
  spellID = tonumber(spellID)
  if not spellID then
    return false
  end
  if type(IsSpellKnown) == "function" then
    local ok, known = pcall(IsSpellKnown, spellID)
    if ok and known then
      return true
    end
  end
  local wantName
  if GetSpellInfo then
    wantName = GetSpellInfo(spellID)
  end
  if not wantName or not GetSpellName then
    return false
  end
  local i = 1
  while true do
    local name = GetSpellName(i, BOOKTYPE_SPELL)
    if not name then
      break
    end
    if name == wantName then
      local link
      if GetSpellLink then
        link = GetSpellLink(i, BOOKTYPE_SPELL)
      end
      local id = spellLinkID(link)
      if not id or id == spellID then
        return true
      end
    end
    i = i + 1
  end
  return false
end

function Cap:ScanSpecialisations()
  local row = rec()
  if not row then
    return
  end
  local specs = {}
  for key, spellID in pairs(SPEC_SPELLS) do
    local known = self:IsSpellInBook(spellID)
    specs[key] = {
      key = key,
      spellID = spellID,
      known = known and true or false,
    }
  end
  row.specialisations = specs
  row.stateTimestamps.specialisations = time()
end

local function isHeaderSkill(skillType, isExpanded)
  return skillType == "header"
end

local cooldownBySpell

local function cooldownGroupForSpell(spellID)
  spellID = tonumber(spellID)
  if not spellID then
    return nil
  end
  if not cooldownBySpell then
    cooldownBySpell = {}
    local data = OnyxiaGold.Data
    local lists = {}
    if data then
      lists[1] = data.Transmutes
      lists[2] = data.EnchantCrafts
      lists[3] = data.Conversions
    end
    for i = 1, table.getn(lists) do
      local list = lists[i]
      if type(list) == "table" then
        for j = 1, table.getn(list) do
          local req = list[j] and list[j].requirements
          local spell = req and tonumber(req.recipeSpellID)
          local group = req and req.cooldown
          if spell and type(group) == "string" and group ~= "" then
            cooldownBySpell[spell] = group
          end
        end
      end
    end
  end
  return cooldownBySpell[spellID]
end

function Cap:CooldownState(group)
  if not group then
    return "COOLDOWN_UNKNOWN"
  end
  local row = rec()
  local obs = row and type(row.cooldowns) == "table" and row.cooldowns[group] or nil
  local now = 0
  if time then
    now = time()
  end
  if OnyxiaGold.Lots and OnyxiaGold.Lots.CooldownState then
    return OnyxiaGold.Lots.CooldownState(obs, now)
  end
  return "COOLDOWN_UNKNOWN"
end

-- Returns the previous collapsed-header map, and whether every header expanded.
local function expandAllHeaders()
  local collapsed = {}
  local n = GetNumTradeSkills() or 0
  for i = 1, n do
    local name, skillType, _, isExpanded = GetTradeSkillInfo(i)
    if isHeaderSkill(skillType) then
      collapsed[name] = not truthy(isExpanded)
    end
  end
  local guard = 0
  local changed = true
  while changed and guard < 80 do
    changed = false
    guard = guard + 1
    n = GetNumTradeSkills() or 0
    for i = 1, n do
      local _, skillType, _, isExpanded = GetTradeSkillInfo(i)
      if isHeaderSkill(skillType) and not truthy(isExpanded) then
        if ExpandTradeSkillHeader then
          ExpandTradeSkillHeader(i)
        else
          return collapsed, false
        end
        changed = true
        break
      end
    end
  end
  return collapsed, not changed
end

local function restoreHeaders(collapsed)
  if type(collapsed) ~= "table" then
    return
  end
  local guard = 0
  local changed = true
  while changed and guard < 80 do
    changed = false
    guard = guard + 1
    local n = GetNumTradeSkills() or 0
    for i = 1, n do
      local name, skillType, _, isExpanded = GetTradeSkillInfo(i)
      if isHeaderSkill(skillType) and collapsed[name] and truthy(isExpanded) then
        if CollapseTradeSkillHeader then
          CollapseTradeSkillHeader(i)
        end
        changed = true
        break
      end
    end
  end
end

-- One open trade-skill row. Reagent item links and made-counts are 3.3.5
-- APIs. A missing count is left unknown. It is not guessed.
function Cap:ReadTradeSkillRecipe(index, profession, name, spellID)
  local Book = OnyxiaGold.RecipeBook
  if not Book or not Book.FromClientRow then
    return nil
  end
  if profession ~= "Alchemy" and profession ~= "Enchanting" then
    return nil
  end
  local reagents = {}
  local reagentCount = 0
  if type(GetTradeSkillNumReagents) == "function" then
    reagentCount = tonumber(GetTradeSkillNumReagents(index)) or 0
  end
  for r = 1, reagentCount do
    local reagentName, count
    if type(GetTradeSkillReagentInfo) == "function" then
      reagentName, _, count = GetTradeSkillReagentInfo(index, r)
    end
    local link
    if type(GetTradeSkillReagentItemLink) == "function" then
      link = GetTradeSkillReagentItemLink(index, r)
    end
    table.insert(reagents, {
      name = reagentName,
      count = count,
      link = link,
    })
  end
  local itemLink
  if type(GetTradeSkillItemLink) == "function" then
    itemLink = GetTradeSkillItemLink(index)
  end
  local outputMin, outputMax
  if type(GetTradeSkillNumMade) == "function" then
    local ok, minMade, maxMade = pcall(GetTradeSkillNumMade, index)
    if ok then
      outputMin = minMade
      outputMax = maxMade
    end
  end
  local cooldownRemaining
  if type(GetTradeSkillCooldown) == "function" then
    local ok, value = pcall(GetTradeSkillCooldown, index)
    if ok and type(value) == "number" then
      cooldownRemaining = value
    end
  end
  local now = 0
  if time then
    now = time()
  end
  return Book.FromClientRow({
    spellID = spellID,
    name = name,
    profession = profession,
    reagents = reagents,
    itemLink = itemLink,
    outputMin = outputMin,
    outputMax = outputMax,
    cooldownRemaining = cooldownRemaining,
  }, now)
end

function Cap:ScanOpenTradeSkill()
  if self.scanInProgress then
    return
  end
  if GetTime and self.suppressTradeUntil and GetTime() < self.suppressTradeUntil then
    return
  end
  local row = rec()
  if not row then
    return
  end
  if not GetTradeSkillLine or not GetNumTradeSkills then
    return
  end
  local skillName, skillRank, skillMax = GetTradeSkillLine()
  if not skillName or skillName == "UNKNOWN" or (UNKNOWN and skillName == UNKNOWN) then
    return
  end
  self.scanInProgress = true
  local key = professionKeyFromSkillName(skillName) or skillName
  local collapsed, expanded = expandAllHeaders()
  if not expanded then
    restoreHeaders(collapsed)
    self.scanInProgress = false
    if GetTime then
      self.suppressTradeUntil = GetTime() + 1.25
    end
    OnyxiaGold.Log:Warn("Capabilities", "Recipe scan incomplete for " .. tostring(key) .. "; previous snapshot kept")
    return
  end
  OnyxiaGold.Database:MigrateKnownRecipes(row)
  if type(row.knownRecipes) ~= "table" then
    row.knownRecipes = {}
  end
  local fresh = {}
  local captured = {}
  local capturedCount = 0
  local deterministicCount = 0
  local found = 0
  local unlinked = 0
  local observed = {}
  local canReadCooldown = type(GetTradeSkillCooldown) == "function"
  local n = GetNumTradeSkills() or 0
  for i = 1, n do
    local name, skillType = GetTradeSkillInfo(i)
    if name and not isHeaderSkill(skillType) then
      local link
      if GetTradeSkillRecipeLink then
        link = GetTradeSkillRecipeLink(i)
      end
      local spellID
      if type(link) == "string" then
        spellID = tonumber(string.match(link, "enchant:(%d+)"))
          or tonumber(string.match(link, "spell:(%d+)"))
      end
      if spellID then
        fresh[spellID] = true
        found = found + 1
        if key == "Alchemy" or key == "Enchanting" then
          local recipe = self:ReadTradeSkillRecipe(i, key, name, spellID)
          if recipe then
            captured[spellID] = recipe
            capturedCount = capturedCount + 1
            if recipe.deterministic then
              deterministicCount = deterministicCount + 1
            end
          end
        end
        if canReadCooldown then
          local group = cooldownGroupForSpell(spellID)
          if group then
            local ok, value = pcall(GetTradeSkillCooldown, i)
            local remaining = 0
            if ok then
              remaining = tonumber(value) or 0
            end
            if remaining < 0 then
              remaining = 0
            end
            local prev = observed[group]
            if not prev or remaining > prev.remainingSeconds then
              observed[group] = {
                recipeSpellID = spellID,
                remainingSeconds = remaining,
              }
            end
          end
        end
      else
        unlinked = unlinked + 1
      end
    end
  end
  restoreHeaders(collapsed)
  if unlinked > 0 then
    self.scanInProgress = false
    if GetTime then
      self.suppressTradeUntil = GetTime() + 1.25
    end
    OnyxiaGold.Log:Warn("Capabilities", string.format(
      "Recipe scan %s left %d rows without a spell link; previous snapshot kept",
      tostring(key), unlinked
    ))
    return
  end
  -- Complete scan replaces this profession. It does not append, and it does
  -- not touch any other profession's snapshot.
  row.knownRecipes[key] = fresh
  if key == "Alchemy" or key == "Enchanting" then
    if type(row.recipeBook) ~= "table" then
      row.recipeBook = {}
    end
    row.recipeBook[key] = {
      scannedAt = time(),
      recipes = captured,
    }
  end
  if canReadCooldown and next(observed) then
    if type(row.cooldowns) ~= "table" then
      row.cooldowns = {}
    end
    local now = time()
    for group, obs in pairs(observed) do
      local remaining = obs.remainingSeconds or 0
      row.cooldowns[group] = {
        recipeSpellID = obs.recipeSpellID,
        cooldownGroup = group,
        remainingSeconds = remaining,
        observedAt = now,
        readyAt = now + remaining,
      }
    end
  end
  local legacy = row.knownRecipes._legacy
  if type(legacy) == "table" then
    for spellID, _ in pairs(fresh) do
      legacy[spellID] = nil
    end
    local map = OnyxiaGold.Database:SpellProfessionMap()
    for spellID, profession in pairs(map) do
      if profession == key then
        legacy[spellID] = nil
      end
    end
    if not next(legacy) then
      row.knownRecipes._legacy = nil
    end
  end
  row.recipeScans[key] = {
    timestamp = time(),
    profession = key,
    skillRank = tonumber(skillRank) or 0,
    skillMax = tonumber(skillMax) or 0,
    count = found,
    complete = true,
    snapshotReplaced = true,
  }
  row.stateTimestamps.recipes = time()
  self.scanInProgress = false
  if GetTime then
    self.suppressTradeUntil = GetTime() + 1.25
  end
  OnyxiaGold.Log:Debug("Capabilities", string.format(
    "Recipe scan replaced %s rank=%s recipes=%d book=%d deterministic=%d",
    tostring(key), tostring(skillRank), found, capturedCount, deterministicCount
  ))
  return true
end

function Cap:HasProfession(name)
  local row = rec()
  if not row or not name then
    return false
  end
  local p = row.professions[name]
  return p and (p.rank or 0) > 0
end

function Cap:GetProfessionSkill(name)
  local row = rec()
  if not row or not name then
    return nil
  end
  return row.professions[name]
end

function Cap:RecipeSnapshotReplaced(profession)
  local row = rec()
  if not row or not profession or type(row.recipeScans) ~= "table" then
    return false
  end
  local scan = row.recipeScans[profession]
  return scan and scan.snapshotReplaced and true or false
end

-- profession scopes the lookup. A replaced snapshot does not consult _legacy,
-- so an abandoned profession cannot keep ghost recipes after a complete rescan.
function Cap:HasRecipe(recipeSpellID, profession)
  recipeSpellID = tonumber(recipeSpellID)
  if not recipeSpellID then
    return true
  end
  local row = rec()
  if not row or type(row.knownRecipes) ~= "table" then
    return nil
  end
  local known = row.knownRecipes
  if profession then
    local set = known[profession]
    if type(set) == "table" and set[recipeSpellID] then
      return true
    end
    if self:RecipeSnapshotReplaced(profession) then
      return false
    end
    if not self:HasRecipeScan(profession) then
      return false
    end
    local legacy = known._legacy
    if type(legacy) == "table" and legacy[recipeSpellID] then
      return true
    end
    -- Pre-migration flat set, if a scan exists and has not been replaced yet.
    if known[recipeSpellID] and type(known[recipeSpellID]) ~= "table" then
      return true
    end
    return false
  end
  for key, set in pairs(known) do
    if key ~= "_legacy" and type(set) == "table" and set[recipeSpellID] then
      return true
    end
  end
  local legacy = known._legacy
  if type(legacy) == "table" and legacy[recipeSpellID] then
    return true
  end
  if known[recipeSpellID] and type(known[recipeSpellID]) ~= "table" then
    return true
  end
  return false
end

function Cap:HasRecipeScan(profession)
  local row = rec()
  if not row or not profession then
    return false
  end
  local scan = row.recipeScans[profession]
  return scan and scan.timestamp ~= nil
end

function Cap:RecipeScanAge(profession)
  local row = rec()
  if not row or not profession then
    return nil
  end
  local scan = row.recipeScans[profession]
  if not scan or not scan.timestamp then
    return nil
  end
  return OnyxiaGold.AgeSeconds(scan.timestamp)
end

function Cap:HasSpecialisation(name)
  if not name then
    return false
  end
  if name == "Transmutation Master" then
    name = "Transmutation"
  end
  local row = rec()
  if row and row.specialisations and row.specialisations[name] then
    return row.specialisations[name].known and true or false
  end
  if name == "Transmutation" then
    return self:IsSpellInBook(SPEC_SPELLS.Transmutation)
  end
  return false
end

function Cap:CanExecute(requirements)
  local result = {
    executable = true,
    reason = nil,
    missingProfession = nil,
    missingSkill = nil,
    missingRecipe = nil,
    unknownRecipe = nil,
    missingSpecialisation = nil,
    missingClass = nil,
    missingLevel = nil,
    globalOnly = nil,
    personalState = nil,
  }
  if type(requirements) ~= "table" then
    return result
  end

  -- A blank skill is not zero. Do not treat an unset requirement as met.
  if requirements.skillUnset then
    result.executable = false
    result.skillUnset = true
    result.reason = "Skill requirement is unset"
    return result
  end

  if requirements.requiredClass then
    local classFile = OnyxiaGold.CharacterState and OnyxiaGold.CharacterState:ClassFile()
    if classFile and classFile ~= requirements.requiredClass then
      result.executable = false
      result.missingClass = requirements.requiredClass
      result.reason = "Requires " .. tostring(requirements.requiredClass)
      return result
    end
  end

  if requirements.minimumLevel then
    local level = OnyxiaGold.CharacterState and OnyxiaGold.CharacterState:Level() or 0
    if level < requirements.minimumLevel then
      result.executable = false
      result.missingLevel = requirements.minimumLevel - level
      result.reason = "Level " .. tostring(level) .. "/" .. tostring(requirements.minimumLevel)
      return result
    end
  end

  local profession = requirements.profession
  if profession then
    local skill = self:GetProfessionSkill(profession)
    local rank = skill and (skill.rank or 0) or 0
    if rank <= 0 then
      result.executable = false
      result.missingProfession = profession
      local factory = OnyxiaGold.Data.Factory
      if factory and factory.MissingProfessionState then
        result.personalState = factory:MissingProfessionState(profession)
      else
        result.personalState = "LOCKED_PROFESSION"
      end
      result.globalOnly = result.personalState == "GLOBAL_ONLY"
      result.reason = "Missing " .. tostring(profession)
      return result
    end
    local need = tonumber(requirements.minimumSkill) or 0
    if rank < need then
      result.executable = false
      result.missingSkill = need - rank
      result.reason = profession .. " skill " .. tostring(rank) .. "/" .. tostring(need)
      return result
    end
  end

  local recipeSpellID = tonumber(requirements.recipeSpellID)
  if recipeSpellID then
    if profession and not self:HasRecipeScan(profession) then
      result.executable = false
      result.unknownRecipe = recipeSpellID
      result.reason = "UNKNOWN_RECIPE_STATE"
      return result
    end
    if not self:HasRecipe(recipeSpellID, profession) then
      result.executable = false
      result.missingRecipe = recipeSpellID
      result.reason = "Recipe not known"
      return result
    end
  end

  local spec = requirements.specialisationRequired
  if spec and not self:HasSpecialisation(spec) then
    result.executable = false
    result.missingSpecialisation = spec
    result.reason = "Requires " .. tostring(spec)
    return result
  end

  return result
end

function Cap:ProfessionSummary()
  local alchemy = self:GetProfessionSkill("Alchemy")
  local enchanting = self:GetProfessionSkill("Enchanting")
  local jc = self:GetProfessionSkill("Jewelcrafting")
  local tmDetected = self:HasSpecialisation("Transmutation")
  local override = OnyxiaGold:IsTransmuteMasterOverride()
  return {
    alchemy = alchemy,
    enchanting = enchanting,
    jewelcrafting = jc,
    transmuteMasterDetected = tmDetected,
    transmuteMasterOverride = override,
    transmuteMaster = OnyxiaGold:IsTransmuteMaster(),
    alchemyRecipeAge = self:RecipeScanAge("Alchemy"),
    enchantingRecipeAge = self:RecipeScanAge("Enchanting"),
    jcRecipeAge = self:RecipeScanAge("Jewelcrafting"),
  }
end

function Cap:GetFactoryStatus()
  local messages = {}
  local complete = true
  local gaps = {}

  local alchemy = self:GetProfessionSkill("Alchemy")
  local alchRank = alchemy and (alchemy.rank or 0) or 0
  local alchMax = alchemy and (alchemy.maxRank or 0) or 0
  if alchRank <= 0 then
    complete = false
    table.insert(messages, "Alchemy not learned")
    table.insert(gaps, { profession = "Alchemy", have = 0, need = 450 })
  elseif alchRank < 450 then
    complete = false
    table.insert(messages, "Alchemy needs " .. tostring(450 - alchRank) .. " skill")
    table.insert(gaps, { profession = "Alchemy", have = alchRank, need = 450 })
  end

  local tmDetected = self:HasSpecialisation("Transmutation")
  if alchRank > 0 and not tmDetected then
    complete = false
    if OnyxiaGold:IsTransmuteMasterOverride() then
      table.insert(messages, "Transmutation Master override on; not detected")
    else
      table.insert(messages, "Transmutation Master not detected")
    end
  end

  local enchanting = self:GetProfessionSkill("Enchanting")
  local encRank = enchanting and (enchanting.rank or 0) or 0
  if encRank <= 0 then
    complete = false
    table.insert(messages, "Enchanting not learned")
    table.insert(gaps, { profession = "Enchanting", have = 0, need = 450 })
  elseif encRank < 450 then
    complete = false
    table.insert(messages, "Enchanting needs " .. tostring(450 - encRank) .. " skill")
    table.insert(gaps, { profession = "Enchanting", have = encRank, need = 450 })
  end

  local jc = self:GetProfessionSkill("Jewelcrafting")
  local hasJC = jc and (jc.rank or 0) > 0
  if hasJC and encRank <= 0 then
    complete = false
    table.insert(messages, "Jewelcrafting detected; factory target is Enchanting")
  end

  local message
  if complete then
    message = "Factory setup complete"
  elseif table.getn(messages) > 0 then
    message = "Factory setup incomplete: " .. table.concat(messages, "; ")
  else
    message = "Factory setup incomplete"
  end

  return {
    complete = complete,
    matchesTarget = complete,
    message = message,
    messages = messages,
    gaps = gaps,
    alchemyRank = alchRank,
    alchemyMax = alchMax,
    enchantingRank = encRank,
    jewelcraftingRank = hasJC and jc.rank or 0,
    transmuteMaster = tmDetected and true or false,
  }
end

function Cap:CanDisenchantItem(itemLevel, quality)
  local need = OnyxiaGold.Data.GetDisenchantSkillRequired
    and OnyxiaGold.Data.GetDisenchantSkillRequired(itemLevel, quality)
  if not need then
    return {
      executable = false,
      reason = "Item is not disenchantable",
    }
  end
  return self:CanExecute({
    profession = "Enchanting",
    minimumSkill = need,
  })
end
