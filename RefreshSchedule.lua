--[[
  OnyxiaGold.RefreshSchedule
  Coalesce UI-thread rebuilds. A burst of auction, mail, bag, or profession
  events schedules one refresh after the burst goes quiet. That refresh
  runs in short slices so the client can paint between them. A second
  pass is not started until the first one has finished and gone quiet.
  Pure Lua 5.1. No WoW frame is created here.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.RefreshSchedule = OnyxiaGold.RefreshSchedule or {}

local Schedule = OnyxiaGold.RefreshSchedule

Schedule.quiet = 0.75
Schedule.budgetMs = 12
Schedule.yieldEvery = 4
Schedule.pending = false
Schedule.waiting = false
Schedule.running = false
Schedule.deadline = 0
Schedule.wantEngine = false
Schedule.wantPlanner = false

function Schedule.New(quiet)
  return setmetatable({
    quiet = tonumber(quiet) or Schedule.quiet or 0.75,
    pending = false,
    waiting = false,
    running = false,
    deadline = 0,
    wantEngine = false,
    wantPlanner = false,
  }, { __index = Schedule })
end

function Schedule:Push(now, kind)
  self.pending = true
  if kind == "engine" then
    self.wantEngine = true
  else
    self.wantPlanner = true
  end
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
  self.running = false
  self.co = nil
  self.activeSlice = nil
  if self.pending then
    self.waiting = true
    now = tonumber(now) or 0
    if now >= (self.deadline or 0) then
      self.deadline = now + (tonumber(self.quiet) or 0.75)
    end
  else
    self.waiting = false
  end
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

-- Called from the hot loops. No work when a refresh is not sliced.
-- debugprofilestop is the 3.3.5 frame timer. The gap while this coroutine
-- is yielded is not counted, or the next tick would yield immediately.
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
      local budget = tonumber(Schedule.budgetMs) or 12
      if budget < 1 then
        budget = 1
      end
      if now - slice.mark >= budget then
        slice.mark = nil
        coroutine.yield()
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
  local every = tonumber(Schedule.yieldEvery) or 4
  if every < 1 then
    every = 1
  end
  if slice.steps % every == 0 then
    slice.steps = 0
    coroutine.yield()
  end
end

function Schedule:Advance(now)
  if not self.co then
    return "done"
  end
  if not self.activeSlice then
    self.activeSlice = {}
  end
  local ok, err = coroutine.resume(self.co)
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
  local engine = self.wantEngine and true or false
  self.wantEngine = false
  self.wantPlanner = false
  self.activeSlice = {}
  self.co = coroutine.create(function()
    if engine and OnyxiaGold.OpportunityEngine and OnyxiaGold.OpportunityEngine.Refresh then
      OnyxiaGold.OpportunityEngine:Refresh()
      return
    end
    if OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.Refresh then
      OnyxiaGold.ActionPlanner:Refresh()
    end
    if OnyxiaGold.UI and OnyxiaGold.UI.frame and OnyxiaGold.UI.Refresh then
      OnyxiaGold.UI:Refresh()
    end
  end)
  return self:Advance(now)
end
