--[[
  OnyxiaGold.CandidateCache
  Market-level opportunities, direct flips, and the recipe dependency graph.

  Rebuilt when the market revision or the recipe revision changes.
  A bag, gold, mail, or bank change does not walk market.latest and does
  not rebuild path topology. The personal planner only prices the seeds
  stored here.

  Discovery publishes atomically. A cancelled build leaves the previous
  cache in place.

  Wall-clock time may be long. A single slice may not be.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.CandidateCache = OnyxiaGold.CandidateCache or {}

local Cache = OnyxiaGold.CandidateCache

Cache.flips = {}
Cache.catalog = {}
Cache.pathSeeds = {}
Cache.recipes = {}
Cache.byInput = {}
Cache.byOutput = {}
Cache.byCooldown = {}
Cache.pathByInput = {}
Cache.marketRevision = -1
Cache.recipeRevision = -1
Cache.candidateRevision = 0
Cache.building = false

local TIER_CAP = 40

local function nitems(t)
  if type(t) ~= "table" then
    return 0
  end
  return table.getn(t)
end

local function tick()
  local schedule = OnyxiaGold.RefreshSchedule
  if schedule and schedule.Tick then
    schedule.Tick()
  end
end

local function perfAdd(name, n)
  local perf = OnyxiaGold.Performance
  if perf and perf.Add then
    perf:Add(name, n)
  end
end

local function isolated(name)
  local flag = OnyxiaGold.PerfIsolate
  return flag == name
end

function Cache:IsCurrent()
  local rev = OnyxiaGold.Revisions
  if not rev then
    return self.marketRevision ~= -1
  end
  return self.marketRevision == rev:Get("market") and self.recipeRevision == rev:Get("recipe")
end

function Cache:Flips()
  if not self:IsCurrent() then
    return {}
  end
  return self.flips or {}
end

function Cache:PathSeeds()
  if not self:IsCurrent() then
    return {}
  end
  return self.pathSeeds or {}
end

function Cache:DependenciesForItem(itemID)
  itemID = tonumber(itemID)
  local list = itemID and self.byInput and self.byInput[itemID]
  return list or {}
end

function Cache:DependenciesForOutput(itemID)
  itemID = tonumber(itemID)
  local list = itemID and self.byOutput and self.byOutput[itemID]
  return list or {}
end

function Cache:DependenciesForCooldown(group)
  if not group or not self.byCooldown then
    return {}
  end
  return self.byCooldown[group] or {}
end

function Cache:PathsTouching(itemID)
  itemID = tonumber(itemID)
  local list = itemID and self.pathByInput and self.pathByInput[itemID]
  return list or {}
end

function Cache:MarkReserved(itemID, cooldown)
  local seeds = self.pathSeeds or {}
  local touched = self:PathsTouching(itemID)
  for i = 1, nitems(touched) do
    local seed = seeds[touched[i]]
    if seed then
      seed.dirty = true
    end
  end
  if cooldown and self.byCooldown and self.byCooldown[cooldown] then
    local rows = self.byCooldown[cooldown]
    for i = 1, nitems(rows) do
      local seed = rows[i]
      if type(seed) == "table" and seed.first then
        seed.dirty = true
      end
    end
  end
end

local function tierOf(cash)
  cash = tonumber(cash) or 0
  if cash <= 10000 then
    return 1
  end
  if cash <= 100000 then
    return 2
  end
  if cash <= 500000 then
    return 3
  end
  if cash <= 2000000 then
    return 4
  end
  return 5
end

local function betterFlip(a, b)
  local sa = (tonumber(a.profit) or 0) * (tonumber(a.confidence) or 0)
  local sb = (tonumber(b.profit) or 0) * (tonumber(b.confidence) or 0)
  if sa ~= sb then
    return sa > sb
  end
  return (a.itemID or 0) < (b.itemID or 0)
end

local function insertTier(bucket, found)
  local n = nitems(bucket)
  local spot = n + 1
  for i = 1, n do
    if betterFlip(found, bucket[i]) then
      spot = i
      break
    end
  end
  if spot > TIER_CAP then
    return
  end
  local last = n
  if last >= TIER_CAP then
    last = TIER_CAP - 1
  end
  for i = last, spot, -1 do
    bucket[i + 1] = bucket[i]
  end
  bucket[spot] = found
end

local function inputList(recipe)
  local list = {}
  local raw = recipe and recipe.reagents or {}
  for i = 1, nitems(raw) do
    local row = raw[i]
    local id = tonumber(row and row.itemID)
    local count = tonumber(row and row.count) or 1
    if id and count > 0 then
      list[nitems(list) + 1] = { itemID = id, count = count, name = row.name }
    end
  end
  return list
end

local function pushIndex(map, key, value)
  if not key then
    return
  end
  local list = map[key]
  if not list then
    list = {}
    map[key] = list
  end
  list[nitems(list) + 1] = value
end

-- One walk of the saved market. Rows are not sorted: table.sort cannot
-- yield, and discovery does not need item-id order. The execution set is
-- ranked afterwards and stays small.
function Cache:DiscoverFlips()
  if isolated("flips") then
    return { execution = {}, catalog = {} }
  end
  local perf = OnyxiaGold.Performance
  if perf and perf.Begin then
    perf:Begin("flips")
  end
  local LotsApi = OnyxiaGold.Lots
  local db = OnyxiaGold.Database
  local prices = OnyxiaGold.Prices
  local empty = { execution = {}, catalog = {} }
  if not LotsApi or not LotsApi.FlipMargin or not db or not db.GetMarket then
    if perf and perf.End then
      perf:End("flips")
    end
    return empty
  end
  local market = db.currentMarket
  if not market and db.GetMarket then
    market = db:GetMarket()
  end
  local latest = market and market.latest
  if type(latest) ~= "table" then
    if perf and perf.End then
      perf:End("flips")
    end
    return empty
  end
  local rev = OnyxiaGold.Revisions
  local marketRev = rev and rev:Get("market") or 0
  local cutBPS = 500
  if OnyxiaGold.GetAuctionHouseCutBPS then
    cutBPS = OnyxiaGold:GetAuctionHouseCutBPS()
  end
  local staleAfter = OnyxiaGold.Config and OnyxiaGold.Config.QuickScanStaleSeconds
  local info = OnyxiaGold.ItemInfo
  local catalog = {}
  local tiers = { {}, {}, {}, {}, {} }
  local seen = 0
  for key, rec in pairs(latest) do
    seen = seen + 1
    if seen % 8 == 0 then
      tick()
      if rev and rev:Get("market") ~= marketRev then
        if perf and perf.End then
          perf:End("flips")
        end
        return nil
      end
    end
    if self.rowHook then
      self.rowHook(seen, key)
    end
    local itemID = tonumber(key) or tonumber(rec and rec.itemID)
    perfAdd("marketRowsSeen", 1)
    perfAdd("flipItems", 1)
    local reject = true
    if itemID and type(rec) == "table" and rec.source ~= "external" then
      local meta = info and info.Peek and info:Peek(itemID)
      if meta then
        perfAdd("itemMetaHits", 1)
      else
        perfAdd("itemMetaMisses", 1)
        if info and info.Queue then
          info:Queue(itemID)
        end
        meta = nil
      end
      local gear = meta and info and ((info.IsWeapon and info:IsWeapon(meta)) or (info.IsArmor and info:IsArmor(meta)))
      local age = prices and prices.GetAge and prices:GetAge(itemID)
      local stale = true
      if LotsApi.IsStale then
        stale = LotsApi.IsStale(age, staleAfter)
      end
      local name = rec.name
      if type(name) ~= "string" or name == "" then
        if OnyxiaGold.Data and OnyxiaGold.Data.GetItemName then
          name = OnyxiaGold.Data.GetItemName(itemID)
        end
      end
      local depth = prices and prices.GetDepth and prices:GetDepth(itemID)
      local covered = prices and prices.GetDepthCoveredQuantity and prices:GetDepthCoveredQuantity(itemID)
      local auctions = tonumber(rec.buyoutAuctionCount or rec.auctionCount) or 0
      local quantity = tonumber(covered or rec.buyoutQuantity or rec.totalQuantity) or 0
      if not gear and not stale and meta and meta.vendorPrice ~= nil
        and type(name) == "string" and name ~= ""
        and type(depth) == "table" and auctions >= 3 and quantity > 4 then
        local minP = nil
        local maxP = nil
        for i = 1, nitems(depth) do
          local p = tonumber(depth[i] and (depth[i].p or depth[i].unitPrice))
          if p and p > 0 then
            if not minP or p < minP then
              minP = p
            end
            if not maxP or p > maxP then
              maxP = p
            end
          end
        end
        local spread = minP and maxP and minP < maxP
        if spread then
          local unitProceeds = math.floor(maxP * (10000 - cutBPS) / 10000)
          if unitProceeds > minP then
            reject = false
            perfAdd("flipDeepEvaluated", 1)
            local own = OnyxiaGold.AuctionStop and OnyxiaGold.AuctionStop.OwnCheapestUnit
              and OnyxiaGold.AuctionStop.OwnCheapestUnit(itemID)
            local found = LotsApi.FlipMargin({
              levels = depth,
              covered = covered,
              vendorUnit = meta.vendorPrice,
              hours = 24,
              cutBPS = cutBPS,
              ownMinimum = own,
              name = name,
              itemID = itemID,
            })
            if found and (tonumber(found.profit) or 0) > 0 then
              local confidence = 0.5
              if LotsApi.FlipConfidence then
                confidence = LotsApi.FlipConfidence({
                  auctions = rec.buyoutAuctionCount or rec.auctionCount,
                  quantity = rec.buyoutQuantity or rec.totalQuantity,
                  sale = found.saleUnit,
                  unit = found.unit,
                  age = age,
                })
              end
              found.confidence = confidence
              found.itemID = itemID
              found.name = name
              found.vendorPrice = meta.vendorPrice
              found.bookGeneration = 0
              found.candidateID = "flip:" .. tostring(itemID) .. ":" .. tostring(marketRev)
                .. ":" .. tostring(found.unit) .. "x" .. tostring(found.count)
              catalog[nitems(catalog) + 1] = found
              insertTier(tiers[tierOf(found.cash)], found)
              perfAdd("flipFound", 1)
            end
          end
        end
      end
    end
    if reject then
      perfAdd("flipCheapRejected", 1)
    end
  end
  local execution = {}
  for tier = 1, 5 do
    local bucket = tiers[tier]
    for i = 1, nitems(bucket) do
      execution[nitems(execution) + 1] = bucket[i]
    end
  end
  if perf and perf.End then
    perf:End("flips")
  end
  return { execution = execution, catalog = catalog }
end

function Cache:BuildRecipeGraph(book)
  if isolated("paths") then
    return true
  end
  local perf = OnyxiaGold.Performance
  if perf and perf.Begin then
    perf:Begin("paths")
  end
  perfAdd("pathTopologyBuilds", 1)
  perfAdd("knownCandidateWalks", 1)
  local Book = OnyxiaGold.RecipeBook
  local recipes = {}
  local producers = {}
  local consumers = {}
  local byInput = {}
  local byOutput = {}
  local byCooldown = {}
  local pathByInput = {}
  local seeds = {}
  local function consider(recipe)
    if not Book or not Book.CanPrice or not Book.CanPrice(recipe, time and time() or 0) then
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
    if not outputID then
      return
    end
    local prices = OnyxiaGold.Prices
    local recordRow = prices and prices.GetRecord and prices:GetRecord(outputID)
    if recordRow and recordRow.source == "external" then
      return
    end
    local outputCount = tonumber(recipe.outputCount) or 1
    if outputCount < 1 then
      outputCount = 1
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
    local reagents = inputList(recipe)
    if nitems(reagents) < 1 then
      return
    end
    local crafts = 200
    if Book.CooldownOpen and Book.CooldownOpen(recipe, time and time() or 0) == "ready" then
      crafts = 1
    end
    local candidate = {
      known = true,
      candidateID = "recipe:" .. tostring(recipe.spellID),
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
      cooldown = recipe.cooldownGroup or (recipe.requirements and recipe.requirements.cooldown),
    }
    recipes[nitems(recipes) + 1] = candidate
    pushIndex(producers, outputID, candidate)
    pushIndex(byOutput, outputID, candidate.candidateID)
    if candidate.cooldown then
      pushIndex(byCooldown, candidate.cooldown, candidate)
    end
    for i = 1, nitems(reagents) do
      local id = reagents[i].itemID
      pushIndex(consumers, id, candidate)
      pushIndex(byInput, id, candidate.candidateID)
    end
  end
  if type(book) == "table" and book.Alchemy or (type(book) == "table" and book.Enchanting) then
    if Book and Book.Walk then
      Book.Walk(book, function(recipe)
        tick()
        consider(recipe)
      end)
    end
  elseif Book and Book.Walk then
    local db = OnyxiaGold.Database
    local row = db and db.GetCharacter and db:GetCharacter()
    local stored = row and row.recipeBook
    if type(stored) == "table" then
      Book.Walk(stored, function(recipe)
        tick()
        consider(recipe)
      end)
    end
  end
  local pairsSeen = 0
  for itemID, made in pairs(producers) do
    local used = consumers[itemID]
    if used then
      for a = 1, nitems(made) do
        for b = 1, nitems(used) do
          pairsSeen = pairsSeen + 1
          if pairsSeen % 8 == 0 then
            tick()
          end
          local first = made[a]
          local second = used[b]
          if first ~= second and first.spellID ~= second.spellID then
            perfAdd("pathPairsConsidered", 1)
            local deps = {}
            local seenDep = {}
            local function addDep(id)
              if id and not seenDep[id] then
                seenDep[id] = true
                deps[nitems(deps) + 1] = id
              end
            end
            local firstReagents = first.reagents or {}
            for i = 1, nitems(firstReagents) do
              addDep(firstReagents[i].itemID)
            end
            local secondReagents = second.reagents or {}
            for i = 1, nitems(secondReagents) do
              addDep(secondReagents[i].itemID)
            end
            local seed = {
              candidateID = "path:" .. tostring(first.spellID) .. ":" .. tostring(second.spellID),
              first = first,
              second = second,
              firstCandidateID = first.candidateID,
              secondCandidateID = second.candidateID,
              intermediateItemID = itemID,
              outputItemID = second.outputItemID,
              inputDependencyIDs = deps,
              marketRevision = self.marketRevision,
              recipeRevision = self.recipeRevision,
              dirty = false,
            }
            local index = nitems(seeds) + 1
            seeds[index] = seed
            for i = 1, nitems(deps) do
              pushIndex(pathByInput, deps[i], index)
            end
            pushIndex(pathByInput, itemID, index)
            if first.cooldown then
              pushIndex(byCooldown, first.cooldown, seed)
            end
            if second.cooldown then
              pushIndex(byCooldown, second.cooldown, seed)
            end
          end
        end
      end
    end
  end
  perfAdd("pathSeeds", nitems(seeds))
  self.partialRecipes = recipes
  self.partialSeeds = seeds
  self.partialByInput = byInput
  self.partialByOutput = byOutput
  self.partialByCooldown = byCooldown
  self.partialPathByInput = pathByInput
  if perf and perf.End then
    perf:End("paths")
  end
  return true
end

function Cache:Publish(marketRev, recipeRev, flips)
  self.flips = flips and flips.execution or {}
  self.catalog = flips and flips.catalog or {}
  self.recipes = self.partialRecipes or {}
  self.pathSeeds = self.partialSeeds or {}
  self.byInput = self.partialByInput or {}
  self.byOutput = self.partialByOutput or {}
  self.byCooldown = self.partialByCooldown or {}
  self.pathByInput = self.partialPathByInput or {}
  self.partialRecipes = nil
  self.partialSeeds = nil
  self.partialByInput = nil
  self.partialByOutput = nil
  self.partialByCooldown = nil
  self.partialPathByInput = nil
  self.marketRevision = marketRev
  self.recipeRevision = recipeRev
  self.building = false
  local rev = OnyxiaGold.Revisions
  if rev and rev.Bump then
    self.candidateRevision = rev:Bump("candidate")
  else
    self.candidateRevision = (self.candidateRevision or 0) + 1
  end
  local oppCount = 0
  local engine = OnyxiaGold.OpportunityEngine
  if engine and engine.GetResults then
    oppCount = nitems(engine:GetResults() or {})
  end
  perfAdd("candidates", oppCount + nitems(self.flips))
end

function Cache:Build()
  local rev = OnyxiaGold.Revisions
  local marketRev = rev and rev:Get("market") or 0
  local recipeRev = rev and rev:Get("recipe") or 0
  self.building = true
  local engine = OnyxiaGold.OpportunityEngine
  if engine and engine.Refresh and not isolated("planner") then
    engine:Refresh()
  end
  tick()
  if rev and (rev:Get("market") ~= marketRev or rev:Get("recipe") ~= recipeRev) then
    self.building = false
    return false
  end
  local flips = self:DiscoverFlips()
  if not flips then
    self.building = false
    return false
  end
  local graphed = self:BuildRecipeGraph()
  if not graphed then
    self.building = false
    return false
  end
  if rev and (rev:Get("market") ~= marketRev or rev:Get("recipe") ~= recipeRev) then
    self.partialRecipes = nil
    self.partialSeeds = nil
    self.building = false
    return false
  end
  self:Publish(marketRev, recipeRev, flips)
  return true
end
