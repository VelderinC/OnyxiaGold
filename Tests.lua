--[[
  Pure economic tests. /og test and tests/run.lua both call Run().
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Tests = OnyxiaGold.Tests or {}

local Tests = OnyxiaGold.Tests

local function nitems(t)
  if type(t) ~= "table" then
    return 0
  end
  if table.getn then
    return table.getn(t)
  end
  return 0
end

function Tests:Run()
  local Lots = OnyxiaGold.Lots
  local lines = {}
  local failed = 0
  local function check(name, ok)
    if ok then
      table.insert(lines, name .. ": PASS")
    else
      failed = failed + 1
      table.insert(lines, name .. ": FAIL")
    end
  end

  local function quote(levels, need, constraints)
    return Lots.Quote(levels, need, constraints)
  end

  local whole = quote({ { p = 10000, q = 20, n = 1, s = 20 } }, 8)
  check("whole-lot 20 needed 8", whole.complete
    and whole.purchasedUnits == 20
    and whole.consumedUnits == 8
    and whole.excessUnits == 12
    and whole.cashRequired == 200000
    and whole.economicConsumedCost == 80000
    and whole.leftoverAssetValue == 120000)

  local pair = quote({
    { p = 10000, q = 5, n = 1, s = 5 },
    { p = 10000, q = 5, n = 1, s = 5 },
  }, 8)
  check("multiple 5+5 needed 8", pair.complete
    and pair.purchasedUnits == 10
    and pair.consumedUnits == 8
    and pair.excessUnits == 2
    and pair.cashRequired == 100000)

  local rich = quote({
    { p = 10000, q = 20, n = 1, s = 20 },
    { p = 11000, q = 8, n = 1, s = 8 },
  }, 8, { capital = 1000000 })
  local tight = quote({
    { p = 10000, q = 20, n = 1, s = 20 },
    { p = 11000, q = 8, n = 1, s = 8 },
  }, 8, { capital = 100000 })
  local tie = quote({
    { p = 10000, q = 20, n = 1, s = 20 },
    { p = 10000, q = 8, n = 1, s = 8 },
  }, 8, { capital = 1000000 })
  check("oversized cheap versus exact expensive", rich.complete
    and rich.cashRequired == 200000
    and rich.economicConsumedCost == 80000
    and tight.complete
    and tight.cashRequired == 88000
    and tie.complete
    and tie.cashRequired == 80000)

  local sessionOk = false
  local Session = OnyxiaGold.SessionState
  if Session and Session.Begin then
    Session:Begin(1000000, 1000000)
    Session.depth[1] = { levels = { { p = 10000, q = 20, n = 1, s = 20 } }, covered = 20 }
    Session.bags = {}
    local first = Session:Reserve({
      cash = 200000,
      inputs = { { itemID = 1, ownedUnits = 0, buyUnits = 8 } },
    })
    local leftover = Session:GetBagCount(1)
    Session.depth[1] = { levels = { { p = 10000, q = 4, n = 1, s = 4 } }, covered = 4 }
    local second = Session:Reserve({
      cash = 0,
      inputs = { { itemID = 1, ownedUnits = 8, buyUnits = 0 } },
    })
    sessionOk = first and leftover == 12 and second and Session:GetBagCount(1) == 4
  end
  check("leftover reused by next action", sessionOk)

  local listingOk = false
  if Session and Session.Begin then
    Session:Begin(1000000, 1000000)
    Session.depth[7] = { levels = { { p = 10000, q = 20, n = 1, s = 20 } }, covered = 20 }
    Session.bags = {}
    local took = Session:Reserve({
      cash = 200000,
      inputs = { { itemID = 7, ownedUnits = 0, buyUnits = 8 } },
    })
    local again = Session:Reserve({
      cash = 200000,
      inputs = { { itemID = 7, ownedUnits = 0, buyUnits = 8 } },
    })
    listingOk = took and not again and Session:CoveredQuantity(7) == 0
  end
  check("two actions cannot consume same listing", listingOk)

  local bagOk = false
  if Session and Session.Begin then
    Session:Begin(0, 0)
    Session.bags = { [9] = 10 }
    local used = Session:Reserve({
      cash = 0,
      inputs = { { itemID = 9, ownedUnits = 8, buyUnits = 0 } },
    })
    local blocked = Session:Reserve({
      cash = 0,
      inputs = { { itemID = 9, ownedUnits = 8, buyUnits = 0 } },
    })
    bagOk = used and not blocked and Session:GetBagCount(9) == 2
  end
  check("two actions cannot consume same bag stock", bagOk)

  local kept = Lots.AcceptQuantity({ 100, -20 }, 0)
  local batchStillPositive = (100 - 20) > 0
  check("marginal craft 2 loses while batch stays positive", kept == 1 and batchStillPositive)

  local multiOk = false
  if Session and Session.Begin then
    Session:Begin(1000000, 1000000)
    Session.depth[11] = { levels = { { p = 5000, q = 8, n = 1, s = 8 } }, covered = 8 }
    Session.depth[12] = { levels = { { p = 7000, q = 2, n = 1, s = 2 } }, covered = 2 }
    local a = Session:Quote(11, 8)
    local b = Session:Quote(12, 2)
    multiOk = a.complete and b.complete and (a.cashRequired + b.cashRequired) == 54000
      and a.economicConsumedCost + b.economicConsumedCost == 54000
  end
  check("multi-input recipe", multiOk)

  local mailOk = false
  if Session and Session.Begin then
    Session:Begin(100000, 900000)
    local reserved = Session:Reserve({ cash = 50000, inputs = {} })
    local tooMuch = Session:Reserve({ cash = 200000, inputs = {} })
    mailOk = reserved
      and Session:RemainingCash() == 50000
      and Session:AfterMailCash() == 850000
      and not tooMuch
  end
  check("reserve after mail", mailOk)

  check("stale market", Lots.IsStale(nil, 600) and Lots.IsStale(601, 600) and not Lots.IsStale(600, 600))

  local dear = Lots.DisenchantExit({
    floorNet = 50000,
    expectedNet = 80000,
    vendor = 1000,
    intactNet = 200000,
    intactKnown = true,
    soulbound = false,
  })
  check("DE versus valuable intact gear", dear.state == "SELL" and dear.floor == 50000 and dear.expected == 80000)

  local bound = Lots.DisenchantExit({
    floorNet = 50000,
    expectedNet = 80000,
    vendor = 1000,
    intactKnown = false,
    soulbound = true,
  })
  check("DE soulbound non-sale", bound.state == "DE")

  local small = quote({
    { p = 10000, q = 5, n = 1, s = 5 },
    { p = 12000, q = 5, n = 1, s = 5 },
  }, 8)
  check("small-stack combination", small.complete and small.purchasedUnits == 10 and small.consumedUnits == 8)

  local nextBid = Lots.RequiredBid(100, 500, 50)
  local opening = Lots.RequiredBid(100, 0, 50)
  check("bid minIncrement", nextBid == 550 and opening == 100 and not (500 <= 520 and nextBid <= 520))

  local posted = Lots.PostEconomics(1000000, 1, 1000000, 500)
  check("post revenue versus profit", posted.expectedRevenue == 950000
    and posted.cashReleased == 950000
    and posted.inventoryValue == 1000000
    and posted.expectedProfit == -50000
    and posted.stackBuyout == 1000000)

  local badRealm = Lots.AcceptExternalSnapshot({
    schemaVersion = 1,
    source = "ah.nerfed.net",
    realm = "Icecrown",
    faction = "Alliance",
    scannedAt = 1,
    items = {},
  })
  local goodSnap = Lots.AcceptExternalSnapshot({
    schemaVersion = 1,
    source = "ah.nerfed.net",
    realm = "Onyxia",
    faction = "Alliance",
    scannedAt = 1,
    items = {},
  })
  check("external snapshot rejection", not badRealm and goodSnap)

  local keep = Lots.ShouldReplaceSnapshot(false, { downloadFailed = true })
  local replace = Lots.ShouldReplaceSnapshot(true, {})
  local realm = Lots.ShouldReplaceSnapshot(true, { realmMismatch = true })
  check("Windows snapshot overwrite", not keep and replace and not realm)

  local toolMissing = Lots.ClassifyTool("TRANSMUTATION_STONE", {})
  local toolBank = Lots.ClassifyTool("TRANSMUTATION_STONE", { inBank = true })
  local toolHeld = Lots.ClassifyTool("TRANSMUTATION_STONE", { onPerson = true })
  local stones = OnyxiaGold.Data and OnyxiaGold.Data.TransmutationStones or {}
  local stoneSet = {}
  for i = 1, nitems(stones) do
    stoneSet[stones[i]] = true
  end
  check("tool category", toolMissing == "TOOL_MISSING"
    and toolBank == "WITHDRAW_TOOL"
    and toolHeld == nil
    and stoneSet[13503] and stoneSet[35748] and stoneSet[35749]
    and stoneSet[35750] and stoneSet[35751] and stoneSet[44322]
    and stoneSet[44323] and stoneSet[44324] and not stoneSet[31080])

  local unknown = Lots.CooldownState(nil, 1000)
  local ready = Lots.CooldownState({ observedAt = 10, readyAt = 10 }, 1000)
  local waiting = Lots.CooldownState({ observedAt = 10, readyAt = 5000 }, 1000)
  check("real cooldown unknown/ready", unknown == "COOLDOWN_UNKNOWN"
    and ready == "READY" and waiting == "ON_COOLDOWN")

  local rebuild = Lots.ShouldRebuildOpportunities({
    database = true, character = true, inventory = true, capabilities = true, hasMarket = true,
  })
  local twice = Lots.ShouldRebuildOpportunities({
    database = true, character = true, inventory = true, capabilities = true, hasMarket = true, alreadyRan = true,
  })
  check("login opportunity rebuild", rebuild and not twice)

  check("PlaceAuctionBid requires revalidation",
    not Lots.AllowPlaceAuctionBid({ index = 1, buyout = 100 }, false)
    and Lots.AllowPlaceAuctionBid({ index = 1, buyout = 100 }, true)
    and not Lots.AllowPlaceAuctionBid(nil, true))

  check("StartAuction requires live validation",
    not Lots.AllowStartAuction({ validated = false, matches = true, buyout = 100 })
    and not Lots.AllowStartAuction({ validated = true, stale = true, matches = true, buyout = 100 })
    and Lots.AllowStartAuction({ validated = true, matches = true, buyout = 100 }))

  check("TakeInbox requires a click", not Lots.AllowTakeInbox(false) and Lots.AllowTakeInbox(true))

  check("DISENCHANT requires a safe exit",
    not Lots.AllowDisenchant("CHECK_AH")
    and not Lots.AllowDisenchant("SELL")
    and Lots.AllowDisenchant("DE")
    and not Lots.HOUSE_SHOW_STARTS_QUERY)

  local continuePage, incomplete = Lots.ShouldContinuePaging(0, 30, true)
  local stopEarly = Lots.ShouldContinuePaging(0, 30, true)
  check("paging does not stop on one expensive page", continuePage and stopEarly and Lots.PAGE_SORT_UNVERIFIED and not incomplete)

  -- 999001 is not a spell in Data/Recipes.lua. 12 units in, 1 item out.
  -- The cheap lot is 20, so one craft leaves 8. The next 12 have to buy
  -- the expensive lot, and that craft's own profit is not positive.
  local Book = OnyxiaGold.RecipeBook
  local known = Book.FromClientRow({
    spellID = 999001,
    name = "Fixture Elixir",
    profession = "Alchemy",
    reagents = { { itemID = 91001, count = 12 } },
    outputItemID = 91002,
    outputMin = 1,
    outputMax = 1,
  }, 1000)
  local function quoteKnown(itemID, quantity)
    return Session:Quote(itemID, quantity)
  end
  Session:Begin(1000000, 1000000)
  Session.bags = {}
  Session.depth[91001] = {
    levels = {
      { p = 100, q = 20, n = 1, s = 20 },
      { p = 10000, q = 12, n = 1, s = 12 },
    },
    covered = 32,
  }
  local action = Book.Plan(known, {
    now = 1000,
    quote = quoteKnown,
    saleUnit = 5000,
    cutBPS = 500,
    confidence = 1,
    liquid = 1000000,
  })
  local reserved = false
  local leftover = -1
  if action and action.reserve then
    reserved = Session:Reserve(action.reserve)
    leftover = Session:GetBagCount(91001)
  end
  local net = Book.NetSale(5000, 500)
  local score = Lots.ActionScore(action and action.expectedProfit or 0, 1, action and action.cashRequiredNow or 0, 1000000)
  check("known recipe not in Recipes.lua", known and known.deterministic
    and not Book.HasStaticEvaluator(999001)
    and Book.HasStaticEvaluator(60350)
    and action
    and action.kind == "BUY_AND_CRAFT"
    and action.crafts == 1
    and action.expectedProfit == net - 1200
    and action.expectedProfit > 0
    and action.cashRequiredNow == 2000
    and action.score == score
    and action.nextMarginal ~= nil
    and action.nextMarginal <= 0
    and reserved
    and leftover == 8)

  Session:Begin(1000000, 1000000)
  Session.bags = {}
  Session.depth[91001] = {
    levels = {
      { p = 100, q = 20, n = 1, s = 20 },
      { p = 10000, q = 12, n = 1, s = 12 },
    },
    covered = 32,
  }
  local quiet = Book.Plan(known, {
    now = 1000,
    quote = quoteKnown,
    saleUnit = 1000,
    cutBPS = 500,
    confidence = 1,
    liquid = 1000000,
  })
  check("next craft marginal not positive", not quiet and Book.NetSale(1000, 500) < 1200)

  local spread = Book.FromClientRow({
    spellID = 999002,
    name = "Fixture Range",
    profession = "Alchemy",
    reagents = { { itemID = 91001, count = 1 } },
    outputItemID = 91002,
    outputMin = 1,
    outputMax = 2,
  }, 1000)
  local staticRecipe = Book.FromClientRow({
    spellID = 60350,
    name = "Transmute: Titanium",
    profession = "Alchemy",
    reagents = { { itemID = 91001, count = 12 } },
    outputItemID = 91002,
    outputCount = 1,
  }, 1000)
  local staticPlan = Book.Plan(staticRecipe, {
    now = 1000,
    quote = quoteKnown,
    saleUnit = 5000,
    cutBPS = 500,
  })
  local waiting = Book.FromClientRow({
    spellID = 999003,
    name = "Fixture Cooldown",
    profession = "Enchanting",
    reagents = { { itemID = 91001, count = 12 } },
    outputItemID = 91002,
    outputCount = 1,
    cooldownRemaining = 50,
  }, 1000)
  local cooling = Book.Plan(waiting, {
    now = 1000,
    quote = quoteKnown,
    saleUnit = 5000,
    cutBPS = 500,
  })
  check("static and uneven recipes stay off the generic edge",
    spread and not spread.deterministic
    and not Book.Plan(spread, { now = 1000, quote = quoteKnown, saleUnit = 5000, cutBPS = 500 })
    and staticRecipe and not staticPlan
    and waiting and not cooling)

  -- Two steps. Step two's sale is 90g. The purse is 50g and the buy is a
  -- whole lot of 20 for 20g, not the 8 units the craft consumes. That sale
  -- must not become cash for the buy. 10g cannot fund the 20g buy either.
  local Plan = OnyxiaGold.SessionPlan
  local sessionAction = {
    kind = "BUY_AND_CRAFT",
    crafts = 1,
    cashRequiredNow = 200000,
    expectedProfit = 310000,
    person = {
      inputLines = {
        {
          itemID = 1,
          buyUnits = 8,
          purchasedUnits = 20,
          buyCost = 200000,
          excessUnits = 12,
        },
      },
    },
    breakdown = { proceeds = 900000 },
  }
  local sessionNames = { [1] = "Saronite Bar", output = "Titanium Bar" }
  local sessionSteps = Plan.StepsFromAction(sessionAction, sessionNames)
  local session = Plan.Present({
    cash = 500000,
    profit = 310000,
    saleProceeds = 900000,
    steps = sessionSteps,
  })
  local shortSession = Plan.Present({
    cash = 100000,
    profit = 310000,
    saleProceeds = 900000,
    steps = Plan.StepsFromAction(sessionAction, sessionNames),
  })
  local reversed = Plan.Present({
    cash = 500000,
    profit = 310000,
    saleProceeds = 900000,
    steps = {
      { role = "craft", name = "Titanium Bar", count = 1, proceeds = 900000 },
      { role = "buy", name = "Saronite Bar", count = 20, cash = 200000 },
    },
  })
  local nextLine = session.nextLine or ""
  local buyAt = string.find(nextLine, "Buy", 1, true)
  local craftAt = string.find(nextLine, "Craft", 1, true)
  local spoken = (session.steps[1] and session.steps[1].line or "")
    .. " " .. (session.steps[2] and session.steps[2].line or "")
  local spokenBuy = string.find(spoken, "Buy", 1, true)
  local spokenCraft = string.find(spoken, "Craft", 1, true)
  check("two-step session does not spend the later sale on the buy",
    nitems(sessionSteps) == 2
    and session.spent == 200000
    and session.purse == 300000
    and session.capitalDeployed == 200000
    and nitems(session.steps) == 2
    and session.steps[1].role == "buy"
    and session.steps[1].count == 20
    and session.steps[1].excessUnits == 12
    and session.steps[2].role == "craft"
    and session.steps[2].count == 1
    and buyAt == 1
    and not craftAt
    and spokenBuy
    and spokenCraft
    and spokenBuy < spokenCraft
    and string.find(nextLine, "Buy 20 Saronite Bar. Maximum spend 20g. Expected session profit +31g.", 1, true)
    and shortSession.spent == 0
    and shortSession.purse == 100000
    and nitems(shortSession.steps) == 0
    and not shortSession.nextLine
    and reversed.steps[1].role == "buy"
    and reversed.steps[2].role == "craft"
    and string.find(reversed.nextLine or "", "Buy", 1, true) == 1
    and reversed.purse == 300000)

  local closed = Plan.Present({
    cash = 500000,
    profit = 310000,
    auctionOpen = false,
    professionOpen = false,
    steps = {
      { role = "buy", name = "Saronite Bar", count = 20, cash = 200000 },
      { role = "craft", name = "Titanium Bar", count = 1, profession = "Alchemy" },
      { role = "post", name = "Titanium Bar", count = 1, cash = 0, proceeds = 900000 },
    },
  })
  check("closed auction and profession windows are named",
    closed.steps[1].role == "buy"
    and closed.steps[2].role == "craft"
    and closed.steps[3].role == "post"
    and string.find(closed.steps[1].line, "Open the Auction House.", 1, true)
    and string.find(closed.steps[2].line, "Open Alchemy.", 1, true)
    and string.find(closed.steps[3].line, "Open the Auction House.", 1, true)
    and string.find(closed.nextLine or "", "Open the Auction House. Buy 20 Saronite Bar. Maximum spend 20g.", 1, true)
    and string.find(closed.nextLine or "", "Expected session profit +31g.", 1, true)
    and closed.spent == 200000
    and closed.purse == 300000)

  -- Two crafts, no shared listing. Loss is priced and then dropped because
  -- its own marginal profit is not positive. Twice stops at one craft.
  local both = Plan.Portfolio({
    {
      name = "Thin",
      output = "Thin Bar",
      profit = 60000,
      net = 100000,
      crafts = 1,
      profession = "Alchemy",
      reagents = { { itemID = 2, count = 8, name = "Herb" } },
    },
    {
      name = "Rich",
      output = "Rich Bar",
      profit = 120000,
      net = 200000,
      crafts = 1,
      profession = "Alchemy",
      reagents = { { itemID = 1, count = 8, name = "Ore" } },
    },
    {
      name = "Loss",
      output = "Loss",
      profit = 1,
      net = 1,
      crafts = 1,
      reagents = { { itemID = 3, count = 8, name = "Dust" } },
    },
    {
      name = "Twice",
      output = "Twice",
      profit = 4200,
      net = 5000,
      crafts = 2,
      reagents = { { itemID = 4, count = 8, name = "Twice Reagent" } },
    },
  }, {
    cash = 1000000,
    depth = {
      [1] = { levels = { { p = 10000, q = 10, n = 1, s = 10 } }, covered = 10 },
      [2] = { levels = { { p = 5000, q = 10, n = 1, s = 10 } }, covered = 10 },
      [3] = { levels = { { p = 10000, q = 10, n = 1, s = 10 } }, covered = 10 },
      [4] = {
        levels = {
          { p = 100, q = 8, n = 1, s = 8 },
          { p = 10000, q = 8, n = 1, s = 8 },
        },
        covered = 16,
      },
    },
  })
  local bothSteps = both and both.steps or {}
  local bothRoles = {}
  local bothNames = {}
  local twiceBuy = 0
  for i = 1, nitems(bothSteps) do
    local step = bothSteps[i]
    table.insert(bothRoles, step.role or "")
    table.insert(bothNames, step.name or "")
    if step.role == "buy" and step.itemID == 4 then
      twiceBuy = step.count or 0
    end
  end
  local bothLine = both and both.nextLine or ""
  check("two crafts that share no lots appear in profit order",
    both
    and nitems(both.crafts) == 3
    and both.crafts[1].name == "Rich Bar"
    and both.crafts[2].name == "Thin Bar"
    and both.crafts[3].name == "Twice"
    and both.crafts[3].crafts == 1
    and both.profit == 184200
    and both.spent == 150800
    and both.purse == 849200
    and table.concat(bothRoles, ",") == "buy,craft,post,buy,craft,post,buy,craft,post"
    and bothNames[1] == "Ore"
    and bothNames[2] == "Rich Bar"
    and bothNames[4] == "Herb"
    and bothNames[5] == "Thin Bar"
    and twiceBuy == 8
    and not string.find(table.concat(bothNames, " "), "Loss", 1, true)
    and string.find(bothLine, "Buy 10 Ore. Maximum spend 10g. Expected session profit +18g 42s.", 1, true)
    and not string.find(bothLine, "Herb", 1, true)
    and not string.find(bothLine, "Craft", 1, true))

  local shared = Plan.Portfolio({
    {
      name = "Steel",
      output = "Steel",
      profit = 120000,
      net = 200000,
      crafts = 1,
      profession = "Alchemy",
      reagents = { { itemID = 7, count = 8, name = "Saronite" } },
    },
    {
      name = "Titanium",
      output = "Titanium",
      profit = 420000,
      net = 500000,
      crafts = 1,
      profession = "Alchemy",
      reagents = { { itemID = 7, count = 8, name = "Saronite" } },
    },
  }, {
    cash = 1000000,
    depth = {
      [7] = { levels = { { p = 10000, q = 20, n = 1, s = 20 } }, covered = 20 },
    },
  })
  local sharedBuys = 0
  local sharedBuyCount = 0
  local sharedCrafts = {}
  local sharedSteps = shared and shared.steps or {}
  for i = 1, nitems(sharedSteps) do
    local step = sharedSteps[i]
    if step.role == "buy" and step.itemID == 7 then
      sharedBuys = sharedBuys + 1
      sharedBuyCount = step.count or 0
    elseif step.role == "craft" then
      table.insert(sharedCrafts, step.name or "")
    end
  end
  local sharedLine = shared and shared.nextLine or ""
  check("two crafts that need the same listing buy it once",
    shared
    and sharedBuys == 1
    and sharedBuyCount == 20
    and shared.spent == 200000
    and shared.purse == 800000
    and shared.profit == 540000
    and nitems(shared.crafts) == 2
    and sharedCrafts[1] == "Titanium"
    and sharedCrafts[2] == "Steel"
    and string.find(sharedLine, "Buy 20 Saronite. Maximum spend 20g. Expected session profit +54g.", 1, true)
    and not string.find(sharedLine, "Craft", 1, true))

  local shortPurse = Plan.Portfolio({
    {
      name = "Rich",
      output = "Rich Bar",
      profit = 120000,
      net = 200000,
      crafts = 1,
      reagents = { { itemID = 1, count = 8, name = "Ore" } },
    },
    {
      name = "Thin",
      output = "Thin Bar",
      profit = 60000,
      net = 100000,
      crafts = 1,
      reagents = { { itemID = 2, count = 8, name = "Herb" } },
    },
  }, {
    cash = 120000,
    depth = {
      [1] = { levels = { { p = 10000, q = 10, n = 1, s = 10 } }, covered = 10 },
      [2] = { levels = { { p = 5000, q = 10, n = 1, s = 10 } }, covered = 10 },
    },
  })
  check("a later sale is not cash for the next buy",
    shortPurse
    and nitems(shortPurse.crafts) == 1
    and shortPurse.crafts[1].name == "Rich Bar"
    and shortPurse.spent == 100000
    and shortPurse.purse == 20000)

  local crowded = Plan.Portfolio({
    {
      name = "First",
      output = "First",
      profit = 100000,
      net = 200000,
      crafts = 1,
      reagents = { { itemID = 41, count = 8, name = "First Reagent" } },
    },
    {
      name = "Second",
      output = "Second",
      profit = 50000,
      net = 100000,
      crafts = 1,
      reagents = { { itemID = 42, count = 8, name = "Second Reagent" } },
    },
  }, {
    cash = 1000000,
    freeSlots = 1,
    stackSize = { [41] = 20, [42] = 20 },
    depth = {
      [41] = { levels = { { p = 1000, q = 20, n = 1, s = 20 } }, covered = 20 },
      [42] = { levels = { { p = 1000, q = 20, n = 1, s = 20 } }, covered = 20 },
    },
  })
  check("two crafts that need the same bag slot do not both buy",
    crowded
    and nitems(crowded.crafts) == 1
    and crowded.crafts[1].name == "First")

  local cooldown = Plan.Portfolio({
    {
      name = "Metal",
      output = "Metal",
      profit = 40000,
      net = 50000,
      crafts = 1,
      cooldown = "transmute_20h",
      reagents = { { itemID = 32, count = 1, name = "Ore" } },
    },
    {
      name = "Gem",
      output = "Gem",
      profit = 50000,
      net = 60000,
      crafts = 1,
      cooldown = "transmute_20h",
      reagents = { { itemID = 31, count = 1, name = "Green" } },
    },
  }, {
    cash = 1000000,
    depth = {
      [31] = { levels = { { p = 1000, q = 1, n = 1, s = 1 } }, covered = 1 },
      [32] = { levels = { { p = 1000, q = 1, n = 1, s = 1 } }, covered = 1 },
    },
  })
  check("the 20-hour transmute occupies the cooldown once",
    cooldown
    and nitems(cooldown.crafts) == 1
    and cooldown.crafts[1].name == "Gem"
    and Session:CooldownUsed("transmute_20h"))

  -- A lot a little under P25 does not survive the cut and the deposit.
  -- A lot that does is a flip: buy, then post. It shares the session with
  -- a craft only when they do not need the same gold, and it does not take
  -- a lot that craft already reserved.
  local function flipLevels(price)
    return {
      { p = price, q = 20, n = 1, s = 20 },
      { p = 10000, q = 80, n = 4, s = 20 },
    }
  end
  local slight = Lots.FlipMargin({
    levels = flipLevels(9600),
    covered = 100,
    deposit = 10000,
    cutBPS = 500,
    name = "Ore",
    itemID = 9,
  })
  local thin = Lots.FlipMargin({
    levels = {
      { p = 1000, q = 20, n = 1, s = 20 },
      { p = 10000, q = 20, n = 1, s = 20 },
    },
    covered = 40,
    deposit = 100,
    cutBPS = 500,
  })
  local oneOther = Lots.FlipMargin({
    levels = {
      { p = 1000, q = 10, n = 1, s = 10 },
      { p = 10000, q = 100, n = 1, s = 100 },
    },
    covered = 110,
    deposit = 100,
    cutBPS = 500,
  })
  local cleared = Lots.FlipMargin({
    levels = flipLevels(5000),
    covered = 100,
    deposit = 10000,
    cutBPS = 500,
    name = "Ore",
    itemID = 9,
  })
  local undercut = Lots.FlipMargin({
    levels = flipLevels(5000),
    covered = 100,
    deposit = 10000,
    cutBPS = 500,
    ownMinimum = 10001,
  })
  local outside = Lots.FlipMargin({
    levels = flipLevels(5000),
    covered = 100,
    deposit = 10000,
    external = true,
  })
  local broken = Lots.FlipMargin({
    levels = flipLevels(5000),
    covered = 100,
    deposit = 10000,
    disenchant = true,
  })
  local flipCandidate = {
    kind = "flip",
    itemID = 9,
    name = "Ore",
    deposit = 10000,
    cutBPS = 500,
  }
  local craftCandidate = {
    name = "Bar",
    output = "Bar",
    profit = 70000,
    net = 150000,
    crafts = 1,
    profession = "Alchemy",
    reagents = { { itemID = 3, count = 8, name = "Herb" } },
  }
  local function flipResources(purse)
    return {
      cash = purse,
      depth = {
        [9] = { levels = flipLevels(5000), covered = 100 },
        [3] = { levels = { { p = 10000, q = 10, n = 1, s = 10 } }, covered = 10 },
      },
    }
  end
  local sharedGold = Plan.Portfolio({ flipCandidate, craftCandidate }, flipResources(300000))
  local sameGold = Plan.Portfolio({ flipCandidate, craftCandidate }, flipResources(150000))
  local sharedSteps = sharedGold and sharedGold.steps or {}
  local sharedRoles = {}
  for i = 1, nitems(sharedSteps) do
    table.insert(sharedRoles, sharedSteps[i].role or "")
  end
  local sameSteps = sameGold and sameGold.steps or {}
  local sameHasCraft = false
  for i = 1, nitems(sameSteps) do
    if sameSteps[i].role == "craft" then
      sameHasCraft = true
    end
  end
  local reservedLot = Plan.Portfolio({
    flipCandidate,
    {
      name = "Bar",
      output = "Bar",
      profit = 500000,
      net = 300000,
      crafts = 1,
      profession = "Alchemy",
      reagents = { { itemID = 9, count = 8, name = "Ore" } },
    },
  }, {
    cash = 500000,
    depth = {
      [9] = { levels = flipLevels(5000), covered = 100 },
    },
  })
  local reservedBuys = 0
  local reservedSteps = reservedLot and reservedLot.steps or {}
  for i = 1, nitems(reservedSteps) do
    if reservedSteps[i].role == "buy" then
      reservedBuys = reservedBuys + 1
    end
  end
  check("a flip clears the cut and the deposit, and shares gold only when both fit",
    not slight
    and not thin
    and not oneOther
    and not undercut
    and not outside
    and not broken
    and Lots.DepositCopper(1000, 20, 24) == 6000
    and Lots.DepositCopper(0, 20, 24) == 100
    and not Lots.DepositCopper(nil, 20, 24)
    and cleared
    and cleared.profit == 80000
    and cleared.cash == 100000
    and cleared.deposit == 10000
    and cleared.count == 20
    and cleared.saleUnit == 10000
    and sharedGold
    and nitems(sharedGold.flips) == 1
    and nitems(sharedGold.crafts) == 1
    and sharedGold.flips[1].name == "Ore"
    and sharedGold.crafts[1].name == "Bar"
    and sharedGold.profit == 150000
    and sharedGold.spent == 210000
    and sharedGold.purse == 90000
    and table.concat(sharedRoles, ",") == "buy,post,buy,craft,post"
    and sharedSteps[1].flip
    and sharedSteps[1].name == "Ore"
    and sharedSteps[2].role == "post"
    and string.find(sharedSteps[2].line or "", "Deposit 1g", 1, true)
    and string.find(sharedGold.nextLine or "", "Buy 20 Ore. Maximum spend 10g. Expected session profit +15g.", 1, true)
    and not string.find(sharedGold.nextLine or "", "Craft", 1, true)
    and sameGold
    and nitems(sameGold.flips) == 1
    and nitems(sameGold.crafts) == 0
    and not sameHasCraft
    and sameGold.spent == 110000
    and sameGold.purse == 40000
    and string.find(sameGold.nextLine or "", "Buy 20 Ore. Maximum spend 10g. Expected session profit +8g.", 1, true)
    and reservedLot
    and nitems(reservedLot.flips) == 0
    and nitems(reservedLot.crafts) == 1
    and reservedBuys == 1
    and reservedLot.spent == 100000)

  local enchantClosed = Plan.Present({
    cash = 0,
    profit = 10000,
    professionOpen = false,
    steps = {
      { role = "craft", name = "Scroll", count = 1, profession = "Enchanting" },
    },
  })
  check("a closed profession window is named before the craft",
    enchantClosed
    and string.find(enchantClosed.nextLine or "", "Open Enchanting. Craft 1 Scroll.", 1, true) == 1
    and enchantClosed.steps[1].role == "craft")

  -- The reagent is only in the bank. Bag gold could buy the listing, and
  -- that later sale is not cash. The withdraw is the next step. The craft
  -- stays underneath it. Bag gold is not spent.
  local bankCraft = {
    name = "Elixir",
    output = "Elixir",
    profit = 80000,
    net = 80000,
    crafts = 1,
    profession = "Alchemy",
    reagents = { { itemID = 11, count = 5, name = "Dreamfoil" } },
  }
  local bankDepth = {
    [11] = { levels = { { p = 10000, q = 5, n = 1, s = 5 } }, covered = 5 },
  }
  local banked = Plan.Portfolio({ bankCraft }, {
    cash = 200000,
    bank = { [11] = 5 },
    auctionOpen = false,
    professionOpen = false,
    depth = bankDepth,
  })
  local bankSteps = banked and banked.steps or {}
  local bankRoles = {}
  local bankBuy = false
  for i = 1, nitems(bankSteps) do
    table.insert(bankRoles, bankSteps[i].role or "")
    if bankSteps[i].role == "buy" then
      bankBuy = true
    end
  end
  local bankLine = banked and banked.nextLine or ""
  check("a bank reagent is withdrawn before the craft and bag gold is not spent",
    banked
    and not bankBuy
    and banked.spent == 0
    and banked.purse == 200000
    and banked.profit == 80000
    and table.concat(bankRoles, ",") == "withdraw,craft,post"
    and bankSteps[1].name == "Dreamfoil"
    and bankSteps[1].count == 5
    and bankSteps[2].role == "craft"
    and string.find(bankLine, "Withdraw 5 Dreamfoil.", 1, true) == 1
    and string.find(bankLine, "Expected session profit +8g.", 1, true)
    and not string.find(bankLine, "Buy", 1, true)
    and not string.find(bankLine, "Open Alchemy", 1, true)
    and string.find(bankSteps[2].line or "", "Open Alchemy. Craft 1 Elixir.", 1, true)
    and Session:GetBagCount(11) == 0
    and Session:GetBankCount(11) == 0)

  local stoneCraft = Plan.Portfolio({
    {
      name = "Elixir",
      output = "Elixir",
      profit = 80000,
      net = 80000,
      crafts = 1,
      profession = "Alchemy",
      stone = { itemID = 13503, name = "Alchemist's Stone" },
      reagents = { { itemID = 11, count = 5, name = "Dreamfoil" } },
    },
  }, {
    cash = 200000,
    bags = { [11] = 5 },
    bank = { [13503] = 1 },
    depth = bankDepth,
  })
  local stoneLine = stoneCraft and stoneCraft.nextLine or ""
  check("a transmutation stone in the bank is withdrawn before the craft",
    stoneCraft
    and stoneCraft.spent == 0
    and stoneCraft.purse == 200000
    and stoneCraft.steps[1].role == "withdraw"
    and stoneCraft.steps[1].name == "Alchemist's Stone"
    and stoneCraft.steps[2].role == "craft"
    and string.find(stoneLine, "Withdraw Alchemist's Stone.", 1, true) == 1
    and Session:GetBankCount(13503) == 0
    and Session:GetBagCount(13503) == 0)

  local mailed = Plan.Portfolio({ bankCraft }, {
    cash = 200000,
    mailItems = { [11] = 5 },
    auctionOpen = false,
    professionOpen = false,
    depth = bankDepth,
  })
  local mailedLine = mailed and mailed.nextLine or ""
  local mailedBuy = false
  local mailedSteps = mailed and mailed.steps or {}
  for i = 1, nitems(mailedSteps) do
    if mailedSteps[i].role == "buy" then
      mailedBuy = true
    end
  end
  check("a purchased item in the mail is taken before the craft",
    mailed
    and not mailedBuy
    and mailed.spent == 0
    and mailed.purse == 200000
    and mailedSteps[1].role == "mail"
    and mailedSteps[2].role == "craft"
    and string.find(mailedLine, "Open the mailbox. Take mail.", 1, true) == 1
    and not string.find(mailedLine, "Open the Auction House.", 1, true)
    and Session:GetBagCount(11) == 0
    and Session:GetMailCount(11) == 0)

  local fromMail = Plan.Portfolio({ bankCraft }, {
    cash = 0,
    mailGold = 200000,
    auctionOpen = false,
    depth = bankDepth,
  })
  local fromMailLine = fromMail and fromMail.nextLine or ""
  local fromMailSteps = fromMail and fromMail.steps or {}
  check("sale gold in the mail is named before the buy and a later sale is not cash",
    fromMail
    and fromMail.spent == 50000
    and fromMail.purse == 150000
    and fromMailSteps[1].role == "mail"
    and fromMailSteps[1].mail == "gold"
    and fromMailSteps[2].role == "buy"
    and fromMailSteps[2].cash == 50000
    and string.find(fromMailLine, "Open the mailbox. Take gold.", 1, true) == 1
    and not string.find(fromMailLine, "Open the Auction House.", 1, true)
    and string.find(fromMailSteps[2].line or "", "Open the Auction House.", 1, true)
    and string.find(fromMailSteps[2].line or "", "Buy 5 Dreamfoil.", 1, true))

  local personal = Plan.Portfolio({ bankCraft }, {
    cash = 200000,
    personal = { [11] = 5 },
    cod = { [11] = 5 },
    depth = bankDepth,
  })
  local personalSteps = personal and personal.steps or {}
  local personalMail = false
  for i = 1, nitems(personalSteps) do
    if personalSteps[i].role == "mail" or personalSteps[i].role == "withdraw" then
      personalMail = true
    end
  end
  check("personal mail and cash-on-delivery are not taken for the craft",
    personal
    and personal.spent == 50000
    and personalSteps[1].role == "buy"
    and not personalMail)

  local passed = nitems(lines) - failed
  local head
  if failed == 0 then
    head = "OnyxiaGold test: PASS"
  else
    head = "OnyxiaGold test: FAIL"
  end
  table.insert(lines, tostring(passed) .. " passed, " .. tostring(failed) .. " failed")
  table.insert(lines, 1, head)
  return table.concat(lines, "\n"), failed == 0
end
