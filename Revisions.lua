--[[
  OnyxiaGold.Revisions
  Domain counters. A counter moves only when that data changes.

  Market and recipe revisions rebuild candidates. A character revision
  reallocates the cache. Plan revision is an output of a finished plan,
  not an input to the plan that produced it. Window events do not
  pretend the economy changed.

  Pure Lua 5.1.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Revisions = OnyxiaGold.Revisions or {}

local Rev = OnyxiaGold.Revisions

local NAMES = {
  market = true,
  recipe = true,
  character = true,
  candidate = true,
  plan = true,
  ui = true,
  cash = true,
  bag = true,
  bank = true,
  mail = true,
  owned = true,
  capability = true,
  cooldown = true,
  policy = true,
}

Rev.market = Rev.market or 0
Rev.recipe = Rev.recipe or 0
Rev.character = Rev.character or 0
Rev.candidate = Rev.candidate or 0
Rev.plan = Rev.plan or 0
Rev.ui = Rev.ui or 0
Rev.cash = Rev.cash or 0
Rev.bag = Rev.bag or 0
Rev.bank = Rev.bank or 0
Rev.mail = Rev.mail or 0
Rev.owned = Rev.owned or 0
Rev.capability = Rev.capability or 0
Rev.cooldown = Rev.cooldown or 0
Rev.policy = Rev.policy or 0

Rev.changed = Rev.changed or {
  cash = false,
  bags = {},
  bank = {},
  mail = {},
  listed = {},
  cooldowns = {},
}

function Rev:Get(name)
  return tonumber(self[name]) or 0
end

function Rev:Bump(name)
  if not NAMES[name] then
    return 0
  end
  self[name] = (tonumber(self[name]) or 0) + 1
  return self[name]
end

local function blankChanges()
  return {
    cash = false,
    bags = {},
    bank = {},
    mail = {},
    listed = {},
    cooldowns = {},
  }
end

local function noteItem(map, itemID)
  itemID = tonumber(itemID)
  if itemID then
    map[itemID] = true
  end
end

-- Character revision moves only at a real economic mutation.
-- reason selects the finer counter: cash, bag, bank, mail, owned,
-- capability, cooldown. The changed-resource set records which ids moved.
function Rev:BumpCharacter(reason, itemID)
  self.character = (tonumber(self.character) or 0) + 1
  self.lastCharacterReason = reason
  local changed = self.changed or blankChanges()
  self.changed = changed
  if reason == "cash" or reason == "money" then
    self.cash = (tonumber(self.cash) or 0) + 1
    changed.cash = true
  elseif reason == "bag" or reason == "bags" then
    self.bag = (tonumber(self.bag) or 0) + 1
    noteItem(changed.bags, itemID)
  elseif reason == "bank" then
    self.bank = (tonumber(self.bank) or 0) + 1
    noteItem(changed.bank, itemID)
  elseif reason == "mail" then
    self.mail = (tonumber(self.mail) or 0) + 1
    noteItem(changed.mail, itemID)
  elseif reason == "owned" or reason == "auctions" then
    self.owned = (tonumber(self.owned) or 0) + 1
    noteItem(changed.listed, itemID)
  elseif reason == "capability" or reason == "skill" then
    self.capability = (tonumber(self.capability) or 0) + 1
  elseif reason == "cooldown" then
    self.cooldown = (tonumber(self.cooldown) or 0) + 1
    if itemID then
      changed.cooldowns[itemID] = true
    end
  end
  return self.character
end

function Rev:NoteBagItem(itemID)
  local changed = self.changed or blankChanges()
  self.changed = changed
  noteItem(changed.bags, itemID)
end

function Rev:NoteListedItem(itemID)
  local changed = self.changed or blankChanges()
  self.changed = changed
  noteItem(changed.listed, itemID)
end

function Rev:TakeChanges()
  local changed = self.changed or blankChanges()
  self.changed = blankChanges()
  return changed
end

function Rev:Snapshot()
  return {
    market = self.market,
    recipe = self.recipe,
    character = self.character,
    candidate = self.candidate,
    plan = self.plan,
    ui = self.ui,
    cash = self.cash,
    bag = self.bag,
    bank = self.bank,
    mail = self.mail,
    owned = self.owned,
    capability = self.capability,
    cooldown = self.cooldown,
    policy = self.policy,
  }
end

-- Inputs a domain job is allowed to read. Plan revision is not an input
-- of the plan that creates it.
function Rev:CaptureFor(domain)
  if domain == "market" then
    return {
      market = self:Get("market"),
      recipe = self:Get("recipe"),
      policy = self:Get("policy"),
    }
  end
  if domain == "plan" then
    return {
      candidate = self:Get("candidate"),
      character = self:Get("character"),
      policy = self:Get("policy"),
    }
  end
  if domain == "ui" then
    return {
      plan = self:Get("plan"),
      ui = self:Get("ui"),
    }
  end
  return self:Snapshot()
end

function Rev:IsCurrentFor(domain, snap)
  if type(snap) ~= "table" then
    return false
  end
  local now = self:CaptureFor(domain)
  for key, value in pairs(now) do
    if snap[key] ~= value then
      return false
    end
  end
  for key, value in pairs(snap) do
    if now[key] ~= nil and now[key] ~= value then
      return false
    end
  end
  return true
end

-- Kept so older callers can ask. New jobs use CaptureFor / IsCurrentFor.
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
