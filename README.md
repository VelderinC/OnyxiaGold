# OnyxiaGold

Economic optimisation and Auction House analysis addon for **Warmane Onyxia** (World of Warcraft 3.3.5a, WotLK ICC-era).

This is not a generic Auctioneer clone. The long-term goal is to treat the Auction House as an economic transformation graph and answer:

**What is the best thing I can actually do right now with this character, with the professions, recipes, inventory, and liquid capital I currently have?**

Version **0.1.41** keeps the /og window on a solid dark back. The atlas tile was not drawing, and the skin had removed the dialog backdrop, so the frame was see-through. Version **0.1.40** shows, on each buy in What to do now, the price that row will pay, the expected sale of the item that gets posted, and the profit the plan already computed for that craft or flip. A missing price stays blank. The line at the top still says the maximum spend. Version **0.1.38** records a completed sale with the proceeds the client reported. The auction-house cut, the deposit returned, the time listed, and a relist are written only when they are known, and the copy log names the plan when the sale is tied to one. What to do now still uses the conservative sale price. Version **0.1.37** can craft through an intermediate. When one known recipe makes the reagent for another and keeping that item beats selling it and buying it again, the session buys the first craft's lots, crafts both, and posts the final output. The intermediate stays in the plan and its sale is not cash. Version **0.1.36** is a visual skin for the window, buttons, and scan bar. It is not an economic change: prices, plans, and clicks stay as they were, and the next errand text stays on the line at the top. Version **0.1.35** names the errand first when the next step cannot be done from where you are: the Auction House, the mailbox, a bank withdraw, or Alchemy or Enchanting. A reagent or transmutation stone that is only in the bank is withdrawn before the craft, and bag gold is not spent as if it were already in the bags. Version **0.1.34** can add a direct flip beside those crafts: buy one whole auction lot, then post it, when the resale at the P25 of the rest of the book still clears the auction-house cut and the deposit, the lot is less than a quarter of the book, and it does not spend gold or a lot a craft already needs. Version **0.1.33** can put more than one craft in one session when they do not need the same gold, the same bag slots, the same auction lots, or the same cooldown. Each craft stays buy, then craft, then post. The line at the top is still the single next step, and the session profit is the sum. A later sale is not cash for a buy. Version **0.1.32** shows one session in real order: buy the whole lots, then craft, then post. The line at the top names that next action, the most it can spend or how many items, and the session profit. Version **0.1.31** saves the Alchemy and Enchanting recipes the profession window actually shows. A deterministic recipe from that book can become a row in What to do now, on the same rank score as the recipes already written down. Version **0.1.30** prices a buy as the whole auction you would actually purchase. Leftover materials stay in the plan. A craft is added only while that extra craft is still worth more than it consumes. Posting an owned stack reports the sale proceeds and the profit separately. A profitable 20-hour transmute still ranks above repeatable crafts, and only after the profession window has shown the cooldown is ready. The 450 profession target is the destination. The plan uses the live skill. A recipe above that skill is not the next row.

The addon stays inside the normal 3.3.5a Lua environment. It does not buy or post on a timer, does not loot mail, and does not use anything outside the WoW client.

GitHub: https://github.com/VelderinC/OnyxiaGold

**Target factory character:** Alliance Druid, Warmane Onyxia.

**Target professions (detected, never assumed):**

- Alchemy 450 · Transmutation Master
- Enchanting 450

Jewelcrafting remains in the generic capability model for GLOBAL market analysis. It is not the factory pair and must not appear as ACTIONABLE_NOW unless the current character actually has JC and the recipe.

## Current features

1. **Fast Scan** (`/og scan`) — name queries for the markets that can change the current plan: watchlist, recipe inputs and outputs, bags, bank, mail, your listings, and the plan. Item ID filter. External prices only raise items already in that set.
2. **Deep Scan** (`/og deep`) — watchlist plus recipe commodities, still not the whole auction house
3. **Full Scan** (`/og full`) — page-by-page browse of the entire AH
4. Whole-auction acquisition. Cash required is the listing total. Economic cost is the units the recipe consumes. Excess stays in the session for the next action
5. One buy path: targeted query, item-ID filter, whole-lot choice, then PlaceAuctionBid on the Buy click after the live row is checked again
6. Personal quotes stop when the next craft's marginal profit is not positive
7. Owned disenchant compares a conservative floor with vendor and, when known, the intact sale. A valuable BoE is not marked DE. States are DE, SELL, CHECK_AH, UNKNOWN_EXIT, and VENDOR
8. Post rows separate expected revenue, cash released, inventory value, and expected profit. A stale or external snapshot is not posted. The price matches the market when that is above the floor
9. Optional `OnyxiaGoldExternal` companion addon. Missing companion is fine. External data never authorises a buy
10. Any verified transmutation stone in bags or equipped. Bank-only is withdraw. None is missing. The stone is not consumed
11. Transmute cooldown is read with GetTradeSkillCooldown while Alchemy is open. Until then the row is COOLDOWN_UNKNOWN
12. `/reload` runs one opportunity rebuild when the database, character, inventory, professions, and a market snapshot are already there
13. Factory inventory dispositions depend on bags, bank, mail, or listed
14. Quantity-weighted P10 / P25 / median / P75 / mean
15. Essence and shard conversion arbitrage, Saronite to Titanium, epic-gem and older 20-hour transmutes, and the no-cooldown alchemy crafts already in the recipe file
16. Realm/faction market keys, character snapshots, liquid / mail / pending / listed, 10% reserve, and `/og test`

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
| `/og scan` or `/og quick` | Fast Scan (decision-critical markets) |
| `/og deep` | Deep Scan (watchlist and recipe commodities) |
| `/og full` | Full Scan (entire AH) |
| `/og test` | Run the economic checks and print one line per check |
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

## Fast Scan, Deep Scan, and Full Scan

**Fast Scan** queries the decision-critical item set by name, keeps paging until that name search is exhausted, then **filters every row by item ID**. It **updates only queried items** and never wipes the rest of the market snapshot. **Deep Scan** is the watchlist plus recipe inputs and outputs.

**Full Scan** walks every browse page with an empty name query and **replaces** the current realm/faction `latest` snapshot.

Both require the Auction House window to be open. Closing the AH aborts without writing.

## Market depth and prices

All money is **integer copper** (1 gold = 10000 copper).

- `totalQuantity` — every listed unit, including bid-only
- `buyoutQuantity` — units with a buyout (instant-buy stock)
- `GetQuantity()` returns **buyoutQuantity** so acquisition math cannot count bid-only stock
- `buyoutQuantity` is the full instant-buy count. `depthCoveredQuantity` is how much of that book the persisted depth still represents
- `GetAcquisitionCost(id, n)` is the **cash** required to buy whole auctions that cover `n`. It returns **nil** if the covered book cannot fill `n`
- `GetEconomicAcquisitionCost(id, n)` is the cost of the units the recipe consumes. Leftover units stay valued at what was paid for them
- `GetAcquisitionQuote` returns requested, purchased, consumed, and excess units, cash required, economic cost, leftover value, the selected lots, and `complete`
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
| 8 Saronite Bars → 1 Titanium Bar | Alchemy 395, recipe 60350. 440 is difficulty colour, not the requirement. No cooldown. Transmute Master is an EV modifier (1.20x), not a craft gate. Any transmutation stone (Philosopher's Stone 9149, Alchemist's Stone 13503, or a later alchemist stone) must be in bags or equipped. It is not consumed. Mercurial Stone 31080 is a reagent, not a tool |
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
- `getAll` is off unless `/og getall` is turned on. Warmane getAll is untested
- Browse pages are not treated as price-sorted. Warmane's sort has not been verified, so a buy keeps paging while the page is full, up to the page cap. The optimiser only sees the page it is on
- 3.3.5a has no exact-match AH query. Scans rely on name plus an item ID filter
- `seller_temp_invoice` pending mail is implemented, but 3.3.5 MailFrame may not expose it
- Owner-auction snapshot does not page. If `shown < total`, Listed is approximate (`complete = false`)
- If the mailbox has not loaded every message, Mail Ready and Pending are approximate (`snapshotComplete = false`)
- Known recipes are replaced per profession on a complete tradeskill scan
- A shared transmute is not actionable until Alchemy has been opened and the cooldown was read. A nil cooldown on a scanned recipe means ready
- Disenchant expected value currently equals the conservative floor. Northrend uncommon rates and the skill-floor table are not confirmed on Warmane. Unknown bind plus no intact price is CHECK_AH, not DE
- `sensibleCrafts` is a cap against the visible output book, not a sale rate
- Bag free slots, stack size, and partial room are stored on a bag scan. A buy can be refused when those slots cannot hold the lots. Peak occupancy is what the plan records
- Post uses a fresh non-external snapshot as the live check. The Post click does not send a new query first. Stale and external prices are refused
- Bank counts are last-open snapshots. Recipe knowledge is only as current as the last tradeskill window
- Recursive crafting, farm gold-per-hour, auction-house disenchant buys, and unattended buy/post/loot are out of scope
- Neutral AH is not partitioned (player faction market only)
- The planner reserves cash, bag units, and a cloned auction book inside one plan. Bank stock is not bag stock

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
30. Lua 5.1 review: no `#` length operator, no `math.mod`, no `continue`. Integer remainder uses `%`.
31. Alchemy 450 + Enchanting 450 + TM is reported as factory setup complete.
32. Alchemy 450 + Jewelcrafting 450 is detected, but factory setup is incomplete (Enchanting missing).
33. Alchemy transmute remains personally actionable when requirements are met.
34. Future DE opportunities require Enchanting (LOCKED_SKILL / LOCKED_PROFESSION when missing).
35. JC cuts, when added, are GLOBAL_ONLY unless this character has JC.
36. Tailoring craft stages are locked; an already-listed crafted item may still be a DE input.
37. Transmute Master modifies only recipes with `supportsTransmuteMastery = true`.

## Author

Charles / Velderin
