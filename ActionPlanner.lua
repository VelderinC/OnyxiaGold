--[[
  OnyxiaGold.ActionPlanner
  Turns market opportunities into a personal, capital-constrained action list.

  OpportunityEngine asks whether a transformation is economically good.
  ActionPlanner asks whether THIS character can and should do it now.

  Greedy on current deployable gold only. Expected sales are never cash.
  Owned bag materials reduce cashRequiredNow but keep economic opportunity cost.
  Post-mail deployable comes from Capital:GetSpendableAfterMail(), which
  reserves against liquid + claimable mail.

  Capacity fields stay separate:
    marketProfitableCrafts, physicalPossibleCrafts, affordableCrafts,
    capabilityAllowedCrafts, executableCrafts, sensibleCrafts.
  sensibleCrafts does not yet apply an output-liquidity model.

  Candidate classes (ranking remains data-driven, not a hard Alchemy > Enchanting order):
  zero-cash owned transforms, high-EV Alchemy, Enchanting destruction (v0.2.0),
  Enchanting material conversions, scroll manufacturing, other AH arbitrage,
  then profession-independent farms when capital is waiting.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.ActionPlanner = OnyxiaGold.ActionPlanner or {}

local Planner = OnyxiaGold.ActionPlanner
Planner.actions = {}
Planner.locked = {}
Planner.session = nil

local function inputSpec(opp)
  local itemID = opp.inputItemIDs and opp.inputItemIDs[1]
  local count = tonumber(opp.inputCount) or 1
  return itemID, count
end

local function meetsThreshold(profit)
  local minAbs
  if OnyxiaGoldDB and OnyxiaGoldDB.settings then
    minAbs = tonumber(OnyxiaGoldDB.settings.minimumAbsoluteProfit)
  end
  if not minAbs then
    minAbs = tonumber(OnyxiaGold.Config.MinimumAbsoluteProfit)
  end
  if minAbs and profit < minAbs then
    return false
  end
  return true
end

-- cash, economicInput, ownedValue, complete
local function craftCost(opp, crafts, owned)
  local itemID, inCount = inputSpec(opp)
  crafts = tonumber(crafts) or 0
  if crafts <= 0 then
    return 0, 0, 0, true
  end
  if not itemID then
    return nil, nil, nil, false
  end
  local needed = crafts * inCount
  local fromOwned = owned
  if fromOwned > needed then
    fromOwned = needed
  end
  local toBuy = needed - fromOwned
  local cash = 0
  if toBuy > 0 then
    cash = OnyxiaGold.Prices:GetAcquisitionCost(itemID, toBuy)
    if not cash then
      return nil, nil, nil, false
    end
  end
  local unit = OnyxiaGold.Prices:GetLiquidationPrice(itemID) or 0
  local ownedValue = fromOwned * unit
  return cash, ownedValue + cash, ownedValue, true
end

local function maxCraftsForCash(opp, owned, deployable, capMax)
  local lo = 0
  local hi = capMax
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    local cash, _, _, complete = craftCost(opp, mid, owned)
    if complete and cash and cash <= deployable then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return lo
end

function Planner:Personalize(opp, deployable, afterMailDeployable)
  deployable = tonumber(deployable) or 0
  -- 0 means the caller is ignoring mail (cash-allocation loop).
  -- Otherwise this is Capital:GetSpendableAfterMail(), already reserve-adjusted,
  -- minus gold this session has already assigned.
  afterMailDeployable = tonumber(afterMailDeployable) or 0
  local itemID, inCount = inputSpec(opp)
  local owned = 0
  if itemID and OnyxiaGold.Inventory then
    owned = OnyxiaGold.Inventory:GetImmediatelyAvailableCount(itemID)
  end
  local cap = { executable = true }
  if OnyxiaGold.Capabilities and OnyxiaGold.Capabilities.CanExecute then
    cap = OnyxiaGold.Capabilities:CanExecute(opp.requirements)
  end

  local marketProfitable = tonumber(opp.marketProfitableCrafts)
  if marketProfitable == nil then
    marketProfitable = tonumber(opp.maxProfitableCrafts) or 0
  end
  local buyoutQty = 0
  if itemID and OnyxiaGold.Prices and OnyxiaGold.Prices.GetBuyoutQuantity then
    buyoutQty = OnyxiaGold.Prices:GetBuyoutQuantity(itemID) or 0
  end
  local physical = 0
  if inCount > 0 then
    physical = math.floor(((owned or 0) + buyoutQty) / inCount)
  end

  -- Capability is not the same number as physical stock.
  -- No cooldown cap: the character can perform every physically possible craft.
  -- Cooldown: at most one. Missing profession/recipe/skill: zero.
  local capabilityAllowed = 0
  if cap.executable then
    capabilityAllowed = physical
    if opp.requirements and opp.requirements.cooldown and capabilityAllowed > 1 then
      capabilityAllowed = 1
    end
  end

  local affordableNow = 0
  local affordableAfterMail = 0
  if physical > 0 then
    affordableNow = maxCraftsForCash(opp, owned, deployable, physical)
    affordableAfterMail = maxCraftsForCash(opp, owned, afterMailDeployable, physical)
  end

  local person = {
    opp = opp,
    state = "ACTIONABLE_NOW",
    cap = cap,
    ownedInputs = owned,
    inputCount = inCount,
    marketProfitableCrafts = marketProfitable,
    physicalPossibleCrafts = physical,
    affordableCrafts = affordableNow,
    capabilityAllowedCrafts = capabilityAllowed,
    executableCrafts = 0,
    -- Output liquidity is not modelled yet, so sensible does not shrink executable.
    sensibleCrafts = 0,
    cashRequiredNow = 0,
    economicInputValue = 0,
    ownedInputValue = 0,
    missingInputCost = 0,
    economicProfit = 0,
    reason = cap.reason,
  }

  local function commit(n)
    local cash, economic, ownedValue, complete = craftCost(opp, n, owned)
    if not complete or not cash then
      return nil
    end
    local netPer = tonumber(opp.netRevenue) or 0
    return n * netPer - economic, cash, economic, ownedValue
  end

  local function accept(n)
    local profit, cash, economic, ownedValue = commit(n)
    if not profit then
      return false
    end
    person.executableCrafts = n
    person.sensibleCrafts = n
    person.cashRequiredNow = cash
    person.economicInputValue = economic
    person.ownedInputValue = ownedValue
    person.missingInputCost = cash
    person.economicProfit = profit
    person.roi = (cash > 0) and (profit / cash) or (ownedValue > 0 and (profit / ownedValue) or 0)
    return true
  end

  if opp.oldestDataAge and opp.oldestDataAge > (OnyxiaGold.Config.FullScanStaleSeconds or 3600) then
    person.state = "STALE_DATA"
    person.reason = "Market data stale"
    return person
  end

  if not cap.executable then
    if cap.unknownRecipe then
      person.state = "UNKNOWN_RECIPE_STATE"
    elseif cap.globalOnly or cap.personalState == "GLOBAL_ONLY" then
      person.state = "GLOBAL_ONLY"
    elseif cap.missingProfession then
      person.state = "LOCKED_PROFESSION"
    elseif cap.missingSkill then
      person.state = "LOCKED_SKILL"
    elseif cap.missingRecipe then
      person.state = "LOCKED_RECIPE"
    else
      person.state = "LOCKED_PROFESSION"
    end
    return person
  end

  if physical <= 0 then
    person.state = "UNPROFITABLE"
    person.reason = "Not profitable"
    return person
  end

  local execCap = affordableNow
  if capabilityAllowed < execCap then
    execCap = capabilityAllowed
  end
  if execCap > 0 then
    local n = execCap
    while n > 0 do
      local profit = commit(n)
      if profit and profit > 0 and meetsThreshold(profit) then
        accept(n)
        person.state = "ACTIONABLE_NOW"
        return person
      end
      n = n - 1
    end
    person.state = "UNPROFITABLE"
    person.reason = "Economic profit <= 0 after opportunity cost"
    person.executableCrafts = 0
    person.sensibleCrafts = 0
    return person
  end

  local afterCap = affordableAfterMail
  if capabilityAllowed < afterCap then
    afterCap = capabilityAllowed
  end
  if afterCap > 0 then
    local n = afterCap
    while n > 0 do
      local profit = commit(n)
      if profit and profit > 0 and meetsThreshold(profit) then
        person.state = "ACTIONABLE_AFTER_MAIL"
        person.reason = "Collect mail first"
        person.executableCrafts = 0
        person.sensibleCrafts = 0
        return person
      end
      n = n - 1
    end
  end

  person.state = "WAITING_FOR_FUNDS"
  person.reason = "Insufficient liquid gold"
  local cash, _, _, complete = craftCost(opp, 1, owned)
  if complete then
    person.cashRequiredNow = cash or 0
    person.missingInputCost = person.cashRequiredNow
  end
  return person
end

local function scoreOf(person)
  local profit = person.economicProfit or 0
  local conf = (person.opp and person.opp.confidence) or 1
  local cash = person.cashRequiredNow or 0
  local score = profit * conf
  if cash <= 0 then
    score = score * 2
  end
  local liquid = OnyxiaGold.Capital and OnyxiaGold.Capital:GetLiquid() or 0
  if liquid > 0 and liquid < 500000 and cash > 0 then
    score = score / (1 + cash / liquid)
  end
  return score
end

local function actionFromPerson(person, index)
  local opp = person.opp
  local crafts = person.sensibleCrafts or person.executableCrafts or 0
  local cash = person.cashRequiredNow or 0
  local ownedCrafts = 0
  if person.inputCount and person.inputCount > 0 then
    ownedCrafts = math.floor((person.ownedInputs or 0) / person.inputCount)
  end
  if ownedCrafts > crafts then
    ownedCrafts = crafts
  end

  local kind = "CRAFT"
  local name = opp.name or "Craft"
  local detail
  if cash <= 0 then
    kind = "CRAFT_OWNED"
    detail = string.format("Use owned materials · %d crafts", crafts)
    name = "Use owned: " .. tostring(opp.name)
  else
    local itemID = opp.inputItemIDs and opp.inputItemIDs[1]
    local needBuy = crafts * (person.inputCount or 1) - (person.ownedInputs or 0)
    if needBuy < 0 then
      needBuy = 0
    end
    local itemName = itemID and (OnyxiaGold.Data.GetItemName and OnyxiaGold.Data.GetItemName(itemID)) or "materials"
    kind = "BUY_AND_CRAFT"
    name = "Buy " .. tostring(needBuy) .. " " .. tostring(itemName)
    detail = string.format("Then %d %s", crafts, tostring(opp.name))
  end

  return {
    index = index,
    kind = kind,
    name = name,
    typeLabel = opp.typeLabel or opp.type,
    expectedProfit = person.economicProfit,
    cashRequiredNow = cash,
    crafts = crafts,
    ownedCrafts = ownedCrafts,
    state = person.state,
    detail = detail,
    confidence = opp.confidence,
    roi = person.roi,
    sourceOpp = opp,
    person = person,
  }
end

function Planner:Refresh()
  self.actions = {}
  self.locked = {}
  local opps = {}
  if OnyxiaGold.OpportunityEngine and OnyxiaGold.OpportunityEngine.GetResults then
    opps = OnyxiaGold.OpportunityEngine:GetResults() or {}
  end
  local deployable = OnyxiaGold.Capital and OnyxiaGold.Capital:GetSpendableNow() or 0
  local afterMailSpendable = OnyxiaGold.Capital and OnyxiaGold.Capital:GetSpendableAfterMail() or deployable
  local claimable = OnyxiaGold.Capital and OnyxiaGold.Capital:GetClaimableMail() or 0
  local liquid = OnyxiaGold.Capital and OnyxiaGold.Capital:GetLiquid() or 0
  local reserve = OnyxiaGold.Capital and OnyxiaGold.Capital:GetWorkingCapital() or 0

  -- Gold already assigned in this plan still has to come out of the
  -- post-collection budget. Do not add claimable on top of remaining deployable.
  local function afterMailBudget(unspent)
    local spent = deployable - (tonumber(unspent) or 0)
    if spent < 0 then
      spent = 0
    end
    local left = afterMailSpendable - spent
    if left < 0 then
      left = 0
    end
    return left
  end

  local remaining = deployable
  local used = {}
  local people = {}
  for i = 1, table.getn(opps) do
    people[i] = self:Personalize(opps[i], deployable, afterMailBudget(deployable))
  end

  local guard = 0
  while guard < 20 do
    guard = guard + 1
    local bestI
    local bestScore
    for i = 1, table.getn(people) do
      if not used[i] then
        local person = self:Personalize(opps[i], remaining, 0)
        people[i] = person
        if person.state == "ACTIONABLE_NOW" and (person.sensibleCrafts or 0) > 0 then
          if (person.cashRequiredNow or 0) <= remaining then
            local s = scoreOf(person)
            if not bestScore or s > bestScore then
              bestScore = s
              bestI = i
            elseif s == bestScore then
              local bestP = people[bestI]
              local roiA = person.roi or 0
              local roiB = bestP.roi or 0
              if roiA > roiB or (roiA == roiB and (person.cashRequiredNow or 0) < (bestP.cashRequiredNow or 0)) then
                bestI = i
              end
            end
          end
        end
      end
    end
    if not bestI then
      break
    end
    used[bestI] = true
    local person = people[bestI]
    remaining = remaining - (person.cashRequiredNow or 0)
    if remaining < 0 then
      remaining = 0
    end
    table.insert(self.actions, actionFromPerson(person, table.getn(self.actions) + 1))
  end

  local unlockedByMail = 0
  for i = 1, table.getn(people) do
    if not used[i] then
      local person = self:Personalize(opps[i], remaining, afterMailBudget(remaining))
      people[i] = person
      if person.state == "ACTIONABLE_AFTER_MAIL" then
        unlockedByMail = unlockedByMail + 1
      elseif person.state == "WAITING_FOR_FUNDS"
        or person.state == "LOCKED_PROFESSION"
        or person.state == "GLOBAL_ONLY"
        or person.state == "LOCKED_SKILL"
        or person.state == "LOCKED_RECIPE"
        or person.state == "UNKNOWN_RECIPE_STATE"
        or person.state == "STALE_DATA"
        or person.state == "UNPROFITABLE" then
        table.insert(self.locked, person)
      end
    end
  end

  local mailPartial = OnyxiaGold.Mail and OnyxiaGold.Mail.IsSnapshotComplete
    and OnyxiaGold.Mail:IsSnapshotComplete() == false
  local function formatReady(amount)
    local text = OnyxiaGold.FormatGoldShort(amount)
    if mailPartial then
      return "~" .. text .. "+"
    end
    return text
  end

  if claimable > 0 and unlockedByMail > 0 then
    table.insert(self.actions, {
      index = table.getn(self.actions) + 1,
      kind = "COLLECT_MAIL",
      name = "Collect Auction House mail",
      typeLabel = "Mail",
      expectedProfit = 0,
      cashRequiredNow = 0,
      crafts = 0,
      state = "ACTIONABLE_NOW",
      detail = string.format(
        "Ready %s · then %s liquid · unlocks %d",
        formatReady(claimable),
        formatReady(liquid + claimable),
        unlockedByMail
      ),
      claimable = claimable,
      mailPartial = mailPartial and true or false,
      unlocks = unlockedByMail,
    })
  elseif claimable > 0 and table.getn(self.actions) == 0 then
    table.insert(self.actions, {
      index = 1,
      kind = "COLLECT_MAIL",
      name = "Collect Auction House mail",
      typeLabel = "Mail",
      expectedProfit = 0,
      cashRequiredNow = 0,
      crafts = 0,
      state = "ACTIONABLE_NOW",
      detail = "Ready " .. formatReady(claimable),
      claimable = claimable,
      mailPartial = mailPartial and true or false,
    })
  end

  self.session = {
    liquid = liquid,
    reserve = reserve,
    deployable = deployable,
    deployableAfterMail = afterMailSpendable,
    remaining = remaining,
    claimable = claimable,
    pending = OnyxiaGold.Capital and OnyxiaGold.Capital:GetPendingAuctionGold() or 0,
    unknownRecipes = 0,
  }
  for i = 1, table.getn(self.locked) do
    if self.locked[i].state == "UNKNOWN_RECIPE_STATE" then
      self.session.unknownRecipes = self.session.unknownRecipes + 1
    end
  end

  OnyxiaGold.Log:Debug("Planner", string.format(
    "actions=%d locked=%d remaining=%d",
    table.getn(self.actions), table.getn(self.locked), remaining
  ))
  return self.actions
end

function Planner:GetActions()
  return self.actions or {}
end

function Planner:GetLocked()
  return self.locked or {}
end

function Planner:GetSession()
  return self.session
end

function Planner:UnknownRecipeHint()
  local function hintProfession(name)
    if OnyxiaGold.Capabilities:HasProfession(name) and not OnyxiaGold.Capabilities:HasRecipeScan(name) then
      return "Open " .. name .. " once so OnyxiaGold can scan known recipes."
    end
    return nil
  end
  if not OnyxiaGold.Capabilities then
    return nil
  end
  local session = self.session
  if session and (session.unknownRecipes or 0) > 0 then
    return hintProfession("Alchemy")
      or hintProfession("Enchanting")
      or hintProfession("Jewelcrafting")
      or "Open the relevant profession so OnyxiaGold can scan known recipes."
  end
  return hintProfession("Alchemy")
    or hintProfession("Enchanting")
    or hintProfession("Jewelcrafting")
end
