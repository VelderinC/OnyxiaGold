-- Pure Lua runner. Lua 5.1 or later. No WoW client.
if not table.getn then
  function table.getn(t)
    return #t
  end
end

OnyxiaGold = {}
OnyxiaGold.DB_VERSION = 4
OnyxiaGold.Config = {
  AuctionHouseCut = 0.05,
  PageSize = 50,
  MaxHistoryPoints = 30,
  MaxScanSummaries = 20,
  MaxLogLines = 800,
  MaxTradeLines = 400,
  MaxDepthLevelsPerItem = 100,
  QuickScanStaleSeconds = 600,
  SliceBudgetMs = 2,
  SliceWarnMs = 4,
  HighValuePostCopper = 500000,
}
function OnyxiaGold:Debug()
end
function OnyxiaGold:Warn()
end
function OnyxiaGold:Print()
end
function OnyxiaGold:GetAuctionHouseCut()
  return 0.05
end
function OnyxiaGold:GetAuctionHouseCutBPS()
  return 500
end

function GetRealmName()
  return "Onyxia"
end

function UnitFactionGroup()
  return "Horde"
end

function UnitName()
  return "Tester"
end

function time()
  return os.time()
end

function date(fmt, when)
  return os.date(fmt, when)
end

function CreateFrame()
  return {
    RegisterEvent = function() end,
    SetScript = function() end,
    Show = function() end,
    Hide = function() end,
  }
end

local root = arg and arg[0] or "tests/run.lua"
root = string.gsub(root, "tests/run%.lua$", "")
root = string.gsub(root, "tests\\run%.lua$", "")
if root ~= "" and string.sub(root, -1) ~= "/" and string.sub(root, -1) ~= "\\" then
  root = root .. "/"
end

local function load(path)
  local chunk, err = loadfile(root .. path)
  if not chunk then
    io.stderr:write(tostring(err) .. "\n")
    os.exit(1)
  end
  chunk()
end

load("RefreshSchedule.lua")
load("Revisions.lua")
load("Performance.lua")
load("Prices.lua")
load("Lots.lua")
load("Data/ItemGroups.lua")
load("Data/Recipes.lua")
load("SessionState.lua")
load("RecipeBook.lua")
load("SessionPlan.lua")
load("TradeLog.lua")
load("Database.lua")
load("ItemInfo.lua")
load("Log.lua")
load("CandidateCache.lua")
load("AuctionStop.lua")
load("Tests.lua")

local text, ok = OnyxiaGold.Tests:Run()
io.write(text)
io.write("\n")
if ok then
  os.exit(0)
end
os.exit(1)
