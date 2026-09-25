--[[
  OnyxiaGold.ActionPlanner
  Turns market opportunities into a personal, capital-constrained action list.

  OpportunityEngine asks whether a transformation is economically good.
  ActionPlanner asks whether THIS character can and should do it now.

  Greedy on current deployable gold only. Expected sales are never cash.
  Owned bag materials reduce cashRequiredNow but keep economic opportunity cost.

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

local function physicalCap(opp, owned)
  local itemID, inCount = inputSpec(opp)
  local fromMarket = tonumber(opp.maxProfitableCrafts) or 0
  local buyoutQty = 0
  if itemID and OnyxiaGold.Prices and OnyxiaGold.Prices.GetBuyoutQuantity then
    buyoutQty = OnyxiaGold.Prices:GetBuyoutQuantity(itemID) or 0
  end
  local fromStock = 0
  if inCount > 0 then
    fromStock = math.floor(((owned or 0) + buyoutQty) / inCount)
  end
  if fromStock > fromMarket then
    return fromStock
  end
  return fromMarket
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

function Planner:Personalize(opp, deployable, claimable)
  deployable = tonumber(deployable) or 0
  claimable = tonumber(claimable) or 0
  local itemID, inCount = inputSpec(opp)
  local owned = 0
  if itemID and OnyxiaGold.Inventory then
    owned = OnyxiaGold.Inventory:GetImmediatelyAvailableCount(itemID)
  end
  local cap = { executable = true }
  if OnyxiaGold.Capabilities and OnyxiaGold.Capabilities.CanExecute then
    cap = OnyxiaGold.Capabilities:CanExecute(opp.requirements)
  end
  local maxProfitable = physicalCap(opp, owned)
  if opp.requirements and opp.requirements.cooldown and maxProfitable > 1 then
    maxProfitable = 1
  end
  local capMax = maxProfitable

  local person = {
    opp = opp,
    state = "ACTIONABLE_NOW",
    cap = cap,
    ownedInputs = owned,
    inputCount = inCount,
    maxProfitableCrafts = maxProfitable,
    maxAffordableCrafts = 0,
    maxExecutableCrafts = 0,
    cashRequiredNow = 0,
    economicInputValue = 0,
    ownedInputValue = 0,
    missingInputCost = 0,
    economicProfit = 0,
    reason = cap.reason,
  }

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

  if maxProfitable <= 0 then
    person.state = "UNPROFITABLE"
    person.reason = "Not profitable"
    return person
  end

  local affordableNow = maxCraftsForCash(opp, owned, deployable, capMax)
  local affordableAfterMail = maxCraftsForCash(opp, owned, deployable + claimable, capMax)
  person.maxAffordableCrafts = affordableNow

  local function applyN(n)
    local cash, economic, ownedValue, complete = craftCost(opp, n, owned)
    if not complete or not cash then
      return false
    end
    local netPer = tonumber(opp.netRevenue) or 0
    local profit = n * netPer - economic
    person.maxExecutableCrafts = n
    person.cashRequiredNow = cash
    person.economicInputValue = economic
    person.ownedInputValue = ownedValue
    person.missingInputCost = cash
    person.economicProfit = profit
    person.roi = (cash > 0) and (profit / cash) or (ownedValue > 0 and (profit / ownedValue) or 0)
    return profit
  end

  if affordableNow > 0 then
    local n = affordableNow
    while n > 0 do
      local profit = applyN(n)
      if profit and profit > 0 and meetsThreshold(profit) then
        person.state = "ACTIONABLE_NOW"
        return person
      end
      n = n - 1
    end
    person.state = "UNPROFITABLE"
    person.reason = "Economic profit <= 0 after opportunity cost"
    person.maxExecutableCrafts = 0
    return person
  end

  if affordableAfterMail > 0 then
    local n = affordableAfterMail
    while n > 0 do
      local profit = applyN(n)
      person.maxAffordableCrafts = 0
      if profit and profit > 0 and meetsThreshold(profit) then
        person.state = "ACTIONABLE_AFTER_MAIL"
        person.reason = "Collect mail first"
        return person
      end
      n = n - 1
    end
  end

  person.state = "WAITING_FOR_FUNDS"
  person.reason = "Insufficient liquid gold"
  local _, _, _, complete = craftCost(opp, 1, owned)
  if complete then
    local cash = craftCost(opp, 1, owned)
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
  local crafts = person.maxExecutableCrafts or 0
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
  local claimable = OnyxiaGold.Capital and OnyxiaGold.Capital:GetClaimableMail() or 0
  local liquid = OnyxiaGold.Capital and OnyxiaGold.Capital:GetLiquid() or 0
  local reserve = OnyxiaGold.Capital and OnyxiaGold.Capital:GetWorkingCapital() or 0

  local remaining = deployable
  local used = {}
  local people = {}
  for i = 1, table.getn(opps) do
    people[i] = self:Personalize(opps[i], deployable, claimable)
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
        if person.state == "ACTIONABLE_NOW" and (person.maxExecutableCrafts or 0) > 0 then
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

  local afterMail = 0
  for i = 1, table.getn(people) do
    if not used[i] then
      local person = self:Personalize(opps[i], remaining, claimable)
      people[i] = person
      if person.state == "ACTIONABLE_AFTER_MAIL" then
        afterMail = afterMail + 1
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

  if claimable > 0 and afterMail > 0 then
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
        "Ready %s · then ~%s liquid · unlocks %d",
        OnyxiaGold.FormatGoldShort(claimable),
        OnyxiaGold.FormatGoldShort(liquid + claimable),
        afterMail
      ),
      claimable = claimable,
      unlocks = afterMail,
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
      detail = "Ready " .. OnyxiaGold.FormatGoldShort(claimable),
      claimable = claimable,
    })
  end

  self.session = {
    liquid = liquid,
    reserve = reserve,
    deployable = deployable,
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
