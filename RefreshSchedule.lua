--[[
  OnyxiaGold.RefreshSchedule
  One refresh architecture.

  market: rebuild CandidateCache, then the personal plan, then paint.
  plan: reallocate the current cache into a personal plan, then paint.
  ui: paint execution state. No market discovery and no planner.

  A job may take many frames. Wall-clock latency is acceptable.
  A hitch is not. Safe mode slices are about 0.75–1.0 ms.
  2 ms is only an emergency ceiling for aggressive testing.
  No function may run 4 ms without yielding.

  A running job captures the revisions of its inputs. If those
  revisions move, the job aborts at the next yield. It does not
  publish. One replacement is scheduled after the quiet period.

  Heavy work pauses while the player is buying, posting, scanning,
  or settling a transaction. Gameplay always wins.

  Push schedules work. It does not claim that character data changed.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.RefreshSchedule = OnyxiaGold.RefreshSchedule or {}

local Schedule = OnyxiaGold.RefreshSchedule

Schedule.quiet = 0.75
Schedule.budgetMs = 0.85
Schedule.warnMs = 4
Schedule.yieldEvery = 8
Schedule.pending = false
Schedule.waiting = false
Schedule.running = false
Schedule.deadline = 0
Schedule.job = nil
Schedule.reason = nil
Schedule.mode = "safe"
Schedule.paused = false
Schedule.interactions = {}
Schedule.skipFrames = 0
Schedule.settleUntil = 0
Schedule.staleCancels = 0
Schedule.runawayLimitSlices = 12000
Schedule.runawayLimitWall = 180

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

local function clockNow()
  if type(GetTime) == "function" then
    return tonumber(GetTime()) or 0
  end
  return 0
end

function Schedule.BudgetMs()
  if Schedule.mode == "aggressive" then
    local budget = 2
    if OnyxiaGold.Config and OnyxiaGold.Config.SliceBudgetMs then
      budget = tonumber(OnyxiaGold.Config.SliceBudgetMs) or 2
    end
    if budget < 0.5 then
      budget = 0.5
    end
    if budget > 2 then
      budget = 2
    end
    return budget
  end
  local budget = tonumber(Schedule.budgetMs) or 0.85
  if OnyxiaGold.Config and OnyxiaGold.Config.SliceBudgetMs then
    local configured = tonumber(OnyxiaGold.Config.SliceBudgetMs)
    if configured and configured > 0 then
      budget = configured
    end
  end
  if budget < 0.5 then
    budget = 0.5
  end
  if budget > 1 then
    budget = 1
  end
  return budget
end

local function budgetMs()
  return Schedule.BudgetMs()
end

local function perfAdd(name, n)
  local perf = OnyxiaGold.Performance
  if perf and perf.Add then
    perf:Add(name, n)
  end
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
    mode = Schedule.mode or "safe",
    paused = false,
    interactions = {},
    skipFrames = 0,
    settleUntil = 0,
    staleCancels = 0,
  }, { __index = Schedule })
end

function Schedule:SetInteraction(name, on)
  if not name then
    return
  end
  local flags = self.interactions
  if type(flags) ~= "table" then
    flags = {}
    self.interactions = flags
  end
  if on then
    flags[name] = true
  else
    flags[name] = nil
  end
end

function Schedule:NoteTransaction(now)
  now = tonumber(now) or clockNow()
  local untilT = now + 0.6
  if not self.settleUntil or untilT > self.settleUntil then
    self.settleUntil = untilT
  end
  self:SetInteraction("settling", true)
end

function Schedule:HeavyBlocked(now)
  if self.paused then
    return true
  end
  now = tonumber(now) or clockNow()
  if self.settleUntil and now < self.settleUntil then
    return true
  end
  if self.settleUntil and now >= self.settleUntil then
    self:SetInteraction("settling", false)
  end
  local flags = self.interactions
  if type(flags) == "table" then
    for _, on in pairs(flags) do
      if on then
        return true
      end
    end
  end
  local stop = OnyxiaGold.AuctionStop
  if stop then
    local phase = stop.buyPhase
    if phase and phase ~= "idle" and phase ~= "" then
      return true
    end
    if stop.paging then
      return true
    end
  end
  local scanner = OnyxiaGold.Scanner
  if scanner and scanner.IsScanning and scanner:IsScanning() then
    return true
  end
  return false
end

function Schedule:Capture(kind)
  local rev = OnyxiaGold.Revisions
  local snap = nil
  if rev and rev.CaptureFor then
    snap = rev:CaptureFor(kind)
  end
  local token = {
    kind = kind,
    snap = snap,
  }
  function token:IsCurrent()
    if not snap or not rev or not rev.IsCurrentFor then
      return true
    end
    return rev:IsCurrentFor(kind, snap)
  end
  return token
end

function Schedule:IsObsolete()
  local slice = self.activeSlice or Schedule.activeSlice
  local token = slice and slice.token
  if token and token.IsCurrent and not token:IsCurrent() then
    return true
  end
  return false
end

-- Schedules work. Does not bump character, market, or plan revisions.
function Schedule:Push(now, kind, reason)
  kind = normalize(kind)
  if self.errorHold and self.errorHold.kind == kind then
    local rev = OnyxiaGold.Revisions
    local same = true
    if rev and rev.IsCurrentFor and self.errorHold.snap then
      same = rev:IsCurrentFor(kind, self.errorHold.snap)
    end
    if same and reason ~= "refresh" and reason ~= "resume" and reason ~= "opportunities" then
      return
    end
    self.errorHold = nil
  end
  local nextRank = rankOf(kind)
  local have = rankOf(self.job)
  if self.job and nextRank < have and not self.running then
    return
  end
  if self.running and self.job and nextRank < rankOf(self.job) then
    return
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
  now = tonumber(now) or 0
  local deadline = now + quiet
  if self.settleUntil and deadline < self.settleUntil then
    deadline = self.settleUntil
  end
  self.deadline = deadline
  if not self.running then
    self.waiting = true
  end
end

-- One character replan for a burst of events. An unchanged snapshot
-- does not schedule anything.
function Schedule:PushCharacter(now, reason, changed)
  if not changed then
    perfAdd("unchangedSnapshots", 1)
    return false
  end
  if OnyxiaGold.Revisions and OnyxiaGold.Revisions.BumpCharacter then
    OnyxiaGold.Revisions:BumpCharacter(reason)
  end
  self:Push(now, "plan", reason)
  return true
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
  if self.wallStart then
    local elapsed = clockNow() - self.wallStart
    if type(GetTime) ~= "function" then
      elapsed = 0
    end
    if elapsed < 0 then
      elapsed = 0
    end
    local perf = OnyxiaGold.Performance
    if perf and perf.AddTime and elapsed > 0 then
      perf:AddTime("wall", elapsed * 1000)
    end
  end
  self.wallStart = nil
  self.running = false
  self.co = nil
  self.activeSlice = nil
  if Schedule.activeSlice and Schedule.activeSlice.owner == self then
    Schedule.activeSlice = nil
  end
  local ran = self.ranJob
  local ranRank = rankOf(ran)
  local nextRank = rankOf(self.job)
  local token = self.token
  local current = token and token.IsCurrent and token:IsCurrent()
  if self.pending and current and ranRank >= 2 and nextRank > 0 and nextRank < ranRank then
    self.pending = false
    self.job = nil
    self.waiting = false
    self.ranJob = nil
    self.token = nil
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
  self.token = nil
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
  local cache = OnyxiaGold.CandidateCache
  if cache and cache.building then
    cache.building = false
    cache.partial = nil
  end
end

function Schedule:CancelObsolete(now)
  self:RestorePartial()
  self.staleCancels = (self.staleCancels or 0) + 1
  perfAdd("staleCancels", 1)
  self.cancelled = true
  local kind = self.ranJob or "plan"
  self.running = false
  self.co = nil
  self.activeSlice = nil
  if Schedule.activeSlice and Schedule.activeSlice.owner == self then
    Schedule.activeSlice = nil
  end
  self.wallStart = nil
  self.token = nil
  self.ranJob = nil
  if not self.pending then
    self.job = kind
    self.pending = true
  end
  self.waiting = true
  now = tonumber(now) or 0
  local quiet = tonumber(self.quiet) or 0.75
  if now + quiet > (self.deadline or 0) then
    self.deadline = now + quiet
  end
end

function Schedule:StopRunaway(now, why)
  self:RestorePartial()
  self.running = false
  self.co = nil
  self.activeSlice = nil
  if Schedule.activeSlice and Schedule.activeSlice.owner == self then
    Schedule.activeSlice = nil
  end
  self.errorHold = { kind = self.ranJob or "plan", snap = self.token and self.token.snap }
  self.pending = false
  self.waiting = false
  self.job = nil
  self.wallStart = nil
  self.token = nil
  perfAdd("runaways", 1)
  if OnyxiaGold.Log and OnyxiaGold.Log.Warn then
    OnyxiaGold.Log:Warn("Perf", "Stopped a runaway " .. tostring(self.errorHold.kind) .. " job (" .. tostring(why) .. ")")
  end
end

function Schedule.Tick()
  local slice = Schedule.activeSlice
  if not slice then
    return
  end
  if slice.token and slice.token.IsCurrent and not slice.token:IsCurrent() then
    coroutine.yield("obsolete")
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
        if slice.token and slice.token.IsCurrent and not slice.token:IsCurrent() then
          coroutine.yield("obsolete")
        end
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
    if slice.token and slice.token.IsCurrent and not slice.token:IsCurrent() then
      coroutine.yield("obsolete")
    end
    if perf and perf.YieldResume then
      perf:YieldResume()
    end
  end
end

function Schedule:Advance(now)
  if not self.co then
    return "done"
  end
  if (self.skipFrames or 0) > 0 then
    self.skipFrames = self.skipFrames - 1
    return "backoff"
  end
  local heavy = self.ranJob == "market" or self.ranJob == "plan"
  if heavy and self:HeavyBlocked(now) then
    return "paused"
  end
  self.jobSlices = (self.jobSlices or 0) + 1
  if self.jobSlices > (tonumber(self.runawayLimitSlices) or 12000) then
    self:StopRunaway(now, "slices")
    return "runaway"
  end
  if self.wallStart and type(GetTime) == "function" then
    local age = clockNow() - self.wallStart
    if age > (tonumber(self.runawayLimitWall) or 180) then
      self:StopRunaway(now, "wall")
      return "runaway"
    end
  end
  if not self.activeSlice then
    self.activeSlice = { token = self.token, owner = self }
  end
  Schedule.activeSlice = self.activeSlice
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
  local ok, yielded = coroutine.resume(self.co)
  local spent = 0
  if started and type(debugprofilestop) == "function" then
    local stopped = debugprofilestop()
    if type(stopped) == "number" then
      spent = stopped - started
      if spent < 0 then
        spent = 0
      end
      local perf = OnyxiaGold.Performance
      if perf and perf.NoteSlice then
        perf:NoteSlice(spent)
      end
      self.jobCpu = (self.jobCpu or 0) + spent
    end
  end
  local limit = budgetMs()
  if spent > limit * 2 then
    self.skipFrames = 2
  elseif spent > limit then
    self.skipFrames = 1
  end
  if ok and yielded == "obsolete" then
    self:CancelObsolete(now)
    return "cancelled"
  end
  local dead = coroutine.status(self.co) == "dead"
  if not ok or dead then
    if not ok then
      self:RestorePartial()
      self.errorHold = { kind = self.ranJob, snap = self.token and self.token.snap }
      self.running = false
      self.co = nil
      self.activeSlice = nil
      if Schedule.activeSlice and Schedule.activeSlice.owner == self then
        Schedule.activeSlice = nil
      end
      local changed = self.token and self.token.IsCurrent and not self.token:IsCurrent()
      if not (self.pending and changed) then
        self.pending = false
        self.waiting = false
        self.job = nil
      else
        self.waiting = true
        self.errorHold = nil
      end
      self.token = nil
      self.wallStart = nil
      if OnyxiaGold.Log and OnyxiaGold.Log.Warn then
        OnyxiaGold.Log:Warn("Refresh", tostring(yielded))
      end
      return "error"
    end
    self:Finish(now)
    return "done"
  end
  return "slice"
end

local function isolated(name)
  local flag = OnyxiaGold.PerfIsolate
  if not flag or flag == "" or flag == "none" then
    return false
  end
  return flag == name
end

local function runJob(job)
  local perf = OnyxiaGold.Performance
  if job == "market" then
    if perf and perf.AllocMark then
      perf:AllocMark("market")
    end
    if not isolated("flips") and not isolated("paths") then
      local cache = OnyxiaGold.CandidateCache
      if cache and cache.Build then
        cache:Build()
      elseif OnyxiaGold.OpportunityEngine and OnyxiaGold.OpportunityEngine.Refresh then
        OnyxiaGold.OpportunityEngine:Refresh()
      end
    end
    if perf and perf.AllocDelta then
      perf:AllocDelta("market")
    end
  end
  if job == "market" or job == "plan" then
    if not isolated("planner") then
      if perf and perf.AllocMark then
        perf:AllocMark("planner")
      end
      if OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.Refresh then
        OnyxiaGold.ActionPlanner:Refresh()
      end
      if perf and perf.AllocDelta then
        perf:AllocDelta("planner")
      end
    end
  end
  if not isolated("ui") then
    if OnyxiaGold.UI and OnyxiaGold.UI.frame and OnyxiaGold.UI.Refresh then
      OnyxiaGold.UI:Refresh()
    end
  end
end

function Schedule:Begin(now)
  now = tonumber(now) or 0
  local perf = OnyxiaGold.Performance
  if perf and perf.NotePump then
    perf:NotePump(self.running or (self.pending and self.waiting))
  end
  if self.co then
    return self:Advance(now)
  end
  if (self.skipFrames or 0) > 0 and not self.running then
    self.skipFrames = self.skipFrames - 1
    return "backoff"
  end
  if self:Poll(now) ~= "start" then
    return "idle"
  end
  local job = self.job or "ui"
  if (job == "market" or job == "plan") and self:HeavyBlocked(now) then
    self.running = false
    self.pending = true
    self.waiting = true
    self.job = job
    local resumeAt = now + 0.25
    if self.settleUntil and resumeAt < self.settleUntil then
      resumeAt = self.settleUntil
    end
    self.deadline = resumeAt
    return "deferred"
  end
  if OnyxiaGold.Scanner and OnyxiaGold.Scanner.IsScanning and OnyxiaGold.Scanner:IsScanning() and job ~= "market" then
    self.running = false
    self.pending = true
    self.waiting = true
    self.deadline = now + 0.25
    return "deferred"
  end
  local reason = self.reason
  self.job = nil
  self.reason = nil
  self.ranJob = job
  self.cancelled = false
  self.jobSlices = 0
  self.jobCpu = 0
  self.token = self:Capture(job)
  self.revAtStart = self.token and self.token.snap or nil
  if perf and perf.NoteRefresh then
    perf:NoteRefresh(job, reason)
  end
  self.wallStart = clockNow()
  self.activeSlice = { token = self.token, owner = self }
  Schedule.activeSlice = self.activeSlice
  local runner = self.runner or runJob
  self.co = coroutine.create(function()
    runner(job)
  end)
  return self:Advance(now)
end

function Schedule:SetMode(mode)
  if mode == "aggressive" then
    self.mode = "aggressive"
    Schedule.mode = "aggressive"
  else
    self.mode = "safe"
    Schedule.mode = "safe"
  end
  return Schedule.mode
end

function Schedule:TogglePause(now)
  self.paused = not self.paused
  if not self.paused then
    self:Push(tonumber(now) or clockNow(), "plan", "resume")
  end
  return self.paused
end

function Schedule:JobLine()
  local kind = self.ranJob or self.job or "none"
  local age = 0
  if self.wallStart then
    age = clockNow() - self.wallStart
    if age < 0 then
      age = 0
    end
  end
  local snap = self.token and self.token.snap
  local revText = "none"
  if type(snap) == "table" then
    local parts = {}
    for key, value in pairs(snap) do
      parts[table.getn(parts) + 1] = tostring(key) .. "=" .. tostring(value)
    end
    table.sort(parts)
    if table.getn(parts) > 0 then
      revText = table.concat(parts, " ")
    end
  end
  local pending = self.job or "none"
  return string.format(
    "job: %s age %.2fs cpu %.2f ms cancelled %s stale %d pending %s inputs %s",
    tostring(kind),
    age,
    tonumber(self.jobCpu) or 0,
    self.cancelled and "yes" or "no",
    tonumber(self.staleCancels) or 0,
    tostring(pending),
    revText
  )
end
