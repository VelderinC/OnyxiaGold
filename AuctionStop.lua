--[[
  OnyxiaGold.AuctionStop
  Stop price for the auction page he is looking at.

  Marks each row under the stop, over it, or a bid. Small stacks are lots,
  not scrap. Opening the house refreshes personal state and does not query,
  bind a row, or fill a post price.
  A full page does not end the search. Warmane browse order is unverified,
  so paging continues until the page is short or the page cap is hit.
  This view queries one item name, page by page, and only from auction events.

  A buy row runs one live name query. Lots.Select chooses the whole listing.
  The UI button is the only PlaceAuctionBid, and it buys that one lot.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.AuctionStop = OnyxiaGold.AuctionStop or {}

local Stop = OnyxiaGold.AuctionStop
Stop.paging = false
Stop.page = 0
Stop.pageRows = {}
Stop.stopUnit = 0
Stop.recipeCount = 1
Stop.remaining = 0
Stop.queryName = ""
Stop.postCopper = nil
Stop.buyPhase = "idle"
Stop.buyStatus = nil
Stop.buyActionIndex = nil
Stop.offer = nil
Stop.bought = {}
Stop.skipIndex = nil
Stop.skipCount = nil
Stop.skipBuyout = nil
Stop.ignoreEmpty = false

local PAGE_CAP = 30

local function money(copper)
  if OnyxiaGold.FormatMoney then
    return OnyxiaGold.FormatMoney(copper)
  end
  return tostring(copper or 0)
end

function Stop.UnitStop(netPerCraft, otherInputCost, inputCount)
  netPerCraft = tonumber(netPerCraft) or 0
  otherInputCost = tonumber(otherInputCost) or 0
  inputCount = tonumber(inputCount) or 1
  if inputCount < 1 then
    inputCount = 1
  end
  local room = netPerCraft - otherInputCost
  if room <= 0 then
    return 0
  end
  return math.floor(room / inputCount)
end

function Stop.PostFloorUnit(inputCost, outputCount, vendorUnit)
  inputCost = tonumber(inputCost) or 0
  outputCount = tonumber(outputCount) or 1
  if outputCount < 1 then
    outputCount = 1
  end
  vendorUnit = tonumber(vendorUnit) or 0
  if inputCost < 0 then
    inputCost = 0
  end
  local function netOf(unit)
    local cut = 0
    if OnyxiaGold.ApplyAuctionHouseCut then
      cut = OnyxiaGold:ApplyAuctionHouseCut(unit)
    else
      cut = unit
    end
    return cut * outputCount
  end
  local lo = 0
  local hi = inputCost
  if hi < 1 then
    hi = 1
  end
  local guard = 0
  while netOf(hi) < inputCost and guard < 40 do
    hi = hi * 2
    guard = guard + 1
  end
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if netOf(mid) >= inputCost then
      hi = mid
    else
      lo = mid + 1
    end
  end
  if vendorUnit > lo then
    lo = vendorUnit
  end
  return lo
end

function Stop.PostBuyout(unit, stackCount)
  unit = tonumber(unit) or 0
  stackCount = tonumber(stackCount) or 1
  if stackCount < 1 then
    stackCount = 1
  end
  return unit * stackCount
end

-- His cheapest buyout for this item, in copper per unit. Nil if he has none.
function Stop.OwnCheapestUnit(itemID)
  itemID = tonumber(itemID)
  local row = OnyxiaGold.Database and OnyxiaGold.Database.GetCharacter and OnyxiaGold.Database:GetCharacter()
  local listings = row and row.auctions and row.auctions.listings
  if not itemID or type(listings) ~= "table" then
    return nil
  end
  local best
  for i = 1, table.getn(listings) do
    local listing = listings[i]
    local count = listing and tonumber(listing.count) or 0
    local buyout = listing and tonumber(listing.buyout) or 0
    if listing and listing.itemID == itemID and count > 0 and buyout > 0 then
      local unit = math.floor(buyout / count)
      if unit > 0 and (not best or unit < best) then
        best = unit
      end
    end
  end
  return best
end

-- Deposit for the stack already in the post slot. Nil when the client has no number.
-- Durations are the 3.3.5 dropdown values: 1, 2, 3. No deposit formula lives here.
function Stop.DepositText(stackCount)
  if type(CalculateAuctionDeposit) ~= "function" then
    return nil
  end
  stackCount = tonumber(stackCount) or 1
  if stackCount < 1 then
    stackCount = 1
  end
  local labels = {
    AUCTION_DURATION_ONE or "12 hours",
    AUCTION_DURATION_TWO or "24 hours",
    AUCTION_DURATION_THREE or "48 hours",
  }
  local parts = {}
  for i = 1, 3 do
    local ok, value = pcall(CalculateAuctionDeposit, i, stackCount)
    value = ok and tonumber(value) or nil
    if value and value > 0 then
      table.insert(parts, labels[i] .. " " .. money(value))
    end
  end
  if table.getn(parts) < 1 then
    return nil
  end
  return "Deposit " .. table.concat(parts, ", ") .. "."
end

-- leave: his auction is already the cheapest, so the box is not moved under it.
-- post: a price at or above the floor. One copper under someone else's minimum when that stays above the floor.
function Stop.DecidePost(itemID, floorUnit, stackCount)
  floorUnit = tonumber(floorUnit) or 0
  if floorUnit < 1 then
    floorUnit = 1
  end
  stackCount = tonumber(stackCount) or 1
  if stackCount < 1 then
    stackCount = 1
  end
  local own = Stop.OwnCheapestUnit(itemID)
  local market
  if itemID and OnyxiaGold.Prices and OnyxiaGold.Prices.GetMarketMinimum then
    market = OnyxiaGold.Prices:GetMarketMinimum(itemID)
  end
  local deposit = Stop.DepositText(stackCount)
  local depositLine = deposit or "Put the stack in the post slot. The deposit is what CalculateAuctionDeposit returns."
  if own and (not market or own <= market) then
    return {
      decision = "leave",
      postCopper = nil,
      line = "Leave it. Your auction is already the cheapest. " .. depositLine,
    }
  end
  local unit = floorUnit
  if OnyxiaGold.Lots and OnyxiaGold.Lots.PostPolicy then
    local policy = OnyxiaGold.Lots.PostPolicy({
      economicFloor = floorUnit,
      marketMinimum = market,
      ownMinimum = own,
      stackSize = stackCount,
      liveValidated = true,
    })
    if policy.decision == "leave" then
      return {
        decision = "leave",
        postCopper = nil,
        line = "Leave it. Your auction is already the cheapest. " .. depositLine,
      }
    end
    if policy.targetPrice and policy.targetPrice > 0 then
      unit = policy.targetPrice
    end
  elseif market and market > floorUnit then
    unit = market
  end
  if own and unit < own and (not market or market >= own) then
    return {
      decision = "leave",
      postCopper = nil,
      line = "Leave it. Your auction is already the cheapest. " .. depositLine,
    }
  end
  return {
    decision = "post",
    postCopper = Stop.PostBuyout(unit, stackCount),
    unit = unit,
    line = "Post at " .. money(Stop.PostBuyout(unit, stackCount)) .. ". " .. depositLine,
  }
end

function Stop.Classify(auction, stopUnit, recipeCount, remaining)
  auction = auction or {}
  stopUnit = tonumber(stopUnit) or 0
  recipeCount = tonumber(recipeCount) or 1
  if recipeCount < 1 then
    recipeCount = 1
  end
  remaining = tonumber(remaining) or 0
  local count = tonumber(auction.count) or 1
  if count < 1 then
    count = 1
  end
  local buyout = tonumber(auction.buyout) or 0
  local minBid = tonumber(auction.minBid) or 0
  local bidAmount = tonumber(auction.bidAmount) or 0
  local current = bidAmount > 0 and bidAmount or minBid
  local stopText = money(stopUnit)

  local hasBuyout = buyout > 0
  local unit = hasBuyout and math.floor(buyout / count) or 0
  local nextBid = current
  if OnyxiaGold.Lots and OnyxiaGold.Lots.RequiredBid then
    nextBid = OnyxiaGold.Lots.RequiredBid(minBid, bidAmount, auction.minIncrement)
  elseif bidAmount > 0 then
    nextBid = bidAmount
  end
  local bidUnit = math.floor(nextBid / count)
  local verb = "under"
  local loss = 0
  local locksCash = false
  if hasBuyout and unit > stopUnit then
    loss = buyout - stopUnit * count
    if loss < 0 then
      loss = 0
    end
    if current > 0 and bidUnit <= stopUnit then
      verb = "bid"
      locksCash = true
    else
      verb = "over"
    end
  elseif not hasBuyout and bidUnit > stopUnit then
    verb = "over"
    loss = current - stopUnit * count
    if loss < 0 then
      loss = 0
    end
  end

  local line
  if verb == "bid" then
    line = string.format(
      "Stop %s · %d more · bid · loss %s · gold leaves the purse until the auction ends or you are outbid",
      stopText, remaining, money(loss)
    )
  elseif verb == "over" then
    line = string.format("Stop %s · %d more · over · loss %s", stopText, remaining, money(loss))
  else
    line = string.format("Stop %s · %d more · under", stopText, remaining)
  end

  return {
    verb = verb,
    overStop = verb == "over",
    loss = loss,
    locksCash = locksCash,
    line = line,
  }
end

-- Warmane page order is not verified. A page that is entirely over the stop
-- does not end the search. The caller stops on an empty or short page, or at the cap.
function Stop.JudgePage(rows, page, pageCap)
  local n = table.getn(rows or {})
  page = tonumber(page) or 0
  pageCap = tonumber(pageCap) or PAGE_CAP
  if n < 1 then
    return { queryNext = false, paging = false, incomplete = false }
  end
  local full = n >= (OnyxiaGold.Config and OnyxiaGold.Config.PageSize or 50)
  local cont, incomplete = true, false
  if OnyxiaGold.Lots and OnyxiaGold.Lots.ShouldContinuePaging then
    cont, incomplete = OnyxiaGold.Lots.ShouldContinuePaging(page, pageCap, full)
  elseif page + 1 >= pageCap then
    cont = false
    incomplete = true
  end
  return { queryNext = cont, paging = cont, incomplete = incomplete }
end

-- One buy algorithm: the same whole-lot selector the planner uses.
-- The offer is the first lot in that plan. A stack may be larger than the
-- recipe still needs. Bids are not offers.
function Stop.PickListing(rows, stopUnit, remaining)
  stopUnit = tonumber(stopUnit) or 0
  remaining = tonumber(remaining) or 0
  local sawUnder = false
  if type(rows) ~= "table" or remaining < 1 then
    return nil, false
  end
  local lots = {}
  for i = 1, table.getn(rows) do
    local row = rows[i]
    local count = tonumber(row and row.count) or 0
    local buyout = tonumber(row and row.buyout) or 0
    local index = tonumber(row and row.index)
    if index and index >= 1 and count > 0 and buyout > 0 then
      local unit = math.floor(buyout / count)
      if unit > 0 and unit <= stopUnit then
        sawUnder = true
        table.insert(lots, {
          p = unit,
          s = count,
          cash = buyout,
          index = index,
          itemID = row and row.itemID,
          name = (row and row.name) or "",
          page = row and row.page,
        })
      end
    end
  end
  if not OnyxiaGold.Lots or not OnyxiaGold.Lots.Select then
    return nil, sawUnder
  end
  local quote = OnyxiaGold.Lots.Select(lots, remaining, nil)
  local lot = quote and quote.complete and quote.selectedLots and quote.selectedLots[1]
  if not lot or not lot.index then
    return nil, sawUnder
  end
  return {
    index = lot.index,
    count = lot.s,
    buyout = lot.cash,
    unit = lot.p,
    name = lot.name or "",
    itemID = lot.itemID,
    page = lot.page,
    purchasedUnits = quote.purchasedUnits,
    incomplete = false,
  }, sawUnder
end

function Stop:PlanKey(action)
  if action and type(action.planKey) == "string" and action.planKey ~= "" then
    return action.planKey
  end
  local itemID = action and (action.buyItemID or action.itemID)
  if action and action.flip then
    return "flip:" .. tostring(itemID)
  end
  return "buy:" .. tostring(itemID)
end

function Stop:CurrentPlanRevision()
  local rev = OnyxiaGold.Revisions
  if rev and rev.Get then
    return rev:Get("plan")
  end
  local planner = OnyxiaGold.ActionPlanner
  return planner and tonumber(planner.planRevision) or 0
end

-- A purchase belongs to the plan that issued it. A later plan already
-- sees the bags, so the old count is not subtracted again.
function Stop:InFlightCount(action)
  local rev = self:CurrentPlanRevision()
  local flight = self.inflight
  if not flight or flight.planRevision ~= rev then
    self.inflight = nil
    return 0
  end
  local key = self:PlanKey(action)
  if flight.key ~= key then
    return 0
  end
  return tonumber(flight.count) or 0
end

function Stop:HouseOpen()
  return AuctionFrame and AuctionFrame.IsShown and AuctionFrame:IsShown() and true or false
end

function Stop:BuyListening()
  return self.buyPhase == "search" or self.buyPhase == "settle" or self.buyPhase == "armed"
end

function Stop:RefreshBuyRow()
  if OnyxiaGold.UI and OnyxiaGold.UI.UpdateList and OnyxiaGold.UI.rows then
    OnyxiaGold.UI:UpdateList()
  end
end

-- First return only. tonumber() would treat the total as a base.
local function listSize()
  if type(GetNumAuctionItems) ~= "function" then
    return 0
  end
  local n = GetNumAuctionItems("list")
  return tonumber(n) or 0
end

function Stop:ListReady()
  if type(GetNumAuctionItems) ~= "function" then
    return false
  end
  local n = listSize()
  if n < 1 then
    if self.ignoreEmpty then
      return false
    end
    return true
  end
  if type(GetAuctionItemLink) ~= "function" then
    return false
  end
  for i = 1, n do
    local link = GetAuctionItemLink("list", i)
    if type(link) ~= "string" or link == "" then
      return false
    end
  end
  return true
end

function Stop:ReadLiveRows()
  local out = {}
  if type(GetNumAuctionItems) ~= "function" or type(GetAuctionItemInfo) ~= "function" then
    return out
  end
  if type(GetAuctionItemLink) ~= "function" or not OnyxiaGold.ParseItemID then
    return out
  end
  local n = listSize()
  local want = tonumber(self.itemID)
  local player = type(UnitName) == "function" and UnitName("player") or nil
  for i = 1, n do
    local name, _, count, _, _, _, minBid, minIncrement, buyout, bidAmount, _, owner = GetAuctionItemInfo("list", i)
    local itemID = OnyxiaGold.ParseItemID(GetAuctionItemLink("list", i))
    if want and itemID == want then
      local mine = player and type(owner) == "string" and owner ~= "" and owner == player
      if not mine then
        table.insert(out, {
          index = i,
          name = (type(name) == "string" and name ~= "" and name) or self.queryName or "",
          count = tonumber(count) or 0,
          buyout = tonumber(buyout) or 0,
          minBid = tonumber(minBid) or 0,
          minIncrement = tonumber(minIncrement) or 0,
          bidAmount = tonumber(bidAmount) or 0,
          itemID = itemID,
        })
      end
    end
  end
  return out
end

function Stop:DropSkipped(rows)
  local index = self.skipIndex
  local count = self.skipCount
  local buyout = self.skipBuyout
  self.skipIndex = nil
  self.skipCount = nil
  self.skipBuyout = nil
  if not index then
    return rows
  end
  local kept = {}
  for i = 1, table.getn(rows) do
    local row = rows[i]
    if not (row.index == index and row.count == count and row.buyout == buyout) then
      table.insert(kept, row)
    end
  end
  return kept
end

function Stop:CapturePageRows()
  local rows = {}
  if type(GetNumAuctionItems) ~= "function" or type(GetAuctionItemInfo) ~= "function" then
    self.pageRows = rows
    return rows
  end
  local n = listSize()
  for i = 1, n do
    local _, _, count, _, _, _, minBid, minIncrement, buyout, bidAmount = GetAuctionItemInfo("list", i)
    table.insert(rows, self.Classify({
      count = tonumber(count) or 1,
      minBid = tonumber(minBid) or 0,
      minIncrement = tonumber(minIncrement) or 0,
      buyout = tonumber(buyout) or 0,
      bidAmount = tonumber(bidAmount) or 0,
    }, self.stopUnit or 0, self.recipeCount or 1, self.remaining or 0))
  end
  self.pageRows = rows
  return rows
end

function Stop:PaintCaptured(rows)
  if OnyxiaGold.UI and OnyxiaGold.UI.PaintAuctionPage then
    OnyxiaGold.UI:PaintAuctionPage({ rows = rows })
  end
end

function Stop:ArmOffer(best)
  self.offer = best
  self.pendingOffer = nil
  self.buyPhase = "armed"
  self.buyStatus = "confirm"
  if self.searchIncomplete then
    best.incomplete = true
    self.buyStatus = "confirm"
  end
  best.plannedCount = self.plannedCount
  best.plannedUnit = self.plannedUnit
  if OnyxiaGold.Log and OnyxiaGold.Log.Debug then
    OnyxiaGold.Log:Debug("AuctionStop", string.format(
      "buy offer page=%s index=%d count=%d buyout=%d unit=%d remaining=%d purchased=%s",
      tostring(best.page), best.index, best.count, best.buyout, best.unit, self.remaining or 0,
      tostring(best.purchasedUnits)
    ))
  end
  self:RefreshBuyRow()
end

function Stop:ArmFromCurrentPage()
  local pending = self.pendingOffer
  if not pending then
    self.buyPhase = "idle"
    self.buyStatus = "none"
    self:RefreshBuyRow()
    return
  end
  local rows = self:ReadLiveRows()
  local match
  for i = 1, table.getn(rows) do
    local row = rows[i]
    if row.count == pending.count and row.buyout == pending.buyout and row.itemID == pending.itemID then
      match = row
      break
    end
  end
  if not match then
    self.offer = nil
    self.pendingOffer = nil
    self.buyPhase = "idle"
    self.buyStatus = "stale"
    self:RefreshBuyRow()
    return
  end
  pending.index = match.index
  pending.page = self.page
  self:ArmOffer(pending)
end

function Stop:ReadBuyPage()
  if not self:HouseOpen() then
    self.buyPhase = "idle"
    self.offer = nil
    self.buyStatus = "closed"
    self:RefreshBuyRow()
    return
  end
  if OnyxiaGold.Scanner and OnyxiaGold.Scanner.IsScanning and OnyxiaGold.Scanner:IsScanning() then
    self.buyPhase = "idle"
    self.offer = nil
    self.buyStatus = "busy"
    self:RefreshBuyRow()
    return
  end
  if (tonumber(self.remaining) or 0) < 1 then
    self.buyPhase = "idle"
    self.offer = nil
    self.buyStatus = "done"
    self.skipIndex = nil
    self.skipCount = nil
    self.skipBuyout = nil
    self:RefreshBuyRow()
    return
  end
  if self.buyPhase == "reposition" then
    self:ArmFromCurrentPage()
    return
  end
  if self.buyPhase == "settle" then
    self.liveLots = {}
    self.buyPhase = "search"
  end
  if type(self.liveLots) ~= "table" then
    self.liveLots = {}
  end
  local rows = self:ReadLiveRows()
  if self.skipIndex then
    rows = self:DropSkipped(rows)
  end
  local page = self.page or 0
  for i = 1, table.getn(rows) do
    local row = rows[i]
    row.page = page
    self.liveLots[table.getn(self.liveLots) + 1] = row
  end
  self:PaintCaptured(self:CapturePageRows())
  local pageSize = OnyxiaGold.Config and OnyxiaGold.Config.PageSize or 50
  local full = listSize() >= pageSize
  local cont, incomplete = false, false
  if OnyxiaGold.Lots and OnyxiaGold.Lots.ShouldContinuePaging then
    cont, incomplete = OnyxiaGold.Lots.ShouldContinuePaging(page, PAGE_CAP, full)
  end
  if cont and self.queryName and self.queryName ~= "" and type(QueryAuctionItems) == "function" then
    self.page = page + 1
    self.buyPhase = "search"
    self.buyStatus = "search"
    self.offer = nil
    QueryAuctionItems(self.queryName, nil, nil, nil, nil, nil, self.page, nil, nil)
    self:RefreshBuyRow()
    return
  end
  self.searchIncomplete = incomplete and true or false
  local collected = self.liveLots
  self.liveLots = {}
  local best = self.PickListing(collected, self.stopUnit, self.remaining)
  if not best then
    self.offer = nil
    self.buyPhase = "idle"
    self.buyStatus = incomplete and "incomplete" or "none"
    self:RefreshBuyRow()
    return
  end
  if self.searchIncomplete then
    best.incomplete = true
  end
  local bestPage = tonumber(best.page) or page
  if bestPage ~= page and type(QueryAuctionItems) == "function" then
    self.pendingOffer = best
    self.page = bestPage
    self.buyPhase = "reposition"
    self.buyStatus = "search"
    self.offer = nil
    QueryAuctionItems(self.queryName, nil, nil, nil, nil, nil, bestPage, nil, nil)
    self:RefreshBuyRow()
    return
  end
  self:ArmOffer(best)
end

function Stop:OnBuyList()
  if not self:BuyListening() then
    return
  end
  local n = listSize()
  -- A bid refreshes the page. An empty clear in between is not the result.
  if n < 1 and (self.buyPhase == "settle" or self.buyPhase == "armed") then
    return
  end
  if not self:ListReady() then
    return
  end
  self:ReadBuyPage()
end

local function buyKind(action)
  local kind = action and action.kind
  return kind == "BUY" or kind == "BUY_AND_CRAFT"
end

function Stop:RowState(action)
  if not buyKind(action) then
    return nil
  end
  if action.index ~= self.buyActionIndex or not self.buyStatus then
    return nil
  end
  return {
    status = self.buyStatus,
    name = self.queryName,
    offer = self.offer,
  }
end

function Stop:RequestBuy(action)
  if not buyKind(action) then
    return
  end
  self.buyActionIndex = action.index
  self.offer = nil
  self.skipIndex = nil
  self.skipCount = nil
  self.skipBuyout = nil
  self.ignoreEmpty = false
  if not self:HouseOpen() then
    self.paging = false
    self.buyPhase = "idle"
    self.buyStatus = "closed"
    return
  end
  if OnyxiaGold.Scanner and OnyxiaGold.Scanner.IsScanning and OnyxiaGold.Scanner:IsScanning() then
    self.paging = false
    self.buyPhase = "idle"
    self.buyStatus = "busy"
    return
  end
  if not self:Bind(action) then
    self.paging = false
    self.buyPhase = "idle"
    self.buyStatus = "none"
    return
  end
  self.planKey = self:PlanKey(action)
  self.plannedCount = tonumber(self.remaining) or 0
  self.plannedUnit = tonumber(self.stopUnit) or 0
  self.liveLots = {}
  self.pendingOffer = nil
  self.searchIncomplete = false
  local bought = self:InFlightCount(action)
  self.remaining = (tonumber(self.remaining) or 0) - bought
  if self.remaining < 1 then
    self.paging = false
    self.buyPhase = "idle"
    self.buyStatus = "done"
    return
  end
  if not self.queryName or self.queryName == "" then
    self.paging = false
    self.buyPhase = "idle"
    self.buyStatus = "none"
    return
  end
  local canQuery = true
  if type(CanSendAuctionQuery) == "function" then
    canQuery = CanSendAuctionQuery() and true or false
  end
  if type(QueryAuctionItems) ~= "function" or not canQuery then
    self.paging = false
    self.buyPhase = "idle"
    self.buyStatus = "busy"
    return
  end
  self.paging = false
  self.page = 0
  self.buyPhase = "search"
  self.buyStatus = "search"
  self.ignoreEmpty = true
  QueryAuctionItems(self.queryName, nil, nil, nil, nil, nil, 0, nil, nil)
  self.ignoreEmpty = false
end

function Stop:LiveBid()
  local offer = self.offer
  if not offer or self.buyPhase ~= "armed" then
    return nil
  end
  if not self:HouseOpen() then
    self.buyPhase = "idle"
    self.offer = nil
    self.buyStatus = "closed"
    return nil
  end
  if type(GetAuctionItemInfo) ~= "function" or type(GetAuctionItemLink) ~= "function" then
    self.buyPhase = "idle"
    self.offer = nil
    self.buyStatus = "stale"
    return nil
  end
  local name, _, count, _, _, _, _, _, buyout, _, _, owner = GetAuctionItemInfo("list", offer.index)
  local itemID = OnyxiaGold.ParseItemID(GetAuctionItemLink("list", offer.index))
  count = tonumber(count) or 0
  buyout = tonumber(buyout) or 0
  local player = type(UnitName) == "function" and UnitName("player") or nil
  local mine = player and type(owner) == "string" and owner ~= "" and owner == player
  if mine or itemID ~= self.itemID or count ~= offer.count or buyout ~= offer.buyout or count < 1 or buyout < 1 then
    self.buyPhase = "idle"
    self.offer = nil
    self.buyStatus = "stale"
    return nil
  end
  local unit = math.floor(buyout / count)
  if unit > (tonumber(self.stopUnit) or 0) then
    self.buyPhase = "idle"
    self.offer = nil
    self.buyStatus = "none"
    return nil
  end
  if type(name) == "string" and name ~= "" then
    offer.name = name
  end
  return {
    index = offer.index,
    buyout = buyout,
    count = count,
  }
end

function Stop:BeginSettle(bid)
  local count = tonumber(bid and bid.count) or 0
  local rev = self:CurrentPlanRevision()
  local key = self.planKey or self:PlanKey({ buyItemID = self.itemID, flip = self.flipBuy })
  local flight = self.inflight
  if flight and flight.key == key and flight.planRevision == rev then
    flight.count = (tonumber(flight.count) or 0) + count
  else
    self.inflight = {
      key = key,
      count = count,
      planRevision = rev,
      itemID = self.itemID,
      status = "PENDING_BUY",
    }
  end
  self.remaining = (tonumber(self.remaining) or 0) - count
  if self.remaining < 0 then
    self.remaining = 0
  end
  self.skipIndex = bid and bid.index
  self.skipCount = bid and bid.count
  self.skipBuyout = bid and bid.buyout
  self.offer = nil
  self.buyPhase = "settle"
  self.buyStatus = "settle"
  self.ignoreEmpty = true
end

function Stop:NoteBidSent()
  self.ignoreEmpty = false
end

local function queryAllowed()
  if type(CanSendAuctionQuery) ~= "function" then
    return true
  end
  local ok = CanSendAuctionQuery()
  return ok and true or false
end

local function costOfCount(itemID, count)
  count = tonumber(count) or 0
  if count <= 0 or not itemID then
    return 0
  end
  local session = OnyxiaGold.SessionState
  if session and session.IsActive and session:IsActive() and session.EconomicCost then
    local part = session:EconomicCost(itemID, count)
    if part then
      return part
    end
  end
  if OnyxiaGold.Prices and OnyxiaGold.Prices.GetEconomicAcquisitionCost then
    local part = OnyxiaGold.Prices:GetEconomicAcquisitionCost(itemID, count)
    if part then
      return part
    end
  end
  local unit = 0
  if OnyxiaGold.Prices and OnyxiaGold.Prices.GetLiquidationPrice then
    unit = OnyxiaGold.Prices:GetLiquidationPrice(itemID) or 0
  end
  return unit * count
end

function Stop:Bind(action)
  if action and action.flip then
    local itemID = tonumber(action.buyItemID)
    local name = action.queryName or action.sortName or ""
    local count = tonumber(action.flipCount) or 0
    local stopUnit = tonumber(action.stopUnit) or 0
    self.postCopper = nil
    self.postLine = nil
    self.postDecision = nil
    if not itemID or name == "" or count < 1 or stopUnit < 1 then
      return false
    end
    self.itemID = itemID
    self.queryName = name
    self.remaining = count
    self.recipeCount = count
    self.stopUnit = stopUnit
    return true
  end
  self.postCopper = nil
  self.postLine = nil
  self.postDecision = nil
  local person = action and action.person
  local opp = person and person.opp
  local lines = person and person.inputLines
  if not person or not opp or type(lines) ~= "table" then
    return false
  end
  local want = tonumber(action.buyItemID)
  local focus
  for i = 1, table.getn(lines) do
    local line = lines[i]
    if line and (line.buyUnits or 0) > 0 and not focus then
      if not want or tonumber(line.itemID) == want then
        focus = line
      end
    end
  end
  if not focus then
    return false
  end
  local other = 0
  for i = 1, table.getn(lines) do
    local line = lines[i]
    if line and line ~= focus then
      other = other + costOfCount(line.itemID, line.count)
    end
  end
  local count = tonumber(focus.count) or 1
  if count < 1 then
    count = 1
  end
  self.stopUnit = self.UnitStop(tonumber(opp.netRevenue) or 0, other, count)
  self.recipeCount = count
  self.remaining = focus.buyUnits or 0
  self.itemID = focus.itemID
  local name = ""
  if focus.itemID and OnyxiaGold.Data and OnyxiaGold.Data.GetItemName then
    name = OnyxiaGold.Data.GetItemName(focus.itemID) or ""
  end
  self.queryName = name

  local crafts = person.sensibleCrafts or 0
  local inputCost = 0
  if crafts > 0 then
    inputCost = math.floor((person.economicInputValue or 0) / crafts)
  end
  local outCount = tonumber(opp.outputCount) or 1
  local expected = tonumber(opp.expectedOutput) or 1
  if expected <= 0 then
    expected = 1
  end
  local per = outCount * expected
  local vendor = 0
  local outID = opp.outputItemIDs and opp.outputItemIDs[1]
  if outID and type(GetItemInfo) == "function" then
    local info = { GetItemInfo(outID) }
    vendor = tonumber(info[11]) or 0
  end
  local unit = self.PostFloorUnit(inputCost, per, vendor)
  local decided = self.DecidePost(outID, unit, 1)
  self.postCopper = decided and decided.postCopper or nil
  self.postLine = decided and decided.line or nil
  self.postDecision = decided and decided.decision or nil
  return true
end

function Stop:SendQuery()
  if not self.paging then
    return
  end
  if (self.page or 0) >= PAGE_CAP then
    self.paging = false
    return
  end
  if OnyxiaGold.Scanner and OnyxiaGold.Scanner.IsScanning and OnyxiaGold.Scanner:IsScanning() then
    return
  end
  if type(QueryAuctionItems) ~= "function" then
    return
  end
  if not queryAllowed() then
    return
  end
  QueryAuctionItems(self.queryName or "", nil, nil, nil, nil, nil, self.page or 0, nil, nil)
end

function Stop:OnListUpdate()
  if self:BuyListening() then
    -- One row for a Buy the player already clicked. Not a plan rebuild.
    self:OnBuyList()
    return
  end
  if self.postCheck then
    self:FinishPostCheck()
    return
  end
  if not self.paging then
    return
  end
  if OnyxiaGold.Scanner and OnyxiaGold.Scanner.IsScanning and OnyxiaGold.Scanner:IsScanning() then
    return
  end
  if type(GetNumAuctionItems) ~= "function" or type(GetAuctionItemInfo) ~= "function" then
    self.paging = false
    return
  end
  local rows = self:CapturePageRows()
  local decision = self.JudgePage(rows, self.page, PAGE_CAP)
  self:PaintCaptured(rows)
  if decision.queryNext and (self.page or 0) + 1 < PAGE_CAP then
    self.page = (self.page or 0) + 1
    self.paging = true
    self:SendQuery()
  else
    self.paging = false
  end
end

function Stop:OnHouseShown()
  -- Do not bind a row, query, page, or fill a post price.
  self.paging = false
  if OnyxiaGold.Scanner and OnyxiaGold.Scanner.IsScanning and OnyxiaGold.Scanner:IsScanning() then
    return
  end
  local clock = OnyxiaGold.RefreshSchedule
  if clock and clock.Push then
    local now = 0
    if type(GetTime) == "function" then
      now = tonumber(GetTime()) or 0
    end
    clock:Push(now, "ui", "ah-show")
  end
end

function Stop:BeginPostCheck(itemID, name)
  itemID = tonumber(itemID)
  if not itemID or type(name) ~= "string" or name == "" then
    return false
  end
  if type(QueryAuctionItems) ~= "function" then
    return false
  end
  if self:BuyListening() then
    return false
  end
  self.postCheck = { itemID = itemID, name = name }
  self.postCheckItem = itemID
  self.paging = false
  QueryAuctionItems(name, nil, nil, nil, nil, nil, 0, nil, nil)
  return true
end

function Stop:FinishPostCheck()
  if not self:ListReady() then
    return
  end
  local check = self.postCheck
  self.postCheck = nil
  if not check then
    return
  end
  local saved = self.itemID
  self.itemID = check.itemID
  local rows = self:ReadLiveRows()
  self.itemID = saved
  local minUnit
  for i = 1, table.getn(rows) do
    local row = rows[i]
    local count = tonumber(row.count) or 0
    local buyout = tonumber(row.buyout) or 0
    if count > 0 and buyout > 0 then
      local unit = math.floor(buyout / count)
      if unit > 0 and (not minUnit or unit < minUnit) then
        minUnit = unit
      end
    end
  end
  local now = 0
  if type(GetTime) == "function" then
    now = tonumber(GetTime()) or 0
  elseif type(time) == "function" then
    now = time()
  end
  self.livePost = {
    itemID = check.itemID,
    marketMinimum = minUnit,
    at = now,
  }
  local clock = OnyxiaGold.RefreshSchedule
  if clock and clock.Push then
    clock:Push(now, "ui", "post-check")
  end
end

function Stop:LivePostFresh(itemID)
  local live = self.livePost
  itemID = tonumber(itemID)
  if not live or live.itemID ~= itemID or not live.marketMinimum then
    return nil
  end
  local now = 0
  if type(GetTime) == "function" then
    now = tonumber(GetTime()) or 0
  elseif type(time) == "function" then
    now = time()
  end
  if now - (tonumber(live.at) or 0) > 20 then
    return nil
  end
  return live
end

local frame = CreateFrame("Frame")
Stop.frame = frame
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:SetScript("OnEvent", function(_, event)
  if event == "AUCTION_HOUSE_SHOW" then
    Stop:OnHouseShown()
  elseif event == "AUCTION_ITEM_LIST_UPDATE" then
    Stop:OnListUpdate()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    Stop.paging = false
    Stop.ignoreEmpty = false
    Stop.postCheck = nil
    if Stop.buyActionIndex then
      Stop.buyPhase = "idle"
      Stop.offer = nil
      Stop.buyStatus = "closed"
      Stop:RefreshBuyRow()
    end
  end
end)
