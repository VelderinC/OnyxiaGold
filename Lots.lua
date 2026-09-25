--[[
  OnyxiaGold.Lots
  Whole-auction acquisition. An auction lot is indivisible.

  Objective, in order:
    1. Cover the requested units with whole lots.
    2. Respect available capital and bag space when those limits are known.
    3. Minimise economicConsumedCost.
       That is the cost of the units the recipe consumes. Leftover units
       stay inventory, valued at what was paid for them, so they are not
       treated as a loss.
    4. When two plans are within 1 copper of economic cost, prefer the
       plan that spends less cash now.
    5. Then fewer lots, then the earlier lot.

  A cheap 20-stack can beat a dearer exact stack on economic cost when
  capital and bags can hold it. The exact stack wins when capital or bags
  cannot hold the 20, or when the economic costs match and it spends less.

  Bids stay a separate class. The next bid is the current bid plus
  minIncrement once someone has bid. The current bid itself is not a price
  the player can submit.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Lots = OnyxiaGold.Lots or {}

local Lots = OnyxiaGold.Lots

-- Opening the auction house must not start a browse query.
Lots.HOUSE_SHOW_STARTS_QUERY = false

local function nitems(t)
  if type(t) ~= "table" then
    return 0
  end
  if table.getn then
    return table.getn(t)
  end
  return 0
end

local function copyLot(lot, level, seq)
  local size = tonumber(lot.s or lot.size or lot.q) or 0
  local price = tonumber(lot.p or lot.unitPrice) or 0
  local cash = tonumber(lot.cash)
  if not cash then
    cash = price * size
  end
  return {
    p = price,
    s = size,
    cash = cash,
    level = level,
    seq = seq,
    index = lot.index,
    itemID = lot.itemID,
    name = lot.name,
  }
end

-- Keep whole auctions inside the covered quantity. A partial stack is not created.
function Lots.WholeLevels(depth, covered)
  local out = {}
  local left = tonumber(covered) or 0
  local sum = 0
  if type(depth) ~= "table" or left <= 0 then
    return out, 0
  end
  for i = 1, nitems(depth) do
    if left <= 0 then
      break
    end
    local lvl = depth[i]
    local p = lvl and (lvl.p or lvl.unitPrice)
    local q = lvl and (lvl.q or lvl.quantity)
    local copies = (lvl and (lvl.n or lvl.auctions)) or 1
    local stack = lvl and tonumber(lvl.s)
    if p and p > 0 and q and q > 0 then
      local use = q
      if use > left then
        use = left
      end
      if stack and stack > 0 and copies > 0 then
        local fit = math.floor(use / stack)
        if fit > copies then
          fit = copies
        end
        if fit > 0 then
          local kept = fit * stack
          table.insert(out, { p = p, q = kept, n = fit, s = stack })
          sum = sum + kept
          left = left - kept
        end
      else
        table.insert(out, { p = p, q = use, n = copies, s = stack })
        sum = sum + use
        left = left - use
      end
    end
  end
  return out, sum
end

function Lots.Expand(levels, requested)
  local lots = {}
  requested = tonumber(requested) or 0
  if type(levels) ~= "table" then
    return lots
  end
  for i = 1, nitems(levels) do
    local lvl = levels[i]
    local price = lvl and tonumber(lvl.p or lvl.unitPrice)
    local qty = lvl and tonumber(lvl.q or lvl.quantity)
    local copies = lvl and tonumber(lvl.n or lvl.auctions) or 1
    local stack = lvl and tonumber(lvl.s)
    if price and price > 0 and qty and qty > 0 then
      if not stack or stack < 1 then
        if copies > 0 and qty % copies == 0 then
          stack = qty / copies
        else
          stack = qty
          copies = 1
        end
      end
      if copies < 1 then
        copies = 1
      end
      if copies * stack > qty then
        copies = math.floor(qty / stack)
      end
      local emit = copies
      if requested > 0 and stack > 0 then
        local need = math.floor((requested + stack - 1) / stack) + 2
        if need < 1 then
          need = 1
        end
        if emit > need then
          emit = need
        end
      end
      if emit > 40 then
        emit = 40
      end
      for seq = 1, emit do
        table.insert(lots, copyLot({
          p = price,
          s = stack,
          cash = price * stack,
          index = lvl.index,
          itemID = lvl.itemID,
          name = lvl.name,
        }, i, seq))
      end
    end
  end
  return lots
end

local function slotsFor(units, partial, stack)
  if not stack or stack < 1 then
    return nil
  end
  local spill = units - (tonumber(partial) or 0)
  if spill <= 0 then
    return 0
  end
  return math.floor((spill + stack - 1) / stack)
end

local function bagAllows(units, constraints)
  if type(constraints) ~= "table" or constraints.freeSlots == nil then
    return true
  end
  local need = slotsFor(units, constraints.partialRoom, constraints.stackSize)
  if need == nil then
    return true
  end
  return need <= (tonumber(constraints.freeSlots) or 0)
end

local function betterPlan(a, b)
  if not b then
    return true
  end
  local delta = a.economic - b.economic
  if delta < -1 then
    return true
  end
  if delta > 1 then
    return false
  end
  if a.cash < b.cash then
    return true
  end
  if a.cash > b.cash then
    return false
  end
  if a.count < b.count then
    return true
  end
  return false
end

local function collectLots(from, units)
  local seq = {}
  local guard = 0
  local seen = {}
  while units and units > 0 and guard < 80 do
    if seen[units] then
      break
    end
    seen[units] = true
    local step = from[units]
    if not step then
      break
    end
    table.insert(seq, 1, step.lot)
    units = step.prev
    guard = guard + 1
  end
  return seq
end

function Lots.Select(lots, requested, constraints)
  requested = math.floor(tonumber(requested) or 0)
  constraints = constraints or {}
  local capital = constraints.capital
  if capital ~= nil then
    capital = tonumber(capital) or 0
  end
  local quote = {
    requestedUnits = requested,
    purchasedUnits = 0,
    consumedUnits = 0,
    excessUnits = 0,
    cashRequired = 0,
    economicConsumedCost = 0,
    leftoverAssetValue = 0,
    selectedLots = {},
    complete = false,
  }
  if requested <= 0 then
    quote.complete = true
    return quote
  end
  local work = {}
  for i = 1, nitems(lots) do
    local lot = lots[i]
    if lot and (tonumber(lot.s) or 0) > 0 and (tonumber(lot.p) or 0) > 0 then
      local row = copyLot(lot, lot.level, lot.seq or i)
      row.pos = i
      table.insert(work, row)
    end
  end
  table.sort(work, function(a, b)
    if a.p ~= b.p then
      return a.p < b.p
    end
    if a.s ~= b.s then
      return a.s < b.s
    end
    local ia = tonumber(a.index) or 0
    local ib = tonumber(b.index) or 0
    if ia ~= ib then
      return ia < ib
    end
    return (a.pos or 0) < (b.pos or 0)
  end)
  if nitems(work) > 64 then
    local kept = {}
    local cover = {}
    for i = 1, nitems(work) do
      if i <= 64 then
        table.insert(kept, work[i])
      elseif work[i].s >= requested and nitems(cover) < 8 then
        table.insert(cover, work[i])
      end
    end
    for i = 1, nitems(cover) do
      table.insert(kept, cover[i])
    end
    work = kept
    quote.capped = true
  end

  local bestCash = {}
  local from = {}
  bestCash[0] = 0
  local maxU = 0
  local best = nil

  for lotIndex = 1, nitems(work) do
    local lot = work[lotIndex]
    local snapshotCash = {}
    local snapshotFrom = {}
    for u = 0, maxU do
      snapshotCash[u] = bestCash[u]
      snapshotFrom[u] = from[u]
    end
    local limit = maxU
    for u = 0, limit do
      local cash = snapshotCash[u]
      if cash ~= nil and u < requested then
        local newCash = cash + lot.cash
        local allowed = (capital == nil or newCash <= capital)
        local newUnits = u + lot.s
        if allowed and bagAllows(newUnits, constraints) then
          if newUnits >= requested then
            local take = requested - u
            local part = lot.cash
            if take < lot.s and lot.s > 0 then
              part = math.floor(lot.cash * take / lot.s)
            end
            local chain = collectLots(snapshotFrom, u)
            table.insert(chain, lotIndex)
            local plan = {
              economic = cash + part,
              cash = newCash,
              count = nitems(chain),
              chain = chain,
            }
            if betterPlan(plan, best) then
              best = plan
            end
          else
            local previous = bestCash[newUnits]
            if previous == nil or newCash < previous then
              bestCash[newUnits] = newCash
              from[newUnits] = { prev = u, lot = lotIndex }
              if newUnits > maxU then
                maxU = newUnits
              end
            end
          end
        end
      end
    end
  end

  if not best then
    return quote
  end
  local selected = {}
  local purchased = 0
  for i = 1, nitems(best.chain) do
    local lot = work[best.chain[i]]
    table.insert(selected, {
      p = lot.p,
      s = lot.s,
      cash = lot.cash,
      level = lot.level,
      seq = lot.seq,
      index = lot.index,
      itemID = lot.itemID,
      name = lot.name,
    })
    purchased = purchased + lot.s
  end
  local consumed = requested
  if consumed > purchased then
    consumed = purchased
  end
  quote.selectedLots = selected
  quote.purchasedUnits = purchased
  quote.consumedUnits = consumed
  quote.excessUnits = purchased - consumed
  quote.cashRequired = best.cash
  quote.economicConsumedCost = best.economic
  quote.leftoverAssetValue = best.cash - best.economic
  if quote.leftoverAssetValue < 0 then
    quote.leftoverAssetValue = 0
  end
  quote.complete = purchased >= requested
  return quote
end

function Lots.Quote(levels, requested, constraints)
  local lots = Lots.Expand(levels, requested)
  local quote = Lots.Select(lots, requested, constraints)
  quote.requestedQuantity = quote.requestedUnits
  quote.filledQuantity = quote.purchasedUnits
  quote.totalCost = quote.cashRequired
  quote.levelsConsumed = nitems(quote.selectedLots)
  if quote.consumedUnits > 0 then
    quote.averageUnitCost = math.floor(quote.economicConsumedCost / quote.consumedUnits)
  elseif quote.complete then
    quote.averageUnitCost = 0
  end
  local last = quote.selectedLots[nitems(quote.selectedLots)]
  quote.marginalUnitCost = last and last.p or nil
  return quote
end

function Lots.RequiredBid(minBid, bidAmount, minIncrement)
  minBid = tonumber(minBid) or 0
  bidAmount = tonumber(bidAmount) or 0
  minIncrement = tonumber(minIncrement) or 0
  if minIncrement < 0 then
    minIncrement = 0
  end
  if bidAmount > 0 then
    return bidAmount + minIncrement
  end
  return minBid
end

function Lots.IsStale(age, threshold)
  if age == nil then
    return true
  end
  threshold = tonumber(threshold) or 600
  return age > threshold
end

-- Conservative floor is the action value. Expected value is reported beside it.
-- DISENCHANT is not returned for an unknown intact sale.
function Lots.DisenchantExit(args)
  args = args or {}
  local floorNet = tonumber(args.floorNet)
  local expectedNet = tonumber(args.expectedNet)
  local vendor = tonumber(args.vendor) or 0
  if vendor < 0 then
    vendor = 0
  end
  local intact = tonumber(args.intactNet)
  local action = floorNet
  if action == nil then
    action = expectedNet
  end
  local state = "UNKNOWN_EXIT"
  if args.destruction then
    if action and action > 0 then
      state = "DE"
    end
  elseif args.soulbound then
    if action and action > vendor then
      state = "DE"
    elseif vendor > 0 then
      state = "VENDOR"
    else
      state = "UNKNOWN_EXIT"
    end
  elseif args.intactKnown and intact then
    local sale = intact
    if action and action > sale and action > vendor then
      state = "DE"
    elseif sale >= vendor then
      state = "SELL"
    elseif vendor > 0 then
      state = "VENDOR"
    else
      state = "UNKNOWN_EXIT"
    end
  elseif action and action > vendor then
    state = "CHECK_AH"
  elseif vendor > 0 and (not action or vendor >= action) then
    state = "VENDOR"
  else
    state = "UNKNOWN_EXIT"
  end
  return {
    state = state,
    floor = floorNet,
    expected = expectedNet,
    vendor = vendor,
    intact = intact,
  }
end

function Lots.PostEconomics(saleUnit, stack, inventoryUnit, cutBPS)
  saleUnit = tonumber(saleUnit) or 0
  stack = tonumber(stack) or 1
  if stack < 1 then
    stack = 1
  end
  inventoryUnit = tonumber(inventoryUnit) or saleUnit
  cutBPS = tonumber(cutBPS) or 500
  local gross = math.floor(saleUnit * stack + 0.5)
  local revenue = math.floor(gross * (10000 - cutBPS) / 10000)
  if revenue < 0 then
    revenue = 0
  end
  local inventoryValue = inventoryUnit * stack
  return {
    saleUnit = saleUnit,
    stackBuyout = gross,
    expectedRevenue = revenue,
    cashReleased = revenue,
    inventoryValue = inventoryValue,
    expectedProfit = revenue - inventoryValue,
  }
end

-- Match the market when it is above the floor. Do not undercut by one copper.
-- A stale or external book cannot authorise the post.
function Lots.PostPolicy(args)
  args = args or {}
  local floor = tonumber(args.economicFloor) or 0
  if floor < 1 then
    floor = 1
  end
  local stack = tonumber(args.stackSize) or 1
  if stack < 1 then
    stack = 1
  end
  local market = tonumber(args.marketMinimum)
  local own = tonumber(args.ownMinimum)
  local decision = "post"
  local target = floor
  if args.stale or args.external or not args.liveValidated then
    decision = "needs_validation"
  elseif own and (not market or own <= market) then
    decision = "leave"
    target = own
  elseif market and market > floor then
    target = market
  end
  return {
    economicFloor = floor,
    marketMinimum = market,
    ownMinimum = own,
    targetPrice = target,
    stackSize = stack,
    totalBuyout = target * stack,
    decision = decision,
    deposit = args.deposit,
  }
end

function Lots.AcceptQuantity(marginals, minimum)
  local kept = 0
  if type(marginals) ~= "table" then
    return 0
  end
  for i = 1, nitems(marginals) do
    local marginal = tonumber(marginals[i])
    if not marginal or marginal <= 0 then
      break
    end
    if minimum and marginal < minimum then
      break
    end
    kept = i
  end
  return kept
end

function Lots.ClassifyTool(category, found)
  if category ~= "TRANSMUTATION_STONE" then
    return nil
  end
  found = found or {}
  if found.onPerson then
    return nil
  end
  if found.inBank then
    return "WITHDRAW_TOOL"
  end
  return "TOOL_MISSING"
end

function Lots.CooldownState(obs, now)
  now = tonumber(now) or 0
  if type(obs) ~= "table" or not obs.observedAt then
    return "COOLDOWN_UNKNOWN"
  end
  local readyAt = tonumber(obs.readyAt)
  if readyAt and now < readyAt then
    return "ON_COOLDOWN"
  end
  return "READY"
end

function Lots.ShouldRebuildOpportunities(state)
  state = state or {}
  if state.alreadyRan then
    return false
  end
  if not state.database or not state.character or not state.inventory then
    return false
  end
  if not state.capabilities or not state.hasMarket then
    return false
  end
  return true
end

function Lots.AcceptExternalSnapshot(data)
  if type(data) ~= "table" then
    return false, "schema"
  end
  if data.schemaVersion ~= 1 then
    return false, "schema"
  end
  if data.source ~= "ah.nerfed.net" then
    return false, "source"
  end
  if data.realm ~= "Onyxia" then
    return false, "realm"
  end
  if data.faction ~= "Alliance" then
    return false, "faction"
  end
  if type(data.scannedAt) ~= "number" then
    return false, "schema"
  end
  if type(data.items) ~= "table" then
    return false, "schema"
  end
  return true, nil
end

-- Never replace a good snapshot after a failed refresh.
function Lots.ShouldReplaceSnapshot(newOk, reasons)
  reasons = reasons or {}
  if not newOk then
    return false
  end
  if reasons.downloadFailed or reasons.parseFailed or reasons.realmMismatch
    or reasons.factionMismatch or reasons.schemaFailure then
    return false
  end
  return true
end

function Lots.AllowPlaceAuctionBid(offer, revalidated)
  if type(offer) ~= "table" then
    return false
  end
  if not revalidated then
    return false
  end
  local buyout = tonumber(offer.buyout) or 0
  local index = tonumber(offer.index) or 0
  return buyout > 0 and index >= 1
end

function Lots.AllowStartAuction(check)
  check = check or {}
  if not check.validated or check.stale or check.external then
    return false
  end
  if not check.matches then
    return false
  end
  local buyout = tonumber(check.buyout) or 0
  return buyout > 0
end

function Lots.AllowTakeInbox(fromClick)
  return fromClick and true or false
end

function Lots.AllowDisenchant(state)
  return state == "DE"
end

-- Warmane has not been shown to sort later browse pages by price.
Lots.PAGE_SORT_UNVERIFIED = true

function Lots.ShouldContinuePaging(page, pageCap, pageIsFull)
  page = tonumber(page) or 0
  pageCap = tonumber(pageCap) or 30
  if not pageIsFull then
    return false, false
  end
  if page + 1 >= pageCap then
    return false, true
  end
  return true, false
end
