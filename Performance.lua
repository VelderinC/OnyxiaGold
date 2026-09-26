--[[
  OnyxiaGold.Performance
  Counters for /og perf. Nothing is printed every frame.
  debugprofilestop is the 3.3.5 frame timer when the client provides it.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Performance = OnyxiaGold.Performance or {}

local Perf = OnyxiaGold.Performance

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

function Perf:Reset()
  self.counts = {}
  self.times = {}
  self.sliceCount = 0
  self.sliceSum = 0
  self.maxSlice = 0
  self.violations = 0
  self.lastViolation = nil
  self.lastRefresh = nil
  self.lastReason = nil
  self.reasons = {}
  self.section = nil
  self.sectionMark = nil
  self.lastWarnAt = nil
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
  self.section = name
  self.sectionMark = profilerNow()
end

function Perf:End(name)
  if self.section == name and self.sectionMark then
    local now = profilerNow()
    if now then
      self:AddTime(name, now - self.sectionMark)
    end
  end
  if self.section == name then
    self.section = nil
    self.sectionMark = nil
  end
end

-- Drop the yielded gap out of the active section.
function Perf:YieldPause()
  if self.section and self.sectionMark then
    local now = profilerNow()
    if now then
      self:AddTime(self.section, now - self.sectionMark)
    end
    self.sectionMark = nil
  end
end

function Perf:YieldResume()
  if self.section then
    self.sectionMark = profilerNow()
  end
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
  local warn = 4
  if OnyxiaGold.Config and OnyxiaGold.Config.SliceWarnMs then
    warn = tonumber(OnyxiaGold.Config.SliceWarnMs) or 4
  end
  if ms < warn then
    return
  end
  self.violations = (self.violations or 0) + 1
  self.lastViolation = ms
  local now = 0
  if type(GetTime) == "function" then
    now = tonumber(GetTime()) or 0
  end
  if self.lastWarnAt and now - self.lastWarnAt < 2 then
    return
  end
  self.lastWarnAt = now
  if OnyxiaGold.Log and OnyxiaGold.Log.Warn then
    OnyxiaGold.Log:Warn("Perf", string.format("Uninterrupted slice %.2f ms", ms))
  end
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

function Perf:HudLine()
  local maxSlice = tonumber(self.maxSlice) or 0
  local slices = tonumber(self.sliceCount) or 0
  local candidates = self:Count("candidates")
  return string.format("Plan %.1fms max slice · %d slices · %d candidates", maxSlice, slices, candidates)
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
    lines[table.getn(lines) + 1] = text
  end
  add("OnyxiaGold perf")
  add("last refresh: " .. tostring(self.lastRefresh or "none"))
  local reasonText = {}
  local reasons = self.reasons or {}
  for name, count in pairs(reasons) do
    reasonText[table.getn(reasonText) + 1] = tostring(name) .. " " .. tostring(count)
  end
  table.sort(reasonText)
  if table.getn(reasonText) < 1 then
    add("refresh triggers: none")
  else
    add("refresh triggers: " .. table.concat(reasonText, ", "))
  end
  local wall = self:Time("wall")
  add("total wall ms: " .. fmtMs(wall))
  local cpu = self:Time("opportunity") + self:Time("planner") + self:Time("flips")
    + self:Time("recipes") + self:Time("session") + self:Time("ui") + self:Time("tradeLog")
    + self:Time("database")
  add("cpu-active ms: " .. fmtMs(cpu))
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
  add("OpportunityEngine ms: " .. fmtMs(self:Time("opportunity")))
  add("ActionPlanner ms: " .. fmtMs(self:Time("planner")))
  add("flip discovery ms: " .. fmtMs(self:Time("flips")))
  add("recipe discovery ms: " .. fmtMs(self:Time("recipes")))
  add("SessionPlan ms: " .. fmtMs(self:Time("session")))
  add("UI paint ms: " .. fmtMs(self:Time("ui")))
  add("TradeLog paint ms: " .. fmtMs(self:Time("tradeLog")))
  add("DB shape ms: " .. fmtMs(self:Time("database")))
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
  add("flip items evaluated: " .. tostring(self:Count("flipItems")))
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
