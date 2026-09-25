# OnyxiaGold

Economic optimisation and Auction House analysis addon for **Warmane Onyxia** (World of Warcraft 3.3.5a, WotLK ICC-era).

This is not a generic Auctioneer clone. The long-term goal is to treat the Auction House as an economic transformation graph and answer:

**What is the most profitable legitimate action I can take right now?**

Version **0.1.1** makes the market-data layer trustworthy: buyout depth, quantity-weighted statistics, Quick/Full scan, and realm/faction partitioning. Phase 2 (disenchant) is not in this release.

The addon stays inside the normal 3.3.5a Lua environment. It does not click for you, does not send automated buys/posts, and does not use anything outside the WoW client.

GitHub: https://github.com/VelderinC/OnyxiaGold

## Current features

1. **Quick Scan** — name queries for a data-driven watchlist, then filter by item ID
2. **Full Scan** — page-by-page browse of the entire AH
3. Compact buyout **order book** per item (aggregated by unit price)
4. **Depth-aware acquisition cost** (walks cheapest levels until the requested quantity is filled)
5. Quantity-weighted P10 / P25 / median / P75 / mean
6. Essence and shard conversion arbitrage (both directions)
7. Saronite → Titanium transmute EV, with maximum profitable crafts from input depth
8. Realm/faction market keys (`Onyxia|Horde`, `Onyxia|Alliance`)
9. Stale-data age in tooltips; diagnostic log

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
| `/og opportunities` | Recalculate and show opportunities |
| `/og debug` | Toggle debug **chat** echo (the internal log always records) |
| `/og log` | Toggle the copyable diagnostic log window |
| `/og log copy` | Open the log and select all (then Ctrl+C) |
| `/og log clear` | Wipe the log buffer |
| `/og reset` | Warn, then `/og reset confirm` to wipe **price** data (log is kept) |
| `/og master` | Toggle Transmute Master expected-output multiplier |
| `/og getall` | Toggle experimental getAll (off by default; Warmane untested) |

## Quick Scan vs Full Scan

**Quick Scan** queries only `Data/Watchlist.lua` items by name, keeps paging until that name search is exhausted, then **filters every row by item ID**. It **updates only queried items** and never wipes the rest of the market snapshot.

**Full Scan** walks every browse page with an empty name query and **replaces** the current realm/faction `latest` snapshot.

Both require the Auction House window to be open. Closing the AH aborts without writing.

## Market depth and prices

All money is **integer copper** (1 gold = 10000 copper).

- `totalQuantity` — every listed unit, including bid-only
- `buyoutQuantity` — units with a buyout (instant-buy stock)
- `GetQuantity()` returns **buyoutQuantity** so acquisition math cannot count bid-only stock
- `GetAcquisitionCost(id, n)` walks the sorted buyout book. It returns **nil** if buyout stock cannot fill `n`
- `GetAcquisitionQuote` returns filled quantity, total/avg/marginal cost, and `complete`
- Median / percentiles are **quantity-weighted** over compact depth levels, not “one vote per auction”
- Opportunity **sell** unit is **P25**, falling back to P10 then minimum on thin books
- `GetMarketReferencePrice` is the quantity-weighted median
- `GetLiquidationPrice` is P10 (then P25, then min)

AH cut is a single config (`0.05`) applied once to expected sale proceeds.

## Database

SavedVariables version **2**. Layout:

```
OnyxiaGoldDB.markets["Onyxia|Horde"] = {
  latest = { [itemID] = record },  -- includes compact depth
  history = { [itemID] = { stats... } },  -- no depth
  scans = { summaries }
}
```

v1 unpartitioned `latest`/`history`/`scans` are preserved as `pendingLegacy` and assigned to the current realm/faction on `PLAYER_LOGIN` if that market is still empty.

History stores compact stats only (min, p10, p25, median, mean, p75, quantities). Depth is **not** copied into history.

## UI

Columns: Opportunity, Profit (first craft), Potential (input-depth total), ROI, Crafts, Type.

Potential profit is **not guaranteed sales**. Tooltips show acquisition, P10/P25/median, stock, data age, and Transmute Master EV.

## Current supported transformations

| Transformation | Notes |
| --- | --- |
| Greater Eternal Essence ↔ 3 Lesser Eternal Essence | Both directions, depth-aware |
| Greater Planar Essence ↔ 3 Lesser Planar Essence | Both directions |
| Greater Cosmic Essence ↔ 3 Lesser Cosmic Essence | Both directions |
| 3 Small Prismatic Shards ↔ 1 Large Prismatic Shard | Both directions |
| 3 Small Dream Shards ↔ 1 Dream Shard | Both directions |
| 8 Saronite Bars → 1 Titanium Bar | EV; optional Transmute Master 1.20x |

Only opportunities with **first-craft expected profit > 0** after AH cut are listed. Ranking is by **totalExpectedProfit** (input-depth cap), then first-craft profit.

## Known limitations

- No realised sales velocity or dump-the-market absorption model
- Sell side still uses a conservative unit (P25), not a walk of the output book
- Transmute Master remains expected value, not a guaranteed extra bar
- `getAll` is detected and logged but **not** used unless `/og getall` is turned on
- 3.3.5a has no exact-match AH query; Quick Scan relies on name + item ID filter
- Transmute Master is a checkbox, not detected from profession spec
- No disenchant tables, recursive crafting, farm GPH, or automated buy/post
- Neutral AH is not partitioned yet (player faction market only)

## Sharing logs

`/og log` → Select All → Ctrl+C. `/reload` does not wipe the log. `/og reset` wipes prices, not the log.

## Future roadmap

1. **Phase 2** — Disenchant expected value
2. **Phase 3** — Recursive crafting graph
3. **Phase 4** — Multiple exit values / economic floor
4. **Phase 5** — Historical percentiles and volatility
5. **Phase 6** — Realised sales ledger
6. **Phase 7** — Liquidity and market-capacity caps
7. **Phase 8** — Farm route valuation
8. **Phase 9** — Ranked “make me gold” action list

## Author

Charles / Velderin
