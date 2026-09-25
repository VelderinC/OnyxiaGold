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
      local disp = OnyxiaGold.AssetClassifier:Disposition(itemID, count, meta, actions)
      local name = meta and meta.name or (OnyxiaGold.Data.GetItemName and OnyxiaGold.Data.GetItemName(itemID)) or tostring(itemID)
      local worthText = "Worth unknown."
      if disp.worth and OnyxiaGold.FormatMoney then
        worthText = "Worth " .. OnyxiaGold.FormatMoney(disp.worth) .. "."
      end
      table.insert(rows, {
        itemID = itemID,
        name = name,
        count = count,
        place = place,
        label = disp.label,
        badge = disp.badge,
        worth = disp.worth,
        why = disp.why,
        tooltip = name .. " x" .. tostring(count) .. ". " .. place .. ". " .. worthText .. " " .. tostring(disp.why),
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
  table.sort(rows, function(a, b)
    if a.place == b.place then
      return tostring(a.name) < tostring(b.name)
    end
    return tostring(a.place) < tostring(b.place)
  end)
  return rows
end
