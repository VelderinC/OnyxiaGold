--[[
  Farm valuation placeholder.
  Phase 8 will multiply measured route yields by current AH liquidation values.

  Future farm definitions must declare requirements (profession, class, flying, level).
  Capabilities:CanExecute will exclude routes this character cannot perform.

  Do not recommend Mining, Herbalism, or Skinning as replacements for the
  Alchemy + Enchanting factory slots. Those farms are LOCKED_PROFESSION.
  Profession-independent farms (cloth, mobs, vendors) remain eligible.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Engines = OnyxiaGold.Engines or {}
OnyxiaGold.Engines.Farming = OnyxiaGold.Engines.Farming or {}

function OnyxiaGold.Engines.Farming:Collect()
  return {}
end
