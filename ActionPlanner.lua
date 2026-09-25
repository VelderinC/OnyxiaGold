--[[
  OnyxiaGold.ActionPlanner
  Turns market opportunities into a personal, capital-constrained action list.

  OpportunityEngine asks whether a transformation is economically good.
  ActionPlanner asks whether THIS character can and should do it now.

  Greedy on current deployable gold only. Expected sales are never cash.
  Owned bag materials reduce cashRequiredNow but keep economic opportunity cost.
  Post-mail deployable comes from Capital:GetSpendableAfterMail(), which
  reserves against liquid + claimable mail.

  Each Refresh rebuilds SessionState. A selected action reserves its cash,
  the bag units it consumes, and the cloned auction depth it would buy.
  The saved market snapshot is not modified.

  Capacity fields stay separate:
    marketProfitableCrafts, physicalPossibleCrafts, affordableCrafts,
    capabilityAllowedCrafts, executableCrafts, sensibleCrafts.
  sensibleCrafts is a crude output cap: do not plan more output units than
  the visible buyout book still has room for after bags, bank, mail items,
  and his own listings. It is not a liquidity model and it is not a sale rate.
  Held stock is a count, not an asking price. A transmute needs its tool on
  him. A buy stops at free bag slots.

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

local function recipeInputs(opp)
  if type(opp.inputs) == "table" and table.getn(opp.inputs) > 0 then
    return opp.inputs
  end
  local itemID, count = inputSpec(opp)
  if not itemID then
    return {}
  end
  if count < 1 then
    count = 1
  end
  return { { itemID = itemID, count = count } }
end

local function bagCount(itemID)
  local session = OnyxiaGold.SessionState
  if session and session.IsActive and session:IsActive() then
    return session:GetBagCount(itemID) or 0
  end
  if OnyxiaGold.Inventory and OnyxiaGold.Inventory.GetImmediatelyAvailableCount then
    return OnyxiaGold.Inventory:GetImmediatelyAvailableCount(itemID) or 0
  end
  return 0
end

local function coveredBuyout(itemID)
  local session = OnyxiaGold.SessionState
  if session and session.IsActive and session:IsActive() then
    return session:CoveredQuantity(itemID) or 0
  end
  if OnyxiaGold.Prices and OnyxiaGold.Prices.GetBuyoutQuantity then
    return OnyxiaGold.Prices:GetBuyoutQuantity(itemID) or 0
  end
  return 0
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

-- Crude stop. Not a sale rate and not a claim about how fast goods sell.
local OUTPUT_CAP_NOTE = "Output cap, not a liquidity model. Planned output is cut to the visible buyout book."

local function outputPerCraft(opp)
  local count = tonumber(opp.outputCount) or 1
  if count < 1 then
    count = 1
  end
  local expected = tonumber(opp.expectedOutput) or 1
  if expected <= 0 then
    expected = 1
  end
  return count * expected
end

local LATER_STONE_KEYS = {
  "ALCHEMISTS_STONE",
  "ASSASSINS_ALCHEMIST_STONE",
  "GUARDIANS_ALCHEMIST_STONE",
  "REDEEMERS_ALCHEMIST_STONE",
  "MIGHTY_ALCHEMISTS_STONE",
  "INDESTRUCTIBLE_ALCHEMISTS_STONE",
}

local function itemDefID(key)
  local items = OnyxiaGold.Data and OnyxiaGold.Data.Items
  local def = items and items[key]
  return def and def.id or nil
end

local function isLaterStone(itemID)
  itemID = tonumber(itemID)
  if not itemID then
    return false
  end
  for i = 1, table.getn(LATER_STONE_KEYS) do
    if itemDefID(LATER_STONE_KEYS[i]) == itemID then
      return true
    end
  end
  return false
end

-- listed, held, room left after stock and after output already planned.
local function outputSnapshot(opp)
  local outID = opp.outputItemIDs and opp.outputItemIDs[1]
  if not outID then
    return nil
  end
  local listed = tonumber(opp.outputMarketQuantity) or 0
  local held = 0
  local partial = false
  local stale = false
  if OnyxiaGold.Stock and OnyxiaGold.Stock.Describe then
    local stock = OnyxiaGold.Stock:Describe(outID)
    held = tonumber(stock.total) or 0
    partial = stock.partial and true or false
    stale = stock.stale and true or false
  end
  local room = listed - held
  if room < 0 then
    room = 0
  end
  local session = OnyxiaGold.SessionState
  if session and session.IsActive and session:IsActive() and session.RemainingOutput then
    room = session:RemainingOutput(outID, room)
  end
  if room < 0 then
    room = 0
  end
  return {
    listed = listed,
    held = held,
    room = room,
    partial = partial,
    stale = stale,
    overHeld = held > 0 and held >= listed,
  }
end

local function paintStock(person, opp, snap, crafts)
  if not snap then
    return
  end
  person.outputListed = snap.listed
  person.outputHeld = snap.held
  person.outputRoom = snap.room
  person.outputHeldPartial = snap.partial
  person.outputHeldStale = snap.stale
  person.outputStillMake = (tonumber(crafts) or 0) * outputPerCraft(opp)
  local flags = {}
  if snap.partial then
    table.insert(flags, "partial")
  end
  if snap.stale then
    table.insert(flags, "stale")
  end
  local flag = ""
  if table.getn(flags) > 0 then
    flag = " (" .. table.concat(flags, ", ") .. ")"
  end
  person.outputStockLine = string.format(
    "Listed %d · already yours %d%s · still make %d",
    snap.listed, snap.held, flag, person.outputStillMake
  )
  if snap.held > 0 then
    person.outputHeldNote = "Held stock is a count, not an asking price."
  end
end

-- Returns craft count, whether the book cut it, whether he should post or hold, and the snapshot.
local function cappedCrafts(opp, executable)
  executable = tonumber(executable) or 0
  local snap = outputSnapshot(opp)
  if not snap or executable <= 0 then
    return executable, false, false, snap
  end
  local per = outputPerCraft(opp)
  if snap.overHeld then
    return 0, true, true, snap
  end
  if executable * per <= snap.room then
    return executable, false, false, snap
  end
  local allowed = math.floor(snap.room / per)
  if allowed < 0 then
    allowed = 0
  end
  if allowed > executable then
    allowed = executable
  end
  return allowed, true, false, snap
end

-- lines, cash, economicInput, ownedValue, complete
-- Every input is costed. The stone tool is not an input and is not bought.
local function planInputs(opp, crafts)
  crafts = tonumber(crafts) or 0
  local inputs = recipeInputs(opp)
  if crafts <= 0 then
    return {}, 0, 0, 0, true
  end
  if table.getn(inputs) < 1 then
    return nil
  end
  local lines = {}
  local cash = 0
  local ownedValue = 0
  for i = 1, table.getn(inputs) do
    local row = inputs[i]
    local itemID = tonumber(row.itemID)
    local count = tonumber(row.count) or 1
    if count < 1 then
      count = 1
    end
    if not itemID then
      return nil
    end
    local needed = crafts * count
    local owned = bagCount(itemID)
    if owned > needed then
      owned = needed
    end
    if owned < 0 then
      owned = 0
    end
    local toBuy = needed - owned
    if toBuy > 0 then
      local session = OnyxiaGold.SessionState
      local part
      if session and session.IsActive and session:IsActive() then
        part = session:AcquisitionCost(itemID, toBuy)
      else
        part = OnyxiaGold.Prices:GetAcquisitionCost(itemID, toBuy)
      end
      if not part then
        return nil
      end
      cash = cash + part
    end
    local unit = OnyxiaGold.Prices:GetLiquidationPrice(itemID) or 0
    ownedValue = ownedValue + owned * unit
    table.insert(lines, {
      itemID = itemID,
      count = count,
      ownedUnits = owned,
      buyUnits = toBuy,
    })
  end
  return lines, cash, ownedValue + cash, ownedValue, true
end

-- cash, economicInput, ownedValue, complete
local function craftCost(opp, crafts, owned)
  local lines, cash, economic, ownedValue, complete = planInputs(opp, crafts)
  if not lines then
    return nil, nil, nil, false
  end
  return cash, economic, ownedValue, complete
end

-- slots needed, free slots left. Nil slots means the limit is unknown.
local function bagSlotsFor(lines)
  local inv = OnyxiaGold.Inventory
  if not inv or not inv.GetFreeGeneralSlots then
    return nil, nil
  end
  local free = inv:GetFreeGeneralSlots()
  if free == nil then
    return nil, nil
  end
  local session = OnyxiaGold.SessionState
  if session and session.IsActive and session:IsActive() and session.BagSlotsUsed then
    free = free - (session:BagSlotsUsed() or 0)
    if free < 0 then
      free = 0
    end
  end
  local slots = 0
  for i = 1, table.getn(lines or {}) do
    local line = lines[i]
    local stack = inv.GetStackSize and inv:GetStackSize(line.itemID) or nil
    if not stack or stack < 1 then
      return nil, free
    end
    local partial = inv.GetPartialRoom and inv:GetPartialRoom(line.itemID) or 0
    local spill = (line.buyUnits or 0) - partial
    if spill < 0 then
      spill = 0
    end
    slots = slots + math.floor((spill + stack - 1) / stack)
  end
  return slots, free
end

-- true/false if priced, nil if the quote is incomplete.
local function bagFit(opp, n)
  local lines = planInputs(opp, n)
  if not lines then
    return nil, 0
  end
  local slots, free = bagSlotsFor(lines)
  if slots == nil then
    return true, 0
  end
  return slots <= free, slots
end

local function toolDecision(opp)
  local req = opp.requirements
  local toolID = req and tonumber(req.toolItemID)
  if not toolID then
    return nil
  end
  local name = req.tool or "tool"
  if OnyxiaGold.Data and OnyxiaGold.Data.GetItemName then
    name = OnyxiaGold.Data.GetItemName(toolID) or name
  end
  if isLaterStone(toolID) or toolID == itemDefID("MERCURIAL_STONE") then
    return "TOOL_NOT_CONFIRMED", "Tool not confirmed", name
  end
  local inv = OnyxiaGold.Inventory
  local onPerson = inv and inv.GetOnPersonCount and (inv:GetOnPersonCount(toolID) or 0) > 0
  local inBank = inv and inv.GetBankCount and (inv:GetBankCount(toolID) or 0) > 0
  if toolID == itemDefID("PHILOSOPHERS_STONE") and not onPerson
    and inv and inv.UnconfirmedStoneOnPerson and inv:UnconfirmedStoneOnPerson() then
    return "TOOL_NOT_CONFIRMED", "Tool not confirmed", name
  end
  if onPerson then
    return nil
  end
  if inBank then
    return "WITHDRAW_TOOL", "Withdraw " .. name, name
  end
  return "TOOL_MISSING", name .. " is not in bags or equipped", name
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
  local inputs = recipeInputs(opp)
  local itemID = inputs[1] and tonumber(inputs[1].itemID) or nil
  local inCount = inputs[1] and (tonumber(inputs[1].count) or 1) or 1
  if inCount < 1 then
    inCount = 1
  end
  local session = OnyxiaGold.SessionState
  local sessionOn = session and session.IsActive and session:IsActive()
  local owned = itemID and bagCount(itemID) or 0
  local cap = { executable = true }
  if OnyxiaGold.Capabilities and OnyxiaGold.Capabilities.CanExecute then
    cap = OnyxiaGold.Capabilities:CanExecute(opp.requirements)
  end

  local marketProfitable = tonumber(opp.marketProfitableCrafts)
  if marketProfitable == nil then
    marketProfitable = tonumber(opp.maxProfitableCrafts) or 0
  end
  -- Session planning buys from the remaining clone, not the full live book.
  -- Physical crafts are limited by the scarcest input.
  local physical = nil
  for i = 1, table.getn(inputs) do
    local row = inputs[i]
    local id = tonumber(row.itemID)
    local count = tonumber(row.count) or 1
    if count < 1 then
      count = 1
    end
    local have = id and ((bagCount(id) or 0) + coveredBuyout(id)) or 0
    local craftsHere = math.floor(have / count)
    if not physical or craftsHere < physical then
      physical = craftsHere
    end
  end
  if not physical then
    physical = 0
  end

  -- Capability is not the same number as physical stock.
  -- No cooldown cap: the character can perform every physically possible craft.
  -- Cooldown: at most one. Missing profession/recipe/skill: zero.
  local cooldown = opp.requirements and opp.requirements.cooldown
  local cooldownTaken = sessionOn and cooldown and session:CooldownUsed(cooldown)
  local capabilityAllowed = 0
  if cap.executable and not cooldownTaken then
    capabilityAllowed = physical
    if cooldown and capabilityAllowed > 1 then
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
    outputCapped = false,
    outputCapNote = nil,
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
    local lines = planInputs(opp, n)
    person.executableCrafts = n
    person.sensibleCrafts = n
    person.inputLines = lines
    person.cashRequiredNow = cash
    person.economicInputValue = economic
    person.ownedInputValue = ownedValue
    person.missingInputCost = cash
    person.economicProfit = profit
    person.roi = (cash > 0) and (profit / cash) or (ownedValue > 0 and (profit / ownedValue) or 0)
    return true
  end

  if opp.actionable == false then
    person.state = "NOT_ACTIONABLE"
    person.reason = "Not actionable until the recipe and the tool are represented"
    person.capabilityAllowedCrafts = 0
    person.executableCrafts = 0
    person.sensibleCrafts = 0
    return person
  end

  if opp.oldestDataAge and opp.oldestDataAge > (OnyxiaGold.Config.FullScanStaleSeconds or 3600) then
    person.state = "STALE_DATA"
    person.reason = "Market data stale"
    return person
  end

  if cooldownTaken then
    person.state = "COOLDOWN_RESERVED"
    person.reason = "Cooldown already reserved in this plan"
    person.capabilityAllowedCrafts = 0
    return person
  end

  if not cap.executable then
    if cap.skillUnset then
      person.state = "NOT_ACTIONABLE"
      person.reason = cap.reason or "Skill requirement is unset"
      person.capabilityAllowedCrafts = 0
      person.executableCrafts = 0
      person.sensibleCrafts = 0
    elseif cap.unknownRecipe then
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

  local toolState, toolReason = toolDecision(opp)
  if toolState then
    person.state = toolState
    person.reason = toolReason
    person.capabilityAllowedCrafts = 0
    person.executableCrafts = 0
    person.sensibleCrafts = 0
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
    local chosen
    local n = execCap
    while n > 0 do
      local profit = commit(n)
      if profit and profit > 0 and meetsThreshold(profit) then
        chosen = n
        break
      end
      n = n - 1
    end
    if chosen then
      local sensible, capped, hold, snap = cappedCrafts(opp, chosen)
      if hold then
        person.executableCrafts = chosen
        person.sensibleCrafts = 0
        person.outputCapped = true
        person.outputCapNote = OUTPUT_CAP_NOTE
        person.state = "POST_OR_HOLD"
        person.reason = "Post or hold"
        paintStock(person, opp, snap, 0)
        return person
      end
      local fitted = sensible
      local bagLimited = false
      local priced = true
      if sensible >= 1 then
        local fit, _ = bagFit(opp, sensible)
        if fit == nil then
          priced = false
        elseif not fit then
          bagLimited = true
          local lo = 0
          local hi = sensible - 1
          while lo < hi do
            local mid = math.floor((lo + hi + 1) / 2)
            local ok = bagFit(opp, mid)
            if ok then
              lo = mid
            else
              hi = mid - 1
            end
          end
          fitted = lo
        end
      end
      if priced and fitted >= 1 and accept(fitted) then
        person.executableCrafts = chosen
        person.bagLimited = bagLimited
        local _, slots = bagFit(opp, fitted)
        person.bagSlotsUsed = slots or 0
        if capped then
          person.outputCapped = true
          person.outputCapNote = OUTPUT_CAP_NOTE
        end
        paintStock(person, opp, snap, fitted)
        person.state = "ACTIONABLE_NOW"
        return person
      end
      person.executableCrafts = chosen
      person.sensibleCrafts = 0
      paintStock(person, opp, snap, 0)
      if bagLimited and fitted < 1 then
        person.bagLimited = true
        person.state = "BAG_FULL"
        person.reason = "Not enough free bag slots"
      elseif capped then
        person.outputCapped = true
        person.outputCapNote = OUTPUT_CAP_NOTE
        person.state = "OUTPUT_CAPPED"
        person.reason = OUTPUT_CAP_NOTE
      else
        person.state = "UNPROFITABLE"
        person.reason = "Economic profit <= 0 after opportunity cost"
      end
      return person
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
    local bits = {}
    local lines = person.inputLines
    if type(lines) == "table" then
      for i = 1, table.getn(lines) do
        local buy = lines[i].buyUnits or 0
        if buy > 0 then
          local itemName = "materials"
          if lines[i].itemID and OnyxiaGold.Data.GetItemName then
            itemName = OnyxiaGold.Data.GetItemName(lines[i].itemID) or itemName
          end
          table.insert(bits, tostring(buy) .. " " .. itemName)
        end
      end
    end
    if table.getn(bits) == 0 then
      local itemID = opp.inputItemIDs and opp.inputItemIDs[1]
      local needBuy = crafts * (person.inputCount or 1) - (person.ownedInputs or 0)
      if needBuy < 0 then
        needBuy = 0
      end
      local itemName = itemID and (OnyxiaGold.Data.GetItemName and OnyxiaGold.Data.GetItemName(itemID)) or "materials"
      table.insert(bits, tostring(needBuy) .. " " .. tostring(itemName))
    end
    kind = "BUY_AND_CRAFT"
    name = "Buy " .. table.concat(bits, " + ")
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

function Planner:ReserveSelected(person)
  local session = OnyxiaGold.SessionState
  if not session or not session.IsActive or not session:IsActive() then
    return true
  end
  local opp = person.opp or {}
  local crafts = person.sensibleCrafts or person.executableCrafts or 0
  local lines = person.inputLines
  if type(lines) ~= "table" or table.getn(lines) < 1 then
    local itemID = opp.inputItemIDs and opp.inputItemIDs[1]
    local inCount = tonumber(person.inputCount) or 1
    if inCount < 1 then
      inCount = 1
    end
    local needed = crafts * inCount
    local fromOwned = person.ownedInputs or 0
    if fromOwned > needed then
      fromOwned = needed
    end
    if fromOwned < 0 then
      fromOwned = 0
    end
    lines = {
      { itemID = itemID, ownedUnits = fromOwned, buyUnits = needed - fromOwned },
    }
  end
  local first = lines[1] or {}
  local cooldown = opp.requirements and opp.requirements.cooldown
  local outputID = opp.outputItemIDs and opp.outputItemIDs[1]
  local outputUnits = 0
  if outputID then
    outputUnits = crafts * outputPerCraft(opp)
  end
  return session:Reserve({
    itemID = first.itemID,
    cash = person.cashRequiredNow or 0,
    ownedUnits = first.ownedUnits or 0,
    buyUnits = first.buyUnits or 0,
    inputs = lines,
    cooldown = cooldown,
    outputItemID = outputID,
    outputUnits = outputUnits,
    bagSlots = person.bagSlotsUsed or 0,
  })
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

  if OnyxiaGold.SessionState and OnyxiaGold.SessionState.Begin then
    OnyxiaGold.SessionState:Begin(deployable, afterMailSpendable)
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
    if self:ReserveSelected(person) then
      if OnyxiaGold.SessionState and OnyxiaGold.SessionState:IsActive() then
        remaining = OnyxiaGold.SessionState:RemainingCash()
      else
        remaining = remaining - (person.cashRequiredNow or 0)
        if remaining < 0 then
          remaining = 0
        end
      end
      table.insert(self.actions, actionFromPerson(person, table.getn(self.actions) + 1))
    end
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
        or person.state == "UNPROFITABLE"
        or person.state == "COOLDOWN_RESERVED"
        or person.state == "OUTPUT_CAPPED"
        or person.state == "NOT_ACTIONABLE"
        or person.state == "POST_OR_HOLD"
        or person.state == "WITHDRAW_TOOL"
        or person.state == "TOOL_NOT_CONFIRMED"
        or person.state == "TOOL_MISSING"
        or person.state == "BAG_FULL" then
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

  local front = {}
  for i = 1, table.getn(self.locked) do
    local person = self.locked[i]
    local opp = person.opp or {}
    if person.state == "WITHDRAW_TOOL" then
      table.insert(front, {
        kind = "WITHDRAW",
        name = person.reason or "Withdraw tool",
        typeLabel = opp.typeLabel or opp.type,
        expectedProfit = 0,
        cashRequiredNow = 0,
        crafts = 0,
        state = "ACTIONABLE_NOW",
        detail = "Withdraw this before the craft",
        person = person,
        sourceOpp = opp,
      })
      table.insert(front, {
        kind = "CRAFT",
        name = opp.name or "Craft",
        typeLabel = opp.typeLabel or opp.type,
        expectedProfit = 0,
        cashRequiredNow = 0,
        crafts = 0,
        state = "NEEDS_WITHDRAW",
        detail = "Not ready until the tool is in bags or equipped",
        person = person,
        sourceOpp = opp,
      })
    elseif person.state == "POST_OR_HOLD" then
      table.insert(self.actions, {
        kind = "POST_OR_HOLD",
        name = "Post or hold: " .. tostring(opp.name or "output"),
        typeLabel = opp.typeLabel or opp.type,
        expectedProfit = 0,
        cashRequiredNow = 0,
        crafts = 0,
        state = "POST_OR_HOLD",
        detail = "Post or hold",
        person = person,
        sourceOpp = opp,
      })
    end
  end
  for i = table.getn(front), 1, -1 do
    table.insert(self.actions, 1, front[i])
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

  for i = 1, table.getn(self.actions) do
    self.actions[i].index = i
  end

  self.session = {
    liquid = liquid,
    reserve = reserve,
    deployable = deployable,
    deployableAfterMail = afterMailSpendable,
    remaining = remaining,
    reservations = OnyxiaGold.SessionState and OnyxiaGold.SessionState.reserved or nil,
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
