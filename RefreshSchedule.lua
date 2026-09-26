--[[
  OnyxiaGold.RefreshSchedule
  One refresh architecture.

  market: rebuild CandidateCache, then the personal plan, then paint.
  plan: reallocate the current cache into a personal plan, then paint.
  ui: paint execution state. No market discovery and no planner.

  A stronger pending job replaces a weaker one. The work runs after the
  burst goes quiet, in slices short enough for a 3.3.5 frame.
  Pure Lua 5.1. No WoW frame is created here.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.RefreshSchedule = OnyxiaGold.RefreshSchedule or {}

local Schedule = OnyxiaGold.RefreshSchedule

Schedule.quiet = 0.75
Schedule.budgetMs = 2
Schedule.warnMs = 4
Schedule.yieldEvery = 8
Schedule.pending = false
Schedule.waiting = false
Schedule.running = false
Schedule.deadline = 0
Schedule.job = nil
Schedule.reason = nil

local RANK = {
  ui = 1,
  plan = 2,
  market = 3,
}

local function normalize(kind)
  if kind == "engine" or kind == "market" or kind == "MARKET_CANDIDATES" then
    return "market"
  end
  if kind == "planner" or kind == "plan" or kind == "PERSONAL_PLAN" then
    return "plan"
  end
  return "ui"
end

local function rankOf(kind)
  return RANK[kind or ""] or 0
end

local function budgetMs()
  local budget = tonumber(Schedule.budgetMs) or 2
  if OnyxiaGold.Config and OnyxiaGold.Config.SliceBudgetMs then
    budget = tonumber(OnyxiaGold.Config.SliceBudgetMs) or budget
  end
  if budget < 0.5 then
    budget = 0.5
  end
  return budget
end

function Schedule.New(quiet)
  return setmetatable({
    quiet = tonumber(quiet) or Schedule.quiet or 0.75,
    pending = false,
    waiting = false,
    running = false,
    deadline = 0,
    job = nil,
    reason = nil,
  }, { __index = Schedule })
end

function Schedule:Push(now, kind, reason)
  kind = normalize(kind)
  local nextRank = rankOf(kind)
  local have = rankOf(self.job)
  if self.job and nextRank < have then
    return
  end
  if kind == "plan" and OnyxiaGold.Revisions and OnyxiaGold.Revisions.Bump then
    OnyxiaGold.Revisions:Bump("character")
  elseif kind == "ui" and OnyxiaGold.Revisions and OnyxiaGold.Revisions.Bump then
    OnyxiaGold.Revisions:Bump("ui")
  end
  self.job = kind
  if type(reason) == "string" and reason ~= "" then
    self.reason = reason
  end
  self.pending = true
  local quiet = tonumber(self.quiet) or 0.75
  if quiet < 0 then
    quiet = 0
  end
  self.deadline = (tonumber(now) or 0) + quiet
  if not self.running then
    self.waiting = true
  end
end

function Schedule:Poll(now)
  now = tonumber(now) or 0
  if self.running then
    return "running"
  end
  if self.waiting and self.pending and now >= (self.deadline or 0) then
    self.pending = false
    self.waiting = false
    self.running = true
    return "start"
  end
  return "idle"
end

function Schedule:Finish(now)
  if self.wallStart and type(GetTime) == "function" then
    local elapsed = (tonumber(GetTime()) or 0) - self.wallStart
    if elapsed < 0 then
      elapsed = 0
    end
    local perf = OnyxiaGold.Performance
    if perf and perf.AddTime then
      perf:AddTime("wall", elapsed * 1000)
    end
  end
  self.wallStart = nil
  self.running = false
  self.co = nil
  self.activeSlice = nil
  local ran = self.ranJob
  local ranRank = rankOf(ran)
  local nextRank = rankOf(self.job)
  local rev = OnyxiaGold.Revisions
  local unchanged = true
  if rev and rev.SameEconomics and self.revAtStart then
    unchanged = rev:SameEconomics(self.revAtStart) and true or false
  end
  -- A market or plan pass already painted. A weaker request that arrived
  -- during that pass is redundant when the revisions did not move.
  if self.pending and unchanged and ranRank >= 2 and nextRank > 0 and nextRank < ranRank then
    self.pending = false
    self.job = nil
    self.waiting = false
    self.ranJob = nil
    return
  end
  if self.pending then
    self.waiting = true
    now = tonumber(now) or 0
    if now >= (self.deadline or 0) then
      self.deadline = now + (tonumber(self.quiet) or 0.75)
    end
  else
    self.waiting = false
  end
  self.ranJob = nil
end

function Schedule:RestorePartial()
  local engine = OnyxiaGold.OpportunityEngine
  if engine and engine.building then
    if type(engine.published) == "table" then
      engine.results = engine.published
    end
    engine.building = false
  end
  local planner = OnyxiaGold.ActionPlanner
  if planner and planner.building then
    if type(planner.painting) == "table" then
      planner.actions = planner.painting
    end
    planner.building = false
    planner.painting = nil
  end
end

function Schedule.Tick()
  local slice = Schedule.activeSlice
  if not slice then
    return
  end
  if type(debugprofilestop) == "function" then
    local now = debugprofilestop()
    if type(now) == "number" then
      if not slice.mark then
        slice.mark = now
      end
      if now - slice.mark >= budgetMs() then
        local perf = OnyxiaGold.Performance
        if perf and perf.YieldPause then
          perf:YieldPause()
        end
        slice.mark = nil
        coroutine.yield()
        if perf and perf.YieldResume then
          perf:YieldResume()
        end
        if type(debugprofilestop) == "function" then
          local again = debugprofilestop()
          if type(again) == "number" then
            slice.mark = again
          end
        end
      end
      return
    end
  end
  slice.steps = (slice.steps or 0) + 1
  local every = tonumber(Schedule.yieldEvery) or 8
  if every < 1 then
    every = 1
  end
  if slice.steps % every == 0 then
    slice.steps = 0
    local perf = OnyxiaGold.Performance
    if perf and perf.YieldPause then
      perf:YieldPause()
    end
    coroutine.yield()
    if perf and perf.YieldResume then
      perf:YieldResume()
    end
  end
end

function Schedule:Advance(now)
  if not self.co then
    return "done"
  end
  if not self.activeSlice then
    self.activeSlice = {}
  end
  local started
  if type(debugprofilestop) == "function" then
    local mark = debugprofilestop()
    if type(mark) == "number" then
      started = mark
      if not self.activeSlice.mark then
        self.activeSlice.mark = mark
      end
    end
  end
  local ok, err = coroutine.resume(self.co)
  if started and type(debugprofilestop) == "function" then
    local stopped = debugprofilestop()
    if type(stopped) == "number" then
      local perf = OnyxiaGold.Performance
      if perf and perf.NoteSlice then
        perf:NoteSlice(stopped - started)
      end
    end
  end
  local dead = coroutine.status(self.co) == "dead"
  if not ok or dead then
    if not ok then
      self:RestorePartial()
      if OnyxiaGold.Log and OnyxiaGold.Log.Warn then
        OnyxiaGold.Log:Warn("Refresh", tostring(err))
      end
    end
    self:Finish(now)
    if ok then
      return "done"
    end
    return "error"
  end
  return "slice"
end

local function runJob(job)
  if job == "market" then
    local cache = OnyxiaGold.CandidateCache
    if cache and cache.Build then
      cache:Build()
    elseif OnyxiaGold.OpportunityEngine and OnyxiaGold.OpportunityEngine.Refresh then
      OnyxiaGold.OpportunityEngine:Refresh()
    end
  end
  if job == "market" or job == "plan" then
    if OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.Refresh then
      OnyxiaGold.ActionPlanner:Refresh()
    end
  end
  if OnyxiaGold.UI and OnyxiaGold.UI.frame and OnyxiaGold.UI.Refresh then
    OnyxiaGold.UI:Refresh()
  end
end

function Schedule:Begin(now)
  if self.co then
    return self:Advance(now)
  end
  if self:Poll(now) ~= "start" then
    return "idle"
  end
  if OnyxiaGold.Scanner and OnyxiaGold.Scanner.IsScanning and OnyxiaGold.Scanner:IsScanning() then
    self.running = false
    self.pending = true
    self.waiting = true
    self.deadline = (tonumber(now) or 0) + 0.25
    return "deferred"
  end
  local job = self.job or "ui"
  local reason = self.reason
  self.job = nil
  self.reason = nil
  self.ranJob = job
  if OnyxiaGold.Revisions and OnyxiaGold.Revisions.Snapshot then
    self.revAtStart = OnyxiaGold.Revisions:Snapshot()
  else
    self.revAtStart = nil
  end
  local perf = OnyxiaGold.Performance
  if perf and perf.NoteRefresh then
    perf:NoteRefresh(job, reason)
  end
  if type(GetTime) == "function" then
    self.wallStart = tonumber(GetTime()) or 0
  else
    self.wallStart = nil
  end
  self.activeSlice = {}
  self.co = coroutine.create(function()
    runJob(job)
  end)
  return self:Advance(now)
end
