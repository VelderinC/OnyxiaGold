--[[
  OnyxiaGold.SessionState
  One planning pass over virtual cash, virtual bags, and a cloned buyout book.

  ActionPlanner rebuilds this on every Refresh. Selecting an action reserves
  its cash, the bag units it uses, and the auction units it would buy.
  The next action sees what remains.

  The saved market snapshot is never written. Quotes walk the clone only.
  Bank stock is not treated as bag stock. Cooldown groups are marked used
  for this plan only; no timing numbers are invented.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.SessionState = OnyxiaGold.SessionState or {}

local Session = OnyxiaGold.SessionState

function Session:Reset()
  self.active = false
  self.cash = 0
  self.spent = 0
  self.baseDeployable = 0
  self.baseAfterMail = 0
  self.bags = {}
  self.depth = {}
  self.reserved = {}
  self.cooldowns = {}
end

Session:Reset()

local function copyBagSnapshot()
  local bags = {}
  local row = OnyxiaGold.Database and OnyxiaGold.Database:GetCharacter()
  local source = row and row.inventory and row.inventory.bags
  if type(source) ~= "table" then
    return bags
  end
  for itemID, count in pairs(source) do
    local id = tonumber(itemID)
    local n = tonumber(count) or 0
    if id and n > 0 then
      bags[id] = n
    end
  end
  return bags
end

-- New level tables. Callers must not pass these back into the database.
local function cloneCoveredDepth(depth, covered)
  local levels = {}
  local left = tonumber(covered) or 0
  local sum = 0
  if type(depth) ~= "table" or left <= 0 then
    return levels, 0
  end
  for i = 1, table.getn(depth) do
    if left <= 0 then
      break
    end
    local lvl = depth[i]
    local p = lvl and (lvl.p or lvl.unitPrice)
    local q = lvl and (lvl.q or lvl.quantity)
    local n = (lvl and (lvl.n or lvl.auctions)) or 1
    if p and p > 0 and q and q > 0 then
      local use = q
      if use > left then
        use = left
      end
      table.insert(levels, { p = p, q = use, n = n })
      sum = sum + use
      left = left - use
    end
  end
  return levels, sum
end

function Session:Begin(deployable, afterMailDeployable)
  self:Reset()
  self.active = true
  self.cash = tonumber(deployable) or 0
  if self.cash < 0 then
    self.cash = 0
  end
  self.baseDeployable = self.cash
  self.baseAfterMail = tonumber(afterMailDeployable) or self.cash
  if self.baseAfterMail < 0 then
    self.baseAfterMail = 0
  end
  self.bags = copyBagSnapshot()
  return self
end

function Session:IsActive()
  return self.active and true or false
end

function Session:RemainingCash()
  return self.cash or 0
end

function Session:SpentCash()
  return self.spent or 0
end

-- Post-collection deployable minus gold this plan has already reserved.
function Session:AfterMailCash()
  local left = (self.baseAfterMail or 0) - (self.spent or 0)
  if left < 0 then
    left = 0
  end
  return left
end

function Session:GetBagCount(itemID)
  itemID = tonumber(itemID)
  if not itemID then
    return 0
  end
  if not self.active then
    if OnyxiaGold.Inventory and OnyxiaGold.Inventory.GetImmediatelyAvailableCount then
      return OnyxiaGold.Inventory:GetImmediatelyAvailableCount(itemID) or 0
    end
    return 0
  end
  return self.bags[itemID] or 0
end

function Session:EnsureDepth(itemID)
  itemID = tonumber(itemID)
  if not itemID then
    return { levels = {}, covered = 0 }
  end
  local book = self.depth[itemID]
  if book then
    return book
  end
  local src
  local covered = 0
  if OnyxiaGold.Prices then
    if OnyxiaGold.Prices.GetDepth then
      src = OnyxiaGold.Prices:GetDepth(itemID)
    end
    if OnyxiaGold.Prices.GetDepthCoveredQuantity then
      covered = OnyxiaGold.Prices:GetDepthCoveredQuantity(itemID) or 0
    end
  end
  local levels, sum = cloneCoveredDepth(src, covered)
  book = { levels = levels, covered = sum }
  self.depth[itemID] = book
  return book
end

function Session:CoveredQuantity(itemID)
  if not self.active then
    if OnyxiaGold.Prices and OnyxiaGold.Prices.GetDepthCoveredQuantity then
      return OnyxiaGold.Prices:GetDepthCoveredQuantity(itemID) or 0
    end
    return 0
  end
  return self:EnsureDepth(itemID).covered or 0
end

function Session:CooldownUsed(group)
  if not group or not self.active then
    return false
  end
  return self.cooldowns[group] and true or false
end

function Session:Quote(itemID, quantity)
  quantity = math.floor(tonumber(quantity) or 0)
  local book = self:EnsureDepth(itemID)
  local covered = book.covered or 0
  local quote = {
    requestedQuantity = quantity,
    filledQuantity = 0,
    totalCost = 0,
    averageUnitCost = nil,
    marginalUnitCost = nil,
    levelsConsumed = 0,
    complete = false,
    depthCoveredQuantity = covered,
  }
  if quantity <= 0 then
    quote.complete = true
    quote.averageUnitCost = 0
    quote.totalCost = 0
    return quote
  end
  local levels = book.levels
  if type(levels) ~= "table" or covered <= 0 then
    return quote
  end
  local need = quantity
  for i = 1, table.getn(levels) do
    if need <= 0 then
      break
    end
    local lvl = levels[i]
    local p = lvl and lvl.p
    local q = lvl and lvl.q
    if p and p > 0 and q and q > 0 then
      local take = q
      if take > need then
        take = need
      end
      quote.totalCost = quote.totalCost + take * p
      quote.filledQuantity = quote.filledQuantity + take
      quote.marginalUnitCost = p
      quote.levelsConsumed = quote.levelsConsumed + 1
      need = need - take
    end
  end
  if quote.filledQuantity > 0 then
    quote.averageUnitCost = math.floor(quote.totalCost / quote.filledQuantity)
  end
  quote.complete = (quantity <= covered) and (quote.filledQuantity >= quantity)
  return quote
end

function Session:AcquisitionCost(itemID, quantity)
  quantity = tonumber(quantity) or 0
  if quantity <= 0 then
    return 0
  end
  local quote = self:Quote(itemID, quantity)
  if not quote.complete then
    return nil
  end
  return quote.totalCost
end

local function consumeDepth(book, quantity)
  local need = math.floor(tonumber(quantity) or 0)
  if need <= 0 then
    return true
  end
  if (book.covered or 0) < need then
    return false
  end
  local i = 1
  local n = table.getn(book.levels)
  while i <= n and need > 0 do
    local lvl = book.levels[i]
    local q = lvl and lvl.q or 0
    if q <= 0 then
      table.remove(book.levels, i)
      n = n - 1
    elseif q > need then
      lvl.q = q - need
      book.covered = book.covered - need
      need = 0
    else
      need = need - q
      book.covered = book.covered - q
      table.remove(book.levels, i)
      n = n - 1
    end
  end
  if book.covered < 0 then
    book.covered = 0
  end
  return need == 0
end

function Session:Reserve(spec)
  spec = spec or {}
  if not self.active then
    return false
  end
  local cash = tonumber(spec.cash) or 0
  local ownedUnits = tonumber(spec.ownedUnits) or 0
  local buyUnits = tonumber(spec.buyUnits) or 0
  local itemID = tonumber(spec.itemID)
  if cash < 0 or ownedUnits < 0 or buyUnits < 0 then
    return false
  end
  if cash > self.cash then
    return false
  end
  if ownedUnits > 0 then
    if not itemID or (self.bags[itemID] or 0) < ownedUnits then
      return false
    end
  end
  if buyUnits > 0 then
    if not itemID then
      return false
    end
    local quote = self:Quote(itemID, buyUnits)
    if not quote.complete then
      return false
    end
  end
  if spec.cooldown and self.cooldowns[spec.cooldown] then
    return false
  end

  if buyUnits > 0 then
    local book = self:EnsureDepth(itemID)
    if not consumeDepth(book, buyUnits) then
      return false
    end
  end
  self.cash = self.cash - cash
  self.spent = self.spent + cash
  if ownedUnits > 0 then
    self.bags[itemID] = self.bags[itemID] - ownedUnits
    if self.bags[itemID] <= 0 then
      self.bags[itemID] = nil
    end
  end
  if spec.cooldown then
    self.cooldowns[spec.cooldown] = true
  end
  table.insert(self.reserved, {
    itemID = itemID,
    cash = cash,
    ownedUnits = ownedUnits,
    buyUnits = buyUnits,
    cooldown = spec.cooldown,
  })
  if OnyxiaGold.Log and OnyxiaGold.Log.Debug then
    OnyxiaGold.Log:Debug("Session", string.format(
      "reserve item=%s cash=%d owned=%d buy=%d leftCash=%d leftBag=%d leftDepth=%d",
      tostring(itemID), cash, ownedUnits, buyUnits, self.cash,
      itemID and (self.bags[itemID] or 0) or 0,
      itemID and self:CoveredQuantity(itemID) or 0
    ))
  end
  return true
end
