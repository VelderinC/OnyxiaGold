--[[
  OnyxiaGold.Performance
  Counters for /og perf. Nothing is printed every frame.

  Sections nest. Begin returns a token. End closes that token.
  A child does not erase its parent. Inclusive time is the whole
  section. Exclusive time is inclusive minus nested children.
  cpu-active is slice time, not a sum of overlapping sections.

  debugprofilestop is the 3.3.5 frame timer when the client provides it.
  collectgarbage("count") is read only. This file never collects.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Performance = OnyxiaGold.Performance or {}

local Perf = OnyxiaGold.Performance

local function nitems(t)
  if type(t) ~= "table" then
    return 0
  end
  if table.getn then
    return table.getn(t)
  end
  return 0
end

local function profilerNow()
  if type(debugprofilestop) ~= "function" then
    return nil
  end
  local now = debugprofilestop()
  if type(now) ~= "number" then
    return nil
  end
  return now
end

local function wallNow()
  if type(GetTime) == "function" then
    return tonumber(GetTime()) or 0
  end
  return 0
end

function Perf:Reset()
  self.counts = {}
  self.times = {}
  self.exclusive = {}
  self.sliceCount = 0
  self.sliceSum = 0
  self.maxSlice = 0
  self.violations = 0
  self.lastViolation = nil
  self.lastRefresh = nil
  self.lastReason = nil
  self.reasons = {}
  self.stack = {}
  self.section = nil
  self.sectionMark = nil
  self.lastWarnAt = nil
  self.recent = {}
  self.pumps = {}
  self.alloc = {}
  self.showHud = self.showHud
end

Perf:Reset()

function Perf:Add(name, n)
  if not name then
    return
  end
  local counts = self.counts or {}
  self.counts = counts
  counts[name] = (tonumber(counts[name]) or 0) + (tonumber(n) or 1)
end

function Perf:Count(name)
  local counts = self.counts or {}
  return tonumber(counts[name]) or 0
end

function Perf:AddTime(name, ms)
  ms = tonumber(ms)
  if not name or not ms or ms < 0 then
    return
  end
  local times = self.times or {}
  self.times = times
  times[name] = (tonumber(times[name]) or 0) + ms
end

function Perf:Time(name)
  local times = self.times or {}
  return tonumber(times[name]) or 0
end

function Perf:Begin(name)
  local token = {
    name = name,
    mark = profilerNow(),
    child = 0,
    inclusive = 0,
  }
  local stack = self.stack or {}
  self.stack = stack
  local n = nitems(stack)
  token.parent = stack[n]
  stack[n + 1] = token
  self.section = name
  self.sectionMark = token.mark
  return token
end

local function closeToken(self, token)
  if not token then
    return
  end
  local now = profilerNow()
  local running = 0
  if token.mark and now then
    running = now - token.mark
    if running < 0 then
      running = 0
    end
  end
  local inclusive = (tonumber(token.inclusive) or 0) + running
  self:AddTime(token.name, inclusive)
  local exclusive = inclusive - (tonumber(token.child) or 0)
  if exclusive < 0 then
    exclusive = 0
  end
  local exclusiveTimes = self.exclusive or {}
  self.exclusive = exclusiveTimes
  exclusiveTimes[token.name] = (tonumber(exclusiveTimes[token.name]) or 0) + exclusive
  if token.parent then
    token.parent.child = (tonumber(token.parent.child) or 0) + inclusive
  end
  local stack = self.stack or {}
  local n = nitems(stack)
  while n > 0 and stack[n] ~= token do
    stack[n] = nil
    n = n - 1
  end
  if n > 0 and stack[n] == token then
    stack[n] = nil
  end
  local top = stack[nitems(stack)]
  self.section = top and top.name or nil
  self.sectionMark = top and top.mark or nil
end

function Perf:End(nameOrToken)
  local stack = self.stack or {}
  local token
  if type(nameOrToken) == "table" then
    token = nameOrToken
  else
    local n = nitems(stack)
    while n > 0 do
      if stack[n] and stack[n].name == nameOrToken then
        token = stack[n]
        break
      end
      n = n - 1
    end
  end
  closeToken(self, token)
end

function Perf:Exclusive(name)
  local exclusiveTimes = self.exclusive or {}
  return tonumber(exclusiveTimes[name]) or 0
end

-- Drop the yielded gap out of every open section.
function Perf:YieldPause()
  local now = profilerNow()
  local stack = self.stack or {}
  local n = nitems(stack)
  for i = 1, n do
    local token = stack[i]
    if token and token.mark and now then
      local delta = now - token.mark
      if delta < 0 then
        delta = 0
      end
      token.inclusive = (tonumber(token.inclusive) or 0) + delta
      token.mark = nil
    end
  end
  self.sectionMark = nil
end

function Perf:YieldResume()
  local now = profilerNow()
  local stack = self.stack or {}
  local n = nitems(stack)
  for i = 1, n do
    local token = stack[i]
    if token then
      token.mark = now
    end
  end
  local top = stack[n]
  self.section = top and top.name or nil
  self.sectionMark = top and top.mark or nil
end

local function pruneRecent(list, now, window)
  local kept = {}
  local n = nitems(list)
  for i = 1, n do
    local row = list[i]
    if row and now - (tonumber(row.t) or 0) <= window then
      kept[nitems(kept) + 1] = row
    end
  end
  return kept
end

function Perf:NoteSlice(ms)
  ms = tonumber(ms) or 0
  if ms < 0 then
    ms = 0
  end
  self.sliceCount = (self.sliceCount or 0) + 1
  self.sliceSum = (self.sliceSum or 0) + ms
  if ms > (self.maxSlice or 0) then
    self.maxSlice = ms
  end
  local now = wallNow()
  local recent = pruneRecent(self.recent or {}, now, 5)
  recent[nitems(recent) + 1] = { t = now, ms = ms }
  self.recent = recent
  local warn = 4
  if OnyxiaGold.Config and OnyxiaGold.Config.SliceWarnMs then
    warn = tonumber(OnyxiaGold.Config.SliceWarnMs) or 4
  end
  if ms < warn then
    return
  end
  self.violations = (self.violations or 0) + 1
  self.lastViolation = ms
  if self.lastWarnAt and now - self.lastWarnAt < 2 then
    return
  end
  self.lastWarnAt = now
  if OnyxiaGold.Log and OnyxiaGold.Log.Warn then
    OnyxiaGold.Log:Warn("Perf", string.format("Uninterrupted slice %.2f ms", ms))
  end
end

function Perf:NotePump(active)
  local now = wallNow()
  local pumps = pruneRecent(self.pumps or {}, now, 5)
  pumps[nitems(pumps) + 1] = { t = now, active = active and 1 or 0 }
  self.pumps = pumps
end

function Perf:NoteRefresh(kind, reason)
  self.lastRefresh = kind
  if reason and reason ~= "" then
    self.lastReason = reason
    local reasons = self.reasons or {}
    self.reasons = reasons
    reasons[reason] = (tonumber(reasons[reason]) or 0) + 1
  end
  self:Add("refreshes", 1)
end

function Perf:AllocMark(name)
  if type(collectgarbage) ~= "function" then
    return nil
  end
  local ok, kb = pcall(collectgarbage, "count")
  if not ok or type(kb) ~= "number" then
    return nil
  end
  local alloc = self.alloc or {}
  self.alloc = alloc
  alloc[name] = kb
  return kb
end

function Perf:AllocDelta(name)
  if type(collectgarbage) ~= "function" then
    return nil
  end
  local ok, kb = pcall(collectgarbage, "count")
  if not ok or type(kb) ~= "number" then
    return nil
  end
  local alloc = self.alloc or {}
  local before = alloc[name]
  if not before then
    return nil
  end
  local delta = kb - before
  if delta < 0 then
    delta = 0
  end
  self:AddTime(name .. "AllocKb", delta)
  alloc[name] = nil
  return delta
end

function Perf:RecentCpu()
  local now = wallNow()
  local recent = self.recent or {}
  local cpu = 0
  local frames = 0
  for i = 1, nitems(recent) do
    local row = recent[i]
    if row and now - (tonumber(row.t) or 0) <= 5 then
      cpu = cpu + (tonumber(row.ms) or 0)
      frames = frames + 1
    end
  end
  return cpu, frames
end

function Perf:RecentDuty()
  local now = wallNow()
  local pumps = self.pumps or {}
  local total = 0
  local active = 0
  for i = 1, nitems(pumps) do
    local row = pumps[i]
    if row and now - (tonumber(row.t) or 0) <= 5 then
      total = total + 1
      active = active + (tonumber(row.active) or 0)
    end
  end
  local pct = 0
  if total > 0 then
    pct = (active / total) * 100
  end
  return pct, active, total
end

function Perf:HudLine()
  local maxSlice = tonumber(self.maxSlice) or 0
  local slices = tonumber(self.sliceCount) or 0
  local candidates = self:Count("candidates")
  local extra = ""
  local clock = OnyxiaGold.RefreshSchedule
  if clock and clock.paused then
    extra = " · Planning paused"
  elseif clock and clock.running then
    extra = " · Updating"
  end
  return string.format("Plan %.1fms max slice · %d slices · %d candidates%s", maxSlice, slices, candidates, extra)
end

local function fmtMs(ms)
  if not ms or ms <= 0 then
    return "0"
  end
  return string.format("%.2f", ms)
end

function Perf:Report()
  local lines = {}
  local function add(text)
    lines[nitems(lines) + 1] = text
  end
  add("OnyxiaGold perf")
  local clock = OnyxiaGold.RefreshSchedule
  local mode = "safe"
  if clock and clock.mode then
    mode = tostring(clock.mode)
  end
  add("mode: " .. mode)
  if clock and clock.paused then
    add("planning: paused")
  end
  add("last refresh: " .. tostring(self.lastRefresh or "none"))
  local reasonText = {}
  local reasons = self.reasons or {}
  for name, count in pairs(reasons) do
    reasonText[nitems(reasonText) + 1] = tostring(name) .. " " .. tostring(count)
  end
  table.sort(reasonText)
  if nitems(reasonText) < 1 then
    add("refresh triggers: none")
  else
    add("refresh triggers: " .. table.concat(reasonText, ", "))
  end
  if clock and clock.JobLine then
    add(clock:JobLine())
  end
  local wall = self:Time("wall")
  add("total wall ms: " .. fmtMs(wall))
  -- Slice time is the time the coroutine actually ran. Nested sections
  -- are listed separately and are not added into this figure.
  add("cpu-active ms: " .. fmtMs(self.sliceSum))
  local slices = tonumber(self.sliceCount) or 0
  local sum = tonumber(self.sliceSum) or 0
  local avg = 0
  if slices > 0 then
    avg = sum / slices
  end
  add("slices: " .. tostring(slices))
  add("max slice ms: " .. fmtMs(self.maxSlice))
  add("average slice ms: " .. fmtMs(avg))
  add("slice warnings: " .. tostring(self.violations or 0))
  local recentCpu, recentFrames = self:RecentCpu()
  local duty, activePumps, pumpTotal = self:RecentDuty()
  add(string.format("last 5s OnyxiaGold CPU: %.2f ms", recentCpu))
  add(string.format("last 5s active frames: %d / %d (%.1f%%)", activePumps, pumpTotal, duty))
  add("economic slices in 5s: " .. tostring(recentFrames))
  add("inclusive OpportunityEngine ms: " .. fmtMs(self:Time("opportunity")))
  add("inclusive ActionPlanner ms: " .. fmtMs(self:Time("planner")))
  add("inclusive flip discovery ms: " .. fmtMs(self:Time("flips")))
  add("inclusive recipe discovery ms: " .. fmtMs(self:Time("recipes")))
  add("inclusive path ms: " .. fmtMs(self:Time("paths")))
  add("inclusive SessionPlan ms: " .. fmtMs(self:Time("session")))
  add("inclusive UI paint ms: " .. fmtMs(self:Time("ui")))
  add("inclusive TradeLog paint ms: " .. fmtMs(self:Time("tradeLog")))
  add("inclusive DB shape ms: " .. fmtMs(self:Time("database")))
  add("exclusive planner ms: " .. fmtMs(self:Exclusive("planner")))
  add("planner alloc delta KB: " .. fmtMs(self:Time("plannerAllocKb")))
  add("candidate build alloc delta KB: " .. fmtMs(self:Time("marketAllocKb")))
  add("opportunities: " .. tostring(self:Count("opportunities")))
  add("candidates: " .. tostring(self:Count("candidates")))
  add("Personalize calls: " .. tostring(self:Count("personalize")))
  add("personal quote builds: " .. tostring(self:Count("personalQuotes")))
  add("personal quote hits: " .. tostring(self:Count("personalQuoteHits")))
  add("lot quotes: " .. tostring(self:Count("lotQuotes")))
  add("lot quote hits: " .. tostring(self:Count("lotQuoteHits")))
  add("Lots.Select calls: " .. tostring(self:Count("lotSelects")))
  add("lot DP states: " .. tostring(self:Count("lotStates")))
  add("lots considered: " .. tostring(self:Count("lotsConsidered")))
  add("lot inner yields: " .. tostring(self:Count("lotInnerYields")))
  add("quote key builds: " .. tostring(self:Count("quoteKeyBuilds")))
  add("quote key build ms: " .. fmtMs(self:Time("quoteKeyBuildMs")))
  add("quote cache hits: " .. tostring(self:Count("quoteCacheHits")))
  add("quote cache misses: " .. tostring(self:Count("quoteCacheMisses")))
  add("quote cache entries: " .. tostring(self:Count("quoteCacheEntries")))
  add("quote cache evictions: " .. tostring(self:Count("quoteCacheEvictions")))
  add("depth serialisations: " .. tostring(self:Count("depthSerialisations")))
  add("quote book copies: " .. tostring(self:Count("quoteBookCopies")))
  add("market rows seen: " .. tostring(self:Count("marketRowsSeen")))
  add("flip cheap rejected: " .. tostring(self:Count("flipCheapRejected")))
  add("flip deep evaluated: " .. tostring(self:Count("flipDeepEvaluated")))
  add("flip found: " .. tostring(self:Count("flipFound")))
  add("flip items evaluated: " .. tostring(self:Count("flipItems")))
  add("flip cache hits: " .. tostring(self:Count("flipCacheHits")))
  add("flip reprices: " .. tostring(self:Count("flipReprices")))
  add("known candidate walks: " .. tostring(self:Count("knownCandidateWalks")))
  add("path topology builds: " .. tostring(self:Count("pathTopologyBuilds")))
  add("path seeds: " .. tostring(self:Count("pathSeeds")))
  add("path pairs considered: " .. tostring(self:Count("pathPairsConsidered")))
  add("path prices: " .. tostring(self:Count("pathPrices")))
  add("path quantity steps: " .. tostring(self:Count("pathQuantitySteps")))
  add("path reprices after reservation: " .. tostring(self:Count("pathRepricesAfterReservation")))
  add("session reserves: " .. tostring(self:Count("sessionReserves")))
  add("session bag copies: " .. tostring(self:Count("sessionBagCopies")))
  add("depth book clones: " .. tostring(self:Count("depthBookClones")))
  add("depth books mutated: " .. tostring(self:Count("depthBooksMutated")))
  add("quote invalidations: " .. tostring(self:Count("quoteInvalidations")))
  add("item meta hits: " .. tostring(self:Count("itemMetaHits")))
  add("item meta misses: " .. tostring(self:Count("itemMetaMisses")))
  add("stale job cancellations: " .. tostring(self:Count("staleCancels")))
  add("unchanged snapshots: " .. tostring(self:Count("unchangedSnapshots")))
  add("recipe rows evaluated: " .. tostring(self:Count("recipeRows")))
  add("UI refreshes: " .. tostring(self:Count("uiRefresh")))
  add("TradeLog rebuilds: " .. tostring(self:Count("tradeLogRebuilds")))
  add("planner rebuilds: " .. tostring(self:Count("plannerRebuilds")))
  add("engine rebuilds: " .. tostring(self:Count("engineRebuilds")))
  add("DB Ensure calls: " .. tostring(self:Count("dbEnsure")))
  if not profilerNow() then
    add("debugprofilestop: unavailable")
  end
  return table.concat(lines, "\n")
end
