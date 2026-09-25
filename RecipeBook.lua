--[[
  Character profession book and the generic craft edge.

  Alchemy and Enchanting rows come from the open trade-skill window.
  A later open replaces that profession. The book is not a second copy of
  Data/Recipes.lua. Transmute Master, disenchant, item-use conversions,
  shatters, tools, and Warmane corrections stay on those static evaluators.
  A spell that already has one is not priced here.

  A deterministic row has one output item and one output count. Inputs are
  bought with the whole-lot quote. The output is sold at the conservative
  sale price, and the auction-house cut is applied once. The next craft is
  kept only while its own marginal profit stays positive.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.RecipeBook = OnyxiaGold.RecipeBook or {}

local Book = OnyxiaGold.RecipeBook

local PROFESSIONS = {
  Alchemy = true,
  Enchanting = true,
}

local staticSpells

local function nitems(t)
  if type(t) ~= "table" then
    return 0
  end
  return table.getn(t)
end

local function spellIDOf(value)
  if type(value) == "number" then
    return value
  end
  return tonumber(value)
end

function Book.ItemIDFromLink(link)
  if type(link) ~= "string" then
    return nil
  end
  return tonumber(string.match(link, "item:(%d+)"))
end

function Book.SpellIDFromRecipeLink(link)
  if type(link) ~= "string" then
    return nil
  end
  return tonumber(string.match(link, "enchant:(%d+)"))
    or tonumber(string.match(link, "spell:(%d+)"))
end

-- Sale proceeds after one auction-house cut. cutBPS is 500 for the 5% cut.
function Book.NetSale(gross, cutBPS)
  gross = tonumber(gross) or 0
  if gross <= 0 then
    return 0
  end
  cutBPS = tonumber(cutBPS) or 500
  if cutBPS < 0 then
    cutBPS = 0
  elseif cutBPS > 10000 then
    cutBPS = 10000
  end
  return math.floor(gross * (10000 - cutBPS) / 10000)
end

local function addStaticSpell(set, def)
  local req = def and def.requirements
  local spell = req and spellIDOf(req.recipeSpellID)
  if spell then
    set[spell] = true
  end
end

local function addStaticList(set, list)
  if type(list) ~= "table" then
    return
  end
  for i = 1, nitems(list) do
    addStaticSpell(set, list[i])
  end
end

-- Spell ids that already have a hand-written evaluator. Prefer those.
function Book.StaticSpellSet()
  if staticSpells then
    return staticSpells
  end
  local set = {}
  local data = OnyxiaGold.Data
  if data then
    addStaticList(set, data.Transmutes)
    addStaticList(set, data.EnchantCrafts)
    addStaticList(set, data.Conversions)
  end
  staticSpells = set
  return set
end

function Book.HasStaticEvaluator(spellID)
  spellID = spellIDOf(spellID)
  if not spellID then
    return false
  end
  return Book.StaticSpellSet()[spellID] and true or false
end

local function positiveCount(value)
  value = tonumber(value)
  if not value or value < 1 then
    return nil
  end
  value = math.floor(value)
  if value < 1 then
    return nil
  end
  return value
end

local function copyReagents(raw)
  local reagents = {}
  local complete = true
  if type(raw) ~= "table" then
    return reagents, false
  end
  for i = 1, nitems(raw) do
    local row = raw[i] or {}
    local itemID = spellIDOf(row.itemID) or Book.ItemIDFromLink(row.link)
    local count = positiveCount(row.count)
    if itemID and count then
      table.insert(reagents, { itemID = itemID, count = count })
    else
      complete = false
      if itemID or count or (type(row.name) == "string" and row.name ~= "") then
        table.insert(reagents, {
          itemID = itemID,
          count = count,
          name = row.name,
        })
      end
    end
  end
  if nitems(reagents) < 1 then
    complete = false
  end
  return reagents, complete
end

-- One client row, already read off the trade-skill window, into a book entry.
-- Deterministic means the client gave one output item and one output count.
function Book.FromClientRow(row, now)
  if type(row) ~= "table" then
    return nil
  end
  local profession = row.profession
  if not PROFESSIONS[profession] then
    return nil
  end
  local spellID = spellIDOf(row.spellID) or Book.SpellIDFromRecipeLink(row.recipeLink)
  if not spellID then
    return nil
  end
  local name = row.name
  if type(name) ~= "string" or name == "" then
    name = "Recipe " .. tostring(spellID)
  end
  local reagents, reagentsComplete = copyReagents(row.reagents)
  local outputItemID = spellIDOf(row.outputItemID) or Book.ItemIDFromLink(row.itemLink)
  local outputMin = positiveCount(row.outputMin)
  local outputMax = positiveCount(row.outputMax)
  local outputCount = positiveCount(row.outputCount)
  if outputCount and not outputMin and not outputMax then
    outputMin = outputCount
    outputMax = outputCount
  end
  if outputMin and outputMax and outputMin == outputMax then
    outputCount = outputMin
  elseif outputMin and outputMax and outputMin ~= outputMax then
    outputCount = nil
  end
  local deterministic = reagentsComplete
    and outputItemID
    and outputCount
    and true
    or false
  local recipe = {
    spellID = spellID,
    name = name,
    profession = profession,
    reagents = reagents,
    outputItemID = outputItemID,
    outputCount = outputCount,
    outputMin = outputMin,
    outputMax = outputMax,
    deterministic = deterministic and true or false,
  }
  if type(row.cooldownRemaining) == "number" then
    local remaining = row.cooldownRemaining
    if remaining < 0 then
      remaining = 0
    end
    recipe.cooldown = {
      remainingSeconds = remaining,
      observedAt = tonumber(now) or 0,
    }
  end
  return recipe
end

-- "none" has no cooldown. "ready" can be cast once. "waiting" is still down.
function Book.CooldownOpen(recipe, now)
  local cd = recipe and recipe.cooldown
  if type(cd) ~= "table" then
    return "none"
  end
  local remaining = tonumber(cd.remainingSeconds) or 0
  if remaining < 0 then
    remaining = 0
  end
  local observed = tonumber(cd.observedAt) or 0
  now = tonumber(now) or 0
  if now < observed + remaining then
    return "waiting"
  end
  return "ready"
end

function Book.CanPrice(recipe, now)
  if type(recipe) ~= "table" or not recipe.deterministic then
    return false
  end
  if not PROFESSIONS[recipe.profession] then
    return false
  end
  if Book.HasStaticEvaluator(recipe.spellID) then
    return false
  end
  if Book.CooldownOpen(recipe, now) == "waiting" then
    return false
  end
  if not recipe.outputItemID or not positiveCount(recipe.outputCount) then
    return false
  end
  local reagents = recipe.reagents
  if nitems(reagents) < 1 then
    return false
  end
  for i = 1, nitems(reagents) do
    local row = reagents[i]
    if not row or not spellIDOf(row.itemID) or not positiveCount(row.count) then
      return false
    end
  end
  return true
end

local function costAt(recipe, quote, crafts)
  local total = 0
  local reagents = recipe.reagents
  for i = 1, nitems(reagents) do
    local row = reagents[i]
    local part = quote(row.itemID, crafts * row.count)
    if not part or not part.complete then
      return nil
    end
    local economic = tonumber(part.economicConsumedCost)
    if not economic then
      return nil
    end
    total = total + economic
  end
  return total
end

-- crafts kept, economic cost of those crafts, marginal profit of the craft
-- that was refused. A non-positive marginal refuses that craft.
function Book.MarginalCrafts(recipe, quote, net, cap)
  net = tonumber(net) or 0
  local crafts = 0
  local previous = 0
  local nextMarginal = nil
  local limit = tonumber(cap) or 200
  if limit < 0 then
    limit = 0
  elseif limit > 200 then
    limit = 200
  end
  local guard = 0
  while crafts < limit and guard < 200 do
    guard = guard + 1
    local cost = costAt(recipe, quote, crafts + 1)
    if not cost then
      break
    end
    local marginal = net - (cost - previous)
    if marginal <= 0 then
      nextMarginal = marginal
      break
    end
    crafts = crafts + 1
    previous = cost
  end
  return crafts, previous, nextMarginal
end

local function cashFor(recipe, quote, crafts)
  local cash = 0
  local lines = {}
  local reagents = recipe.reagents
  for i = 1, nitems(reagents) do
    local row = reagents[i]
    local need = crafts * row.count
    local part = quote(row.itemID, need)
    if not part or not part.complete then
      return nil
    end
    cash = cash + (tonumber(part.cashRequired) or tonumber(part.totalCost) or 0)
    table.insert(lines, {
      itemID = row.itemID,
      ownedUnits = 0,
      buyUnits = need,
    })
  end
  return cash, lines
end

-- Nil when this recipe must not become an action.
-- The score is the same rank score the action list uses.
function Book.Plan(recipe, opts)
  opts = opts or {}
  local now = tonumber(opts.now) or 0
  if not Book.CanPrice(recipe, now) then
    return nil
  end
  if type(opts.quote) ~= "function" then
    return nil
  end
  local saleUnit = tonumber(opts.saleUnit)
  if not saleUnit or saleUnit <= 0 then
    return nil
  end
  local gross = saleUnit * recipe.outputCount
  local net
  if type(opts.net) == "function" then
    net = opts.net(gross)
  else
    net = Book.NetSale(gross, opts.cutBPS)
  end
  net = tonumber(net) or 0
  if net <= 0 then
    return nil
  end
  local cap = nil
  if Book.CooldownOpen(recipe, now) == "ready" then
    cap = 1
  end
  local crafts, totalCost, nextMarginal = Book.MarginalCrafts(recipe, opts.quote, net, cap)
  if not crafts or crafts < 1 or not totalCost then
    return nil
  end
  local profit = crafts * net - totalCost
  if profit <= 0 then
    return nil
  end
  local firstCost = costAt(recipe, opts.quote, 1)
  if not firstCost then
    return nil
  end
  local firstProfit = net - firstCost
  if firstProfit <= 0 then
    return nil
  end
  local cash, lines = cashFor(recipe, opts.quote, crafts)
  if not cash or not lines then
    return nil
  end
  local confidence = tonumber(opts.confidence) or 1
  local liquid = tonumber(opts.liquid) or 0
  local score = profit * confidence
  if OnyxiaGold.Lots and OnyxiaGold.Lots.ActionScore then
    score = OnyxiaGold.Lots.ActionScore(profit, confidence, cash, liquid)
  end
  return {
    kind = "BUY_AND_CRAFT",
    name = recipe.name,
    typeLabel = recipe.profession,
    expectedProfit = profit,
    firstProfit = firstProfit,
    firstCost = firstCost,
    cashRequiredNow = cash,
    crafts = crafts,
    score = score,
    spellID = recipe.spellID,
    netRevenue = net,
    saleUnit = saleUnit,
    nextMarginal = nextMarginal,
    confidence = confidence,
    reserve = {
      cash = cash,
      inputs = lines,
    },
  }
end

function Book.Walk(book, fn)
  if type(book) ~= "table" or type(fn) ~= "function" then
    return
  end
  for profession, bucket in pairs(book) do
    if PROFESSIONS[profession] and type(bucket) == "table" then
      local recipes = bucket.recipes
      if type(recipes) ~= "table" then
        recipes = bucket
      end
      for _, recipe in pairs(recipes) do
        if type(recipe) == "table" then
          fn(recipe, profession)
        end
      end
    end
  end
end

function Book.ItemIDs(book)
  local seen = {}
  local list = {}
  local function add(itemID)
    itemID = spellIDOf(itemID)
    if itemID and not seen[itemID] then
      seen[itemID] = true
      table.insert(list, itemID)
    end
  end
  Book.Walk(book, function(recipe)
    add(recipe.outputItemID)
    local reagents = recipe.reagents
    for i = 1, nitems(reagents) do
      add(reagents[i] and reagents[i].itemID)
    end
  end)
  return list
end
