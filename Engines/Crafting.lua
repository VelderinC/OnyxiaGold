--[[
  Generic craft edge for the character's Alchemy and Enchanting book.

  One known deterministic recipe does not add a hand-written evaluator.
  Inputs use the whole-lot quote. The output uses the conservative sale
  price and one auction-house cut. A spell already priced by a static
  evaluator is left to that evaluator.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Engines = OnyxiaGold.Engines or {}
OnyxiaGold.Engines.Crafting = OnyxiaGold.Engines.Crafting or {}

local Crafting = OnyxiaGold.Engines.Crafting

local function sliceTick()
  local schedule = OnyxiaGold.RefreshSchedule
  if schedule and schedule.Tick then
    schedule.Tick()
  end
end

local function nitems(t)
  if type(t) ~= "table" then
    return 0
  end
  return table.getn(t)
end

local function quoteInput(itemID, quantity)
  local prices = OnyxiaGold.Prices
  if not prices or not prices.GetAcquisitionQuote then
    return nil
  end
  return prices:GetAcquisitionQuote(itemID, quantity)
end

local function netOf(gross)
  if OnyxiaGold.ApplyAuctionHouseCut then
    return OnyxiaGold:ApplyAuctionHouseCut(gross)
  end
  local Book = OnyxiaGold.RecipeBook
  if Book and Book.NetSale then
    return Book.NetSale(gross, 500)
  end
  return 0
end

function Crafting:Collect()
  local Book = OnyxiaGold.RecipeBook
  local out = {}
  if not Book or not Book.Walk or not Book.Plan then
    return out
  end
  local row = OnyxiaGold.Database and OnyxiaGold.Database.GetCharacter and OnyxiaGold.Database:GetCharacter()
  local book = row and row.recipeBook
  if type(book) ~= "table" then
    return out
  end
  local prices = OnyxiaGold.Prices
  local now = 0
  if time then
    now = time()
  end
  Book.Walk(book, function(recipe)
    sliceTick()
    if not Book.CanPrice(recipe, now) then
      return
    end
    local outputID = tonumber(recipe.outputItemID)
    local record = prices and prices.GetRecord and prices:GetRecord(outputID)
    if record and record.source == "external" then
      return
    end
    local saleUnit = prices and prices.GetOpportunitySaleUnit and prices:GetOpportunitySaleUnit(outputID)
    if not saleUnit or saleUnit <= 0 then
      return
    end
    local plan = Book.Plan(recipe, {
      now = now,
      quote = quoteInput,
      saleUnit = saleUnit,
      net = netOf,
      confidence = 1,
    })
    if not plan then
      return
    end
    local reagents = recipe.reagents or {}
    local inputs = {}
    local inputIDs = {}
    for i = 1, nitems(reagents) do
      local reagent = reagents[i]
      table.insert(inputs, { itemID = reagent.itemID, count = reagent.count })
      table.insert(inputIDs, reagent.itemID)
    end
    local outputQty = 0
    if prices and prices.GetBuyoutQuantity then
      outputQty = prices:GetBuyoutQuantity(outputID) or 0
    end
    local inputQty = nil
    local hasDepth = true
    for i = 1, nitems(inputIDs) do
      local qty = 0
      if prices and prices.GetBuyoutQuantity then
        qty = prices:GetBuyoutQuantity(inputIDs[i]) or 0
      end
      if not inputQty or qty < inputQty then
        inputQty = qty
      end
      if prices and prices.GetDepth and prices:GetDepth(inputIDs[i]) == nil then
        hasDepth = false
      end
    end
    local ageIDs = { outputID }
    for i = 1, nitems(inputIDs) do
      table.insert(ageIDs, inputIDs[i])
    end
    local ages
    if OnyxiaGold.OpportunityEngine and OnyxiaGold.OpportunityEngine.OldestAge then
      ages = OnyxiaGold.OpportunityEngine:OldestAge(ageIDs)
    end
    local conf, confNotes = 1, ""
    if OnyxiaGold.OpportunityEngine and OnyxiaGold.OpportunityEngine.ComputeConfidence then
      conf, confNotes = OnyxiaGold.OpportunityEngine:ComputeConfidence({
        oldestDataAge = ages,
        outputMarketQuantity = outputQty,
        marketProfitableCrafts = plan.crafts,
        outputCount = recipe.outputCount,
        expectedOutput = 1,
        hasDepth = hasDepth,
      })
    end
    local cap = nil
    if Book.CooldownOpen(recipe, now) == "ready" then
      cap = 1
    end
    local fields = {
      type = "CRAFT",
      typeLabel = recipe.profession,
      name = recipe.name,
      investment = plan.firstCost,
      grossRevenue = saleUnit * recipe.outputCount,
      netRevenue = plan.netRevenue,
      expectedProfit = plan.firstProfit,
      roi = (plan.firstCost > 0) and (plan.firstProfit / plan.firstCost) or 0,
      availableQuantity = plan.crafts,
      marketProfitableCrafts = plan.crafts,
      totalExpectedProfit = plan.expectedProfit,
      averageProfitPerCraft = math.floor(plan.expectedProfit / plan.crafts),
      inputMarketQuantity = inputQty or 0,
      outputMarketQuantity = outputQty,
      confidence = conf,
      confidenceNotes = confNotes,
      notes = "Known recipe. The conservative sale price is cut once. The next craft stops when its own profit is not positive.",
      inputs = inputs,
      inputItemIDs = inputIDs,
      outputItemIDs = { outputID },
      oldestDataAge = ages,
      expectedOutput = 1,
      saleUnit = saleUnit,
      requirements = {
        profession = recipe.profession,
        recipeSpellID = recipe.spellID,
      },
      inputCount = inputs[1] and inputs[1].count or 1,
      outputCount = recipe.outputCount,
      recipeId = "known:" .. tostring(recipe.spellID),
      maxCrafts = cap,
    }
    local opp
    if OnyxiaGold.OpportunityEngine and OnyxiaGold.OpportunityEngine.New then
      opp = OnyxiaGold.OpportunityEngine:New(fields)
    else
      opp = fields
    end
    table.insert(out, opp)
  end)
  return out
end
