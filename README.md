# OnyxiaGold

Economic optimisation and Auction House analysis addon for **Warmane Onyxia** (World of Warcraft 3.3.5a, WotLK ICC-era).

This is not a generic Auctioneer clone. The long-term goal is to treat the Auction House as an economic transformation graph and answer:

**What is the most profitable legitimate action I can take right now?**

Version **0.1.0** is a modular MVP. It scans, stores prices, finds a few deterministic arbitrage routes, ranks them, and shows them in a window. Later phases (disenchant EV, recursive crafting, liquidity, farm GPH, realised ledger) are intentionally not built yet.

The addon stays inside the normal 3.3.5a Lua environment. It does not click for you, does not send automated buys/posts, and does not use anything outside the WoW client.

## Current MVP features

1. Page-by-page Auction House scan (3.3.5a `QueryAuctionItems`)
2. SavedVariables price database with versioned schema
3. Unit-price API (lowest, median, quantity, net sale value after AH cut)
4. Essence conversion arbitrage (both directions)
5. Shard conversion arbitrage (both directions)
6. Saronite → Titanium transmute expected-value ranking
7. Opportunity window with gold/silver/copper formatting
8. Slash commands, persistent diagnostic log, and optional debug chat

## Installation

Copy the `OnyxiaGold` folder to:

```
World of Warcraft/
  Interface/
    AddOns/
      OnyxiaGold/
```

The folder that contains `OnyxiaGold.toc` must be named `OnyxiaGold`.

Restart the client (or `/reload` after the files are already in AddOns). Enable **OnyxiaGold** on the character select AddOns list.

## Slash commands

| Command | Action |
| --- | --- |
| `/og` or `/onyxiagold` | Toggle the main window |
| `/og scan` | Start an Auction House scan (AH must be open) |
| `/og opportunities` | Recalculate and show opportunities |
| `/og debug` | Toggle debug **chat** echo (the internal log always records) |
| `/og log` | Toggle the copyable diagnostic log window |
| `/og log copy` | Open the log and select all (then Ctrl+C) |
| `/og log clear` | Wipe the log buffer |
| `/og reset` | Warn, then `/og reset confirm` to wipe **price** data (log is kept) |
| `/og master` | Toggle Transmute Master expected-output multiplier |

## Sharing logs when something breaks

The addon keeps a ring buffer of diagnostic lines in SavedVariables (last 800). Chat stays quiet during scans unless `/og debug` is on. The log still records.

After a problem:

1. Click **Log** on the main window, or type `/og log`
2. Click **Select All** (or `/og log copy`)
3. Press Ctrl+C
4. Paste the dump here

A useful dump includes session start, scan page queries, watched item prices (Saronite, Titanium, essences, shards), and why each conversion was a hit or skip. `/reload` does **not** wipe the log.

## Current supported transformations

| Transformation | Notes |
| --- | --- |
| Greater Eternal Essence ↔ 3 Lesser Eternal Essence | Both directions |
| Greater Planar Essence ↔ 3 Lesser Planar Essence | Both directions |
| Greater Cosmic Essence ↔ 3 Lesser Cosmic Essence | Both directions |
| 3 Small Prismatic Shards ↔ 1 Large Prismatic Shard | Both directions |
| 3 Small Dream Shards ↔ 1 Dream Shard | Both directions |
| 8 Saronite Bars → 1 Titanium Bar | Expected value; optional Transmute Master 1.20x |

Only opportunities with **expected profit > 0** after a 5% Auction House cut are listed. v0.1 ranks by expected profit per conversion, not by gold per hour or market capacity.

All money is stored and calculated as **integer copper** (1 gold = 10000 copper).

## Development status

**v0.1.0 — MVP.** Scan → price → opportunity → UI needs to prove reliable on Warmane Onyxia before Phase 2 work begins.

Placeholder modules exist for Disenchant, Crafting, and Farming so later engines can plug into the same ranking list.

## Known limitations

- Scanning requires the Auction House window to be open. That is a 3.3.5a client rule, not an addon bug.
- The scan walks browse pages (50 listings each). A full AH pass takes time and temporarily takes over the browse list.
- `getAll` full-AH dump is not used in v0.1 (bandwidth / disconnect risk, and some private servers behave differently).
- Incomplete item cache can skip a few listings. The scanner retries the page a few times, then continues.
- Buy cost uses the **lowest unit buyout**, not true market-depth cost. Selling uses **median** unit buyout, then AH cut.
- Available quantity is “how many conversions the current AH stock could theoretically feed”. It does not estimate how many you can actually sell.
- Transmute Master is a checkbox / saved setting. It is **not** detected from your profession specialisation.
- Closing the AH mid-scan aborts without overwriting previous prices.
- No buying, selling, posting, or profession-cast automation.
- No disenchant tables, crafting graph, farm routes, or historical percentile math yet.

## Future roadmap

1. **Phase 2** — Disenchant expected value (iLevel, armour vs weapon, quality, RNG)
2. **Phase 3** — Recursive crafting graph (cheapest source of every intermediate)
3. **Phase 4** — Multiple exit values and an economic floor
4. **Phase 5** — Historical prices (7/30-day median, percentiles, volatility)
5. **Phase 6** — Realised sales ledger and true g/h
6. **Phase 7** — Liquidity and market-capacity caps
7. **Phase 8** — Farm route valuation
8. **Phase 9** — Ranked “make me gold” action list

## File layout

```
OnyxiaGold/
  OnyxiaGold.toc
  Core.lua
  Database.lua
  Scanner.lua
  Prices.lua
  OpportunityEngine.lua
  UI.lua
  Engines/
    Essence.lua
    Shards.lua
    Transmute.lua
    Disenchant.lua
    Crafting.lua
    Farming.lua
  Data/
    Recipes.lua
    DisenchantTables.lua
    ItemGroups.lua
    OnyxiaOverrides.lua
  README.md
```

## Author

Charles / Velderin
