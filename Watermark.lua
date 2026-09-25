--[[
  OnyxiaGold watermark
  Always-visible version label on UIParent. Presentation only.
  Lua 5.1 / Interface 30300. No economic logic.
]]

local frame = CreateFrame("Frame", "OnyxiaGoldWatermark", UIParent)
frame:SetWidth(220)
frame:SetHeight(16)
frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 4, -4)
frame:SetFrameStrata("HIGH")
frame:EnableMouse(false)

local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
label:SetWidth(220)
label:SetHeight(16)
label:SetJustifyH("LEFT")
label:SetJustifyV("MIDDLE")
label:SetTextColor(1, 0.95, 0.8)
label:SetShadowOffset(1, -1)
label:SetShadowColor(0, 0, 0, 1)

local version = GetAddOnMetadata("OnyxiaGold", "Version")
if not version or version == "" then
  version = "?"
end
label:SetText("OnyxiaGold " .. version)

frame:Show()
