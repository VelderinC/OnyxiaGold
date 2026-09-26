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
    page = lot.page,
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

-- Parent links are immutable. The winning chain is walked once, backwards,
-- then reversed. Completing states do not allocate a sequence table.
local function nodeCount(node)
  local count = 0
  local guard = 0
  while node and guard < 80 do
    count = count + 1
    node = node.parent
    guard = guard + 1
  end
  return count
end

local function chainFromNode(node, work)
  local reversed = {}
  local guard = 0
  while node and guard < 80 do
    reversed[guard + 1] = node.lot
    node = node.parent
    guard = guard + 1
  end
  local selected = {}
  local purchased = 0
  local i = guard
  local out = 0
  while i >= 1 do
    local lot = work[reversed[i]]
    if lot then
      out = out + 1
      selected[out] = {
        p = lot.p,
        s = lot.s,
        cash = lot.cash,
        level = lot.level,
        seq = lot.seq,
        index = lot.index,
        itemID = lot.itemID,
        name = lot.name,
        page = lot.page,
      }
      purchased = purchased + lot.s
    end
    i = i - 1
  end
  return selected, purchased
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

  local maxStack = 0
  for i = 1, nitems(work) do
    local size = tonumber(work[i].s) or 0
    if size > maxStack then
      maxStack = size
    end
  end
  -- A stored state is always below the request. The last lot can overshoot
  -- by less than one stack. Anything past that cannot be a cheaper cover.
  local overshoot = requested + maxStack - 1
  if overshoot < requested then
    overshoot = requested
  end
  quote.overshootBound = overshoot

  local bestCash = {}
  local from = {}
  bestCash[0] = 0
  local reachable = { 0 }
  local best = nil
  local frontierMax = tonumber(constraints.frontierMax) or 0
  local frontier = nil
  if frontierMax > requested then
    frontier = {}
  elseif frontierMax > 0 then
    frontierMax = requested
    frontier = {}
  end
  local scratchCash = Lots.scratchCash
  if not scratchCash then
    scratchCash = {}
    Lots.scratchCash = scratchCash
  end
  local scratchFrom = Lots.scratchFrom
  if not scratchFrom then
    scratchFrom = {}
    Lots.scratchFrom = scratchFrom
  end
  local scratchUsed = Lots.scratchUsed
  if not scratchUsed then
    scratchUsed = {}
    Lots.scratchUsed = scratchUsed
  end
  local states = 0
  local perf = OnyxiaGold.Performance
  local queued = {}
  local innerStep = 0

  local function yieldInner()
    innerStep = innerStep + 1
    if innerStep % 32 ~= 0 then
      return
    end
    if perf and perf.Add then
      perf:Add("lotInnerYields", 1)
    end
    Lots.lastInnerYieldLot = Lots.activeLot
    if OnyxiaGold.RefreshSchedule and OnyxiaGold.RefreshSchedule.Tick then
      OnyxiaGold.RefreshSchedule.Tick()
    end
  end

  for lotIndex = 1, nitems(work) do
    Lots.activeLot = lotIndex
    if lotIndex % 4 == 0 and OnyxiaGold.RefreshSchedule and OnyxiaGold.RefreshSchedule.Tick then
      OnyxiaGold.RefreshSchedule.Tick()
    end
    local lot = work[lotIndex]
    local nReach = nitems(reachable)
    for i = 1, nReach do
      local u = reachable[i]
      scratchCash[u] = bestCash[u]
      scratchFrom[u] = from[u]
      scratchUsed[i] = u
    end
    states = states + nReach
    for i = 1, nReach do
      yieldInner()
      local u = scratchUsed[i]
      local cash = scratchCash[u]
      if cash ~= nil and u < requested then
        local newCash = cash + lot.cash
        local allowed = (capital == nil or newCash <= capital)
        local newUnits = u + lot.s
        if newUnits > overshoot then
          allowed = false
        end
        if allowed and bagAllows(newUnits, constraints) then
          local parent = scratchFrom[u]
          local count = (parent and parent.count or 0) + 1
          if newUnits >= requested then
            local take = requested - u
            local part = lot.cash
            if take < lot.s and lot.s > 0 then
              part = math.floor(lot.cash * take / lot.s)
            end
            local plan = {
              economic = cash + part,
              cash = newCash,
              count = count,
              node = { lot = lotIndex, parent = parent, count = count },
            }
            if betterPlan(plan, best) then
              best = plan
            end
          else
            local existed = scratchCash[newUnits] ~= nil
            local previous = bestCash[newUnits]
            if previous == nil or newCash < previous then
              bestCash[newUnits] = newCash
              from[newUnits] = {
                prev = u,
                lot = lotIndex,
                parent = parent,
                count = count,
              }
              if not existed and not queued[newUnits] then
                queued[newUnits] = true
                reachable[nitems(reachable) + 1] = newUnits
              end
            end
          end
          if frontier and u < frontierMax then
            local hi = newUnits
            if hi > frontierMax then
              hi = frontierMax
            end
            local q = u + 1
            while q <= hi do
              local takeQ = q - u
              local partQ = lot.cash
              if takeQ < lot.s and lot.s > 0 then
                partQ = math.floor(lot.cash * takeQ / lot.s)
              end
              local recorded = {
                economic = cash + partQ,
                cash = newCash,
                count = count,
              }
              if betterPlan(recorded, frontier[q]) then
                frontier[q] = recorded
              end
              q = q + 1
              if (q % 32) == 0 then
                yieldInner()
              end
            end
          end
        end
      end
    end
    for i = 1, nReach do
      local u = scratchUsed[i]
      scratchCash[u] = nil
      scratchFrom[u] = nil
    end
  end
  Lots.activeLot = nil
  if perf and perf.Add then
    perf:Add("lotSelects", 1)
    perf:Add("lotStates", states)
    perf:Add("lotsConsidered", nitems(work))
  end

  if frontier then
    quote.frontier = frontier
  end
  if not best then
    return quote
  end
  local selected, purchased = chainFromNode(best.node, work)
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

-- Cached quotes are immutable. Callers read them. They do not write fields
-- or replace selectedLots. A caller that needs a private lot list copies
-- that list itself. The cache key is book id, generation, quantity, and the
-- bag/capital constraint. It does not walk auction depth.

Lots.nextBookID = Lots.nextBookID or 0

function Lots.NextBookID()
  Lots.nextBookID = (Lots.nextBookID or 0) + 1
  return Lots.nextBookID
end

function Lots.AssignBook(book)
  if type(book) ~= "table" then
    return book
  end
  if book.id == nil then
    book.id = Lots.NextBookID()
  end
  if book.generation == nil then
    book.generation = 0
  end
  return book
end

function Lots.ClearQuoteCache()
  Lots.quoteCache = {}
end

function Lots.DropBook(bookID)
  if Lots.quoteCache and bookID ~= nil then
    Lots.quoteCache[bookID] = nil
  end
end

function Lots.DropGeneration(bookID, generation)
  local books = Lots.quoteCache
  local page = books and bookID ~= nil and books[bookID]
  if type(page) == "table" and generation ~= nil then
    page[generation] = nil
    local perf = OnyxiaGold.Performance
    if perf and perf.Add then
      perf:Add("quoteCacheEvictions", 1)
      perf:Add("quoteInvalidations", 1)
    end
  end
end

Lots.quoteCache = Lots.quoteCache or {}

local function bookIdentity(levels, constraints)
  if type(constraints) == "table" and constraints.bookID ~= nil then
    return constraints.bookID, tonumber(constraints.bookGeneration) or 0
  end
  if type(levels) == "table" and levels.id ~= nil and type(levels.levels) == "table" then
    return levels.id, tonumber(levels.generation) or 0
  end
  if type(levels) == "table" then
    return levels, tonumber(constraints and constraints.bookGeneration) or 0
  end
  return 0, 0
end

local function cacheKeys(bookID, generation, quantity, constraints)
  constraints = constraints or {}
  return {
    bookID,
    generation,
    quantity,
    constraints.capital or false,
    constraints.freeSlots or false,
    constraints.stackSize or false,
    constraints.partialRoom or false,
    constraints.frontierMax or false,
  }
end

local function cacheFetch(keys)
  local node = Lots.quoteCache
  for i = 1, 7 do
    if type(node) ~= "table" then
      return nil
    end
    node = node[keys[i]]
  end
  if type(node) ~= "table" then
    return nil
  end
  return node[keys[8]]
end

local function cachePut(keys, quote)
  local node = Lots.quoteCache
  for i = 1, 7 do
    local child = node[keys[i]]
    if type(child) ~= "table" then
      child = {}
      node[keys[i]] = child
    end
    node = child
  end
  node[keys[8]] = quote
end

function Lots.Quote(levels, requested, constraints)
  local perf = OnyxiaGold.Performance
  if perf and perf.Add then
    perf:Add("lotQuotes", 1)
    perf:Add("quoteKeyBuilds", 1)
  end
  local quantity = math.floor(tonumber(requested) or 0)
  local bookID, generation = bookIdentity(levels, constraints)
  local keys = cacheKeys(bookID, generation, quantity, constraints)
  local cached = cacheFetch(keys)
  if cached then
    if perf and perf.Add then
      perf:Add("lotQuoteHits", 1)
      perf:Add("quoteCacheHits", 1)
    end
    return cached
  end
  if perf and perf.Add then
    perf:Add("quoteCacheMisses", 1)
    perf:Add("quoteCacheEntries", 1)
  end
  local lots = Lots.Expand(levels, quantity)
  local quote = Lots.Select(lots, quantity, constraints)
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
  if type(constraints) == "table" and constraints.covered ~= nil then
    quote.depthCoveredQuantity = tonumber(constraints.covered) or 0
  end
  quote.immutable = true
  local stack = type(constraints) == "table" and tonumber(constraints.stackSize) or nil
  if stack and stack > 0 then
    local slots = slotsFor(quote.purchasedUnits or 0, constraints.partialRoom, stack)
    quote.newSlotsRequired = slots
    quote.peakSlots = slots
    local leftoverSlots = slotsFor(quote.excessUnits or 0, 0, stack)
    quote.leftoverSlots = leftoverSlots
  end
  cachePut(keys, quote)
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

-- Faction auction house, 3.3.5. Twelve hours is 15% of the vendor sell
-- value, floored, then doubled for 24 hours and quadrupled for 48.
-- The planning floor is 1 silver. A vendor price of zero stays 1 silver.
-- CalculateAuctionDeposit
-- still belongs to a stack already in the post slot; this is only the
-- copper a flip subtracts before that lot is bought.
function Lots.DepositCopper(vendorUnit, count, hours)
  if vendorUnit == nil then
    return nil
  end
  vendorUnit = math.floor(tonumber(vendorUnit) or 0)
  if vendorUnit < 0 then
    vendorUnit = 0
  end
  count = math.floor(tonumber(count) or 0)
  if count < 1 then
    return nil
  end
  if vendorUnit == 0 then
    return 100
  end
  hours = tonumber(hours) or 24
  local scale = 2
  if hours <= 12 then
    scale = 1
  elseif hours >= 48 then
    scale = 4
  end
  local base = math.floor(vendorUnit * count * 15 / 100)
  if base < 100 then
    base = 100
  end
  return base * scale
end

local function percentileUnit(levels, qty)
  if OnyxiaGold.Prices and OnyxiaGold.Prices.PercentileFromDepth then
    return OnyxiaGold.Prices.PercentileFromDepth(levels, qty, 0.25)
  end
  return nil
end

local function withoutOwn(levels)
  local out = {}
  for i = 1, nitems(levels) do
    local lvl = levels[i]
    if lvl and not lvl.own then
      table.insert(out, {
        p = lvl.p or lvl.unitPrice,
        q = lvl.q or lvl.quantity,
        n = lvl.n or lvl.auctions,
        s = lvl.s,
      })
    end
  end
  return out
end

local function bookTotals(levels)
  local qty = 0
  local auctions = 0
  for i = 1, nitems(levels) do
    local row = levels[i]
    qty = qty + (tonumber(row.q) or 0)
    auctions = auctions + (tonumber(row.n) or 0)
  end
  return qty, auctions
end

local function remainderBook(levels, index)
  local rest = {}
  local qty = 0
  local auctions = 0
  for i = 1, nitems(levels) do
    local row = levels[i]
    local p = tonumber(row.p) or 0
    local n = tonumber(row.n) or 0
    local s = tonumber(row.s) or 0
    local q = tonumber(row.q) or 0
    if i == index then
      n = n - 1
      q = q - s
    end
    if p > 0 and n > 0 and s > 0 and q > 0 then
      if q > n * s then
        q = n * s
      end
      table.insert(rest, { p = p, q = q, n = n, s = s })
      qty = qty + q
      auctions = auctions + n
    end
  end
  return rest, qty, auctions
end

-- One whole auction, resold. Not a craft and not a disenchant buy.
-- The sale unit is the P25 of the book with that lot removed. The lot
-- has to be under a quarter of the book, with at least two auctions left,
-- or that one listing is the whole reason it sits under P25. Profit is
-- that sale after the cut, minus the buyout, minus the deposit. A post
-- under the character's own auction is not a flip. External, stale, and
-- disenchant books return nil.
function Lots.FlipMargin(args)
  args = args or {}
  if args.external or args.disenchant or args.stale then
    return nil
  end
  local cutBPS = tonumber(args.cutBPS) or 500
  if cutBPS < 0 then
    cutBPS = 0
  elseif cutBPS > 10000 then
    cutBPS = 10000
  end
  local raw = withoutOwn(args.levels)
  local covered = args.covered
  if covered == nil then
    local sum = 0
    for i = 1, nitems(raw) do
      sum = sum + (tonumber(raw[i].q) or 0)
    end
    covered = sum
  end
  local levels = Lots.WholeLevels(raw, covered)
  local n = nitems(levels)
  if n < 1 then
    return nil
  end
  local prefix = {}
  local totalQty = 0
  local totalN = 0
  for i = 1, n do
    local row = levels[i]
    totalQty = totalQty + (tonumber(row.q) or 0)
    totalN = totalN + (tonumber(row.n) or 0)
    prefix[i] = totalQty
  end
  if totalQty < 1 or totalN < 1 then
    return nil
  end
  -- P25 position in the original book. Removing one lot shifts only the
  -- tail, so each candidate is a binary search rather than a new book.
  local function priceAt(pos)
    if pos <= 0 then
      pos = 1
    end
    if pos > totalQty then
      pos = totalQty
    end
    local lo = 1
    local hi = n
    while lo < hi do
      local mid = math.floor((lo + hi) / 2)
      if prefix[mid] < pos then
        lo = mid + 1
      else
        hi = mid
      end
    end
    local row = levels[lo]
    return row and tonumber(row.p) or nil
  end
  local own = tonumber(args.ownMinimum)
  if own and own < 1 then
    own = nil
  end
  local best
  for i = 1, n do
    if i % 8 == 0 and OnyxiaGold.RefreshSchedule and OnyxiaGold.RefreshSchedule.Tick then
      OnyxiaGold.RefreshSchedule.Tick()
    end
    local row = levels[i]
    local unit = math.floor(tonumber(row.p) or 0)
    local stack = math.floor(tonumber(row.s) or 0)
    local copies = math.floor(tonumber(row.n) or 0)
    local qty = tonumber(row.q) or 0
    if unit > 0 and stack > 0 and copies > 0 and qty > 0 then
      local newCopies = copies - 1
      local newQty = qty - stack
      if newQty > newCopies * stack then
        newQty = newCopies * stack
      end
      local removed = qty
      local kept = 0
      if newCopies > 0 and newQty > 0 then
        removed = qty - newQty
        kept = newQty
      end
      local restQty = totalQty - removed
      local restN = totalN - 1
      local deep = stack * 4 < totalQty and restN >= 2
      local sale
      if deep and restQty > 0 then
        local target = restQty * 0.25
        if target <= 0 then
          target = 1
        end
        local start = prefix[i - 1] or 0
        if target <= start then
          sale = priceAt(target)
        elseif target <= start + kept then
          sale = unit
        else
          sale = priceAt(target + removed)
        end
      end
      sale = sale and math.floor(tonumber(sale) or 0) or nil
      if sale and sale > 0 and unit < sale and (not own or sale >= own) then
        local deposit = tonumber(args.deposit)
        if deposit == nil and args.vendorUnit ~= nil then
          deposit = Lots.DepositCopper(args.vendorUnit, stack, args.hours)
        end
        if deposit and deposit >= 0 then
          deposit = math.floor(deposit)
          local cash = unit * stack
          local gross = sale * stack
          local proceeds = math.floor(gross * (10000 - cutBPS) / 10000)
          local profit = proceeds - cash - deposit
          if profit > 0 then
            local candidate = {
              kind = "flip",
              itemID = tonumber(args.itemID),
              name = args.name,
              unit = unit,
              count = stack,
              cash = cash,
              deposit = deposit,
              saleUnit = sale,
              proceeds = proceeds,
              profit = profit,
              cutBPS = cutBPS,
            }
            local take = false
            if not best or candidate.profit > best.profit then
              take = true
            elseif candidate.profit == best.profit and candidate.cash < best.cash then
              take = true
            elseif candidate.profit == best.profit and candidate.cash == best.cash and i < (best.index or 0) then
              take = true
            end
            if take then
              candidate.index = i
              best = candidate
            end
          end
        end
      end
    end
  end
  if best then
    best.index = nil
  end
  return best
end

-- Spread alone is not liquidity. Confidence stays below 1 until sales exist.
function Lots.FlipConfidence(args)
  args = args or {}
  local auctions = tonumber(args.auctions) or 0
  local quantity = tonumber(args.quantity) or 0
  local confidence = 0.35
  if auctions >= 8 and quantity >= 40 then
    confidence = 0.85
  elseif auctions >= 4 and quantity >= 20 then
    confidence = 0.7
  elseif auctions >= 2 then
    confidence = 0.55
  end
  local sale = tonumber(args.sale) or 0
  local unit = tonumber(args.unit) or 0
  if sale > 0 and unit > 0 and (sale - unit) / sale > 0.5 then
    confidence = confidence - 0.1
  end
  local age = tonumber(args.age)
  local quick = 600
  if OnyxiaGold.Config and OnyxiaGold.Config.QuickScanStaleSeconds then
    quick = tonumber(OnyxiaGold.Config.QuickScanStaleSeconds) or quick
  end
  if age and age > quick then
    confidence = confidence - 0.15
  end
  if confidence < 0.15 then
    confidence = 0.15
  elseif confidence > 0.9 then
    confidence = 0.9
  end
  return confidence
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

-- Rank score used by What to do now. Owned crafts weigh more than buys.
-- A small purse shrinks a buy. The same formula prices every action.
function Lots.ActionScore(profit, confidence, cash, liquid)
  profit = tonumber(profit) or 0
  confidence = tonumber(confidence) or 1
  cash = tonumber(cash) or 0
  liquid = tonumber(liquid) or 0
  local score = profit * confidence
  if cash <= 0 then
    score = score * 2
  end
  if liquid > 0 and liquid < 500000 and cash > 0 then
    score = score / (1 + cash / liquid)
  end
  return score
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
