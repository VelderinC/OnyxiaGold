--[[
  OnyxiaGold.AuctionStop
  Stop price for the auction page he is looking at.

  Marks each row under the stop, over it, a bid, or a scrap.
  Fills a post price at or above the floor. He presses Blizzard's button.
  Query stops when the visible page is entirely over the stop.
  This view queries one item name, page by page, and only from auction events.
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

  if recipeCount > 1 and count < recipeCount then
    return {
      verb = "scrap",
      overStop = false,
      loss = 0,
      locksCash = false,
      line = string.format(
        "Scrap · stack %d cannot fill a recipe of %d · stop %s · %d more",
        count, recipeCount, stopText, remaining
      ),
    }
  end

  local hasBuyout = buyout > 0
  local unit = hasBuyout and math.floor(buyout / count) or 0
  local bidUnit = math.floor(current / count)
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

function Stop.JudgePage(rows)
  local n = table.getn(rows or {})
  if n < 1 then
    return { queryNext = false, paging = false }
  end
  for i = 1, n do
    if not rows[i].overStop then
      return { queryNext = true, paging = true }
    end
  end
  return { queryNext = false, paging = false }
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
  if session and session.IsActive and session:IsActive() and session.AcquisitionCost then
    local part = session:AcquisitionCost(itemID, count)
    if part then
      return part
    end
  end
  if OnyxiaGold.Prices and OnyxiaGold.Prices.GetAcquisitionCost then
    local part = OnyxiaGold.Prices:GetAcquisitionCost(itemID, count)
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
  self.postCopper = nil
  local person = action and action.person
  local opp = person and person.opp
  local lines = person and person.inputLines
  if not person or not opp or type(lines) ~= "table" then
    return false
  end
  local focus
  for i = 1, table.getn(lines) do
    local line = lines[i]
    if line and (line.buyUnits or 0) > 0 and not focus then
      focus = line
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
  self.postCopper = self.PostBuyout(unit, 1)
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
  local n = tonumber(GetNumAuctionItems("list")) or 0
  local rows = {}
  for i = 1, n do
    local _, _, count, _, _, _, minBid, _, buyout, bidAmount = GetAuctionItemInfo("list", i)
    table.insert(rows, self.Classify({
      count = tonumber(count) or 1,
      minBid = tonumber(minBid) or 0,
      buyout = tonumber(buyout) or 0,
      bidAmount = tonumber(bidAmount) or 0,
    }, self.stopUnit or 0, self.recipeCount or 1, self.remaining or 0))
  end
  self.pageRows = rows
  local decision = self.JudgePage(rows)
  if OnyxiaGold.UI and OnyxiaGold.UI.PaintAuctionPage then
    OnyxiaGold.UI:PaintAuctionPage({ rows = rows })
  end
  if decision.queryNext and (self.page or 0) + 1 < PAGE_CAP then
    self.page = (self.page or 0) + 1
    self.paging = true
    self:SendQuery()
  else
    self.paging = false
  end
end

function Stop:OnHouseShown()
  if OnyxiaGold.Scanner and OnyxiaGold.Scanner.IsScanning and OnyxiaGold.Scanner:IsScanning() then
    return
  end
  if OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.Refresh then
    OnyxiaGold.ActionPlanner:Refresh()
  end
  local actions = {}
  if OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.GetActions then
    actions = OnyxiaGold.ActionPlanner:GetActions() or {}
  end
  local bound = false
  for i = 1, table.getn(actions) do
    if self:Bind(actions[i]) then
      bound = true
      break
    end
  end
  if not bound then
    self.paging = false
    return
  end
  self.page = 0
  self.paging = true
  self:SendQuery()
  if self.postCopper and OnyxiaGold.UI and OnyxiaGold.UI.ApplyPostPrice then
    OnyxiaGold.UI:ApplyPostPrice(self.postCopper)
  end
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
  end
end)
