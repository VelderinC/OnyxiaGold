# OnyxiaGold

Economic optimisation and Auction House analysis addon for **Warmane Onyxia** (World of Warcraft 3.3.5a, WotLK ICC-era).

This is not a generic Auctioneer clone. The long-term goal is to treat the Auction House as an economic transformation graph and answer:

**What is the best thing I can actually do right now with this character, with the professions, recipes, inventory, and liquid capital I currently have?**

Version **0.1.29** keeps a post row after a conversion, transmute, or craft is sitting in your bags. One click lists one stack while the Auction House is open. A profitable 20-hour transmute still ranks above repeatable crafts. The 450 profession target is the destination. The plan uses the live skill. A recipe above that skill is not the next row.

The addon stays inside the normal 3.3.5a Lua environment. It does not buy or post on a timer, does not loot mail, and does not use anything outside the WoW client.

GitHub: https://github.com/VelderinC/OnyxiaGold

**Target factory character:** Alliance Druid, Warmane Onyxia.

**Target professions (detected, never assumed):**

- Alchemy 450 · Transmutation Master
- Enchanting 450

Jewelcrafting remains in the generic capability model for GLOBAL market analysis. It is not the factory pair and must not appear as ACTIONABLE_NOW unless the current character actually has JC and the recipe.

## Current features

1. **Quick Scan** — name queries for a data-driven watchlist, then filter by item ID
2. **Full Scan** — page-by-page browse of the entire AH
3. Compact buyout **order book** per item (aggregated by unit price)
4. **Depth-aware acquisition cost** (walks cheapest levels until the requested quantity is filled)
5. Quantity-weighted P10 / P25 / median / P75 / mean
6. Essence and shard conversion arbitrage (both directions; item-use, no profession), including Magic, Astral, Mystic, and Nether
7. Saronite → Titanium transmute EV, gated on Alchemy 395 + known recipe 60350
8. Realm/faction market keys (`Onyxia|Horde`, `Onyxia|Alliance`)
9. Character snapshots keyed by `Realm|Faction|Name`
10. Liquid gold, mail ready, pending AH invoices, listed auctions, bag/bank materials
11. Working-capital reserve (default 10%)
12. Greedy personal action plan from current deployable gold only
13. Stale-data age in header/tooltips; diagnostic log

## Installation

Copy the `OnyxiaGold` folder to:

```
World of Warcraft/
  Interface/
    AddOns/
      OnyxiaGold/
```

The folder that contains `OnyxiaGold.toc` must be named `OnyxiaGold`.

## Slash commands

| Command | Action |
| --- | --- |
| `/og` or `/onyxiagold` | Toggle the main window |
| `/og scan` or `/og quick` | Quick Scan (watchlist) |
| `/og full` | Full Scan (entire AH) |
| `/og opportunities` | Recalculate market opportunities and the personal plan |
| `/og debug` | Toggle debug **chat** echo (the internal log always records) |
| `/og log` | Toggle the copyable diagnostic log window |
| `/og log copy` | Open the log and select all (then Ctrl+C) |
| `/og log clear` | Wipe the log buffer |
| `/og reset` | Warn, then `/og reset confirm` to wipe **price** data (log, settings, and character snapshots are kept) |
| `/og master` | Toggle Transmute Master **manual override** (Force TM). Detection is used when override is off |
| `/og getall` | Toggle experimental getAll (off by default; Warmane untested) |

## Capital terminology

These are not interchangeable:

| Label | Meaning | Spendable at AH? |
| --- | --- | --- |
| **Liquid** | `GetMoney()` on the character now | Yes |
| **Mail ready** | Gold attached to mailbox messages (last snapshot) | Only after you collect it |
| **Pending** | Seller temporary invoice / delayed AH proceeds | No |
| **Listed** | Asking value of your own auctions | No |
| **Bags** | Market value of tracked materials you are carrying | No (but they cut cash required to craft) |
| **Bank** | Last-known tracked materials in the bank | No (may require a visit) |
| **Deployable now** | Liquid minus the working-capital reserve | Yes (planner budget) |
| **Deployable after mail** | Reserve recalculated on liquid + claimable mail | Only after you collect the mail |
| **Estimated net** | Sum of the above, informational | Never |

Default reserve is **10%** of the liquid gold the reserve is calculated against (`settings.capitalReservePercent`). After mail collection that base is liquid + claimable mail, not current deployable plus the whole mail balance.

Owned materials have **opportunity cost** (liquidation value) in economic profit, and **zero extra cash** in cash-flow.

## Quick Scan vs Full Scan

**Quick Scan** queries only `Data/Watchlist.lua` items by name, keeps paging until that name search is exhausted, then **filters every row by item ID**. It **updates only queried items** and never wipes the rest of the market snapshot.

**Full Scan** walks every browse page with an empty name query and **replaces** the current realm/faction `latest` snapshot.

Both require the Auction House window to be open. Closing the AH aborts without writing.

## Market depth and prices

All money is **integer copper** (1 gold = 10000 copper).

- `totalQuantity` — every listed unit, including bid-only
- `buyoutQuantity` — units with a buyout (instant-buy stock)
- `GetQuantity()` returns **buyoutQuantity** so acquisition math cannot count bid-only stock
- `buyoutQuantity` is the full instant-buy count. `depthCoveredQuantity` is how much of that book the persisted depth still represents
- `GetAcquisitionCost(id, n)` walks the persisted buyout book. It returns **nil** if covered depth cannot fill `n`. It does not price past `depthCoveredQuantity`
- `GetAcquisitionQuote` returns filled quantity, total/avg/marginal cost, `depthCoveredQuantity`, and `complete`
- Median / percentiles / weighted mean are **quantity-weighted over the full runtime book**, then the acquisition depth is truncated for storage
- Opportunity **sell** unit is **P25**, falling back to P10 then minimum on thin books
- `GetMarketReferencePrice` is the quantity-weighted median
- `GetLiquidationPrice` is P10 (then P25, then min)

AH cut is a single config (`0.05`) applied once to expected sale proceeds.

## Database

SavedVariables version **4**. Layout:

```
OnyxiaGoldDB.markets["Onyxia|Alliance"] = {
  latest = { [itemID] = record },  -- includes compact depth
  history = { [itemID] = { stats... } },  -- no depth
  scans = { summaries }
}

OnyxiaGoldDB.characters["Onyxia|Alliance|Name"] = {
  identity, professions, knownRecipes (by profession), recipeScans, specialisations,
  inventory, bank, mail, auctions, capital, stateTimestamps
}
```

Market data stays realm/faction scoped. Personal observations stay character-scoped.

v1 unpartitioned `latest`/`history`/`scans` are preserved as `pendingLegacy` and assigned to the current realm/faction on `PLAYER_LOGIN` if that market is still empty.

Derived action lists are **not** stored. Snapshots are; the planner recalculates.

## UI

Compact header: character, **Alchemy + Enchanting** (actual ranks), factory-setup status, liquid / mail / pending / listed, deployable gold, market age.

If Jewelcrafting is detected, it is shown as `(global)` and the factory line reports that the target second profession is Enchanting.

Main list: **What to do now** (actionable personal steps), not every theoretical market opportunity.

Main list: **What to do now** (actionable personal steps), not every theoretical market opportunity.

Hover the capital line for the portfolio tooltip. Hover an action for cash vs economic cost.

**Force TM** enables a manual Transmutation Master override. When unchecked, spellbook detection is used.

## Current supported transformations

| Transformation | Notes |
| --- | --- |
| Greater Eternal Essence ↔ 3 Lesser Eternal Essence | Item-use; no profession |
| Greater Planar Essence ↔ 3 Lesser Planar Essence | Item-use; no profession |
| Greater Cosmic Essence ↔ 3 Lesser Cosmic Essence | Item-use; no profession |
| Void Shatter | Enchanting 375, spell 45765. One Void Crystal becomes two Large Prismatic Shards. One craft. Runed Eternium Rod (22463) must be on the character. If selling the crystal leaves more, the row says sell. Abyss Crystal has no shatter line |
| 3 Small Prismatic Shards → 1 Large, and the reverse | Enchanting 335, spells 28022 and 42615. Runed Fel Iron Rod (22461) must be on the character and the recipe must be known. Not an item click |
| 3 Small Dream Shards → 1 Dream Shard | Item-use. A Dream Shard does not split |
| 8 Saronite Bars → 1 Titanium Bar | Alchemy 395, recipe 60350. 440 is difficulty colour, not the requirement. No cooldown. Transmute Master is an EV modifier (1.20x), not a craft gate. Philosopher's Stone (item 9149) must be in bags or equipped. It is not consumed |
| Earthsiege Diamond | Alchemy 425, spell 57427. Dark Jade, Huge Citrine, Eternal Fire. No cooldown |
| Skyflare Diamond | Alchemy 430, spell 57425. Bloodstone, Chalcedony, Eternal Air. No cooldown. Cast time stays blank |
| Arcanite, Primal Might, Elemental Fire | One craft of the best. Not the 20-hour cooldown. Elemental Fire is three, and mastery is not applied. Cast times are 2, 5, and 25 seconds |
| Post row | Deposit comes from `CalculateAuctionDeposit`. His cheapest auction is left alone. He presses Blizzard's button |
| Epic gems (Ametrine, King's Amber, Dreadstone, Majestic Zircon, Eye of Zul) | Alchemy 450. One shared 20-hour transmute per plan |
| Cardinal Ruby | Not an action. Minimum skill is unset |

Market opportunities require first-craft expected profit > 0 after AH cut. The action list then keeps only what this character can execute **now** with current gold, bags, and recipes. Expected sale proceeds are never treated as cash for the next buy.

## Known limitations

- No realised sales velocity or dump-the-market absorption model
- Sell side still uses a conservative unit (P25), not a walk of the output book
- Transmute Master remains expected value, not a guaranteed extra bar
- `getAll` is detected and logged but **not** used unless `/og getall` is turned on
- 3.3.5a has no exact-match AH query; Quick Scan relies on name + item ID filter
- `seller_temp_invoice` pending mail is implemented, but 3.3.5 MailFrame may not expose it; confirm on Warmane
- Owner-auction snapshot does not page. If `shown < total`, Listed is approximate (`complete = false`)
- If the mailbox has not loaded every message, Mail Ready and Pending are approximate (`snapshotComplete = false`)
- Known recipes are replaced per profession on a complete tradeskill scan. They are not appended forever
- `sensibleCrafts` is a crude cap against the visible output book after stock he already holds, not a liquidity model or a sale rate. Partial and stale snapshots still count
- A buy stops at free general bag slots. The auction page shows the stop. Post lists one stack from that row, and only from the Post click
- Bank counts are last-open snapshots
- Recipe knowledge is only as current as the last tradeskill window scan
- No disenchant EV tables yet (prepared for v0.2.0; Full Scan is the intended feed)
- Recursive crafting, farm GPH, and automated buy/post/loot are out of scope
- Neutral AH is not partitioned yet (player faction market only)
- The planner reserves cash, bag units, and a cloned auction book inside one plan. Planned output is also capped to the visible buyout book. Bank stock is still not bag stock.
- DE skill-floor table is centralized but must be confirmed on Warmane before buy recommendations

## Sharing logs

`/og log` → Select All → Ctrl+C. `/reload` does not wipe the log. `/og reset` wipes prices, not the log or character snapshots.

## Manual tests (0.1.2)

1. `GetMoney` matches the backpack gold display exactly.
2. Spending gold updates Liquid immediately.
3. Receiving gold updates Liquid immediately.
4. Open mailbox with gold attachments. When every message is loaded, Mail Ready equals total attached money. When `visible < total`, the UI shows an approximate figure, not an exact sum.
5. A pending Auction House invoice is Pending, not Mail Ready.
6. Pending amount follows `bid + deposit - consignment` and does not increase deployable gold.
7. After delayed sale funds become attached, they move Pending → Mail Ready without double-counting.
8. Closing the mailbox persists the snapshot and timestamp.
9. An old mailbox snapshot is marked stale (`~` and tooltip age).
10. Owned AH listings are detected while the AH is open.
11. Listed value does not increase deployable gold.
12. Bag material counts are accurate.
13. Owned materials reduce cash required for an opportunity.
14. Owned materials still carry economic opportunity cost in EV.
15. Alchemy skill is detected with 3.3.5 skill lines (not Retail APIs).
16. Enchanting skill is detected.
17. Transmutation Master is detected (spell 28672) when learned.
18. Opening Alchemy scans known recipes (including Transmute: Titanium if known).
19. Opening Enchanting scans known enchants.
20. Unscanned recipes are UNKNOWN, not a false “missing recipe”.
21. A recipe the character does not know does not appear in the main action list.
22. An opportunity needing 500g with 200g liquid is not actionable now.
23. The same opportunity becomes “after mail” only when post-collection deployable (reserve on liquid + mail) can fund it. Liquid 100g, reserve 10%, mail 900g is 900g deployable, not 990g.
24. Pending 400g with 0 claimable does **not** make it actionable.
25. The 10% planner reserve is respected.
26. The planner never allocates more current liquid than exists.
27. Multiple recommendations do not independently spend the same gold.
28. `/reload` persists character snapshots.
29. No Retail profession APIs (`C_TradeSkillUI`, `GetProfessions`) in the addon.
30. Lua 5.1 review: no `#`, no `%` modulo, no `continue`.
31. Alchemy 450 + Enchanting 450 + TM is reported as factory setup complete.
32. Alchemy 450 + Jewelcrafting 450 is detected, but factory setup is incomplete (Enchanting missing).
33. Alchemy transmute remains personally actionable when requirements are met.
34. Future DE opportunities require Enchanting (LOCKED_SKILL / LOCKED_PROFESSION when missing).
35. JC cuts, when added, are GLOBAL_ONLY unless this character has JC.
36. Tailoring craft stages are locked; an already-listed crafted item may still be a DE input.
37. Transmute Master modifies only recipes with `supportsTransmuteMastery = true`.

## Future roadmap

1. **0.1.3** — Factory Operations. Phase A corrects skill, depth, after-mail reserve, recipe snapshots, partial mail/auctions, and capacity fields. Phase B reserves session cash, bags, and cloned auction depth, caps planned output to the visible book, keeps Dream Shard one-way, leaves prismatic shards off the action list, and adds the epic-gem cooldown choice plus Earthsiege and Skyflare. Still ahead: Factory Mail, Factory Inventory, and disenchant EV.
2. **v0.2.0** — Full disenchant expected-value engine (weapon vs armour, iLevel, quality; Full Scan feed)
3. **v0.2.1+** — Enchanting conversions: Abyssal Shatter, Void Shatter (confirmed 3.3.5 data), vellum scrolls
4. **v0.3+** — Recursive capability-aware transformation graph (GLOBAL paths vs EXECUTABLE paths)
5. Economic floor for owned gear (vendor vs sale vs DE EV)
6. Historical percentiles, realised-sales ledger, liquidity caps
7. Profession-independent farm valuation (never recommend Mining/Herbalism/Skinning as factory replacements)
8. Jewelcrafting cuts remain generic/GLOBAL unless the current character has JC

## Author

Charles / Velderin
