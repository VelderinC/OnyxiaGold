--[[
  Virtual list of items he already holds.
  Does not move bag slots. One row, one disposition.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.FactoryInventory = OnyxiaGold.FactoryInventory or {}

local Factory = OnyxiaGold.FactoryInventory

local function addPlace(rows, place, map, actions)
  if type(map) ~= "table" then
    return
  end
  for itemID, count in pairs(map) do
    itemID = tonumber(itemID)
    count = tonumber(count) or 0
    if itemID and count > 0 then
      local meta = OnyxiaGold.ItemInfo and OnyxiaGold.ItemInfo:Get(itemID) or nil
      local disp = OnyxiaGold.AssetClassifier:Disposition(itemID, count, meta, actions, place)
      local name = meta and meta.name or (OnyxiaGold.Data.GetItemName and OnyxiaGold.Data.GetItemName(itemID)) or tostring(itemID)
      local unit = disp.worth
      local total = nil
      if unit and count then
        total = unit * count
      end
      local worthText = "Unit unknown."
      if unit and total and OnyxiaGold.FormatMoney then
        worthText = "Unit " .. OnyxiaGold.FormatMoney(unit) .. ". Total " .. OnyxiaGold.FormatMoney(total) .. "."
      end
      local function money(value)
        if not value or not OnyxiaGold.FormatMoney then
          return nil
        end
        return OnyxiaGold.FormatMoney(value)
      end
      local exits = ""
      if disp.floor or disp.expected or disp.intact or disp.vendor then
        exits = " Floor " .. tostring(money(disp.floor) or "none")
          .. ". Expected " .. tostring(money(disp.expected) or "none")
          .. ". Sale " .. tostring(money(disp.intact) or "none")
          .. ". Vendor " .. tostring(money(disp.vendor) or "none") .. "."
      end
      table.insert(rows, {
        itemID = itemID,
        name = name,
        count = count,
        place = place,
        label = disp.label,
        badge = disp.badge,
        worth = unit,
        totalWorth = total,
        why = disp.why,
        tooltip = name .. " x" .. tostring(count) .. ". " .. place .. ". " .. worthText .. exits .. " " .. tostring(disp.why),
      })
    end
  end
end

function Factory:Rows()
  local rows = {}
  local character = OnyxiaGold.Database and OnyxiaGold.Database:GetCharacter()
  if not character then
    return rows
  end
  local actions = {}
  if OnyxiaGold.ActionPlanner and OnyxiaGold.ActionPlanner.GetActions then
    actions = OnyxiaGold.ActionPlanner:GetActions() or {}
  end
  addPlace(rows, "Bags", character.inventory and character.inventory.bags, actions)
  addPlace(rows, "Bank", character.bank and character.bank.items, actions)
  addPlace(rows, "Mail", character.mail and character.mail.items, actions)
  local listings = character.auctions and character.auctions.listings
  if type(listings) == "table" then
    local listed = {}
    for i = 1, table.getn(listings) do
      local row = listings[i]
      local itemID = row and tonumber(row.itemID)
      local count = row and tonumber(row.count) or 0
      if itemID and count > 0 then
        listed[itemID] = (listed[itemID] or 0) + count
      end
    end
    addPlace(rows, "Listed", listed, actions)
  end
  table.sort(rows, function(a, b)
    if a.place == b.place then
      return tostring(a.name) < tostring(b.name)
    end
    return tostring(a.place) < tostring(b.place)
  end)
  return rows
end
