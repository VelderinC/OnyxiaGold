--[[
  Optional Onyxia Alliance snapshot written by tools/OnyxiaGoldSync.
  The file is gitignored. A missing file leaves this module empty.
  External numbers never replace a newer live scan and never price a buy.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.ExternalMarket = OnyxiaGold.ExternalMarket or {}

local External = OnyxiaGold.ExternalMarket

local STALE_SECONDS = 3600

local function validSnapshot(data)
  if OnyxiaGold.Lots and OnyxiaGold.Lots.AcceptExternalSnapshot then
    return OnyxiaGold.Lots.AcceptExternalSnapshot(data)
  end
  return false
end

function External:Data()
  if validSnapshot(self.snapshot) then
    return self.snapshot
  end
  return nil
end

function External:Reload()
  -- The companion addon OnyxiaGoldExternal defines this global.
  -- WoW addon Lua has no loadfile, and a missing companion is not an error.
  if validSnapshot(OnyxiaGoldExternalData) then
    self.snapshot = OnyxiaGoldExternalData
  else
    self.snapshot = nil
  end
  return self:Data()
end

function External:AgeSeconds()
  local data = self:Data()
  if not data then
    return nil
  end
  local age = time() - data.scannedAt
  if age < 0 then
    age = 0
  end
  return age
end

function External:IsStale()
  local age = self:AgeSeconds()
  if age == nil then
    return false
  end
  local limit = OnyxiaGold.Config and OnyxiaGold.Config.ExternalStaleSeconds or STALE_SECONDS
  return age > limit
end

function External:StatusLine()
  local age = self:AgeSeconds()
  if age == nil or not OnyxiaGold.FormatAge then
    return nil
  end
  if self:IsStale() then
    return "External market: stale, " .. OnyxiaGold.FormatAge(age) .. " old."
  end
  return "External market: " .. OnyxiaGold.FormatAge(age) .. " old."
end

local function liveIsNewer(itemID, scannedAt)
  local db = OnyxiaGold.Database
  if not db or not db.GetLatest then
    return false
  end
  local live = db:GetLatest(itemID)
  if not live then
    return false
  end
  local ts = tonumber(live.timestamp)
  if not ts then
    return true
  end
  return ts >= scannedAt
end

-- Advisory only. Nil when the snapshot is missing, stale, or older than the live scan.
function External:Quote(itemID)
  local data = self:Data()
  if not data or self:IsStale() then
    return nil
  end
  itemID = tonumber(itemID)
  if not itemID then
    return nil
  end
  if liveIsNewer(itemID, data.scannedAt) then
    return nil
  end
  local row = data.items[itemID]
  if type(row) ~= "table" then
    return nil
  end
  return row
end

-- A snapshot never authorises a purchase.
function External:ForBuying(itemID)
  return nil
end

External:Reload()
