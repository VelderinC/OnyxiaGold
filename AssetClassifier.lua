--[[
  One disposition for an item already on the character.
  Uses the disenchant engine and the price book. An unset yield is not a value.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.AssetClassifier = OnyxiaGold.AssetClassifier or {}

local Classifier = OnyxiaGold.AssetClassifier

local BADGE = {
  USE_NOW = "USE",
  WITHDRAW = "WITHDRAW",
  COLLECT = "COLLECT",
  DISENCHANT = "DE",
  SELL = "SELL",
  CHECK_AH = "CHECK_AH",
  UNKNOWN_EXIT = "UNKNOWN_EXIT",
  VENDOR = "VENDOR",
  WAIT = "WAIT",
  UNKNOWN = "?",
  LOCKED = "LOCKED",
  LISTED = "LISTED",
  LEAVE = "LEAVE",
  REPRICE = "REPRICE",
  HOLD = "HOLD",
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

function Classifier:Disposition(itemID, count, meta, actions, place)
  itemID = tonumber(itemID)
  count = tonumber(count) or 0
  place = place or "Bags"
  if not itemID or count < 1 then
    return result("UNKNOWN", nil, "No count.")
  end
  local action = actionNeeds(itemID, actions)
  if action then
    local worth = OnyxiaGold.Prices and OnyxiaGold.Prices:GetLiquidationPrice(itemID) or nil
    if place == "Bank" then
      return result("WITHDRAW", worth, "Withdraw, then use for " .. tostring(action.name) .. ".")
    end
    if place == "Mail" then
      return result("COLLECT", worth, "Collect, then use for " .. tostring(action.name) .. ".")
    end
    if place == "Listed" then
      return result("LEAVE", worth, "Already listed. Leave it while a craft still needs the material.")
    end
    return result("USE_NOW", worth, "Used by " .. tostring(action.name) .. ".")
  end

  if place == "Listed" then
    local market = OnyxiaGold.Prices and OnyxiaGold.Prices.GetMarketMinimum and OnyxiaGold.Prices:GetMarketMinimum(itemID)
    local own = OnyxiaGold.AuctionStop and OnyxiaGold.AuctionStop.OwnCheapestUnit
      and OnyxiaGold.AuctionStop.OwnCheapestUnit(itemID)
    if own and (not market or own <= market) then
      return result("LEAVE", own, "Your auction is already the cheapest.")
    end
    if market and own and market < own then
      return result("REPRICE", market, "The market minimum is under your auction.")
    end
    return result("LISTED", market, "Listed. Hold it unless a fresh check says to reprice.")
  end

  local exits
  if meta and OnyxiaGold.Engines and OnyxiaGold.Engines.Disenchant and OnyxiaGold.Engines.Disenchant.Exits then
    exits = OnyxiaGold.Engines.Disenchant:Exits(itemID, count, meta)
  end
  if exits and OnyxiaGold.Lots and OnyxiaGold.Lots.AllowDisenchant(exits.state) then
    local cap = OnyxiaGold.Capabilities and OnyxiaGold.Capabilities:CanExecute({
      profession = "Enchanting",
      minimumSkill = OnyxiaGold.Data.GetDisenchantSkillRequired(meta.itemLevel, meta.quality),
    })
    if cap and cap.executable and place == "Bags" then
      local row = result("DISENCHANT", exits.floor, "Disenchant floor beats the known intact exit.")
      row.floor = exits.floor
      row.expected = exits.expected
      row.vendor = exits.vendor
      row.intact = exits.intact
      return row
    end
    if cap and (cap.missingSkill or cap.missingProfession) then
      return result("LOCKED", nil, cap.reason or "Enchanting skill is too low.")
    end
  elseif exits and (exits.state == "CHECK_AH" or exits.state == "UNKNOWN_EXIT" or exits.state == "SELL" or exits.state == "VENDOR") then
    if place == "Mail" then
      local why = "Collect, then " .. exits.state .. "."
      local row = result("COLLECT", exits.intact or exits.floor, why)
      row.floor = exits.floor
      row.expected = exits.expected
      row.vendor = exits.vendor
      row.intact = exits.intact
      return row
    end
    if place == "Bank" and exits.state == "CHECK_AH" then
      return result("WITHDRAW", exits.floor, "Withdraw, then check the auction house before disenchanting.")
    end
    local label = exits.state
    if label == "SELL" then
      label = "SELL"
    elseif label == "VENDOR" then
      label = "VENDOR"
    elseif label == "CHECK_AH" then
      label = "CHECK_AH"
    else
      label = "UNKNOWN_EXIT"
    end
    local worth = exits.intact or exits.floor or exits.vendor
    local why = "Floor, expected, sale, and vendor are separate exits."
    local row = result(label, worth, why)
    row.floor = exits.floor
    row.expected = exits.expected
    row.vendor = exits.vendor
    row.intact = exits.intact
    return row
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
  local function located(label, worth, why)
    if place == "Mail" then
      return result("COLLECT", worth, "Collect, then " .. why)
    end
    if place == "Bank" then
      return result("WITHDRAW", worth, "Withdraw, then " .. why)
    end
    return result(label, worth, why)
  end
  if not sale and vendor <= 0 then
    return located("UNKNOWN", nil, "No price and no vendor value.")
  end
  if sale then
    local net = OnyxiaGold:ApplyAuctionHouseCut(sale)
    if vendor > net then
      return located("VENDOR", vendor, "Vendor is higher than the auction after the cut.")
    end
    return located("SELL", net, "Auction after the cut is the better known exit.")
  end
  return located("VENDOR", vendor, "Vendor is the only known value.")
end
