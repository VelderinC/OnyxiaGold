--[[
  One disposition for an item already on the character.
  Uses the disenchant engine and the price book. An unset yield is not a value.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.AssetClassifier = OnyxiaGold.AssetClassifier or {}

local Classifier = OnyxiaGold.AssetClassifier

local BADGE = {
  USE_NOW = "USE",
  DISENCHANT = "DE",
  SELL = "SELL",
  VENDOR = "VENDOR",
  WAIT = "WAIT",
  UNKNOWN = "?",
  LOCKED = "LOCKED",
}

local function result(label, worth, why)
  return {
    label = label,
    badge = BADGE[label] or "?",
    worth = worth,
    why = why or "",
  }
end

local function actionNeeds(itemID, actions)
  if type(actions) ~= "table" then
    local planner = OnyxiaGold.ActionPlanner
    if not planner or not planner.GetActions then
      return nil
    end
    actions = planner:GetActions() or {}
  end
  for i = 1, table.getn(actions) do
    local action = actions[i]
    if (action.crafts or 0) > 0 then
      local lines = action.person and action.person.inputLines
      if type(lines) == "table" then
        for j = 1, table.getn(lines) do
          local line = lines[j]
          if line and line.itemID == itemID and ((line.ownedUnits or 0) > 0 or (line.buyUnits or 0) > 0) then
            return action
          end
        end
      end
    end
  end
  return nil
end

function Classifier:Disposition(itemID, count, meta, actions)
  itemID = tonumber(itemID)
  count = tonumber(count) or 0
  if not itemID or count < 1 then
    return result("UNKNOWN", nil, "No count.")
  end
  local action = actionNeeds(itemID, actions)
  if action then
    local worth = OnyxiaGold.Prices and OnyxiaGold.Prices:GetLiquidationPrice(itemID) or nil
    return result("USE_NOW", worth, "Used by " .. tostring(action.name) .. ".")
  end

  local de
  if meta and OnyxiaGold.Engines and OnyxiaGold.Engines.Disenchant then
    de = OnyxiaGold.Engines.Disenchant:EvaluateOwned(itemID, count, meta)
  end
  if de then
    local cap = OnyxiaGold.Capabilities and OnyxiaGold.Capabilities:CanExecute(de.requirements)
    if cap and cap.executable then
      return result("DISENCHANT", de.expectedProfit, "Disenchant beats vendor. " .. tostring(de.notes or ""))
    end
    if cap and (cap.missingSkill or cap.missingProfession) then
      return result("LOCKED", nil, cap.reason or "Enchanting skill is too low.")
    end
  end

  local prices = OnyxiaGold.Prices
  if prices and prices:GetRecord(itemID) and prices:IsStale(itemID) then
    return result("WAIT", nil, "Market data is stale.")
  end

  local sale = prices and prices:GetOpportunitySaleUnit(itemID) or nil
  local vendor = meta and tonumber(meta.vendorPrice) or 0
  if vendor < 0 then
    vendor = 0
  end
  if not sale and vendor <= 0 then
    return result("UNKNOWN", nil, "No price and no vendor value.")
  end
  if sale then
    local net = OnyxiaGold:ApplyAuctionHouseCut(sale)
    if vendor > net then
      return result("VENDOR", vendor, "Vendor is higher than the auction after the cut.")
    end
    return result("SELL", net, "Auction after the cut is the better known exit.")
  end
  return result("VENDOR", vendor, "Vendor is the only known value.")
end
