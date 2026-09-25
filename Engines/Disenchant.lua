--[[
  Disenchant expected-value engine.

  Priority: v0.2.0, after 0.1.1 market data, 0.1.2 character state, 0.1.3 planner.

  Do not implement a crude "green → average dust" model.
  Full Scan of green/blue/purple equipment is the intended discovery feed.
  Quick Scan remains for commodities.

  Future Collect() must:
  * require Enchanting via Capabilities:CanExecute
  * use GetDisenchantSkillRequired(itemLevel, quality) as minimumSkill
  * distinguish weapon vs armour distributions
  * set isExpectedValue = true
  * apply AH cut once, on material liquidation, never on the DE act
  * cap or warn on huge output vs current dust/essence depth
  * never treat EV as guaranteed profit

  Personal vs global:
  * Tailoring craft → bracer → DE is NOT executable without Tailoring
  * An underpriced bracer already on the AH IS executable (Enchanting only)
]]

OnyxiaGold = OnyxiaGold or {}
OnyxiaGold.Engines = OnyxiaGold.Engines or {}
OnyxiaGold.Engines.Disenchant = OnyxiaGold.Engines.Disenchant or {}

function OnyxiaGold.Engines.Disenchant:Collect()
  return {}
end
