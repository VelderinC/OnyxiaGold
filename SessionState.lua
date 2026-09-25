--[[
  OnyxiaGold.SessionState
  One planning pass over virtual cash, virtual bags, and a cloned buyout book.

  ActionPlanner rebuilds this on every Refresh. Selecting an action reserves
  its cash, the bag units it uses, and the auction units it would buy.
  The next action sees what remains.

  The saved market snapshot is never written. Quotes walk the clone only.
  A buy takes whole auction lots. Purchased units enter the virtual bags,
  the recipe consumes what it needs, and the excess stays for the next action.
  Output units already planned are remembered here so the next action sees
  a thinner visible book. That count is not a sale rate.
  Bank stock is not treated as bag stock. Cooldown groups are marked used
  for this plan only; no timing numbers are invented.
  A purchase slot is freed when that same action crafts the reagent away.
  Leftover units from a whole lot keep the slots they still occupy, so the
  next action cannot use those slots. Peak occupancy for the action is
  recorded on bagPeak.
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
  self.outputUsed = {}
  self.bagSlotsUsed = 0
  self.bagPeak = 0
  self.heldSlots = 0
  self.freeSlots = nil
  self.stackSizes = {}
  self.basis = {}
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
-- Whole auctions only. A covered cut does not invent a partial stack.
local function cloneCoveredDepth(depth, covered)
  if OnyxiaGold.Lots and OnyxiaGold.Lots.WholeLevels then
    return OnyxiaGold.Lots.WholeLevels(depth, covered)
  end
  return {}, 0
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
  local inv = OnyxiaGold.Inventory
  if inv and inv.GetFreeGeneralSlots then
    self.freeSlots = inv:GetFreeGeneralSlots()
  end
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

function Session:BagSlotsUsed()
  return self.bagSlotsUsed or 0
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

-- Visible output left after earlier actions in this plan. Does not write the snapshot.
function Session:RemainingOutput(itemID, visible)
  visible = tonumber(visible) or 0
  itemID = tonumber(itemID)
  if not self.active or not itemID then
    return visible
  end
  local left = visible - (self.outputUsed[itemID] or 0)
  if left < 0 then
    left = 0
  end
  return left
end

function Session:CooldownUsed(group)
  if not group or not self.active then
    return false
  end
  return self.cooldowns[group] and true or false
end

function Session:StackSize(itemID)
  itemID = tonumber(itemID)
  if self.stackSizes and itemID and self.stackSizes[itemID] then
    local stored = tonumber(self.stackSizes[itemID])
    if stored and stored > 0 then
      return stored
    end
  end
  local inv = OnyxiaGold.Inventory
  if inv and inv.GetStackSize then
    return inv:GetStackSize(itemID)
  end
  return nil
end

-- Room left in a stack already in the virtual bags. Nil stack means unknown.
function Session:PartialRoom(itemID, stack)
  stack = tonumber(stack)
  if not stack or stack < 1 then
    return 0
  end
  local have = self:GetBagCount(itemID)
  if have <= 0 then
    return 0
  end
  local rem = have % stack
  if rem == 0 then
    return 0
  end
  return stack - rem
end

-- Nil means the bag limit is unknown and must not cut a buy.
function Session:SlotsLeft()
  if self.freeSlots == nil then
    return nil
  end
  local left = (tonumber(self.freeSlots) or 0) - (tonumber(self.heldSlots) or 0)
  if left < 0 then
    left = 0
  end
  return left
end

local function stacksOccupied(units, stack)
  units = tonumber(units) or 0
  stack = tonumber(stack)
  if not stack or stack < 1 or units <= 0 then
    return 0
  end
  return math.floor((units + stack - 1) / stack)
end

function Session:BuyConstraints(itemID, capital)
  local constraints = {}
  if capital ~= nil then
    constraints.capital = capital
  end
  local left = self:SlotsLeft()
  if left ~= nil then
    constraints.freeSlots = left
  else
    local inv = OnyxiaGold.Inventory
    if inv and inv.GetFreeGeneralSlots then
      local free = inv:GetFreeGeneralSlots()
      if free ~= nil then
        constraints.freeSlots = free
      end
    end
  end
  local stack = self:StackSize(itemID)
  if stack then
    constraints.stackSize = stack
    constraints.partialRoom = self:PartialRoom(itemID, stack)
  end
  return constraints
end

function Session:QuoteBook(book, quantity, capital, itemID)
  quantity = math.floor(tonumber(quantity) or 0)
  book = book or { levels = {}, covered = 0 }
  if capital == nil then
    capital = self.cash
  end
  local constraints = self:BuyConstraints(itemID, capital)
  local quote
  if OnyxiaGold.Lots and OnyxiaGold.Lots.Quote then
    quote = OnyxiaGold.Lots.Quote(book.levels, quantity, constraints)
  else
    quote = {
      requestedUnits = quantity,
      purchasedUnits = 0,
      consumedUnits = 0,
      excessUnits = 0,
      cashRequired = 0,
      economicConsumedCost = 0,
      leftoverAssetValue = 0,
      selectedLots = {},
      complete = quantity <= 0,
      totalCost = 0,
      filledQuantity = 0,
    }
  end
  quote.depthCoveredQuantity = book.covered or 0
  return quote
end

function Session:Quote(itemID, quantity, capital)
  return self:QuoteBook(self:EnsureDepth(itemID), quantity, capital, itemID)
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
  return quote.cashRequired or quote.totalCost
end

function Session:EconomicCost(itemID, quantity)
  quantity = tonumber(quantity) or 0
  if quantity <= 0 then
    return 0
  end
  local quote = self:Quote(itemID, quantity)
  if not quote.complete then
    return nil
  end
  return quote.economicConsumedCost
end

local function copyBook(book)
  local levels = {}
  local source = book and book.levels or {}
  for i = 1, table.getn(source) do
    local lvl = source[i]
    levels[i] = {
      p = lvl.p,
      q = lvl.q,
      n = lvl.n,
      s = lvl.s,
    }
  end
  return { levels = levels, covered = book and book.covered or 0 }
end

local function consumeLots(book, selected)
  for i = 1, table.getn(selected or {}) do
    local lot = selected[i]
    local lvl = lot and book.levels[lot.level]
    local size = lot and tonumber(lot.s) or 0
    if not lvl or size < 1 or (lvl.q or 0) < size or (lvl.n or 0) < 1 then
      return false
    end
    lvl.n = lvl.n - 1
    lvl.q = lvl.q - size
    book.covered = (book.covered or 0) - size
  end
  local kept = {}
  local covered = 0
  for i = 1, table.getn(book.levels) do
    local lvl = book.levels[i]
    if lvl and (lvl.q or 0) > 0 and (lvl.n or 0) > 0 then
      table.insert(kept, lvl)
      covered = covered + lvl.q
    end
  end
  book.levels = kept
  book.covered = covered
  if book.covered < 0 then
    book.covered = 0
  end
  return true
end

local function reservationLines(spec)
  if type(spec.inputs) == "table" and table.getn(spec.inputs) > 0 then
    return spec.inputs
  end
  local ownedUnits = tonumber(spec.ownedUnits) or 0
  local buyUnits = tonumber(spec.buyUnits) or 0
  local itemID = tonumber(spec.itemID)
  if itemID or ownedUnits > 0 or buyUnits > 0 then
    return {
      { itemID = itemID, ownedUnits = ownedUnits, buyUnits = buyUnits },
    }
  end
  return {}
end

function Session:Reserve(spec)
  spec = spec or {}
  if not self.active then
    return false
  end
  local cash = tonumber(spec.cash) or 0
  if cash < 0 or cash > self.cash then
    return false
  end
  if spec.cooldown and self.cooldowns[spec.cooldown] then
    return false
  end

  local lines = reservationLines(spec)
  local normalized = {}
  local scratch = {}
  local beforeBags = {}
  local bags = {}
  for itemID, count in pairs(self.bags or {}) do
    beforeBags[itemID] = count
    bags[itemID] = count
  end
  local leftCash = self.cash
  local quotedCash = 0
  local buyCount = 0
  for i = 1, table.getn(lines) do
    local line = lines[i] or {}
    local itemID = tonumber(line.itemID)
    local ownedUnits = tonumber(line.ownedUnits) or 0
    local buyUnits = tonumber(line.buyUnits) or 0
    if ownedUnits < 0 or buyUnits < 0 then
      return false
    end
    if ownedUnits > 0 then
      if not itemID or (bags[itemID] or 0) < ownedUnits then
        return false
      end
      bags[itemID] = bags[itemID] - ownedUnits
    end
    local purchased = 0
    local consumed = 0
    local excess = 0
    local selected = nil
    if buyUnits > 0 then
      if not itemID then
        return false
      end
      local book = scratch[itemID]
      if not book then
        book = copyBook(self:EnsureDepth(itemID))
        scratch[itemID] = book
      end
      local quote = self:QuoteBook(book, buyUnits, leftCash, itemID)
      if not quote.complete then
        return false
      end
      if not consumeLots(book, quote.selectedLots) then
        return false
      end
      purchased = quote.purchasedUnits or 0
      consumed = quote.consumedUnits or 0
      excess = quote.excessUnits or 0
      selected = quote.selectedLots
      local part = quote.cashRequired or 0
      quotedCash = quotedCash + part
      leftCash = leftCash - part
      buyCount = buyCount + 1
      bags[itemID] = (bags[itemID] or 0) + purchased - consumed
    end
    if bags[itemID] and bags[itemID] <= 0 then
      bags[itemID] = nil
    end
    table.insert(normalized, {
      itemID = itemID,
      ownedUnits = ownedUnits,
      buyUnits = buyUnits,
      purchasedUnits = purchased,
      consumedUnits = consumed,
      excessUnits = excess,
      selectedLots = selected,
    })
  end
  if buyCount > 0 and cash ~= quotedCash then
    return false
  end
  if self.freeSlots ~= nil then
    local needSlots = 0
    local known = true
    for i = 1, table.getn(normalized) do
      local line = normalized[i]
      local bought = tonumber(line.purchasedUnits) or 0
      if bought > 0 then
        local stack = self:StackSize(line.itemID)
        if not stack or stack < 1 then
          known = false
          break
        end
        local partial = self:PartialRoom(line.itemID, stack)
        local spill = bought - partial
        if spill < 0 then
          spill = 0
        end
        needSlots = needSlots + math.floor((spill + stack - 1) / stack)
      end
    end
    local left = self:SlotsLeft() or 0
    if known and needSlots > left then
      return false
    end
  end

  for itemID, book in pairs(scratch) do
    self.depth[itemID] = book
  end
  self.bags = bags
  if self.freeSlots ~= nil then
    local seen = {}
    for itemID in pairs(beforeBags) do
      seen[itemID] = true
    end
    for itemID in pairs(bags) do
      seen[itemID] = true
    end
    for itemID in pairs(seen) do
      local stack = self:StackSize(itemID)
      if stack and stack > 0 then
        local oldSlots = stacksOccupied(beforeBags[itemID], stack)
        local newSlots = stacksOccupied(bags[itemID], stack)
        self.heldSlots = (self.heldSlots or 0) + (newSlots - oldSlots)
      end
    end
  end
  self.cash = self.cash - cash
  self.spent = self.spent + cash
  local itemID = normalized[1] and normalized[1].itemID or nil
  local ownedUnits = normalized[1] and normalized[1].ownedUnits or 0
  local buyUnits = normalized[1] and normalized[1].buyUnits or 0
  if spec.cooldown then
    self.cooldowns[spec.cooldown] = true
  end
  local outputID = tonumber(spec.outputItemID)
  local outputUnits = tonumber(spec.outputUnits) or 0
  if outputID and outputUnits > 0 then
    self.outputUsed[outputID] = (self.outputUsed[outputID] or 0) + outputUnits
  end
  local bagSlots = tonumber(spec.bagSlots) or 0
  if bagSlots > (self.bagPeak or 0) then
    self.bagPeak = bagSlots
  end
  -- Purchase slots are freed when the same action consumes the reagents.
  -- They are not subtracted from the next action.
  table.insert(self.reserved, {
    itemID = itemID,
    cash = cash,
    ownedUnits = ownedUnits,
    buyUnits = buyUnits,
    inputs = normalized,
    cooldown = spec.cooldown,
    outputItemID = outputID,
    outputUnits = outputUnits,
    bagSlots = bagSlots,
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
