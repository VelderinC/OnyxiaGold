# Changelog

## 0.1.3 — Factory Operations, Phase A and Phase B

Phase A corrects planner and snapshot debt. Phase B reserves cash, bag materials, and cloned auction depth inside one session plan. Factory Mail and Factory Inventory are not in this version.

- Transmute: Titanium (spell 60350) requires Alchemy 395. 440 is difficulty colour, not the skill requirement.
- Min, P10, P25, median, P75, and weighted mean are computed from the full runtime buyout book. Only the persisted acquisition depth is truncated. `depthCoveredQuantity` is stored separately from `buyoutQuantity`. `GetAcquisitionQuote` will not price past covered depth.
- `Capital:GetSpendableAfterMail()` reserves against liquid + claimable mail. Liquid 100g, reserve 10%, mail 900g → 900g deployable after collection, not 990g.
- Known recipes are profession-scoped. A complete profession scan replaces that profession's set. Saved flat sets migrate (database v4).
- A mailbox with unloaded mail persists `snapshotComplete = false` plus `visibleCount` and `totalCount`. The UI does not present that subtotal as exact.
- Own auctions persist `shown`, `total`, and `complete` (`shown >= total`). An incomplete owner list shows Listed as approximate.
- Craft capacity is split into `marketProfitableCrafts`, `physicalPossibleCrafts`, `affordableCrafts`, `capabilityAllowedCrafts`, `executableCrafts`, and `sensibleCrafts`. `sensibleCrafts` does not yet apply an output-liquidity model.
- `SessionState` rebuilds on each plan. A selected action reserves its cash, the bag units it uses, and the auction units it would buy. The next action sees what remains. The saved market snapshot is not modified.

## 0.1.2 — Character State & Capital Awareness

- Personal economic state: liquid gold, mail ready, pending AH invoices, listed auctions, bag/bank materials
- Character snapshots keyed by `Realm|Faction|Name` (database v3)
- Legacy 3.3.5 profession detection (`GetNumSkillLines` / `GetSkillLineInfo`)
- Known-recipe scans when a tradeskill window is opened
- Transmutation Master detection (spell 28672); Force TM remains a manual override
- Working-capital reserve (default 10%) so the planner does not spend the last copper
- Owned bag materials reduce **cash required** but keep **economic opportunity cost**
- Greedy ActionPlanner: sequential capital, no credit for unsold crafts, pending gold is not spendable
- Main window: compact personal header + **What to do now** list
- Factory target pair: **Alchemy 450 / Transmutation Master + Enchanting 450** (detected, not assumed)
- Jewelcrafting kept as generic GLOBAL capability; not the intended factory profession
- Disenchant EV engine prepared (skill floors, item metadata cache) but not implemented
- No automated mail loot, no automated AH buying

## 0.1.1 — Reliable Market Data

- Depth-aware acquisition pricing (compact buyout order book)
- Quantity-weighted market statistics (P10 / P25 / median / P75 / mean)
- Quick Scan (watchlist) and Full Scan (entire AH)
- Realm/faction market partitioning (`Onyxia|Horde`, `Onyxia|Alliance`)
- Improved opportunity capacity: first-craft profit vs input-depth potential
- Fixed FauxScrollFrame scrolling (offset owned by the addon; mouse wheel on the window)
- Stale-data tracking and tooltip age
- UI: Quick/Full/Refresh, Potential column, richer tooltips
- Buyout quantity separated from total/bid-only quantity
- Database v2 migration preserves v1 snapshots

## 0.1.0 — MVP

- Page-by-page AH scanner, SavedVariables, essence/shard conversions, Saronite → Titanium, basic UI and log
