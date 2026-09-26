--[[
  OnyxiaGold.SessionPlan
  One ordered session. It can hold more than one craft when they do not
  need the same gold, the same bag slots, the same auction lots, or the
  same cooldown. A flip is a whole-lot resale, not a craft: buy that lot,
  then post it. It spends current gold, including the deposit, and it does
  not take a lot a craft already reserved.

  Each craft stays in its own order: buy the whole lots, then craft, then
  post. A later sale is not added to the purse, so it cannot pay for a buy.
  Two known recipes can form one path when the first output is a reagent
  of the second and keeping that item beats selling it and buying it
  again. The path buys the lots the first craft still needs, crafts the
  first, crafts the second, and posts only the final output. The
  intermediate stays in the virtual inventory. It is not sold and then
  bought again, and that sale is not purse gold. Both crafts stay only
  while their own marginal profit is positive. Lots, bag slots, and the
  20-hour cooldown are still shared, so the path does not take a listing
  another craft already reserved.
  When the next step cannot be done from here, the top line names that
  errand first: the Auction House, the mailbox, a bank withdraw, or the
  profession window. The buy, craft, or post stays underneath it. Bank
  stock and purchase mail are not bag stock, and they do not spend bag gold.
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

local function sliceTick()
  local schedule = OnyxiaGold.RefreshSchedule
  if schedule and schedule.Tick then
    schedule.Tick()
  end
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
  local buy, mail, withdraw, craft, post = {}, {}, {}, {}, {}
  for i = 1, nitems(steps) do
    local step = steps[i]
    local role = step and step.role
    if role == "buy" then
      table.insert(buy, step)
    elseif role == "mail" then
      table.insert(mail, step)
    elseif role == "withdraw" then
      table.insert(withdraw, step)
    elseif role == "post" then
      table.insert(post, step)
    elseif role == "craft" then
      table.insert(craft, step)
    end
  end
  local ordered = {}
  local function append(list)
    for i = 1, nitems(list) do
      table.insert(ordered, list[i])
    end
  end
  append(buy)
  append(mail)
  append(withdraw)
  append(craft)
  append(post)
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
  local bagLeft = tonumber(spec.bagCash)
  local mailGold = tonumber(spec.mailGold) or 0
  if mailGold < 0 then
    mailGold = 0
  end
  if bagLeft ~= nil and bagLeft < 0 then
    bagLeft = 0
  end
  local mailNoted = false
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
        if bagLeft ~= nil and need > bagLeft and mailGold > 0 and not mailNoted then
          table.insert(funded, {
            role = "mail",
            mail = "gold",
            name = "gold",
            count = 1,
            craft = step.craft,
          })
          mailNoted = true
        end
        if bagLeft ~= nil then
          if need >= bagLeft then
            bagLeft = 0
          else
            bagLeft = bagLeft - need
          end
        end
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

local function withdrawWords(step)
  local count = tonumber(step.count) or 0
  local name = step.name or "item"
  if count > 1 then
    return string.format("Withdraw %d %s.", count, name)
  end
  return "Withdraw " .. name .. "."
end

local function mailWords(step)
  if step and step.mail == "gold" then
    return "Open the mailbox. Take gold."
  end
  return "Open the mailbox. Take mail."
end

-- Display only. The profit is the one number this craft or flip already
-- has. It is copied onto each of that plan's buys and is not split.
local function noteBuyProfit(steps, profit)
  profit = tonumber(profit)
  if not profit then
    return
  end
  for i = 1, nitems(steps) do
    local step = steps[i]
    if step and step.role == "buy" then
      step.rowProfit = profit
    end
  end
end

-- The posted product's expected sale, already on the post step. A buy
-- with no matching post keeps the sale blank.
local function notePostedSale(steps)
  local posts = {}
  local plain = {}
  for i = 1, nitems(steps) do
    local step = steps[i]
    if step and step.role == "post" then
      local proceeds = tonumber(step.proceeds)
      local count = tonumber(step.count)
      if proceeds and proceeds > 0 and count and count > 0 then
        if step.craft ~= nil then
          posts[step.craft] = step
        else
          table.insert(plain, step)
        end
      end
    end
  end
  local onlyPlain = nil
  if nitems(plain) == 1 then
    onlyPlain = plain[1]
  end
  for i = 1, nitems(steps) do
    local step = steps[i]
    if step and step.role == "buy" and step.saleCopper == nil then
      local post = nil
      if step.craft ~= nil then
        post = posts[step.craft]
      else
        post = onlyPlain
      end
      if post then
        step.saleCopper = tonumber(post.proceeds)
        step.saleCount = tonumber(post.count)
        step.saleName = post.name
      end
    end
  end
end

function Plan.BuyLine(step)
  if not step then
    return ""
  end
  local count = tonumber(step.count) or 0
  local name = step.name or "item"
  local cash = tonumber(step.cash)
  local text
  if cash and cash > 0 then
    text = string.format("Buy %d %s for %s.", count, name, Plan.Plain(cash))
  else
    text = string.format("Buy %d %s.", count, name)
  end
  local saleCount = tonumber(step.saleCount)
  local saleCash = tonumber(step.saleCopper)
  if saleCount and saleCount > 0 and saleCash and saleCash > 0 then
    local saleName = step.saleName
    if type(saleName) == "string" and saleName ~= "" then
      text = text .. string.format(" Sell %d %s for %s.", saleCount, saleName, Plan.Plain(saleCash))
    else
      text = text .. string.format(" Sell %d for %s.", saleCount, Plan.Plain(saleCash))
    end
  end
  if step.rowProfit ~= nil then
    local profit = tonumber(step.rowProfit)
    if profit then
      text = text .. " Profit " .. Plan.Plain(profit) .. "."
    end
  end
  return text
end

function Plan.StepLine(step)
  if not step then
    return ""
  end
  local count = tonumber(step.count) or 0
  local name = step.name or "item"
  if step.role == "buy" then
    return Plan.BuyLine(step)
  elseif step.role == "craft" then
    return string.format("Craft %d %s. %d to craft.", count, name, count)
  elseif step.role == "post" then
    local deposit = tonumber(step.deposit) or 0
    if deposit > 0 then
      return string.format("Post %d %s. Deposit %s.", count, name, Plan.Plain(deposit))
    end
    return string.format("Post %d %s. %d to post.", count, name, count)
  elseif step.role == "withdraw" then
    return withdrawWords(step)
  elseif step.role == "mail" then
    return mailWords(step)
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
  elseif step.role == "withdraw" then
    return withdrawWords(step) .. " " .. profitBit
  elseif step.role == "mail" then
    return mailWords(step) .. " " .. profitBit
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
  notePostedSale(steps)
  for i = 1, nitems(steps) do
    local step = steps[i]
    local hint = Plan.WindowHint(step, spec)
    step.windowHint = hint
    step.line = Plan.StepLine(step)
    if hint then
      step.line = hint .. " " .. step.line
    end
  end
  local first = steps[1]
  plan.nextLine = Plan.NextLine(first, plan.profit)
  if plan.nextLine and first and first.windowHint then
    plan.nextLine = first.windowHint .. " " .. plan.nextLine
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
      local asideID = tonumber(line.itemID)
      local banked = tonumber(line.bankUnits) or 0
      if banked > 0 then
        table.insert(steps, {
          role = "withdraw",
          itemID = asideID,
          count = banked,
          name = (asideID and names[asideID]) or line.name or "item",
        })
      end
      local mailed = tonumber(line.mailUnits) or 0
      if mailed > 0 then
        table.insert(steps, {
          role = "mail",
          mail = "item",
          itemID = asideID,
          count = mailed,
          name = (asideID and names[asideID]) or line.name or "item",
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
  noteBuyProfit(steps, action.expectedProfit)
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
      rowProfit = tonumber(found.profit),
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
    local remain = need - owned
    local bankHave = session.GetBankCount and session:GetBankCount(itemID) or 0
    local fromBank = bankHave
    if fromBank > remain then
      fromBank = remain
    end
    if fromBank < 0 then
      fromBank = 0
    end
    remain = remain - fromBank
    local mailHave = session.GetMailCount and session:GetMailCount(itemID) or 0
    local fromMail = mailHave
    if fromMail > remain then
      fromMail = remain
    end
    if fromMail < 0 then
      fromMail = 0
    end
    local toBuy = remain - fromMail
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
      bankUnits = fromBank,
      mailUnits = fromMail,
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

local function stepsForCraft(candidate, priced, craftId, stoneStep)
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
  for i = 1, nitems(lines) do
    local line = lines[i]
    local mailed = tonumber(line.mailUnits) or 0
    if mailed > 0 then
      table.insert(steps, {
        role = "mail",
        mail = "item",
        craft = craftId,
        itemID = line.itemID,
        count = mailed,
        name = line.name or "item",
      })
    end
  end
  for i = 1, nitems(lines) do
    local line = lines[i]
    local banked = tonumber(line.bankUnits) or 0
    if banked > 0 then
      table.insert(steps, {
        role = "withdraw",
        craft = craftId,
        itemID = line.itemID,
        count = banked,
        name = line.name or "item",
      })
    end
  end
  if stoneStep then
    stoneStep.craft = craftId
    table.insert(steps, stoneStep)
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
  noteBuyProfit(steps, priced.profit)
  return steps
end

-- The first recipe's output is one reagent of the second. Both have to be
-- known deterministic crafts. A flip is not a craft, and a recipe is not
-- paired with itself.
local function linkReagent(first, second)
  if type(first) ~= "table" or type(second) ~= "table" or first == second then
    return nil
  end
  if not first.known or not second.known then
    return nil
  end
  if first.kind == "flip" or second.kind == "flip" or first.kind == "path" or second.kind == "path" then
    return nil
  end
  local outID = tonumber(first.outputItemID)
  local per = tonumber(first.outputCount) or 1
  if per < 1 then
    per = 1
  end
  if not outID then
    return nil
  end
  local reagents = second.reagents or {}
  for i = 1, nitems(reagents) do
    local row = reagents[i]
    if tonumber(row and row.itemID) == outID then
      local count = tonumber(row.count) or 1
      if count < 1 then
        count = 1
      end
      return { itemID = outID, count = count, per = per, name = row.name }
    end
  end
  return nil
end

local function scaleReagents(reagents, crafts)
  local out = {}
  crafts = tonumber(crafts) or 1
  if crafts < 1 then
    crafts = 1
  end
  for i = 1, nitems(reagents) do
    local row = reagents[i]
    local count = tonumber(row and row.count) or 1
    if count < 1 then
      count = 1
    end
    local id = tonumber(row and row.itemID)
    if id then
      table.insert(out, { itemID = id, count = crafts * count, name = row.name })
    end
  end
  return out
end

local function mergeReagents(into, reagents)
  for i = 1, nitems(reagents) do
    local row = reagents[i]
    local id = tonumber(row and row.itemID)
    local count = tonumber(row and row.count) or 0
    if id and count > 0 then
      local found
      for j = 1, nitems(into) do
        if tonumber(into[j].itemID) == id then
          found = into[j]
          break
        end
      end
      if found then
        found.count = (tonumber(found.count) or 0) + count
      else
        table.insert(into, { itemID = id, count = count, name = row.name })
      end
    end
  end
  return into
end

local function otherReagents(second, intermediateID, crafts)
  local out = {}
  local reagents = second.reagents or {}
  for i = 1, nitems(reagents) do
    local row = reagents[i]
    if tonumber(row and row.itemID) ~= intermediateID then
      local count = tonumber(row.count) or 1
      if count < 1 then
        count = 1
      end
      local id = tonumber(row.itemID)
      if id then
        table.insert(out, { itemID = id, count = crafts * count, name = row.name })
      end
    end
  end
  return out
end

local function capCrafts(candidate)
  local maxN = tonumber(candidate and candidate.crafts) or 1
  if maxN < 1 then
    maxN = 1
  end
  if candidate and candidate.cooldown and maxN > 1 then
    maxN = 1
  end
  return maxN
end

-- Economic cost of buying the intermediate from the book that is left.
-- Capital is not the limit here: the question is the gold of selling and
-- buying, not whether that buy fits in the purse. Bag slots still apply,
-- because a buy that does not fit is not an available exit.
local function rebuyEconomic(session, itemID, units)
  if not session or not session.Quote then
    return nil
  end
  units = tonumber(units) or 0
  if units <= 0 then
    return 0
  end
  local quote = session:Quote(itemID, units, 20000000000)
  if not quote or not quote.complete then
    return nil
  end
  return tonumber(quote.economicConsumedCost) or 0
end

-- Price one keep-path on the current session. Nil when the link is not
-- there, a craft's own marginal profit is not positive, or selling the
-- first output and buying that reagent is the better gold. Does not reserve.
local function pricePath(first, second)
  local session = OnyxiaGold.SessionState
  if not session or not session.RemainingCash then
    return nil
  end
  local link = linkReagent(first, second)
  if not link then
    return nil
  end
  if first.cooldown and second.cooldown and first.cooldown == second.cooldown then
    return nil
  end
  if first.cooldown and session.CooldownUsed and session:CooldownUsed(first.cooldown) then
    return nil
  end
  if second.cooldown and session.CooldownUsed and session:CooldownUsed(second.cooldown) then
    return nil
  end
  local maxA = capCrafts(first)
  local maxB = capCrafts(second)
  local netA = tonumber(first.net) or 0
  local netB = tonumber(second.net) or 0
  if netB <= 0 then
    return nil
  end
  local kept
  local prevProfit = 0
  local prevBuy = 0
  local prevConsumedA = 0
  local b = 1
  while b <= maxB do
    local need = b * link.count
    local aCrafts = math.floor((need + link.per - 1) / link.per)
    if aCrafts < 1 or aCrafts > maxA then
      break
    end
    local produced = aCrafts * link.per
    if produced < need then
      break
    end
    local inputsA = scaleReagents(first.reagents, aCrafts)
    local inputsB = otherReagents(second, link.itemID, b)
    local combined = {}
    mergeReagents(combined, inputsA)
    mergeReagents(combined, inputsB)
    local priced = priceCraft(session, { reagents = combined, net = 0 }, 1)
    if not priced then
      break
    end
    local econAll = tonumber(priced.economic) or 0
    local econA = econAll
    if nitems(inputsA) > 0 then
      local onlyA = priceCraft(session, { reagents = inputsA, net = 0 }, 1)
      if onlyA then
        econA = tonumber(onlyA.economic) or 0
      end
    else
      econA = 0
    end
    if econA > econAll then
      econA = econAll
    end
    local econOther = econAll - econA
    if econOther < 0 then
      econOther = 0
    end
    local consumedA = econA
    if produced > need and produced > 0 then
      consumedA = math.floor(econA * need / produced)
    end
    local consumed = consumedA + econOther
    local profit = (b * netB) - consumed
    local buyEconomic = rebuyEconomic(session, link.itemID, need)
    local buyKnown = buyEconomic ~= nil
    if not buyKnown then
      buyEconomic = 0
    end
    local saleProceeds = aCrafts * netA
    local saleProfit = saleProceeds - econA
    if saleProfit < 0 then
      saleProfit = 0
    end
    local buyProfit = 0
    if buyKnown then
      buyProfit = (b * netB) - buyEconomic - econOther
      if buyProfit < 0 then
        buyProfit = 0
      end
    end
    local alternative = saleProfit + buyProfit
    local extraProfit = profit - prevProfit
    local extraMake = consumedA - prevConsumedA
    local producer = (buyEconomic - prevBuy) - extraMake
    if not buyKnown then
      producer = extraProfit
    end
    if extraProfit <= 0 or producer <= 0 or profit <= alternative then
      break
    end
    kept = {
      profit = profit,
      cash = priced.cash,
      economic = consumed,
      econA = econA,
      consumedA = consumedA,
      proceeds = b * netB,
      lines = priced.lines,
      firstCrafts = aCrafts,
      secondCrafts = b,
      first = first,
      second = second,
      intermediate = link.itemID,
      produced = produced,
      consumedUnits = need,
      saleUnit = tonumber(second.saleUnit),
    }
    prevProfit = profit
    prevBuy = buyEconomic
    prevConsumedA = consumedA
    b = b + 1
  end
  return kept
end

local function stepsForPath(priced, craftId)
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
  for i = 1, nitems(lines) do
    local line = lines[i]
    local mailed = tonumber(line.mailUnits) or 0
    if mailed > 0 then
      table.insert(steps, {
        role = "mail",
        mail = "item",
        craft = craftId,
        itemID = line.itemID,
        count = mailed,
        name = line.name or "item",
      })
    end
  end
  for i = 1, nitems(lines) do
    local line = lines[i]
    local banked = tonumber(line.bankUnits) or 0
    if banked > 0 then
      table.insert(steps, {
        role = "withdraw",
        craft = craftId,
        itemID = line.itemID,
        count = banked,
        name = line.name or "item",
      })
    end
  end
  local first = priced.first or {}
  local second = priced.second or {}
  local aCrafts = tonumber(priced.firstCrafts) or 0
  local bCrafts = tonumber(priced.secondCrafts) or 0
  if aCrafts > 0 then
    table.insert(steps, {
      role = "craft",
      craft = craftId,
      count = aCrafts,
      name = first.output or first.name or "item",
      profession = first.profession,
    })
  end
  local proceeds = tonumber(priced.proceeds) or 0
  if bCrafts > 0 then
    table.insert(steps, {
      role = "craft",
      craft = craftId,
      count = bCrafts,
      name = second.output or second.name or "item",
      profession = second.profession,
      proceeds = proceeds,
    })
  end
  local per = tonumber(second.outputCount) or 1
  if per < 1 then
    per = 1
  end
  local postUnits = bCrafts * per
  if second.post == false then
    postUnits = 0
  end
  if postUnits > 0 then
    table.insert(steps, {
      role = "post",
      craft = craftId,
      count = postUnits,
      name = second.output or second.name or "item",
      cash = 0,
      itemID = tonumber(second.outputItemID),
      proceeds = proceeds,
    })
  end
  noteBuyProfit(steps, priced.profit)
  return steps
end

local function acceptPath(priced, craftId)
  local session = OnyxiaGold.SessionState
  if not session or not session.Reserve or type(priced) ~= "table" then
    return nil
  end
  local first = priced.first or {}
  local second = priced.second or {}
  local lines = priced.lines or {}
  local ownedCosts = {}
  for lineIndex = 1, nitems(lines) do
    local line = lines[lineIndex]
    ownedCosts[lineIndex] = basisCost(session, line.itemID, line.ownedUnits)
  end
  local per = tonumber(second.outputCount) or 1
  if per < 1 then
    per = 1
  end
  local reserved = session:Reserve({
    cash = priced.cash,
    inputs = lines,
    cooldown = first.cooldown or second.cooldown,
    outputItemID = tonumber(second.outputItemID),
    outputUnits = (tonumber(priced.secondCrafts) or 0) * per,
  })
  if not reserved then
    return nil
  end
  if type(session.cooldowns) ~= "table" then
    session.cooldowns = {}
  end
  if first.cooldown then
    session.cooldowns[first.cooldown] = true
  end
  if second.cooldown then
    session.cooldowns[second.cooldown] = true
  end
  for lineIndex = 1, nitems(lines) do
    local line = lines[lineIndex]
    local id = line.itemID
    local left = (session.basis[id] or 0) - (ownedCosts[lineIndex] or 0)
    left = left + (tonumber(line.leftoverAssetValue) or 0)
    if left < 0 then
      left = 0
    end
    if id then
      session.basis[id] = left
    end
  end
  local leftover = (tonumber(priced.produced) or 0) - (tonumber(priced.consumedUnits) or 0)
  local mid = tonumber(priced.intermediate)
  if leftover > 0 and mid then
    session.bags[mid] = (session:GetBagCount(mid) or 0) + leftover
    local add = (tonumber(priced.econA) or 0) - (tonumber(priced.consumedA) or 0)
    if add > 0 then
      session.basis[mid] = (session.basis[mid] or 0) + add
    end
    if session.freeSlots ~= nil then
      local stack = session:StackSize(mid)
      if stack and stack > 0 then
        session.heldSlots = (session.heldSlots or 0) + math.floor((leftover + stack - 1) / stack)
      end
    end
  end
  return stepsForPath(priced, craftId)
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
-- A known pair whose output feeds the next recipe becomes one path when
-- keeping that output beats selling it and buying the reagent. The path
-- is sorted by that keep profit. A component whose own profit field is
-- higher can still run first; once the path no longer prices, the two
-- crafts are priced on their own.
function Plan.Portfolio(candidates, resources)
  resources = resources or {}
  local Session = OnyxiaGold.SessionState
  if not Session or not Session.Begin then
    return nil
  end
  local bagCash = tonumber(resources.cash) or 0
  if bagCash < 0 then
    bagCash = 0
  end
  local mailGold = tonumber(resources.mailGold) or 0
  if mailGold < 0 then
    mailGold = 0
  end
  local cash = bagCash + mailGold
  Session:Begin(cash, cash)
  Session.bags = {}
  Session.bank = {}
  Session.mail = {}
  Session.equipped = {}
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
  local bank = resources.bank or {}
  for itemID, count in pairs(bank) do
    local id = tonumber(itemID)
    local n = tonumber(count) or 0
    if id and n > 0 then
      Session.bank[id] = n
    end
  end
  local mailed = resources.mailItems or {}
  for itemID, count in pairs(mailed) do
    local id = tonumber(itemID)
    local n = tonumber(count) or 0
    if id and n > 0 then
      Session.mail[id] = n
    end
  end
  local equipped = resources.equipped or {}
  for itemID, on in pairs(equipped) do
    local id = tonumber(itemID)
    if id and on then
      Session.equipped[id] = true
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
  local knownCrafts = {}
  for i = 1, nitems(indexed) do
    local row = indexed[i].row
    if row.known and row.kind ~= "flip" and row.kind ~= "path" then
      table.insert(knownCrafts, row)
    end
  end
  local pathSerial = nitems(indexed)
  for a = 1, nitems(knownCrafts) do
    for b = 1, nitems(knownCrafts) do
      if a ~= b then
        local priced = pricePath(knownCrafts[a], knownCrafts[b])
        if priced and (tonumber(priced.profit) or 0) > 0 then
          pathSerial = pathSerial + 1
          table.insert(indexed, {
            row = {
              kind = "path",
              first = knownCrafts[a],
              second = knownCrafts[b],
              profit = priced.profit,
            },
            index = pathSerial + 1000,
          })
        end
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
  local pathNotes = {}
  local spentCraft = {}
  local profit = 0
  local proceeds = 0
  local function waitingOnPath(candidate)
    if not candidate or not candidate.known or candidate.kind == "path" then
      return false
    end
    for i = 1, nitems(indexed) do
      local row = indexed[i].row
      if row.kind == "path" and (row.first == candidate or row.second == candidate) then
        if not spentCraft[row.first] and not spentCraft[row.second] then
          if pricePath(row.first, row.second) then
            return true
          end
        end
      end
    end
    return false
  end
  for i = 1, nitems(indexed) do
    local candidate = indexed[i].row
    local cooldown = candidate.cooldown
    local blocked = cooldown and Session:CooldownUsed(cooldown)
    local sortProfit = tonumber(candidate.profit) or 0
    if candidate.kind == "flip" then
      if sortProfit > 0 then
        local found = acceptFlip(candidate)
        if found then
          local groupId = nitems(accepted) + nitems(flips) + nitems(pathNotes) + 1
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
    elseif candidate.kind == "path" then
      local first = candidate.first
      local second = candidate.second
      if first and second and not spentCraft[first] and not spentCraft[second] then
        local priced = pricePath(first, second)
        if priced and (tonumber(priced.profit) or 0) > 0 then
          local craftId = nitems(accepted) + nitems(flips) + nitems(pathNotes) + 1
          local crafted = acceptPath(priced, craftId)
          if crafted then
            for stepIndex = 1, nitems(crafted) do
              table.insert(steps, crafted[stepIndex])
            end
            spentCraft[first] = true
            spentCraft[second] = true
            table.insert(pathNotes, {
              first = first.output or first.name,
              second = second.output or second.name,
              profit = priced.profit,
              firstCrafts = priced.firstCrafts,
              secondCrafts = priced.secondCrafts,
            })
            profit = profit + priced.profit
            proceeds = proceeds + (tonumber(priced.proceeds) or 0)
          end
        end
      end
    elseif not blocked and sortProfit > 0 and not spentCraft[candidate] and not waitingOnPath(candidate) then
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
        local stoneStep
        local stone = candidate.stone
        if type(stone) == "table" then
          local stoneID = tonumber(stone.itemID)
          local inBags = stoneID and Session:GetBagCount(stoneID) > 0
          local onPerson = inBags or (stoneID and Session.equipped and Session.equipped[stoneID])
          local inBank = stoneID and Session:GetBankCount(stoneID) > 0
          if stoneID and not onPerson and inBank then
            stoneStep = {
              role = "withdraw",
              count = 1,
              name = stone.name or "transmutation stone",
              itemID = stoneID,
              stone = true,
            }
          end
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
          if stoneStep and stoneStep.itemID then
            local stoneID = stoneStep.itemID
            local left = Session:GetBankCount(stoneID) - 1
            if left > 0 then
              Session.bank[stoneID] = left
            else
              Session.bank[stoneID] = nil
            end
            Session.equipped[stoneID] = true
          end
          local craftId = nitems(accepted) + nitems(flips) + nitems(pathNotes) + 1
          local crafted = stepsForCraft(candidate, kept, craftId, stoneStep)
          for stepIndex = 1, nitems(crafted) do
            table.insert(steps, crafted[stepIndex])
          end
          spentCraft[candidate] = true
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
    bagCash = bagCash,
    mailGold = mailGold,
    profit = profit,
    saleProceeds = proceeds,
    auctionOpen = resources.auctionOpen,
    professionOpen = resources.professionOpen,
    steps = steps,
  })
  plan.crafts = accepted
  plan.flips = flips
  plan.paths = pathNotes
  return plan
end

function Plan.PricePath(first, second)
  return pricePath(first, second)
end

function Plan.AcceptPath(priced)
  return acceptPath(priced, 0)
end

-- The best keep-path among these candidates on the current session.
-- skip(first, second) drops a pair that already failed to reserve.
function Plan.BestPath(candidates, skip)
  local best
  local bestA = 0
  local bestB = 0
  for a = 1, nitems(candidates) do
    for b = 1, nitems(candidates) do
      sliceTick()
      if a ~= b and not (skip and skip(candidates[a], candidates[b])) then
        local priced = pricePath(candidates[a], candidates[b])
        if priced and (tonumber(priced.profit) or 0) > 0 then
          local better = not best or priced.profit > best.profit
          if not better and best and priced.profit == best.profit then
            better = a < bestA or (a == bestA and b < bestB)
          end
          if better then
            best = priced
            bestA = a
            bestB = b
          end
        end
      end
    end
  end
  return best
end

-- Known Alchemy and Enchanting recipes the character can perform.
-- An external price is not a sale and is not a candidate, so it cannot
-- authorise the buys on a path. A missing sale is a zero net: the final
-- craft still has to clear its own marginal profit on a live price.
function Plan.KnownCandidates()
  local Book = OnyxiaGold.RecipeBook
  local db = OnyxiaGold.Database
  if not Book or not Book.Walk or not Book.CanPrice or not db or not db.GetCharacter then
    return {}
  end
  local row = db:GetCharacter()
  local stored = row and row.recipeBook
  if type(stored) ~= "table" then
    return {}
  end
  local now = 0
  if time then
    now = time()
  end
  local prices = OnyxiaGold.Prices
  local out = {}
  Book.Walk(stored, function(recipe)
    sliceTick()
    if not Book.CanPrice(recipe, now) then
      return
    end
    if OnyxiaGold.Capabilities and OnyxiaGold.Capabilities.CanExecute then
      local cap = OnyxiaGold.Capabilities:CanExecute({
        profession = recipe.profession,
        recipeSpellID = recipe.spellID,
      })
      if not cap or not cap.executable then
        return
      end
    end
    local outputID = tonumber(recipe.outputItemID)
    local outputCount = tonumber(recipe.outputCount) or 1
    if not outputID then
      return
    end
    if outputCount < 1 then
      outputCount = 1
    end
    local record = prices and prices.GetRecord and prices:GetRecord(outputID)
    if record and record.source == "external" then
      return
    end
    local saleUnit = nil
    if prices and prices.GetOpportunitySaleUnit then
      saleUnit = prices:GetOpportunitySaleUnit(outputID)
    end
    local net = 0
    if saleUnit and saleUnit > 0 then
      local gross = saleUnit * outputCount
      if OnyxiaGold.ApplyAuctionHouseCut then
        net = OnyxiaGold:ApplyAuctionHouseCut(gross) or 0
      elseif Book.NetSale then
        net = Book.NetSale(gross, 500)
      end
    end
    local reagents = {}
    local raw = recipe.reagents or {}
    for i = 1, nitems(raw) do
      local reagent = raw[i]
      local id = tonumber(reagent and reagent.itemID)
      local count = tonumber(reagent and reagent.count) or 1
      if not id or count < 1 then
        return
      end
      table.insert(reagents, { itemID = id, count = count, name = reagent.name })
    end
    local crafts = 200
    if Book.CooldownOpen(recipe, now) == "ready" then
      crafts = 1
    end
    table.insert(out, {
      known = true,
      name = recipe.name,
      output = recipe.name,
      outputItemID = outputID,
      outputCount = outputCount,
      net = net,
      saleUnit = saleUnit,
      profit = 0,
      crafts = crafts,
      profession = recipe.profession,
      reagents = reagents,
      spellID = recipe.spellID,
    })
  end)
  return out
end
