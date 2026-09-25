--[[
  OnyxiaGold - Core
  Namespace, config, money helpers, events, and slash commands.
  Compatible with Lua 5.1 / WoW 3.3.5a.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Version = "0.1.0"
OnyxiaGold.DB_VERSION = 1

OnyxiaGold.Data = OnyxiaGold.Data or {}
OnyxiaGold.Engines = OnyxiaGold.Engines or {}

-- Single source of truth for economic constants. Do not scatter cut math.
OnyxiaGold.Config = {
  AuctionHouseCut = 0.05,
  TransmuteMasterMultiplier = 1.20,
  -- Seconds to wait after CanSendAuctionQuery() before sending the next page.
  ScanDelay = 0.45,
  ScanPageTimeout = 12,
  MaxPageRetries = 3,
  -- 3.3.5a browse pages are 50 listings. Processing is still sliced per frame.
  PageSize = 50,
  AuctionsPerFrame = 25,
  FinalizeItemsPerFrame = 30,
  MaxHistoryPoints = 30,
  MaxScanSummaries = 20,
  MaxLogLines = 800,
}

local COPPER_PER_SILVER = 100
local COPPER_PER_GOLD = 10000

function OnyxiaGold:GetAuctionHouseCut()
  local cut = self.Config.AuctionHouseCut
  if OnyxiaGoldDB and OnyxiaGoldDB.settings and OnyxiaGoldDB.settings.auctionHouseCut then
    cut = OnyxiaGoldDB.settings.auctionHouseCut
  end
  if OnyxiaGold.Data.OnyxiaOverrides and OnyxiaGold.Data.OnyxiaOverrides.auctionHouseCut then
    cut = OnyxiaGold.Data.OnyxiaOverrides.auctionHouseCut
  end
  cut = tonumber(cut) or self.Config.AuctionHouseCut
  if cut < 0 then
    cut = 0
  elseif cut > 1 then
    cut = 1
  end
  return cut
end

-- Convert a percentage cut into integer basis points of 10000 (5% = 500).
function OnyxiaGold:GetAuctionHouseCutBPS()
  return math.floor(self:GetAuctionHouseCut() * 10000 + 0.5)
end

-- Apply AH cut using integer math. 1c listings still round down, never negative.
function OnyxiaGold:ApplyAuctionHouseCut(grossCopper)
  grossCopper = tonumber(grossCopper) or 0
  if grossCopper <= 0 then
    return 0
  end
  local bps = self:GetAuctionHouseCutBPS()
  return math.floor(grossCopper * (10000 - bps) / 10000)
end

function OnyxiaGold.GoldToCopper(gold, silver, copper)
  gold = tonumber(gold) or 0
  silver = tonumber(silver) or 0
  copper = tonumber(copper) or 0
  return math.floor(gold * COPPER_PER_GOLD + silver * COPPER_PER_SILVER + copper + 0.5)
end

function OnyxiaGold.FormatMoney(copper)
  copper = tonumber(copper) or 0
  local negative = copper < 0
  if negative then
    copper = -copper
  end
  copper = math.floor(copper + 0.5)
  local g = math.floor(copper / COPPER_PER_GOLD)
  local s = math.floor(math.mod(copper, COPPER_PER_GOLD) / COPPER_PER_SILVER)
  local c = math.mod(copper, COPPER_PER_SILVER)
  local text
  if g > 0 then
    text = string.format("%d|cffffd70ag|r %02d|cffc7c7cfs|r %02d|cffeda55fc|r", g, s, c)
  elseif s > 0 then
    text = string.format("%d|cffc7c7cfs|r %02d|cffeda55fc|r", s, c)
  else
    text = string.format("%d|cffeda55fc|r", c)
  end
  if negative then
    return "|cffff4040-|r" .. text
  end
  return text
end

function OnyxiaGold.FormatMoneySigned(copper)
  copper = tonumber(copper) or 0
  if copper > 0 then
    return "|cff20ff20+|r" .. OnyxiaGold.FormatMoney(copper)
  elseif copper < 0 then
    return OnyxiaGold.FormatMoney(copper)
  end
  return OnyxiaGold.FormatMoney(0)
end

function OnyxiaGold.FormatPercent(ratio)
  ratio = tonumber(ratio) or 0
  return string.format("%d%%", math.floor(ratio * 100 + 0.5))
end

-- 3.3.5a item links: |Hitem:itemId:enchant:gem1:gem2:gem3:gem4:suffix:uniqueId:level|h[name]|h|r
function OnyxiaGold.ParseItemID(link)
  if type(link) ~= "string" then
    return nil
  end
  local id = string.match(link, "item:(%d+)")
  return tonumber(id)
end

function OnyxiaGold:IsDebug()
  return OnyxiaGoldDB and OnyxiaGoldDB.settings and OnyxiaGoldDB.settings.debug
end

function OnyxiaGold:Debug(message, module)
  if OnyxiaGold.Log and OnyxiaGold.Log.Debug then
    OnyxiaGold.Log:Debug(module or "Core", message)
  elseif self:IsDebug() then
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffOnyxiaGold:|r " .. tostring(message))
  end
end

function OnyxiaGold:Print(message, module)
  if OnyxiaGold.Log and OnyxiaGold.Log.Info then
    OnyxiaGold.Log:Info(module or "Core", message)
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99OnyxiaGold:|r " .. tostring(message))
  end
end

function OnyxiaGold:Warn(message, module)
  if OnyxiaGold.Log and OnyxiaGold.Log.Warn then
    OnyxiaGold.Log:Warn(module or "Core", message)
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00OnyxiaGold:|r " .. tostring(message))
  end
end

function OnyxiaGold:IsTransmuteMaster()
  if OnyxiaGold.Data.OnyxiaOverrides and OnyxiaGold.Data.OnyxiaOverrides.transmuteMaster ~= nil then
    return OnyxiaGold.Data.OnyxiaOverrides.transmuteMaster and true or false
  end
  if OnyxiaGoldDB and OnyxiaGoldDB.settings then
    return OnyxiaGoldDB.settings.transmuteMaster and true or false
  end
  return false
end

function OnyxiaGold:GetTransmuteMultiplier()
  if self:IsTransmuteMaster() then
    local m = self.Config.TransmuteMasterMultiplier
    if OnyxiaGoldDB and OnyxiaGoldDB.settings and OnyxiaGoldDB.settings.transmuteMasterMultiplier then
      m = OnyxiaGoldDB.settings.transmuteMasterMultiplier
    end
    return tonumber(m) or 1.20
  end
  return 1.0
end

function OnyxiaGold:ToggleDebug()
  OnyxiaGold.Database:Ensure()
  OnyxiaGoldDB.settings.debug = not OnyxiaGoldDB.settings.debug
  if OnyxiaGoldDB.settings.debug then
    self:Print("Debug chat enabled. Internal log was already recording.")
  else
    self:Print("Debug chat disabled. Internal log still records in /og log.")
  end
end

function OnyxiaGold:HandleSlash(msg)
  msg = string.lower(strtrim(msg or ""))
  if OnyxiaGold.Log then
    OnyxiaGold.Log:Debug("Core", "slash /og " .. msg)
  end
  if msg == "" then
    self.UI:Toggle()
  elseif msg == "scan" then
    self.Scanner:Start()
  elseif msg == "opportunities" or msg == "opp" then
    self.OpportunityEngine:Refresh()
    self.UI:Show()
  elseif msg == "debug" then
    self:ToggleDebug()
  elseif msg == "log" or string.sub(msg, 1, 4) == "log " then
    local rest = ""
    if string.sub(msg, 1, 4) == "log " then
      rest = string.sub(msg, 5)
    end
    self.Log:HandleSlash(rest)
  elseif msg == "reset" then
    self:Print("This will wipe price data (the log is kept). Type |cffffff00/og reset confirm|r to proceed.")
  elseif msg == "reset confirm" then
    self.Database:Reset()
    self.UI:Refresh()
  elseif msg == "master" then
    OnyxiaGold.Database:Ensure()
    OnyxiaGoldDB.settings.transmuteMaster = not OnyxiaGoldDB.settings.transmuteMaster
    if OnyxiaGoldDB.settings.transmuteMaster then
      self:Print("Transmute Master expected output enabled (x" .. tostring(self:GetTransmuteMultiplier()) .. ").")
    else
      self:Print("Transmute Master expected output disabled (x1.00).")
    end
    self.OpportunityEngine:Refresh()
  else
    self:Print("Commands: /og, /og scan, /og opportunities, /og debug, /og log, /og reset, /og master")
  end
end

SLASH_ONYXIAGOLD1 = "/og"
SLASH_ONYXIAGOLD2 = "/onyxiagold"
SlashCmdList["ONYXIAGOLD"] = function(msg)
  OnyxiaGold:HandleSlash(msg)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == "OnyxiaGold" then
    OnyxiaGold.Database:Init()
    if OnyxiaGold.Log and OnyxiaGold.Log.HookErrors then
      OnyxiaGold.Log:HookErrors()
    end
    OnyxiaGold:Debug("Addon loaded, database version " .. tostring(OnyxiaGoldDB.version), "Database")
  elseif event == "PLAYER_LOGIN" then
    if OnyxiaGold.Data.ApplyOnyxiaOverrides then
      OnyxiaGold.Data.ApplyOnyxiaOverrides()
    end
    if OnyxiaGold.Log and OnyxiaGold.Log.StartSession then
      OnyxiaGold.Log:StartSession()
    end
    OnyxiaGold.UI:Create()
    OnyxiaGold:Print("v" .. OnyxiaGold.Version .. " loaded. Type /og to open, /og log to copy diagnostics.")
  end
end)
