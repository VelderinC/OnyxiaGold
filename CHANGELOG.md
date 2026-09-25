# Changelog

## 0.1.31 — Known recipe book

- Opening Alchemy or Enchanting saves every recipe that window shows: spell, reagents, counts, output, and a cooldown when the client returns one. The book stays until that window is opened again.
- A deterministic recipe from that book can show up in What to do now beside the existing rows, on the same rank score. The next craft is left out when its own profit is not positive. Recipes that already have a hand-written line stay on that line.

## 0.1.30 — Economic integrity

- A buy is a whole auction. Cash required is the listing price. Leftover units stay in the plan and the next action can use them. A craft is kept only while its own marginal value stays positive.
- Disenchant is offered only when the intact sale is known and worse, the item cannot be sold, or it is marked destruction stock. Opening the Auction House no longer starts a browse or a post. Post profit is sale proceeds minus the value of the stack, and a stale or external price is not posted.
- External prices load from the OnyxiaGoldExternal addon. The sync tool replaces that file with os.replace and leaves the previous snapshot in place when the download fails. Any transmutation stone in bags or equipped counts. The 20-hour transmute stays unknown until Alchemy has been open and GetTradeSkillCooldown has been read. /reload rebuilds opportunities once when market data is already saved.

## 0.1.29 — Post the finished stack

- After a conversion, transmute, or craft is in your bags, What to do now keeps a row that says to post it, with the bag count and the P25 price after the auction-house cut. The row stays when there is nothing left to buy.
- Post sits on that action row and lists one planned stack. The click tells you to open the Auction House when it is closed. When it is open, that same click puts the stack in the sell slot and posts it.

## 0.1.28 — Window layout

- The /og window is split into Auction, Options, the action list, and Mail. Held is now In bags, Collect Gold is now Take gold, and Factory Sweep is now Take mail. The clicks are unchanged.

## 0.1.27 — Bag sort order

- Sort still stacks partial stacks on one click. Empty slots end up at the front, and items swap into order at the back: same item together, then class, subclass, quality, and name. If the client stops accepting moves, the next click continues.

## 0.1.26 — Button tooltips

- Hovering Held, Collect Gold, or Factory Sweep says what that button does. The clicks themselves are unchanged.

## 0.1.25 — Sort button, window size, quality rims

- The backpack Sort button sits in the title bar, just to the right of the portrait, and is shown again each time that backpack opens. One click still stacks items and packs them to the back.
- The /og window has a corner grip. Its width and height are saved and come back after /reload and relog. Dragging the window still moves it.
- Uncommon, rare, epic, and better items get a thin quality rim on every default bag slot. Poor and common items stay plain.

## 0.1.24 — External market snapshot

- `tools/OnyxiaGoldSync` downloads the Onyxia Alliance snapshot from ah.nerfed.net and writes a gitignored Lua file. The addon still loads when that file is missing.
- A newer live scan is left as it is. External prices are not a buy, and a download that is not the Alliance snapshot does not replace a valid file.

## 0.1.23 — Factory inventory

- Held switches the list to bags, bank, and mail. Each item has one disposition, a text badge, and a colour. The tooltip says what it is worth and why.
- Disenchant is used only when the existing engine has a yield. Missing or stale prices stay unknown or wait. Bags are not rearranged.

## 0.1.22 — Factory mail

- Mail is classified from the invoice, and from the client's own auction subject formats when those globals exist.
- Collect Gold and Factory Sweep are clicks. Each click takes one safe auction-house mail. COD, personal, and unknown mail stay put. Mail is never deleted.
- A full bag pauses an item take. If the take needs a hardware event or the client rejects it, the row says what to click. It does not pretend the mail was collected.

## 0.1.21 — Stack size and deposit

- A new scan keeps stack size beside price. Two stack sizes at the same unit price stay two rows.
- A post row shows the deposit `CalculateAuctionDeposit` returns for 12, 24, and 48 hours. If the client has no number, the row says to put the stack in the post slot.
- If his own auction is already the cheapest, the row says leave it and the buyout box is not moved under that price. Nothing calls `StartAuction` or `CancelAuction`.

## 0.1.20 — One no-cooldown craft

- Arcanite, Primal Might, and Elemental Fire are one comparison. The row casts the winner once and names the gold given up by skipping the runner-up. They are not on the 20-hour cooldown.
- Elemental Fire stays three, with no Transmute Master multiplier. Arcanite shows 2 seconds, Primal Might 5, Elemental Fire 25. Skyflare's cast time stays blank.

## 0.1.19 — Void Shatter floor

- Void Shatter is one Void Crystal into two Large Prismatic Shards, one craft, and only when the Runed Eternium Rod is on the character and the recipe is known. If selling the crystal leaves more, the row says sell.
- The two prismatic recipes need the Runed Fel Iron Rod on the character and a known recipe. Abyss Crystal has no shatter line.

## 0.1.18 — Owned disenchant

- A bag item with a known yield can be disenchanted when that beats its vendor value. Rares become one shard. Epics at item level 200–277 become one Abyss Crystal. Set green brackets use the minimum quantity. Nothing is bought.
- Item levels 166 and 167, Northrend uncommon rates, and Abyssal Shatter stay out. The 0.5% crystal is not added. Equipped gear is not a row. A skill gap returns no row.

## 0.1.17 — Skill 1 actions

- Magic, Astral, Mystic, and Nether essence pairs are item-use conversions. They need no profession and no skill, so they can be the next row at Alchemy 1 and Enchanting 1.
- A recipe above the live skill stays locked. Skill 1 still does not plan Titanium, an epic gem, or a high-level disenchant.

## 0.1.16 — One 20-hour transmute

- One cooldown row. It ranks the epic gems, the eternal cycle, and the old 20-hour metals this character can perform. It names the winner and the gold given up by skipping the runner-up. If none beat selling the materials, the row says skip. Still one cast.
- Titanium, Earthsiege, and Skyflare stay off that cooldown. Cardinal Ruby, Eternal Might, and the discovered primals stay out because their minimum skill is unset.
- Eye of Zul stays three Forest Emeralds and no eternal. Transmute Master stays the 1.20 expectation, and only on transmutes that support it.
- Unknown recipe state stays unknown until a profession scan. A recipe above the live Alchemy or Enchanting skill is locked and is not the next row. Skill 1 does not plan Titanium, an epic gem, or a high-level disenchant.

## 0.1.15 — Preview filters

- Show unlearned Alchemy and Enchanting recipes, and cash-short conversions with no profession, as skill or gold previews rather than buys.

## 0.1.14 — Beyond gold

- An off-by-default checkbox lists profitable Alchemy and Enchanting actions that cost more than deployable gold, with the cash required, the shortfall, and the profession skill when that is also short.

## 0.1.13 — Personal trade history

- Record each character's buys, sales, and auction-house mail proceeds, and show them as copyable text with spent and received totals.

## 0.1.12 — Bag sort

- A Sort button on the backpack stacks partial stacks, then packs items to the back.

## 0.1.11 — Profit breakdown

- Each action row shows the depth-walk buy cost, the P25 sale price, and the proceeds after the cut, plus an off-by-default checkbox for Alchemy and Enchanting crafts above current skill.

## 0.1.10 — Click to buy

- A buy row searches the live auction page, then one click buys one listing at or under the stop.

## 0.1.9 — Readable window and auction button

- Solid dark window, wider columns that no longer collide, and an OnyxiaGold button on the auction house title bar.

## 0.1.7 — Scan progress and action rows

- Show a progress bar while Quick Scan or Full Scan runs, and show the buy, conversion, and post on each action row.

## 0.1.6 — Log clock crash

- Replace `math.mod` with the Lua 5.1 `%` operator so logging no longer crashes on Warmane 3.3.5.

## 0.1.5 — Version watermark

- Always-visible top-left watermark shows OnyxiaGold and the TOC version.

## 0.1.3 — Factory Operations, Phase A and Phase B

Phase A corrects planner and snapshot debt. Phase B reserves cash, bag materials, and cloned auction depth inside one session plan. Factory Mail and Factory Inventory are not in this version.

- Transmute: Titanium (spell 60350) requires Alchemy 395. 440 is difficulty colour, not the skill requirement.
- Min, P10, P25, median, P75, and weighted mean are computed from the full runtime buyout book. Only the persisted acquisition depth is truncated. `depthCoveredQuantity` is stored separately from `buyoutQuantity`. `GetAcquisitionQuote` will not price past covered depth.
- `Capital:GetSpendableAfterMail()` reserves against liquid + claimable mail. Liquid 100g, reserve 10%, mail 900g → 900g deployable after collection, not 990g.
- Known recipes are profession-scoped. A complete profession scan replaces that profession's set. Saved flat sets migrate (database v4).
- A mailbox with unloaded mail persists `snapshotComplete = false` plus `visibleCount` and `totalCount`. The UI does not present that subtotal as exact.
- Own auctions persist `shown`, `total`, and `complete` (`shown >= total`). An incomplete owner list shows Listed as approximate.
- Craft capacity is split into `marketProfitableCrafts`, `physicalPossibleCrafts`, `affordableCrafts`, `capabilityAllowedCrafts`, `executableCrafts`, and `sensibleCrafts`.
- `sensibleCrafts` is a crude output cap. A plan will not add more output units than the visible buyout book already shows. The tooltip calls it a cap, not a liquidity model. It is not a sale rate.
- `SessionState` rebuilds on each plan. A selected action reserves its cash, the bag units it uses, and the auction units it would buy. The next action sees what remains, including output units already planned. The saved market snapshot is not modified.
- Dream Shard combines one way: 3 Small Dream Shards into 1 Dream Shard. The addon does not recommend a split.
- Prismatic shards stay a priced pair. They are not an action until the Enchanting recipe and the Runed Fel Iron Rod are represented.
- Epic gem transmutes share one `transmute_20h` cooldown per plan. Earthsiege and Skyflare are multi-input and are not on that cooldown. Cardinal Ruby is not an action because its minimum skill is unset. Philosopher's Stone is a tool, not a reagent. Transmute Master stays the 1.20 expectation only on transmutes that support it.
- The live auction page for the next buy is marked with a stop, the units that still fit, and the gold lost if that auction is over the stop. A one-unit scrap that cannot fill the recipe is marked scrap. The post box is filled at or above the floor. Querying stops when the visible page is entirely over the stop. He presses Blizzard's button.
- The output cap's room is the visible book minus bags, bank, mail items, and his own listings. Partial or stale snapshots stay marked and still count. If he already holds at least that book, the row says post or hold. Stock is a count, not an asking price.
- A transmute needs Philosopher's Stone (item 9149) in bags or equipped. Later stones stay "tool not confirmed". A rod in the bank is a withdraw line, not a finished craft. Buy quantity stops at free bag slots. Equipped gear is not a disenchant or vendor row. Tools are not consumed in the profit math.

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
