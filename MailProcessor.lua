--[[
  OnyxiaGold.MailProcessor
  User-triggered collection of auction-house mail.
  One take per click, because 3.3.5 take functions need a hardware event.
  COD, personal, and unknown mail are never taken. Mail is never deleted.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.MailProcessor = OnyxiaGold.MailProcessor or {}

local Processor = OnyxiaGold.MailProcessor
Processor.state = "IDLE"
Processor.step = nil

local SAFE = {
  AH_SALE_GOLD = true,
  AH_PURCHASE_ITEM = true,
  AH_WON_ITEM = true,
  AH_EXPIRED_ITEM = true,
  AH_CANCELLED_ITEM = true,
}

local function messages()
  local row = OnyxiaGold.Database and OnyxiaGold.Database:GetCharacter()
  local list = row and row.mail and row.mail.messages
  if type(list) ~= "table" then
    return {}
  end
  return list
end

local function plannedItem(itemID)
  local planner = OnyxiaGold.ActionPlanner
  if not planner or not planner.GetActions then
    return false
  end
  local actions = planner:GetActions() or {}
  for i = 1, table.getn(actions) do
    local lines = actions[i].person and actions[i].person.inputLines
    if type(lines) == "table" then
      for j = 1, table.getn(lines) do
        if lines[j] and lines[j].itemID == itemID and (lines[j].buyUnits or 0) > 0 then
          return true
        end
      end
    end
  end
  return false
end

local function rankOf(message)
  if message.class == "AH_SALE_GOLD" then
    return 1
  end
  local attached = message.items or {}
  for i = 1, table.getn(attached) do
    if plannedItem(attached[i].itemID) then
      return 2
    end
  end
  if message.class == "AH_PURCHASE_ITEM" or message.class == "AH_WON_ITEM" then
    return 3
  end
  if message.class == "AH_EXPIRED_ITEM" or message.class == "AH_CANCELLED_ITEM" then
    return 4
  end
  return nil
end

function Processor:Summary()
  local counts = {
    gold = 0,
    goldCopper = 0,
    materials = 0,
    returns = 0,
    personal = 0,
    cod = 0,
    unknown = 0,
    pending = 0,
  }
  local list = messages()
  for i = 1, table.getn(list) do
    local message = list[i]
    if message.class == "AH_SALE_GOLD" then
      counts.gold = counts.gold + 1
      counts.goldCopper = counts.goldCopper + (message.money or 0)
    elseif message.class == "AH_PURCHASE_ITEM" or message.class == "AH_WON_ITEM" then
      counts.materials = counts.materials + 1
    elseif message.class == "AH_EXPIRED_ITEM" or message.class == "AH_CANCELLED_ITEM" then
      counts.returns = counts.returns + 1
    elseif message.class == "PERSONAL_MAIL" then
      counts.personal = counts.personal + 1
    elseif message.class == "COD_MAIL" then
      counts.cod = counts.cod + 1
    elseif message.class == "AH_PENDING_SALE" then
      counts.pending = counts.pending + 1
    else
      counts.unknown = counts.unknown + 1
    end
  end
  counts.state = self.state
  counts.step = self.step
  return counts
end

function Processor:SummaryLine()
  local s = self:Summary()
  local gold = OnyxiaGold.FormatMoney and OnyxiaGold.FormatMoney(s.goldCopper) or tostring(s.goldCopper)
  local line = string.format(
    "Factory mail. Gold %s. Materials %d. Returns %d. Personal %d. COD %d. Unknown %d.",
    gold, s.materials, s.returns, s.personal, s.cod, s.unknown
  )
  if self.step then
    line = line .. " " .. self.step
  end
  return line
end

local function forbidden(message)
  if not message then
    return true
  end
  if message.class == "COD_MAIL" or message.class == "PERSONAL_MAIL" or message.class == "UNKNOWN" then
    return true
  end
  if message.safety ~= "SAFE_AUTO_PROCESS" or not SAFE[message.class] then
    return true
  end
  if (tonumber(message.cod) or 0) > 0 then
    return true
  end
  return false
end

function Processor:NextSafe(goldOnly)
  local list = messages()
  local best, bestRank
  for i = 1, table.getn(list) do
    local message = list[i]
    if not forbidden(message) then
      local rank = rankOf(message)
      local gold = message.class == "AH_SALE_GOLD"
      if rank and (not goldOnly or gold) then
        if not bestRank or rank < bestRank or (rank == bestRank and message.index < best.index) then
          best = message
          bestRank = rank
        end
      end
    end
  end
  return best
end

local function needsBag(message)
  return message and message.class ~= "AH_SALE_GOLD" and (tonumber(message.itemCount) or 0) > 0
end

local function bagBlocked(message)
  if not needsBag(message) then
    return false
  end
  local inv = OnyxiaGold.Inventory
  if not inv or not inv.GetFreeGeneralSlots then
    return true, "Bag space is unknown. Open the bags, then click again."
  end
  local free = inv:GetFreeGeneralSlots()
  if free == nil then
    return true, "Bag space is unknown. Open the bags, then click again."
  end
  if free < 1 then
    return true, "Factory Sweep paused. Need a free bag slot."
  end
  return false
end

function Processor:Take(message, fromClick)
  if forbidden(message) then
    self.state = "BLOCKED_MAIL"
    self.step = "Left untouched."
    return false
  end
  local takeAllowed = OnyxiaGold.Lots and OnyxiaGold.Lots.AllowTakeInbox and OnyxiaGold.Lots.AllowTakeInbox(fromClick)
  if not takeAllowed then
    self.state = "WAITING_FOR_CLIENT"
    self.step = "Click again. Taking mail needs a hardware event."
    return false
  end
  local blocked, why = bagBlocked(message)
  if blocked then
    self.state = "BAG_FULL"
    self.step = why or "Factory Sweep paused. Need a free bag slot."
    return false
  end
  local index = message.index
  if message.class == "AH_SALE_GOLD" then
    if type(TakeInboxMoney) ~= "function" then
      self.state = "ERROR"
      self.step = "Open the sale mail and take the money."
      return false
    end
    local ok = pcall(TakeInboxMoney, index)
    if not ok then
      self.state = "ERROR"
      self.step = "Open the sale mail and take the money. This click could not take it."
      return false
    end
  else
    if type(TakeInboxItem) ~= "function" then
      self.state = "ERROR"
      self.step = "Open the auction mail and take the item."
      return false
    end
    local ok = pcall(TakeInboxItem, index, 1)
    if not ok then
      self.state = "ERROR"
      self.step = "Open the auction mail and take the item. This click could not take it."
      return false
    end
  end
  self.state = "WAITING_FOR_CLIENT"
  self.step = "Waiting for the mailbox to update."
  self.attempted = index
  return true
end

function Processor:CollectGold(fromClick)
  local message = self:NextSafe(true)
  if not message then
    self.state = "COMPLETE"
    self.step = "No sale gold to collect."
    return false
  end
  self.state = "PROCESSING"
  return self:Take(message, fromClick)
end

function Processor:Sweep(fromClick)
  local message = self:NextSafe(false)
  if not message then
    self.state = "COMPLETE"
    self.step = "No safe auction mail left."
    return false
  end
  self.state = "PROCESSING"
  return self:Take(message, fromClick)
end
