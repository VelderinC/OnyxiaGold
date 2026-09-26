--[[
  OnyxiaGold.Revisions
  Domain counters. Market and recipe changes rebuild candidates.
  Character changes reallocate the cache. Window events do not.
  Pure Lua 5.1.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Revisions = OnyxiaGold.Revisions or {}

local Rev = OnyxiaGold.Revisions

Rev.market = 0
Rev.recipe = 0
Rev.character = 0
Rev.candidate = 0
Rev.plan = 0
Rev.ui = 0

function Rev:Get(name)
  return tonumber(self[name]) or 0
end

function Rev:Bump(name)
  if self[name] == nil or type(self[name]) ~= "number" then
    return 0
  end
  self[name] = self[name] + 1
  return self[name]
end

function Rev:Snapshot()
  return {
    market = self.market,
    recipe = self.recipe,
    character = self.character,
    candidate = self.candidate,
    plan = self.plan,
    ui = self.ui,
  }
end

-- Ui-only bumps do not invalidate a plan that already painted.
function Rev:SameEconomics(snap)
  if type(snap) ~= "table" then
    return false
  end
  return snap.market == self.market
    and snap.recipe == self.recipe
    and snap.character == self.character
    and snap.candidate == self.candidate
    and snap.plan == self.plan
end
