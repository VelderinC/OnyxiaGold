--[[
  OnyxiaGold.SessionPlan
  One ordered session. It can hold more than one craft when they do not
  need the same gold, the same bag slots, the same auction lots, or the
  same cooldown. A flip is a whole-lot resale, not a craft: buy that lot,
  then post it. It spends current gold, including the deposit, and it does
  not take a lot a craft already reserved.

  Each craft stays in its own order: buy the whole lots, then craft, then
  post. A later sale is not added to the purse, so it cannot pay for a buy.
  This file does not choose auction lots. Quotes go through SessionState,
  which calls Lots.Select.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.SessionPlan = OnyxiaGold.SessionPlan or {}

local Plan = OnyxiaGold.SessionPlan

local function nitems(t)
  if type(t) ~= "table" then
    return 0
  end
  if table.getn then
    return table.getn(t)
  end
  return 0
end

function Plan.Plain(copper)
  copper = tonumber(copper) or 0
  local negative = copper < 0
  if negative then
    copper = -copper
  end
  copper = math.floor(copper + 0.5)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local text
  if g > 0 and s > 0 and c > 0 then
    text = string.format("%dg %ds %dc", g, s, c)
  elseif g > 0 and s > 0 then
    text = string.format("%dg %ds", g, s)
  elseif g > 0 and c > 0 then
    text = string.format("%dg %dc", g, c)
  elseif g > 0 then
    text = string.format("%dg", g)
  elseif s > 0 and c > 0 then
    text = string.format("%ds %dc", s, c)
  elseif s > 0 then
    text = string.format("%ds", s)
  else
    text = string.format("%dc", c)
  end
  if negative then
    return "-" .. text
  end
  return text
end

function Plan.Signed(copper)
  copper = tonumber(copper) or 0
  if copper > 0 then
    return "+" .. Plan.Plain(copper)
  end
  return Plan.Plain(copper)
end

local function orderWithin(steps)
  local buy, craft, post = {}, {}, {}
  for i = 1, nitems(steps) do
    local step = steps[i]
    local role = step and step.role
    if role == "buy" then
      table.insert(buy, step)
    elseif role == "post" then
      table.insert(post, step)
    elseif role == "craft" then
      table.insert(craft, step)
    end
  end
  local ordered = {}
  for i = 1, nitems(buy) do
    table.insert(ordered, buy[i])
  end
  for i = 1, nitems(craft) do
    table.insert(ordered, craft[i])
  end
  for i = 1, nitems(post) do
    table.insert(ordered, post[i])
  end
  return ordered
end

-- Steps that share a craft id stay together. Inside one craft the order
-- is buy, then craft, then post. A missing id is one craft, which is how
-- a single-craft session was already written.
local function orderSteps(steps)
  local groups = {}
  local order = {}
  for i = 1, nitems(steps) do
    local step = steps[i]
    local key = step and step.craft
    if key == nil then
      key = 0
    end
    if not groups[key] then
      groups[key] = {}
      table.insert(order, key)
    end
    table.insert(groups[key], step)
  end
  local ordered = {}
  for g = 1, nitems(order) do
    local part = orderWithin(groups[order[g]])
    for i = 1, nitems(part) do
      table.insert(ordered, part[i])
    end
  end
  return ordered
end

-- Buy steps spend the purse. Craft and post steps do not put their
-- sale proceeds back into that purse.
function Plan.Compose(spec)
  spec = spec or {}
  local cash = tonumber(spec.cash) or 0
  if cash < 0 then
    cash = 0
  end
  local ignored = tonumber(spec.saleProceeds) or 0
  local ordered = orderSteps(spec.steps)
  for i = 1, nitems(ordered) do
    ignored = ignored + (tonumber(ordered[i].proceeds) or 0)
  end
  local purse = cash
  local spent = 0
  local funded = {}
  local blocked = false
  for i = 1, nitems(ordered) do
    if blocked then
      break
    end
    local step = ordered[i]
    if step.role == "buy" then
      local need = (tonumber(step.cash) or 0) + (tonumber(step.hold) or 0)
      if need < 0 then
        need = 0
      end
      if need > purse then
        blocked = true
      else
        purse = purse - need
        spent = spent + need
        table.insert(funded, step)
      end
    else
      table.insert(funded, step)
    end
  end
  return {
    steps = funded,
    spent = spent,
    purse = purse,
    profit = tonumber(spec.profit) or 0,
    capitalDeployed = spent,
    activeSteps = nitems(funded),
    ignoredProceeds = ignored,
  }
end

function Plan.StepLine(step)
  if not step then
    return ""
  end
  local count = tonumber(step.count) or 0
  local name = step.name or "item"
  if step.role == "buy" then
    return string.format("Buy %d %s. Maximum spend %s.", count, name, Plan.Plain(step.cash))
  elseif step.role == "craft" then
    return string.format("Craft %d %s. %d to craft.", count, name, count)
  elseif step.role == "post" then
    local deposit = tonumber(step.deposit) or 0
    if deposit > 0 then
      return string.format("Post %d %s. Deposit %s.", count, name, Plan.Plain(deposit))
    end
    return string.format("Post %d %s. %d to post.", count, name, count)
  end
  return name
end

function Plan.NextLine(step, profit)
  if not step then
    return nil
  end
  local profitBit = "Expected session profit " .. Plan.Signed(profit) .. "."
  local count = tonumber(step.count) or 0
  local name = step.name or "item"
  if step.role == "buy" then
    return string.format("Buy %d %s. Maximum spend %s. %s", count, name, Plan.Plain(step.cash), profitBit)
  elseif step.role == "craft" then
    return string.format("Craft %d %s. %d to craft. %s", count, name, count, profitBit)
  elseif step.role == "post" then
    local deposit = tonumber(step.deposit) or 0
    if deposit > 0 then
      return string.format("Post %d %s. Deposit %s. %s", count, name, Plan.Plain(deposit), profitBit)
    end
    return string.format("Post %d %s. %d to post. %s", count, name, count, profitBit)
  end
  return nil
end

function Plan.WindowHint(step, opts)
  opts = opts or {}
  if not step then
    return nil
  end
  if step.role == "buy" or step.role == "post" then
    if opts.auctionOpen == false then
      return "Open the Auction House."
    end
  elseif step.role == "craft" then
    local profession = step.profession
    local open = opts.professionOpen
    if type(opts.professionShown) == "function" then
      open = opts.professionShown(profession) and true or false
    end
    if open == false and type(profession) == "string" and profession ~= "" then
      return "Open " .. profession .. "."
    end
  end
  return nil
end

function Plan.Present(spec)
  local plan = Plan.Compose(spec)
  local steps = plan.steps
  for i = 1, nitems(steps) do
    local step = steps[i]
    local hint = Plan.WindowHint(step, spec)
    step.windowHint = hint
    step.line = Plan.StepLine(step)
    if hint then
      step.line = step.line .. " " .. hint
    end
  end
  local first = steps[1]
  plan.nextLine = Plan.NextLine(first, plan.profit)
  if plan.nextLine and first and first.windowHint then
    plan.nextLine = plan.nextLine .. " " .. first.windowHint
  end
  local counted = plan.activeSteps
  local word = "steps"
  if counted == 1 then
    word = "step"
  end
  plan.summaryLine = string.format(
    "Capital deployed %s. %d %s.",
    Plan.Plain(plan.spent),
    counted,
    word
  )
  return plan
end

-- Whole-lot counts and cash are already on the action. Crafts stay at
-- the count the marginal rule kept. A post is only added when the
-- breakdown already has output units to sell.
function Plan.StepsFromAction(action, names)
  names = names or {}
  local steps = {}
  if type(action) ~= "table" then
    return steps
  end
  local person = action.person
  local lines = person and person.inputLines
  for i = 1, nitems(lines) do
    local line = lines[i]
    if line then
      local purchased = tonumber(line.purchasedUnits) or 0
      local buyUnits = tonumber(line.buyUnits) or 0
      local cash = tonumber(line.buyCost) or 0
      local count = purchased
      if count < 1 then
        count = buyUnits
      end
      if count > 0 and (buyUnits > 0 or cash > 0) then
        local itemID = tonumber(line.itemID)
        table.insert(steps, {
          role = "buy",
          itemID = itemID,
          count = count,
          cash = cash,
          name = (itemID and names[itemID]) or line.name or "item",
          excessUnits = tonumber(line.excessUnits) or 0,
        })
      end
    end
  end
  local crafts = tonumber(action.crafts) or 0
  if crafts > 0 then
    local proceeds = 0
    if type(action.breakdown) == "table" then
      proceeds = tonumber(action.breakdown.proceeds) or 0
    end
    table.insert(steps, {
      role = "craft",
      count = crafts,
      name = names.output or action.outputName or "item",
      profession = names.profession or action.profession,
      proceeds = proceeds,
    })
  end
  local info = action.breakdown
  local postUnits = type(info) == "table" and tonumber(info.postUnits) or 0
  if postUnits and postUnits > 0 then
    table.insert(steps, {
      role = "post",
      count = postUnits,
      name = names.output or action.outputName or "item",
      cash = 0,
      itemID = tonumber(info.outputItemID),
      proceeds = tonumber(info.proceeds) or 0,
    })
  end
  return steps
end

function Plan.FlipSteps(found, groupId)
  if type(found) ~= "table" then
    return nil
  end
  local count = tonumber(found.count) or 0
  local cash = tonumber(found.cash) or 0
  local deposit = tonumber(found.deposit) or 0
  if count < 1 or cash < 1 or deposit < 0 then
    return nil
  end
  local name = found.name or "item"
  return {
    {
      role = "buy",
      flip = true,
      craft = groupId,
      itemID = found.itemID,
      count = count,
      cash = cash,
      hold = deposit,
      unit = found.unit,
      name = name,
    },
    {
      role = "post",
      flip = true,
      craft = groupId,
      itemID = found.itemID,
      count = count,
      cash = 0,
      deposit = deposit,
      saleUnit = found.saleUnit,
      name = name,
      proceeds = tonumber(found.proceeds) or 0,
    },
  }
end

local function supplies(buyer, user)
  if not buyer or not user then
    return false
  end
  local buys = buyer.buys or {}
  local uses = user.uses or {}
  local userBuys = user.buys or {}
  for id, on in pairs(uses) do
    if on and buys[id] and not userBuys[id] then
      return true
    end
  end
  return false
end

-- Higher priority first (a 20-hour cast), then higher profit. A craft that
-- only uses leftovers stays after the craft that buys that listing.
function Plan.ArrangeCrafts(groups)
  local sorted = {}
  for i = 1, nitems(groups) do
    sorted[i] = groups[i]
  end
  table.sort(sorted, function(a, b)
    local pa = tonumber(a.priority) or 0
    local pb = tonumber(b.priority) or 0
    if pa ~= pb then
      return pa > pb
    end
    local fa = tonumber(a.profit) or 0
    local fb = tonumber(b.profit) or 0
    if fa ~= fb then
      return fa > fb
    end
    return (tonumber(a.index) or 0) < (tonumber(b.index) or 0)
  end)
  local placed = {}
  local ordered = {}
  local function place(group, seen)
    if placed[group] or seen[group] then
      return
    end
    seen[group] = true
    for i = 1, nitems(sorted) do
      local other = sorted[i]
      if other ~= group and supplies(other, group) then
        place(other, seen)
      end
    end
    placed[group] = true
    table.insert(ordered, group)
  end
  for i = 1, nitems(sorted) do
    place(sorted[i], {})
  end
  return ordered
end

local function copyBook(book)
  local levels = {}
  local source = book and book.levels or {}
  for i = 1, nitems(source) do
    local lvl = source[i]
    if lvl then
      levels[i] = {
        p = lvl.p,
        q = lvl.q,
        n = lvl.n,
        s = lvl.s,
        own = lvl.own,
      }
    end
  end
  return { levels = levels, covered = book and book.covered or 0 }
end

local function basisCost(session, itemID, units)
  units = tonumber(units) or 0
  itemID = tonumber(itemID)
  if not itemID or units <= 0 then
    return 0
  end
  local have = session:GetBagCount(itemID)
  local basis = session.basis and session.basis[itemID] or 0
  if have <= 0 or basis <= 0 then
    return 0
  end
  if units > have then
    units = have
  end
  return math.floor(basis * units / have)
end

-- Price n crafts against the session without reserving. Nil when the lots,
-- the purse, or the bag slots cannot cover it. Marginal profit is the
-- caller's concern; this returns the economic profit of exactly n crafts.
local function priceCraft(session, candidate, crafts)
  local reagents = candidate.reagents or {}
  local net = tonumber(candidate.net) or 0
  local lines = {}
  local cash = 0
  local economic = 0
  local slotNeed = 0
  for i = 1, nitems(reagents) do
    local row = reagents[i]
    local itemID = tonumber(row.itemID)
    local count = tonumber(row.count) or 1
    if count < 1 then
      count = 1
    end
    if not itemID then
      return nil
    end
    local need = crafts * count
    local owned = session:GetBagCount(itemID)
    if owned > need then
      owned = need
    end
    if owned < 0 then
      owned = 0
    end
    local toBuy = need - owned
    local quote
    if toBuy > 0 then
      quote = session:Quote(itemID, toBuy)
      if not quote or not quote.complete then
        return nil
      end
    else
      quote = {
        complete = true,
        cashRequired = 0,
        economicConsumedCost = 0,
        purchasedUnits = 0,
        consumedUnits = 0,
        excessUnits = 0,
        leftoverAssetValue = 0,
      }
    end
    local bought = tonumber(quote.purchasedUnits) or 0
    if bought > 0 and session.freeSlots ~= nil then
      local stack = session:StackSize(itemID)
      if stack and stack > 0 then
        local partial = session:PartialRoom(itemID, stack)
        local spill = bought - partial
        if spill < 0 then
          spill = 0
        end
        slotNeed = slotNeed + math.floor((spill + stack - 1) / stack)
      end
    end
    cash = cash + (tonumber(quote.cashRequired) or 0)
    economic = economic + (tonumber(quote.economicConsumedCost) or 0)
    economic = economic + basisCost(session, itemID, owned)
    table.insert(lines, {
      itemID = itemID,
      name = row.name,
      ownedUnits = owned,
      buyUnits = toBuy,
      buyCost = tonumber(quote.cashRequired) or 0,
      purchasedUnits = bought,
      excessUnits = tonumber(quote.excessUnits) or 0,
      leftoverAssetValue = tonumber(quote.leftoverAssetValue) or 0,
    })
  end
  if cash > (session:RemainingCash() or 0) then
    return nil
  end
  local left = session:SlotsLeft()
  if left ~= nil and slotNeed > left then
    return nil
  end
  return {
    crafts = crafts,
    cash = cash,
    economic = economic,
    profit = crafts * net - economic,
    lines = lines,
  }
end

local function stepsForCraft(candidate, priced, craftId)
  local steps = {}
  local lines = priced.lines or {}
  for i = 1, nitems(lines) do
    local line = lines[i]
    local purchased = tonumber(line.purchasedUnits) or 0
    local buyUnits = tonumber(line.buyUnits) or 0
    local cash = tonumber(line.buyCost) or 0
    if purchased > 0 and (buyUnits > 0 or cash > 0) then
      table.insert(steps, {
        role = "buy",
        craft = craftId,
        itemID = line.itemID,
        count = purchased,
        cash = cash,
        name = line.name or "item",
        excessUnits = tonumber(line.excessUnits) or 0,
      })
    end
  end
  local crafts = tonumber(priced.crafts) or 0
  local net = tonumber(candidate.net) or 0
  local proceeds = crafts * net
  if crafts > 0 then
    table.insert(steps, {
      role = "craft",
      craft = craftId,
      count = crafts,
      name = candidate.output or candidate.name or "item",
      profession = candidate.profession,
      proceeds = proceeds,
    })
  end
  local per = tonumber(candidate.outputCount) or 1
  if per < 1 then
    per = 1
  end
  local postUnits = crafts * per
  if candidate.post == false then
    postUnits = 0
  end
  if postUnits > 0 then
    table.insert(steps, {
      role = "post",
      craft = craftId,
      count = postUnits,
      name = candidate.output or candidate.name or "item",
      cash = 0,
      itemID = tonumber(candidate.outputItemID),
      proceeds = proceeds,
    })
  end
  return steps
end

local function flipQuote(row)
  local Lots = OnyxiaGold.Lots
  local Book = OnyxiaGold.SessionState
  if not Lots or not Lots.FlipMargin or not Book or type(row) ~= "table" then
    return nil
  end
  local id = tonumber(row.itemID)
  local book = id and Book.depth and Book.depth[id]
  if not book then
    return nil
  end
  return Lots.FlipMargin({
    levels = book.levels,
    covered = book.covered,
    deposit = row.deposit,
    cutBPS = row.cutBPS,
    ownMinimum = row.ownMinimum,
    external = row.external,
    disenchant = row.disenchant,
    stale = row.stale,
    vendorUnit = row.vendorUnit,
    hours = row.hours,
    name = row.name,
    itemID = id,
  })
end

local function acceptFlip(row)
  local Book = OnyxiaGold.SessionState
  local found = flipQuote(row)
  if not Book or not found or (tonumber(found.profit) or 0) <= 0 then
    return nil
  end
  local quote = Book:Quote(found.itemID, found.count)
  if not quote or not quote.complete then
    return nil
  end
  local selected = quote.selectedLots or {}
  if nitems(selected) ~= 1 then
    return nil
  end
  local lot = selected[1]
  if lot.p ~= found.unit or lot.s ~= found.count then
    return nil
  end
  local cash = tonumber(quote.cashRequired) or 0
  if cash ~= found.cash then
    return nil
  end
  if cash + (tonumber(found.deposit) or 0) > (Book:RemainingCash() or 0) then
    return nil
  end
  local reserved = Book:Reserve({
    cash = cash,
    hold = found.deposit,
    retain = true,
    inputs = {
      { itemID = found.itemID, buyUnits = found.count },
    },
  })
  if not reserved then
    return nil
  end
  return found
end

-- candidates are crafts this character can already perform, plus flips.
-- profit is the sort key. net is one craft's sale after the cut and is
-- never purse cash. resources.depth is the covered buyout book. Two crafts
-- are both kept when their gold, bag slots, listings, and cooldown do not
-- collide. A craft is kept only while its own marginal profit stays positive.
-- A flip is buy, then post. It spends the deposit from current gold and
-- does not take a lot a craft already reserved.
function Plan.Portfolio(candidates, resources)
  resources = resources or {}
  local Session = OnyxiaGold.SessionState
  if not Session or not Session.Begin then
    return nil
  end
  local cash = tonumber(resources.cash) or 0
  if cash < 0 then
    cash = 0
  end
  Session:Begin(cash, cash)
  Session.bags = {}
  Session.basis = {}
  Session.depth = {}
  Session.stackSizes = {}
  Session.heldSlots = 0
  if resources.freeSlots == nil then
    Session.freeSlots = nil
  else
    Session.freeSlots = tonumber(resources.freeSlots) or 0
  end
  local bags = resources.bags or {}
  for itemID, count in pairs(bags) do
    local id = tonumber(itemID)
    local n = tonumber(count) or 0
    if id and n > 0 then
      Session.bags[id] = n
    end
  end
  local basis = resources.basis or {}
  for itemID, value in pairs(basis) do
    local id = tonumber(itemID)
    local n = tonumber(value) or 0
    if id and n > 0 then
      Session.basis[id] = n
    end
  end
  local depth = resources.depth or {}
  for itemID, book in pairs(depth) do
    local id = tonumber(itemID)
    if id and type(book) == "table" then
      Session.depth[id] = copyBook(book)
    end
  end
  local stacks = resources.stackSize or {}
  for itemID, size in pairs(stacks) do
    local id = tonumber(itemID)
    local n = tonumber(size) or 0
    if id and n > 0 then
      Session.stackSizes[id] = n
    end
  end
  local used = resources.cooldowns or {}
  for group, on in pairs(used) do
    if on then
      Session.cooldowns[group] = true
    end
  end

  local indexed = {}
  for i = 1, nitems(candidates) do
    local row = candidates[i]
    if type(row) == "table" then
      table.insert(indexed, { row = row, index = i })
    end
  end
  for i = 1, nitems(indexed) do
    local row = indexed[i].row
    if row.kind == "flip" then
      local found = flipQuote(row)
      if found then
        row.profit = found.profit
      else
        row.profit = 0
      end
    end
  end
  table.sort(indexed, function(a, b)
    local pa = tonumber(a.row.profit) or 0
    local pb = tonumber(b.row.profit) or 0
    if pa ~= pb then
      return pa > pb
    end
    return a.index < b.index
  end)

  local steps = {}
  local accepted = {}
  local flips = {}
  local profit = 0
  local proceeds = 0
  for i = 1, nitems(indexed) do
    local candidate = indexed[i].row
    local cooldown = candidate.cooldown
    local blocked = cooldown and Session:CooldownUsed(cooldown)
    local sortProfit = tonumber(candidate.profit) or 0
    if candidate.kind == "flip" then
      if sortProfit > 0 then
        local found = acceptFlip(candidate)
        if found then
          local groupId = nitems(accepted) + nitems(flips) + 1
          local flipped = Plan.FlipSteps(found, groupId)
          if flipped then
            for stepIndex = 1, nitems(flipped) do
              table.insert(steps, flipped[stepIndex])
            end
            table.insert(flips, {
              name = found.name,
              itemID = found.itemID,
              profit = found.profit,
              count = found.count,
            })
            profit = profit + found.profit
            proceeds = proceeds + (tonumber(found.proceeds) or 0)
          end
        end
      end
    elseif not blocked and sortProfit > 0 then
      local maxCrafts = tonumber(candidate.crafts) or 1
      if maxCrafts < 1 then
        maxCrafts = 1
      end
      local kept
      local previous = 0
      local n = 1
      while n <= maxCrafts do
        local priced = priceCraft(Session, candidate, n)
        if not priced then
          break
        end
        local marginal = priced.profit - previous
        if marginal <= 0 then
          break
        end
        kept = priced
        previous = priced.profit
        n = n + 1
      end
      if kept and kept.profit > 0 then
        local ownedCosts = {}
        for lineIndex = 1, nitems(kept.lines) do
          local line = kept.lines[lineIndex]
          ownedCosts[lineIndex] = basisCost(Session, line.itemID, line.ownedUnits)
        end
        local reserved = Session:Reserve({
          cash = kept.cash,
          inputs = kept.lines,
          cooldown = cooldown,
        })
        if reserved then
          for lineIndex = 1, nitems(kept.lines) do
            local line = kept.lines[lineIndex]
            local id = line.itemID
            local left = (Session.basis[id] or 0) - (ownedCosts[lineIndex] or 0)
            left = left + (tonumber(line.leftoverAssetValue) or 0)
            if left < 0 then
              left = 0
            end
            if id then
              Session.basis[id] = left
            end
          end
          local craftId = nitems(accepted) + nitems(flips) + 1
          local crafted = stepsForCraft(candidate, kept, craftId)
          for stepIndex = 1, nitems(crafted) do
            table.insert(steps, crafted[stepIndex])
          end
          table.insert(accepted, {
            name = candidate.output or candidate.name,
            profit = kept.profit,
            crafts = kept.crafts,
          })
          profit = profit + kept.profit
          proceeds = proceeds + (kept.crafts * (tonumber(candidate.net) or 0))
        end
      end
    end
  end

  local plan = Plan.Present({
    cash = cash,
    profit = profit,
    saleProceeds = proceeds,
    auctionOpen = resources.auctionOpen,
    professionOpen = resources.professionOpen,
    steps = steps,
  })
  plan.crafts = accepted
  plan.flips = flips
  return plan
end
