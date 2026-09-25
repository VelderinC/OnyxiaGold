--[[
  Crafting graph placeholder.
  Recursive costing is later (v0.3+).

  Jewelcrafting cuts and Tailoring shuffles belong in the GLOBAL graph.
  They are ACTIONABLE_NOW only when Capabilities:CanExecute succeeds
  for the logged-in character. The intended Druid has Alchemy + Enchanting,
  so JC/Tailoring crafts are GLOBAL_ONLY / LOCKED_PROFESSION.

  An already-listed crafted item (e.g. a Netherweave bracer on the AH)
  may still be a personal Disenchant input.
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Engines = OnyxiaGold.Engines or {}
OnyxiaGold.Engines.Crafting = OnyxiaGold.Engines.Crafting or {}

function OnyxiaGold.Engines.Crafting:Collect()
  return {}
end
