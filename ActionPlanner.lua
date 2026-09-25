--[[
  OnyxiaGold.ActionPlanner
  Turns market opportunities into a personal, capital-constrained action list.

  OpportunityEngine asks whether a transformation is economically good.
  ActionPlanner asks whether THIS character can and should do it now.

  Greedy on current deployable gold only. Expected sales are never cash.
  The visible list is one session. It can hold more than one craft when they
  do not need the same gold, the same bag slots, the same auction lots, or
  the same cooldown. Each craft is buy the whole lots, then craft, then post.
  The top line is the single next step. When that step cannot be done from
  here, the line names the errand first and the buy, craft, or post stays
  underneath. Expected session profit is the sum.
  Owned bag materials reduce cashRequiredNow but keep economic opportunity cost.
  Bank stock and purchase mail are not bag stock. They do not spend bag gold.
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

  A profitable 20-hour transmute is one cast and sorts above repeatable crafts.
  The row names the winner and the gold given up by skipping the runner-up.
  If none of the recipes this skill can perform beat selling their materials,
  the row says skip. Titanium, Earthsiege, and Skyflare are not on that cooldown.
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

local function bankCount(itemID)
  local session = OnyxiaGold.SessionState
  if session and session.IsActive and session:IsActive() and session.GetBankCount then
    return session:GetBankCount(itemID) or 0
  end
  if OnyxiaGold.Inventory and OnyxiaGold.Inventory.GetBankCount then
    return OnyxiaGold.Inventory:GetBankCount(itemID) or 0
  end
  return 0
end

local function mailCount(itemID)
  local session = OnyxiaGold.SessionState
  if session and session.IsActive and session:IsActive() and session.GetMailCount then
    return session:GetMailCount(itemID) or 0
  end
  if OnyxiaGold.Mail and OnyxiaGold.Mail.GetPurchaseCount then
    return OnyxiaGold.Mail:GetPurchaseCount(itemID) or 0
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
    return {}, 0, 0, 0, true, 0
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
    local remain = needed - owned
    local banked = bankCount(itemID)
    if banked > remain then
      banked = remain
    end
    if banked < 0 then
      banked = 0
    end
    remain = remain - banked
    local mailed = mailCount(itemID)
    if mailed > remain then
      mailed = remain
    end
    if mailed < 0 then
      mailed = 0
    end
    local toBuy = remain - mailed
    local buyCost = 0
    local economicBuy = 0
    local leftover = 0
    local purchased = 0
    local consumed = 0
    local excess = 0
    if toBuy > 0 then
      local session = OnyxiaGold.SessionState
      local quote
      if session and session.IsActive and session:IsActive() then
        quote = session:Quote(itemID, toBuy)
      elseif OnyxiaGold.Prices and OnyxiaGold.Prices.GetAcquisitionQuote then
        quote = OnyxiaGold.Prices:GetAcquisitionQuote(itemID, toBuy)
      end
      if not quote or not quote.complete then
        return nil
      end
      buyCost = quote.cashRequired or quote.totalCost or 0
      economicBuy = quote.economicConsumedCost or buyCost
      leftover = quote.leftoverAssetValue or 0
      purchased = quote.purchasedUnits or toBuy
      consumed = quote.consumedUnits or toBuy
      excess = quote.excessUnits or 0
      cash = cash + buyCost
    end
    local unit
    if opp and opp.saleExitUnknown then
      unit = tonumber(opp.vendorUnit) or 0
    else
      unit = OnyxiaGold.Prices:GetLiquidationPrice(itemID) or 0
    end
    ownedValue = ownedValue + (owned + banked + mailed) * unit
    table.insert(lines, {
      itemID = itemID,
      count = count,
      ownedUnits = owned,
      bankUnits = banked,
      mailUnits = mailed,
      buyUnits = toBuy,
      buyCost = buyCost,
      economicCost = economicBuy,
      purchasedUnits = purchased,
      consumedUnits = consumed,
      excessUnits = excess,
      leftoverAssetValue = leftover,
    })
  end
  local economicBuy = 0
  local leftover = 0
  for i = 1, table.getn(lines) do
    economicBuy = economicBuy + (lines[i].economicCost or 0)
    leftover = leftover + (lines[i].leftoverAssetValue or 0)
  end
  return lines, cash, ownedValue + economicBuy, ownedValue, true, leftover
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
-- Consumed reagents free their slots before the next craft. Leftover units
-- from a whole lot keep the slots they still occupy.
local function bagSlotsFor(lines)
  local session = OnyxiaGold.SessionState
  local sessionOn = session and session.IsActive and session:IsActive()
  local inv = OnyxiaGold.Inventory
  local free
  if sessionOn and session.SlotsLeft then
    free = session:SlotsLeft()
  end
  if free == nil and inv and inv.GetFreeGeneralSlots then
    free = inv:GetFreeGeneralSlots()
  end
  if free == nil then
    return nil, nil
  end
  local slots = 0
  for i = 1, table.getn(lines or {}) do
    local line = lines[i]
    local stack
    if sessionOn and session.StackSize then
      stack = session:StackSize(line.itemID)
    end
    if (not stack or stack < 1) and inv and inv.GetStackSize then
      stack = inv:GetStackSize(line.itemID)
    end
    if not stack or stack < 1 then
      return nil, free
    end
    local partial = 0
    if sessionOn and session.PartialRoom then
      partial = session:PartialRoom(line.itemID, stack)
    elseif inv and inv.GetPartialRoom then
      partial = inv:GetPartialRoom(line.itemID) or 0
    end
    local incoming = line.purchasedUnits or line.buyUnits or 0
    local spill = incoming - partial
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
  local category = req and (req.requiredToolCategory or req.toolCategory)
  if category == "TRANSMUTATION_STONE" then
    local stones = OnyxiaGold.Data and OnyxiaGold.Data.TransmutationStones or {}
    local inv = OnyxiaGold.Inventory
    local bankName
    for i = 1, table.getn(stones) do
      local id = stones[i]
      local onPerson = inv and inv.GetOnPersonCount and (inv:GetOnPersonCount(id) or 0) > 0
      local inBank = inv and inv.GetBankCount and (inv:GetBankCount(id) or 0) > 0
      local name = "transmutation stone"
      if OnyxiaGold.Data and OnyxiaGold.Data.GetItemName then
        name = OnyxiaGold.Data.GetItemName(id) or name
      end
      if onPerson then
        return nil
      end
      if inBank and not bankName then
        bankName = name
      end
    end
    if bankName then
      return "WITHDRAW_TOOL", "Withdraw " .. bankName, bankName
    end
    return "TOOL_MISSING", "No transmutation stone in bags or equipped", "transmutation stone"
  end
  local toolID = req and tonumber(req.toolItemID)
  if not toolID then
    return nil
  end
  local name = req.tool or "tool"
  if OnyxiaGold.Data and OnyxiaGold.Data.GetItemName then
    name = OnyxiaGold.Data.GetItemName(toolID) or name
  end
  local inv = OnyxiaGold.Inventory
  local onPerson = inv and inv.GetOnPersonCount and (inv:GetOnPersonCount(toolID) or 0) > 0
  local inBank = inv and inv.GetBankCount and (inv:GetBankCount(toolID) or 0) > 0
  if onPerson then
    return nil
  end
  if inBank then
    return "WITHDRAW_TOOL", "Withdraw " .. name, name
  end
  return "TOOL_MISSING", name .. " is not in bags or equipped", name
end

function Planner:GetPersonalQuote(opp, n)
  n = math.floor(tonumber(n) or 0)
  if n < 0 then
    n = 0
  end
  local lines, cash, economic, _, complete, leftover = planInputs(opp, n)
  if not lines or not complete or not economic then
    return { complete = false }
  end
  local netPer = tonumber(opp and opp.netRevenue) or 0
  local expected = n * netPer
  local profit = expected - economic
  local marginal = profit
  if n > 1 then
    local _, _, prevEconomic, _, prevComplete = planInputs(opp, n - 1)
    if not prevComplete or not prevEconomic then
      return { complete = false }
    end
    marginal = profit - ((n - 1) * netPer - prevEconomic)
  elseif n == 0 then
    marginal = 0
    profit = 0
  end
  return {
    cashRequired = cash or 0,
    economicInput = economic,
    leftoverAssets = leftover or 0,
    expectedNetOutput = expected,
    totalProfit = profit,
    marginalProfit = marginal,
    complete = true,
    inputLines = lines,
  }
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

function Planner:Personalize(opp, deployable, afterMailDeployable, ignoreSkill, beyondGold)
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
  -- Display-only. A skill preview does not reserve cash, bags, or depth,
  -- and it does not change which rows are actionable when the setting is off.
  -- Missing profession (rank 0) is missingProfession, not missingSkill.
  -- An unset minimum skill is never filled in.
  local skillPreview = false
  local previewProfession = nil
  local previewNeed = nil
  local relaxedMissingProfession = false
  if ignoreSkill and not cap.executable and not cap.skillUnset
    and (cap.missingSkill or cap.missingProfession) then
    local req = opp.requirements
    local profession = req and req.profession
    local need = req and tonumber(req.minimumSkill)
    if need and need > 0 and (profession == "Alchemy" or profession == "Enchanting") then
      local relaxed = {}
      for key, value in pairs(req) do
        relaxed[key] = value
      end
      relaxed.minimumSkill = 0
      if cap.missingProfession then
        relaxed.profession = nil
        relaxed.recipeSpellID = nil
      end
      local again = OnyxiaGold.Capabilities:CanExecute(relaxed)
      if again.executable then
        cap = again
        skillPreview = true
        previewProfession = profession
        previewNeed = need
        if req and req.profession and not relaxed.profession then
          relaxedMissingProfession = true
        end
      end
    end
  end
  -- Display-only, and only for the beyond-gold list. Missing profession or
  -- short skill can be priced. An unset minimum skill cannot. This does not
  -- enter the greedy selection and does not change profit math.
  local goldSkillGap = false
  if beyondGold and not cap.skillUnset then
    local req = opp.requirements
    local profession = req and req.profession
    local need = req and tonumber(req.minimumSkill)
    if need and need > 0 and (profession == "Alchemy" or profession == "Enchanting") then
      if not previewProfession then
        previewProfession = profession
        previewNeed = need
      end
      if not cap.executable and (cap.missingProfession or cap.missingSkill) then
        local wasMissingProfession = cap.missingProfession and true or false
        local relaxed = {}
        for key, value in pairs(req) do
          relaxed[key] = value
        end
        relaxed.minimumSkill = 0
        if cap.missingProfession then
          relaxed.profession = nil
          relaxed.recipeSpellID = nil
        end
        local again = OnyxiaGold.Capabilities:CanExecute(relaxed)
        if again.executable then
          cap = again
          goldSkillGap = true
          if wasMissingProfession then
            relaxedMissingProfession = true
          end
        end
      end
    end
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
    local have = id and (bagCount(id) or 0) or 0
    have = have + (id and bankCount(id) or 0) + (id and mailCount(id) or 0)
    if not (opp and opp.ownedOnly) then
      have = have + (id and coveredBuyout(id) or 0)
    end
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
    local craftCap = tonumber(opp.maxCrafts)
    if craftCap and craftCap >= 0 and capabilityAllowed > craftCap then
      capabilityAllowed = craftCap
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
    skillPreview = skillPreview,
    previewProfession = previewProfession,
    previewNeed = previewNeed,
    goldSkillGap = goldSkillGap,
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

  if opp.shatterDecision == "sell" then
    person.state = "SELL_INSTEAD"
    person.reason = "Sell"
    person.capabilityAllowedCrafts = 0
    person.executableCrafts = 0
    person.sensibleCrafts = 0
    return person
  end

  if opp.cooldownDecision == "skip" then
    person.state = "SKIP_COOLDOWN"
    person.reason = "Skip"
    person.capabilityAllowedCrafts = 0
    person.executableCrafts = 0
    person.sensibleCrafts = 0
    return person
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

  if cooldown and OnyxiaGold.Capabilities and OnyxiaGold.Capabilities.CooldownState then
    local cdState = OnyxiaGold.Capabilities:CooldownState(cooldown)
    if cdState == "COOLDOWN_UNKNOWN" then
      person.state = "COOLDOWN_UNKNOWN"
      person.reason = "Cooldown has not been read from the profession window"
      person.capabilityAllowedCrafts = 0
      return person
    end
    if cdState == "ON_COOLDOWN" then
      person.state = "ON_COOLDOWN"
      person.reason = "Transmute cooldown is still running"
      person.capabilityAllowedCrafts = 0
      return person
    end
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

  local toolState, toolReason, toolName = toolDecision(opp)
  -- A stone in the bank is a withdraw, then the craft. It is not a missing tool.
  if toolState == "WITHDRAW_TOOL" then
    person.bankTool = { name = toolName or "transmutation stone", count = 1 }
    toolState = nil
  end
  -- A missing Alchemy or Enchanting profession is still priced for preview.
  -- The normal list (both flags off) still stops on the tool.
  if toolState and not relaxedMissingProfession then
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
    local marketCap = tonumber(opp.marketProfitableCrafts)
    if marketCap and marketCap > 0 and execCap > marketCap then
      execCap = marketCap
    end
    local chosen
    local n = 1
    while n <= execCap do
      local personal = self:GetPersonalQuote(opp, n)
      local marginal = personal and personal.marginalProfit
      if not personal or not personal.complete or not marginal then
        break
      end
      if marginal <= 0 or not meetsThreshold(marginal) then
        break
      end
      chosen = n
      n = n + 1
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
    local personal = self:GetPersonalQuote(opp, 1)
    local marginal = personal and personal.marginalProfit
    if personal and personal.complete and marginal and marginal > 0 and meetsThreshold(marginal) then
      person.state = "ACTIONABLE_AFTER_MAIL"
      person.reason = "Collect mail first"
      person.executableCrafts = 0
      person.sensibleCrafts = 0
      person.cashRequiredNow = personal.cashRequired or 0
      return person
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
  local liquid = OnyxiaGold.Capital and OnyxiaGold.Capital:GetLiquid() or 0
  if OnyxiaGold.Lots and OnyxiaGold.Lots.ActionScore then
    return OnyxiaGold.Lots.ActionScore(
      person.economicProfit or 0,
      (person.opp and person.opp.confidence) or 1,
      person.cashRequiredNow or 0,
      liquid
    )
  end
  return person.economicProfit or 0
end

-- Numbers already on the action. Sale unit is GetOpportunitySaleUnit (P25).
-- Proceeds are crafts * netRevenue, the sale side of economicProfit.
local function breakdownOf(person)
  local opp = person.opp
  local crafts = tonumber(person.sensibleCrafts) or 0
  if crafts <= 0 or type(opp) ~= "table" then
    return nil
  end
  local buys = {}
  local lines = person.inputLines
  if type(lines) == "table" then
    for i = 1, table.getn(lines) do
      local line = lines[i]
      local qty = tonumber(line.buyUnits) or 0
      local cost = tonumber(line.buyCost)
      if qty > 0 and cost then
        table.insert(buys, {
          itemID = line.itemID,
          count = qty,
          cost = cost,
        })
      end
    end
  end
  local outID = opp.outputItemIDs and opp.outputItemIDs[1]
  local saleUnit = tonumber(opp.saleUnit)
  if (not saleUnit or saleUnit <= 0) and outID and OnyxiaGold.Prices and OnyxiaGold.Prices.GetOpportunitySaleUnit then
    saleUnit = tonumber(OnyxiaGold.Prices:GetOpportunitySaleUnit(outID))
  end
  if saleUnit and saleUnit <= 0 then
    saleUnit = nil
  end
  local proceeds = nil
  local units = nil
  if saleUnit and outID then
    proceeds = crafts * (tonumber(opp.netRevenue) or 0)
    units = crafts * outputPerCraft(opp)
  end
  if table.getn(buys) == 0 and not saleUnit then
    return nil
  end
  return {
    buys = buys,
    outputItemID = outID,
    postUnits = units,
    saleUnit = saleUnit,
    proceeds = proceeds,
  }
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
  local namedCast = (opp.sharedCooldownRow and opp.cooldownDecision == "cast") or opp.benchRow
  if opp.sharedCooldownRow and opp.cooldownDecision == "cast" then
    name = opp.winnerName or opp.name or "20-hour transmute"
  elseif opp.benchRow then
    name = opp.winnerName or opp.name or "Transmute"
  end
  if cash <= 0 then
    kind = "CRAFT_OWNED"
    if namedCast then
      detail = opp.forgoneLine or string.format("Use owned materials · %d crafts", crafts)
    else
      detail = string.format("Use owned materials · %d crafts", crafts)
      name = "Use owned: " .. tostring(opp.name)
    end
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
    if namedCast then
      detail = opp.forgoneLine or string.format("Then %d %s", crafts, tostring(name))
    else
      name = "Buy " .. table.concat(bits, " + ")
      detail = string.format("Then %d %s", crafts, tostring(opp.name))
    end
  end
  if opp.castSeconds and opp.castSeconds > 0 then
    detail = (detail or "") .. " · " .. tostring(opp.castSeconds) .. " sec"
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
    breakdown = breakdownOf(person),
  }
end

local function previewAction(person, index)
  local action = actionFromPerson(person, index)
  local profession = person.previewProfession or "Profession"
  local need = tonumber(person.previewNeed) or 0
  action.kind = "SKILL_PREVIEW"
  action.actionable = false
  action.skillLabel = string.format("Needs %s %d.", profession, need)
  action.name = action.skillLabel
  action.state = "SKILL_PREVIEW"
  action.detail = action.skillLabel .. " Not a buy."
  return action
end

-- Far above the 3.3.5 gold cap, so cash is not what limits the priced quantity.
local UNLIMITED_COPPER = 20000000000

local function isGatheringOpportunity(opp)
  local req = opp and opp.requirements
  local profession = type(req) == "table" and req.profession or nil
  local factory = OnyxiaGold.Data and OnyxiaGold.Data.Factory
  if profession and factory and factory.IsGatheringProfession and factory:IsGatheringProfession(profession) then
    return true
  end
  return false
end

-- Cash-short previews include conversions that have no profession.
-- Gathering and unset-skill recipes stay off this list.
local function beyondGoldCandidate(opp)
  if not opp or opp.actionable == false or opp.skillUnset then
    return false
  end
  local req = opp.requirements
  if type(req) == "table" and req.skillUnset then
    return false
  end
  if isGatheringOpportunity(opp) then
    return false
  end
  return true
end

local function goldPreviewAction(person, deployable)
  local action = actionFromPerson(person, 0)
  local cash = tonumber(action.cashRequiredNow) or 0
  local have = tonumber(deployable) or 0
  local shortfall = cash - have
  if shortfall < 0 then
    shortfall = 0
  end
  local skillLabel = nil
  if person.goldSkillGap then
    local profession = person.previewProfession
    local need = tonumber(person.previewNeed)
    if profession and need and need > 0 then
      skillLabel = string.format("Needs %s %d.", profession, need)
    end
  end
  action.actionable = false
  action.skillLabel = skillLabel
  if shortfall > 0 then
    local goldLabel = string.format(
      "Needs %s more. Cash required %s.",
      OnyxiaGold.FormatGoldShort(shortfall),
      OnyxiaGold.FormatGoldShort(cash)
    )
    action.kind = "GOLD_PREVIEW"
    action.goldLabel = goldLabel
    action.state = "GOLD_PREVIEW"
    if skillLabel then
      action.name = goldLabel .. " " .. skillLabel
    else
      action.name = goldLabel
    end
    action.detail = action.name .. " Not a buy."
    return action
  end
  if skillLabel then
    action.kind = "SKILL_PREVIEW"
    action.goldLabel = nil
    action.name = skillLabel
    action.state = "SKILL_PREVIEW"
    action.detail = skillLabel .. " Not a buy."
    return action
  end
  return nil
end

function Planner:ShowAboveSkill()
  return OnyxiaGoldDB
    and OnyxiaGoldDB.settings
    and OnyxiaGoldDB.settings.showAboveSkill
    and true
    or false
end

function Planner:ShowBeyondGold()
  return OnyxiaGoldDB
    and OnyxiaGoldDB.settings
    and OnyxiaGoldDB.settings.showBeyondGold
    and true
    or false
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

local function addSellOutput(map, itemID, typeLabel)
  itemID = tonumber(itemID)
  if not itemID or map[itemID] then
    return
  end
  map[itemID] = typeLabel or "Post"
end

-- Outputs of conversions, transmutes, and crafts that are meant to be sold.
-- A finished stack stays on the list after there is nothing left to buy.
local function sellOutputs()
  local map = {}
  local data = OnyxiaGold.Data
  local conv = data and data.Conversions or {}
  for i = 1, table.getn(conv) do
    local def = conv[i]
    if def then
      addSellOutput(map, def.targetItemID, def.typeLabel)
      if def.reversible then
        addSellOutput(map, def.sourceItemID, def.typeLabel)
      end
    end
  end
  local trans = data and data.Transmutes or {}
  for i = 1, table.getn(trans) do
    local def = trans[i]
    local outputs = def and def.outputs
    if type(outputs) == "table" then
      for j = 1, table.getn(outputs) do
        addSellOutput(map, outputs[j] and outputs[j].itemID, def.typeLabel or "Transmute")
      end
    end
  end
  local crafts = data and data.EnchantCrafts or {}
  for i = 1, table.getn(crafts) do
    local def = crafts[i]
    local outputs = def and def.outputs
    if type(outputs) == "table" then
      for j = 1, table.getn(outputs) do
        addSellOutput(map, outputs[j] and outputs[j].itemID, def.typeLabel or "Enchanting")
      end
    end
  end
  local opps = {}
  if OnyxiaGold.OpportunityEngine and OnyxiaGold.OpportunityEngine.GetResults then
    opps = OnyxiaGold.OpportunityEngine:GetResults() or {}
  end
  for i = 1, table.getn(opps) do
    local opp = opps[i]
    local ids = opp and opp.outputItemIDs
    if type(ids) == "table" and not (opp.saleExitUnknown and opp.type ~= "DISENCHANT") then
      for j = 1, table.getn(ids) do
        local label = opp.typeLabel or opp.type
        if opp.type == "DISENCHANT" then
          label = "Enchanting"
        end
        addSellOutput(map, ids[j], label)
      end
    end
  end
  return map
end

local function realBagCount(itemID)
  if OnyxiaGold.Inventory and OnyxiaGold.Inventory.GetBagCount then
    return OnyxiaGold.Inventory:GetBagCount(itemID) or 0
  end
  return bagCount(itemID)
end

local function reservedInputUnits(actions, itemID)
  local n = 0
  for i = 1, table.getn(actions) do
    local action = actions[i]
    local kind = action and action.kind
    if kind == "BUY_AND_CRAFT" or kind == "CRAFT" or kind == "CRAFT_OWNED" then
      local lines = action.person and action.person.inputLines
      if type(lines) == "table" then
        for j = 1, table.getn(lines) do
          local line = lines[j]
          if line and tonumber(line.itemID) == itemID then
            n = n + (tonumber(line.ownedUnits) or 0)
          end
        end
      end
    end
  end
  return n
end

local function clickStackSize(itemID, postCount)
  local stack
  if OnyxiaGold.Prices and OnyxiaGold.Prices.GetPlannedStackSize then
    stack = OnyxiaGold.Prices:GetPlannedStackSize(itemID)
  end
  if (not stack or stack < 1) and OnyxiaGold.Inventory and OnyxiaGold.Inventory.GetStackSize then
    stack = OnyxiaGold.Inventory:GetStackSize(itemID)
  end
  stack = tonumber(stack) or postCount
  if stack < 1 then
    stack = postCount
  end
  local maxStack = OnyxiaGold.Inventory and OnyxiaGold.Inventory.GetStackSize and OnyxiaGold.Inventory:GetStackSize(itemID)
  if maxStack and maxStack > 0 and stack > maxStack then
    stack = maxStack
  end
  if stack > postCount then
    stack = postCount
  end
  if stack < 1 then
    stack = 1
  end
  return math.floor(stack)
end

-- Finished sellable output still in bags. One row per item.
-- Units a selected buy or craft still needs are left on that row.
local function readyPostActions(actions)
  local posts = {}
  local outputs = sellOutputs()
  local ids = {}
  for itemID in pairs(outputs) do
    table.insert(ids, itemID)
  end
  table.sort(ids)
  for i = 1, table.getn(ids) do
    local itemID = ids[i]
    local inBags = realBagCount(itemID)
    local reserved = reservedInputUnits(actions, itemID)
    local postCount = inBags - reserved
    if postCount < 0 then
      postCount = 0
    end
    local saleUnit = OnyxiaGold.Prices and OnyxiaGold.Prices.GetOpportunitySaleUnit
      and OnyxiaGold.Prices:GetOpportunitySaleUnit(itemID)
    saleUnit = tonumber(saleUnit)
    if postCount >= 1 and saleUnit and saleUnit > 0 then
      local stack = clickStackSize(itemID, postCount)
      local heldUnit = saleUnit
      if OnyxiaGold.Prices and OnyxiaGold.Prices.GetLiquidationPrice then
        local liquid = OnyxiaGold.Prices:GetLiquidationPrice(itemID)
        if liquid and liquid > 0 then
          heldUnit = liquid
        end
      end
      local age = OnyxiaGold.Prices and OnyxiaGold.Prices.GetAge and OnyxiaGold.Prices:GetAge(itemID)
      local stale = true
      if OnyxiaGold.Lots and OnyxiaGold.Lots.IsStale then
        stale = OnyxiaGold.Lots.IsStale(age, OnyxiaGold.Config and OnyxiaGold.Config.QuickScanStaleSeconds)
      end
      local record = OnyxiaGold.Prices and OnyxiaGold.Prices.GetRecord and OnyxiaGold.Prices:GetRecord(itemID)
      local external = record and record.source == "external"
      local marketMin = OnyxiaGold.Prices and OnyxiaGold.Prices.GetMarketMinimum and OnyxiaGold.Prices:GetMarketMinimum(itemID)
      local ownMin = OnyxiaGold.AuctionStop and OnyxiaGold.AuctionStop.OwnCheapestUnit
        and OnyxiaGold.AuctionStop.OwnCheapestUnit(itemID)
      local floorUnit = saleUnit
      if OnyxiaGold.AuctionStop and OnyxiaGold.AuctionStop.PostFloorUnit then
        floorUnit = OnyxiaGold.AuctionStop.PostFloorUnit(heldUnit, 1, 0)
      end
      local fresh = not stale and not external
      local policy = OnyxiaGold.Lots and OnyxiaGold.Lots.PostPolicy and OnyxiaGold.Lots.PostPolicy({
        economicFloor = floorUnit,
        marketMinimum = marketMin,
        ownMinimum = ownMin,
        stackSize = stack,
        stale = stale,
        external = external and true or false,
        liveValidated = fresh,
      })
      local postUnit = saleUnit
      if policy and policy.targetPrice and policy.decision ~= "needs_validation" then
        postUnit = policy.targetPrice
      end
      local economics = OnyxiaGold.Lots and OnyxiaGold.Lots.PostEconomics
        and OnyxiaGold.Lots.PostEconomics(postUnit, stack, heldUnit, OnyxiaGold:GetAuctionHouseCutBPS())
      local gross = economics and economics.stackBuyout or math.floor(postUnit * stack + 0.5)
      local net = economics and economics.expectedRevenue or gross
      local profit = economics and economics.expectedProfit or 0
      local inventoryValue = economics and economics.inventoryValue or (heldUnit * stack)
      local itemName = "item"
      if OnyxiaGold.Data and OnyxiaGold.Data.GetItemName then
        itemName = OnyxiaGold.Data.GetItemName(itemID) or itemName
      end
      local cut = "5%"
      if OnyxiaGold.GetAuctionHouseCut and OnyxiaGold.FormatPercent then
        cut = OnyxiaGold.FormatPercent(OnyxiaGold:GetAuctionHouseCut())
      end
      local name = string.format(
        "Post %d %s. %d in bags. Stack of %d at %s each, %s after the %s cut.",
        postCount,
        itemName,
        inBags,
        stack,
        OnyxiaGold.FormatMoney(postUnit),
        OnyxiaGold.FormatMoney(net),
        cut
      )
      local detail = "Revenue if it sells. Not profit. Open the Auction House, then click Post."
      if policy and policy.decision == "needs_validation" then
        detail = "Needs a fresh market check before it can post."
      end
      table.insert(posts, {
        kind = "POST",
        name = name,
        typeLabel = outputs[itemID] or "Post",
        expectedProfit = profit,
        expectedRevenue = net,
        cashReleased = net,
        inventoryValue = inventoryValue,
        cashRequiredNow = 0,
        crafts = postCount,
        state = "POST",
        detail = detail,
        outputItemID = itemID,
        bagCount = inBags,
        postCount = postCount,
        stackSize = stack,
        saleUnit = postUnit,
        stackBuyout = gross,
        bid = gross,
        buyout = gross,
        duration = 2,
        sortName = itemName,
        snapshotAge = age,
        postStale = stale and true or false,
        postExternal = external and true or false,
        economicFloor = floorUnit,
        marketMinimum = marketMin,
        ownMinimum = ownMin,
        deposit = nil,
      })
    end
  end
  table.sort(posts, function(a, b)
    return (a.sortName or "") < (b.sortName or "")
  end)
  return posts
end

local function dropCoveredHoldRows(actions, posting)
  local kept = {}
  for i = 1, table.getn(actions) do
    local action = actions[i]
    local drop = false
    if action.kind == "POST_OR_HOLD" then
      local opp = action.sourceOpp
      local outID = opp and opp.outputItemIDs and tonumber(opp.outputItemIDs[1])
      if outID and posting[outID] then
        drop = true
      end
    end
    if not drop then
      table.insert(kept, action)
    end
  end
  return kept
end

local function auctionHouseShown()
  return AuctionFrame and AuctionFrame.IsShown and AuctionFrame:IsShown() and true or false
end

local function professionShown(name)
  if type(name) ~= "string" or name == "" then
    return false
  end
  if not TradeSkillFrame or not TradeSkillFrame.IsShown or not TradeSkillFrame:IsShown() then
    return false
  end
  if type(GetTradeSkillLine) ~= "function" then
    return false
  end
  local skillName = GetTradeSkillLine()
  return skillName == name
end

local function craftProfession(action)
  local opp = action and action.sourceOpp
  local req = opp and opp.requirements
  if type(req) == "table" then
    local name = req.profession
    if name == "Alchemy" or name == "Enchanting" then
      return name
    end
  end
  local label = action and action.typeLabel
  if label == "Alchemy" or label == "Enchanting" then
    return label
  end
  if opp and (opp.typeLabel == "Alchemy" or opp.typeLabel == "Enchanting") then
    return opp.typeLabel
  end
  return nil
end

local function outputItemName(action)
  local opp = action and action.sourceOpp
  local itemID = opp and opp.outputItemIDs and tonumber(opp.outputItemIDs[1])
  if itemID and OnyxiaGold.Data and OnyxiaGold.Data.GetItemName then
    local name = OnyxiaGold.Data.GetItemName(itemID)
    if type(name) == "string" and name ~= "" then
      return name
    end
  end
  if opp and type(opp.name) == "string" and opp.name ~= "" then
    return opp.name
  end
  return "item"
end

local function fillSessionPost(action, step)
  local info = action.breakdown or {}
  local itemID = tonumber(step.itemID) or tonumber(info.outputItemID)
  local count = tonumber(step.count) or tonumber(info.postUnits) or 0
  local saleUnit = tonumber(info.saleUnit)
  if not itemID or count < 1 or not saleUnit or saleUnit <= 0 then
    return false
  end
  local stack = clickStackSize(itemID, count)
  local heldUnit = saleUnit
  if OnyxiaGold.Prices and OnyxiaGold.Prices.GetLiquidationPrice then
    local liquid = OnyxiaGold.Prices:GetLiquidationPrice(itemID)
    if liquid and liquid > 0 then
      heldUnit = liquid
    end
  end
  local age = OnyxiaGold.Prices and OnyxiaGold.Prices.GetAge and OnyxiaGold.Prices:GetAge(itemID)
  local stale = true
  if OnyxiaGold.Lots and OnyxiaGold.Lots.IsStale then
    stale = OnyxiaGold.Lots.IsStale(age, OnyxiaGold.Config and OnyxiaGold.Config.QuickScanStaleSeconds)
  end
  local record = OnyxiaGold.Prices and OnyxiaGold.Prices.GetRecord and OnyxiaGold.Prices:GetRecord(itemID)
  local external = record and record.source == "external"
  local marketMin = OnyxiaGold.Prices and OnyxiaGold.Prices.GetMarketMinimum and OnyxiaGold.Prices:GetMarketMinimum(itemID)
  local ownMin = OnyxiaGold.AuctionStop and OnyxiaGold.AuctionStop.OwnCheapestUnit
    and OnyxiaGold.AuctionStop.OwnCheapestUnit(itemID)
  local floorUnit = saleUnit
  if OnyxiaGold.AuctionStop and OnyxiaGold.AuctionStop.PostFloorUnit then
    floorUnit = OnyxiaGold.AuctionStop.PostFloorUnit(heldUnit, 1, 0)
  end
  local fresh = not stale and not external
  local policy = OnyxiaGold.Lots and OnyxiaGold.Lots.PostPolicy and OnyxiaGold.Lots.PostPolicy({
    economicFloor = floorUnit,
    marketMinimum = marketMin,
    ownMinimum = ownMin,
    stackSize = stack,
    stale = stale,
    external = external and true or false,
    liveValidated = fresh,
  })
  local postUnit = saleUnit
  if policy and policy.targetPrice and policy.decision ~= "needs_validation" then
    postUnit = policy.targetPrice
  end
  local cutBPS = 500
  if OnyxiaGold.GetAuctionHouseCutBPS then
    cutBPS = OnyxiaGold:GetAuctionHouseCutBPS()
  end
  local economics = OnyxiaGold.Lots and OnyxiaGold.Lots.PostEconomics
    and OnyxiaGold.Lots.PostEconomics(postUnit, stack, heldUnit, cutBPS)
  local gross = economics and economics.stackBuyout or math.floor(postUnit * stack + 0.5)
  local net = economics and economics.expectedRevenue or gross
  local bagCount = 0
  if OnyxiaGold.Inventory and OnyxiaGold.Inventory.GetImmediatelyAvailableCount then
    bagCount = OnyxiaGold.Inventory:GetImmediatelyAvailableCount(itemID) or 0
  end
  step.post = {
    outputItemID = itemID,
    bagCount = bagCount,
    postCount = count,
    stackSize = stack,
    saleUnit = postUnit,
    stackBuyout = gross,
    bid = gross,
    buyout = gross,
    duration = 2,
    expectedRevenue = net,
    cashReleased = net,
    inventoryValue = economics and economics.inventoryValue or (heldUnit * stack),
    expectedProfit = economics and economics.expectedProfit or 0,
    snapshotAge = age,
    postStale = stale and true or false,
    postExternal = external and true or false,
    economicFloor = floorUnit,
    marketMinimum = marketMin,
    ownMinimum = ownMin,
    deposit = nil,
  }
  return true
end

local function actionFromStep(step, parent, first)
  local row = {
    sessionStep = step.role,
    name = step.line or step.name,
    cashRequiredNow = 0,
    crafts = tonumber(step.count) or 0,
    state = parent.state,
    detail = step.windowHint or parent.detail,
    confidence = parent.confidence,
    sourceOpp = parent.sourceOpp,
    person = parent.person,
    buyItemID = step.itemID,
    typeLabel = parent.typeLabel,
    expectedProfit = 0,
  }
  if first then
    row.expectedProfit = parent.expectedProfit or 0
  end
  if step.role == "buy" then
    row.kind = "BUY"
    row.typeLabel = "Buy"
    row.cashRequiredNow = tonumber(step.cash) or 0
    row.detail = "Whole auction lots. Leftover units stay in the plan. Fund this buy from gold in hand."
    if step.flip then
      row.flip = true
      row.typeLabel = "Flip"
      row.stopUnit = tonumber(step.unit) or 0
      row.queryName = step.name
      row.flipCount = tonumber(step.count) or 0
      row.sortName = step.name
      row.detail = "Whole auction lot. Fund this buy from gold in hand."
    end
    if (tonumber(step.excessUnits) or 0) > 0 then
      row.detail = string.format(
        "Leftover %d. Whole auction lots. Fund this buy from gold in hand.",
        step.excessUnits
      )
    end
  elseif step.role == "post" then
    row.kind = "POST"
    row.typeLabel = "Post"
    local post = step.post or {}
    for key, value in pairs(post) do
      row[key] = value
    end
    row.kind = "POST"
    row.sessionStep = "post"
    row.name = step.line or row.name
    row.cashRequiredNow = 0
    row.detail = step.windowHint or "Post lists one stack."
    if step.flip then
      local sale = tonumber(step.saleUnit) or 0
      local count = tonumber(step.count) or 0
      local gross = sale * count
      row.flip = true
      row.typeLabel = "Flip"
      row.outputItemID = step.itemID
      row.postCount = count
      row.stackSize = count
      row.saleUnit = sale
      row.stackBuyout = gross
      row.bid = gross
      row.buyout = gross
      row.duration = 2
      row.expectedRevenue = tonumber(step.proceeds) or 0
      row.economicFloor = sale
      row.sortName = step.name
      row.detail = step.windowHint or "Post the lot you just bought."
    end
  elseif step.role == "withdraw" then
    row.kind = "WITHDRAW"
    row.typeLabel = "Bank"
    row.cashRequiredNow = 0
    row.crafts = 0
    row.detail = "Withdraw this from the bank. It is not in the bags."
  elseif step.role == "mail" then
    row.kind = "MAIL"
    row.typeLabel = "Mail"
    row.cashRequiredNow = 0
    row.crafts = 0
    if step.mail == "gold" then
      row.detail = "Take gold is one click. Personal mail and cash-on-delivery stay put."
    else
      row.detail = "Take mail is one click. Personal mail and cash-on-delivery stay put."
    end
  else
    row.kind = "CRAFT"
    row.typeLabel = step.profession or parent.typeLabel or "Craft"
    row.cashRequiredNow = 0
  end
  row.windowHint = step.windowHint
  return row
end

local function isSessionCraft(action)
  local kind = action and action.kind
  local crafts = tonumber(action and action.crafts) or 0
  return crafts > 0 and (kind == "BUY_AND_CRAFT" or kind == "CRAFT" or kind == "CRAFT_OWNED")
end

local function namesFor(action)
  local names = {
    output = outputItemName(action),
    profession = craftProfession(action),
  }
  local lines = action.person and action.person.inputLines
  if type(lines) == "table" then
    for i = 1, table.getn(lines) do
      local itemID = tonumber(lines[i] and lines[i].itemID)
      if itemID and OnyxiaGold.Data and OnyxiaGold.Data.GetItemName then
        local name = OnyxiaGold.Data.GetItemName(itemID)
        if type(name) == "string" and name ~= "" then
          names[itemID] = name
        end
      end
    end
  end
  return names
end

local claimedTools = {}

local function groupFor(action, index)
  local names = namesFor(action)
  local steps = {}
  if OnyxiaGold.SessionPlan and OnyxiaGold.SessionPlan.StepsFromAction then
    steps = OnyxiaGold.SessionPlan.StepsFromAction(action, names)
  end
  local kept = {}
  for i = 1, table.getn(steps) do
    local step = steps[i]
    if step.role ~= "post" or fillSessionPost(action, step) then
      step.source = action
      table.insert(kept, step)
    end
  end
  local tool = action.person and action.person.bankTool
  if tool and type(tool.name) == "string" and tool.name ~= "" and not claimedTools[tool.name] then
    claimedTools[tool.name] = true
    table.insert(kept, {
      role = "withdraw",
      count = tonumber(tool.count) or 1,
      name = tool.name,
      source = action,
      stone = true,
    })
  end
  local buys = {}
  local uses = {}
  local lines = action.person and action.person.inputLines
  if type(lines) == "table" then
    for i = 1, table.getn(lines) do
      local line = lines[i]
      local itemID = tonumber(line and line.itemID)
      if itemID then
        local purchased = tonumber(line.purchasedUnits) or 0
        local buyUnits = tonumber(line.buyUnits) or 0
        local cash = tonumber(line.buyCost) or 0
        if purchased > 0 or (buyUnits > 0 and cash > 0) then
          buys[itemID] = true
        end
        if (tonumber(line.ownedUnits) or 0) > 0 then
          uses[itemID] = true
        end
      end
    end
  end
  local priority = 0
  local opp = action.sourceOpp
  if opp and opp.sharedCooldownRow and opp.cooldownDecision == "cast" then
    priority = 1
  end
  local proceeds = 0
  if type(action.breakdown) == "table" then
    proceeds = tonumber(action.breakdown.proceeds) or 0
  end
  return {
    index = index,
    priority = priority,
    profit = tonumber(action.expectedProfit) or 0,
    proceeds = proceeds,
    steps = kept,
    buys = buys,
    uses = uses,
  }
end

-- One resale per item, from lots the crafts have not already reserved.
-- Armor and weapons stay out: this is not a disenchant buy. A stale or
-- external book cannot authorise the purchase.
local function flipGroups()
  local groups = {}
  local LotsApi = OnyxiaGold.Lots
  local Session = OnyxiaGold.SessionState
  local Plan = OnyxiaGold.SessionPlan
  local db = OnyxiaGold.Database
  if not LotsApi or not LotsApi.FlipMargin or not Plan or not Plan.FlipSteps then
    return groups
  end
  if not Session or not Session.IsActive or not Session:IsActive() then
    return groups
  end
  if not db or not db.GetMarket then
    return groups
  end
  local market = db:GetMarket()
  local latest = market and market.latest
  if type(latest) ~= "table" then
    return groups
  end
  local rows = {}
  for key, rec in pairs(latest) do
    local itemID = tonumber(key) or tonumber(rec and rec.itemID)
    if itemID and type(rec) == "table" and rec.source ~= "external" then
      table.insert(rows, { itemID = itemID, rec = rec })
    end
  end
  table.sort(rows, function(a, b)
    return a.itemID < b.itemID
  end)
  local foundRows = {}
  for i = 1, table.getn(rows) do
    local itemID = rows[i].itemID
    local rec = rows[i].rec
    local info = OnyxiaGold.ItemInfo
    local meta = info and info.Get and info:Get(itemID)
    local gear = meta and info and (info:IsWeapon(meta) or info:IsArmor(meta))
    local age = OnyxiaGold.Prices and OnyxiaGold.Prices.GetAge and OnyxiaGold.Prices:GetAge(itemID)
    local stale = true
    if LotsApi.IsStale then
      stale = LotsApi.IsStale(age, OnyxiaGold.Config and OnyxiaGold.Config.QuickScanStaleSeconds)
    end
    local name = rec.name
    if type(name) ~= "string" or name == "" then
      if OnyxiaGold.Data and OnyxiaGold.Data.GetItemName then
        name = OnyxiaGold.Data.GetItemName(itemID)
      end
    end
    if not gear and not stale and meta and meta.vendorPrice ~= nil and type(name) == "string" and name ~= "" then
      local book = Session:EnsureDepth(itemID)
      local own = OnyxiaGold.AuctionStop and OnyxiaGold.AuctionStop.OwnCheapestUnit
        and OnyxiaGold.AuctionStop.OwnCheapestUnit(itemID)
      local cutBPS = 500
      if OnyxiaGold.GetAuctionHouseCutBPS then
        cutBPS = OnyxiaGold:GetAuctionHouseCutBPS()
      end
      local found = LotsApi.FlipMargin({
        levels = book.levels,
        covered = book.covered,
        vendorUnit = meta.vendorPrice,
        hours = 24,
        cutBPS = cutBPS,
        ownMinimum = own,
        name = name,
        itemID = itemID,
      })
      if found and (tonumber(found.profit) or 0) > 0 then
        table.insert(foundRows, found)
      end
    end
  end
  table.sort(foundRows, function(a, b)
    if a.profit ~= b.profit then
      return a.profit > b.profit
    end
    return (a.itemID or 0) < (b.itemID or 0)
  end)
  for i = 1, table.getn(foundRows) do
    local found = foundRows[i]
    local steps = Plan.FlipSteps(found, 0)
    if steps then
      local source = {
        expectedProfit = found.profit,
        state = "ACTIONABLE_NOW",
        typeLabel = "Flip",
        detail = "Buy the lot, then post it.",
        confidence = 1,
      }
      for s = 1, table.getn(steps) do
        steps[s].source = source
      end
      local buys = {}
      buys[found.itemID] = true
      table.insert(groups, {
        index = 100000 + (found.itemID or i),
        priority = 0,
        profit = found.profit,
        proceeds = found.proceeds,
        steps = steps,
        buys = buys,
        uses = {},
      })
    end
  end
  return groups
end

-- Selected crafts become one session. Each keeps buy, then craft, then
-- post. A flip is buy, then post. A later sale is not cash. Previews stay
-- after the session.
function Planner:OrderSession(deployable)
  for key in pairs(claimedTools) do
    claimedTools[key] = nil
  end
  local Plan = OnyxiaGold.SessionPlan
  if not Plan or not Plan.Present or not Plan.StepsFromAction then
    return nil
  end
  local actions = self.actions or {}
  local groups = {}
  for i = 1, table.getn(actions) do
    if isSessionCraft(actions[i]) then
      table.insert(groups, groupFor(actions[i], i))
    end
  end
  local craftCount = table.getn(groups)
  local flips = flipGroups()
  for i = 1, table.getn(flips) do
    table.insert(groups, flips[i])
  end
  if table.getn(groups) < 1 then
    local post
    for i = 1, table.getn(actions) do
      local action = actions[i]
      local kind = action and action.kind
      if kind == "POST" then
        post = action
        break
      end
      if kind ~= "SKILL_PREVIEW" and kind ~= "GOLD_PREVIEW" and kind ~= "COLLECT_MAIL" then
        break
      end
    end
    if not post then
      return nil
    end
    local houseOpen = auctionHouseShown()
    if not houseOpen then
      local name = post.name or ""
      if not string.find(name, "Open the Auction House.", 1, true) then
        post.name = "Open the Auction House. " .. name
      end
      post.windowHint = "Open the Auction House."
    end
    local count = tonumber(post.postCount) or tonumber(post.stackSize) or tonumber(post.crafts) or 0
    local itemName = post.sortName or "item"
    local profit = tonumber(post.expectedProfit) or 0
    local nextLine = Plan.NextLine({ role = "post", count = count, name = itemName }, profit)
    if nextLine and not houseOpen then
      nextLine = "Open the Auction House. " .. nextLine
    end
    local summary = "Capital deployed 0c. 1 step."
    return {
      nextLine = nextLine,
      summaryLine = summary,
      profit = profit,
      capitalDeployed = 0,
      activeSteps = 1,
      steps = { post },
    }
  end
  local ordered = groups
  if Plan.ArrangeCrafts then
    ordered = Plan.ArrangeCrafts(groups)
  end
  local purse = tonumber(deployable) or 0
  local steps = {}
  local totalProfit = 0
  local totalProceeds = 0
  local included = 0
  for g = 1, table.getn(ordered) do
    local group = ordered[g]
    local need = 0
    local groupSteps = group.steps or {}
    for i = 1, table.getn(groupSteps) do
      local step = groupSteps[i]
      if step.role == "buy" then
        need = need + (tonumber(step.cash) or 0) + (tonumber(step.hold) or 0)
      end
    end
    if need <= purse and table.getn(groupSteps) > 0 then
      purse = purse - need
      included = included + 1
      totalProfit = totalProfit + (tonumber(group.profit) or 0)
      totalProceeds = totalProceeds + (tonumber(group.proceeds) or 0)
      for i = 1, table.getn(groupSteps) do
        local step = groupSteps[i]
        step.craft = included
        table.insert(steps, step)
      end
    end
  end
  local plan = Plan.Present({
    cash = tonumber(deployable) or 0,
    profit = totalProfit,
    saleProceeds = totalProceeds,
    auctionOpen = auctionHouseShown(),
    professionShown = professionShown,
    steps = steps,
  })
  if not plan or table.getn(plan.steps or {}) < 1 then
    return nil
  end
  local rows = {}
  local seen = {}
  for i = 1, table.getn(plan.steps) do
    local step = plan.steps[i]
    local craft = step.craft or 0
    local first = not seen[craft]
    seen[craft] = true
    table.insert(rows, actionFromStep(step, step.source, first))
  end
  local posted = {}
  for i = 1, table.getn(rows) do
    local itemID = rows[i] and rows[i].outputItemID
    if itemID then
      posted[itemID] = true
    end
  end
  for i = 1, table.getn(actions) do
    local action = actions[i]
    local kind = action and action.kind
    if kind == "SKILL_PREVIEW" or kind == "GOLD_PREVIEW" then
      table.insert(rows, action)
    elseif craftCount < 1 and kind == "POST" and not action.flip and not posted[action.outputItemID] then
      table.insert(rows, action)
    end
  end
  self.actions = rows
  return plan
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

  -- Skill previews are priced on the fresh book, then left out of the greedy
  -- selection. They are not reserved and they are not buys.
  local previewPeople = {}
  if self:ShowAboveSkill() then
    for i = 1, table.getn(opps) do
      local person = self:Personalize(opps[i], deployable, afterMailBudget(deployable), true)
      if person.skillPreview and person.state == "ACTIONABLE_NOW" and (person.sensibleCrafts or 0) > 0 then
        table.insert(previewPeople, person)
      end
    end
  end

  -- Priced on the fresh book, then left out of the greedy selection.
  -- Not reserved and not buys. "On the normal list" is the unrelaxed pass.
  -- A beyondGold pass already ignores profession and skill, so it cannot
  -- decide whether the real list would have kept the row.
  local goldPeople = {}
  if self:ShowBeyondGold() then
    for i = 1, table.getn(opps) do
      local opp = opps[i]
      if beyondGoldCandidate(opp) then
        local normal = self:Personalize(opp, deployable, afterMailBudget(deployable), false, false)
        local onNormalList = normal.state == "ACTIONABLE_NOW" and (normal.sensibleCrafts or 0) > 0
        if not onNormalList then
          local priced = self:Personalize(opp, UNLIMITED_COPPER, UNLIMITED_COPPER, false, true)
          local hasCrafts = priced.state == "ACTIONABLE_NOW" and (priced.sensibleCrafts or 0) > 0
          if hasCrafts and not onNormalList then
            table.insert(goldPeople, priced)
          end
        end
      end
    end
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
    local bestPri = 0
    for i = 1, table.getn(people) do
      if not used[i] then
        local person = self:Personalize(opps[i], remaining, 0)
        people[i] = person
        if person.state == "ACTIONABLE_NOW" and (person.sensibleCrafts or 0) > 0 then
          if (person.cashRequiredNow or 0) <= remaining then
            local pri = 0
            local src = person.opp
            if src and src.sharedCooldownRow and src.cooldownDecision == "cast" then
              pri = 1
            end
            local s = scoreOf(person)
            local take = false
            if not bestI then
              take = true
            elseif pri > bestPri then
              take = true
            elseif pri == bestPri and s > bestScore then
              take = true
            elseif pri == bestPri and s == bestScore then
              local bestP = people[bestI]
              local roiA = person.roi or 0
              local roiB = bestP.roi or 0
              if roiA > roiB or (roiA == roiB and (person.cashRequiredNow or 0) < (bestP.cashRequiredNow or 0)) then
                take = true
              end
            end
            if take then
              bestScore = s
              bestPri = pri
              bestI = i
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
      if person.opp and person.opp.shatterDecision == "sell" then
        table.insert(self.actions, {
          kind = "SELL",
          name = person.opp.name or "Sell",
          typeLabel = person.opp.typeLabel or "Enchanting",
          expectedProfit = person.opp.expectedProfit or 0,
          cashRequiredNow = 0,
          crafts = 0,
          state = "SELL_INSTEAD",
          detail = person.opp.forgoneLine or "Sell. Shattering leaves less after the cut.",
          person = person,
          sourceOpp = person.opp,
        })
      elseif person.opp and person.opp.cooldownDecision == "skip" then
        table.insert(self.actions, {
          kind = "SKIP_COOLDOWN",
          name = "Skip 20-hour transmute",
          typeLabel = "20-hour",
          expectedProfit = 0,
          cashRequiredNow = 0,
          crafts = 0,
          state = "SKIP_COOLDOWN",
          detail = person.opp.forgoneLine or "Skip. None of these beat selling the materials.",
          person = person,
          sourceOpp = person.opp,
        })
      elseif person.state == "ACTIONABLE_AFTER_MAIL" then
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
        or person.state == "COOLDOWN_UNKNOWN"
        or person.state == "ON_COOLDOWN"
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

  local posts = readyPostActions(self.actions)
  local posting = {}
  for i = 1, table.getn(posts) do
    posting[posts[i].outputItemID] = true
  end
  if table.getn(posts) > 0 then
    self.actions = dropCoveredHoldRows(self.actions, posting)
    local at = 1
    while at <= table.getn(self.actions) do
      local action = self.actions[at]
      if action.kind == "WITHDRAW" or action.state == "NEEDS_WITHDRAW" then
        at = at + 1
      else
        break
      end
    end
    for i = 1, table.getn(posts) do
      table.insert(self.actions, at + i - 1, posts[i])
    end
  end

  if table.getn(previewPeople) > 0 then
    table.sort(previewPeople, function(a, b)
      local pa = a.economicProfit or 0
      local pb = b.economicProfit or 0
      if pa == pb then
        return (a.previewNeed or 0) < (b.previewNeed or 0)
      end
      return pa > pb
    end)
    for i = 1, table.getn(previewPeople) do
      table.insert(self.actions, previewAction(previewPeople[i], 0))
    end
  end

  if table.getn(goldPeople) > 0 then
    local listed = {}
    for i = 1, table.getn(self.actions) do
      local src = self.actions[i].sourceOpp
      if src then
        listed[src] = true
      end
    end
    table.sort(goldPeople, function(a, b)
      local pa = a.economicProfit or 0
      local pb = b.economicProfit or 0
      if pa == pb then
        return (a.cashRequiredNow or 0) < (b.cashRequiredNow or 0)
      end
      return pa > pb
    end)
    for i = 1, table.getn(goldPeople) do
      local person = goldPeople[i]
      if not listed[person.opp] then
        local action = goldPreviewAction(person, deployable)
        if action and (action.kind == "GOLD_PREVIEW" or action.kind == "SKILL_PREVIEW") then
          table.insert(self.actions, action)
          listed[person.opp] = true
        end
      end
    end
  end

  local sessionView = self:OrderSession(deployable)
  if not sessionView or not sessionView.nextLine or sessionView.nextLine == "" then
    local sale = 0
    if OnyxiaGold.Mail and OnyxiaGold.Mail.GetSaleGold then
      sale = OnyxiaGold.Mail:GetSaleGold() or 0
    end
    if sale > 0 and unlockedByMail > 0 then
      sessionView = sessionView or {}
      sessionView.nextLine = "Open the mailbox. Take gold."
      if not sessionView.summaryLine then
        sessionView.summaryLine = "Capital deployed 0c. 1 step."
      end
    end
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
    nextLine = sessionView and sessionView.nextLine or nil,
    summaryLine = sessionView and sessionView.summaryLine or nil,
    expectedProfit = sessionView and sessionView.profit or nil,
    capitalDeployed = sessionView and sessionView.capitalDeployed or nil,
    activeSteps = sessionView and sessionView.activeSteps or nil,
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
