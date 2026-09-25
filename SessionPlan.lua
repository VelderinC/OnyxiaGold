--[[
  OnyxiaGold.SessionPlan
  One ordered session for a craft that was already chosen.

  The visible order is the real order: buy the whole lots, then craft,
  then post the output. A later sale is not added to the purse, so it
  cannot pay for an earlier buy. This file does not choose auction lots.
  Callers pass cash and quantities from Lots.Select.
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

local function orderSteps(steps)
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
      local need = tonumber(step.cash) or 0
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
    if opts.professionOpen == false and type(profession) == "string" and profession ~= "" then
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
