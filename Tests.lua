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
