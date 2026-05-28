# Vision Pivot — 2026-05-29

**Author**: Owner + Claude (assistant)
**Status**: LOCKED (owner-approved)
**Type**: Foundation decision document — supersedes prior vision; anchor reference for all subsequent GDD restructures.

> **Read this first.** This document is the **single source of truth** for the post-2026-05-29 game vision. Any GDD update, code change, or feature decision after this date MUST reconcile against the 8 locked decisions below. Disagreement = update this doc (with explicit revision), then propagate.

---

## 1. Executive summary

**Brainrot Inc.** pivots from "**Roblox idle game with NPC raid + future PvP**" to "**Multi-place hub-and-spoke creature hunter with idle kandang economy + 3-tier boss progression + peer-to-peer trade**".

The new genre DNA: **Pokémon GO + Adopt Me + Loomian Legacy + Pet Simulator** mash — adapted for Roblox mobile-first, kid-friendly audience.

**Core loop (new)**:
```
   Hunt wild Brainrots in Areas (capture with area-tier items)
        ↓
   Bring back to private Kandang → idle production (passive coin helper)
        ↓
   Use captured roster to fight Colony Boss in Area
        ↓
   Progress to CEO Brainrot (Super Boss) in dedicated zones
        ↓
   Spend tokens to enter Raid Dungeons (solo or party, Legendary drops)
        ↓
   Trade peer-to-peer with other players in Lobby
```

**Key shift**: From "**send team, AFK, collect**" idle game **to** "**explore, hunt, raid, trade**" creature-collector hunter — with idle as **background progress helper, NOT pillar**.

---

## 2. The 8 locked decisions (with rationale)

### Decision 1: World Architecture — **Lobby + per-area sub-place** (Roblox Universe)
**Locked value**: Multi-place Roblox Universe. Lobby place = social hub. Sub-places per Area / Super Boss zone / Raid Dungeon / private Kandang.

**Rationale**: Adopt Me / Pokémon GO pattern proven on Roblox. Scales mobile-first (smaller per-server load), enables instanced co-op, supports privacy (Kandang) + sociality (Lobby) cleanly.

**Trade-off accepted**: Cross-place state handoff complexity (`TeleportService` + `TeleportData` + `MemoryStoreService`). Persistence GDD #1 needs cross-place teleport extension.

---

### Decision 2: Capture Mechanic — **Item-based instant capture (no fight required)**
**Locked value**: Player buys **capture items** (area-tier — Forest Item, Cave Item, Sky Item, etc.). Item applied to wild Brainrot → **instant capture** (success rate possibly tier-dependent, TBD). No fight required for capture itself.

**Rationale**: Reduces friction (kid-friendly), creates a clean **coin sink** (items must be purchased), enables Pokémon GO-style Pokeball economy. Pet AI not needed for wild → simplifies hub-world combat surface.

**Trade-off accepted**: Wild Brainrot combat removed from demo flow. Pet AI #25 demo refocuses on boss combat only (Decision 4).

---

### Decision 3: Boss System — **Three distinct tiers**
**Locked structure**:

| Tier | Working name | Location | Access |
|---|---|---|---|
| **Tier 1: Colony Boss** | "Colony Boss" or "Pack Leader" | In each shared Area (1 per area, alongside regulars) | Free explore |
| **Tier 2: Super Boss** | **🚧 NAMING TBD** — candidates: `CEO Brainrot`, `Apex Brainrot`, `Overlord` | Standalone Super Boss sub-place (1 boss only, no regulars) | Free, but area must be unlocked |
| **Tier 3: Raid Boss** | "Raid Boss" | Instanced Raid Dungeon sub-place | **Token-gated** (consume 1 token to enter) |

**Rationale**: Clear progression ladder — wild capture → Colony grind → Super Boss hunt → Raid Dungeon endgame. Each tier has distinct vibe + access pattern. Matches Pokémon GO's tier 1-5 raid model + Monster Hunter's apex predator structure.

---

### Decision 4: Pet AI Role — **Boss combat only (Tier 1+2+3)**
**Locked value**: Pet AI #25 used **exclusively for boss combat** at all 3 tiers. Wild Brainrot capture (Decision 2) does NOT require Pet AI summon — pure item-based.

**Rationale**: Combat surface simplified — Pet AI promoted from "field combat optional" to **pillar combat engine** for all boss encounters. Cleaner mental model for player: "summon = boss only".

**Implication**: Pet AI mechanics (real-time, owner-centered detection, formations) become **mainstream combat** at Tier 1 (Colony in Area), party-coordinated at Tier 2 (CEO), and dungeon-coordinated at Tier 3 (Raid). Battle #5 turn-based engine **fully obsolete** (no remaining use case).

---

### Decision 5: Colony Boss Combat Style — **Solo-able**
**Locked value**: Colony Bosses (Tier 1) are designed to be **soloable** by a single player using Pet AI summons. Future stats tuning may adjust based on player power / playtest. Co-op encouraged via bonus rewards (TBD).

**Rationale**: Colony Bosses spawn in shared Areas (8-player capacity). Co-op-required would create griefing (1 player can't trigger without party). Solo-able prevents the deadlock; party rewards encourage social play organically.

**Open balance question**: Should Colony Boss HP scale with player count in range (Pokémon GO style adaptive scaling)? Defer to first playtest.

---

### Decision 6: Super Boss / CEO Accessibility — **Party-instanced**
**Locked value**: Super Boss zones are **per-party instanced sub-places**. Player can enter solo (own instance) or bring a party (shared instance). No overlap with other parties.

**Rationale**: Tier 2 boss = epic encounter, should feel exclusive to the engaging party. Avoids "first kill wins loot" griefing, gives party 100% focus, scales reward to party effort cleanly.

**Implication**: Need party formation in Lobby + TeleportService with party-based dispatch. Roblox `TeleportService:TeleportPartyAsync` supports this natively.

---

### Decision 7: Raid Boss Token Economy — **Hybrid (daily free + quest reward + DevProduct)**
**Locked value**: Raid Boss tokens obtained via:
- **A. Daily free**: 1 token per day, server-clock reset (no carry-over)
- **B. Quest reward**: Daily Quests can drop tokens (varies per quest type, TBD)
- **C. DevProduct**: Robux purchase ladder (TBD: e.g. 1 token @ 49 R, 5 tokens @ 199 R, 10 tokens @ 349 R)

**Open detail**:
- **Token consumption**: consumed regardless of result (win OR fail)? Or refund on fail?
- **Token tradeable**: NO (would create exploit market). Tokens are bound to player.
- **Token cap**: max stack per player (TBD: e.g. 10 tokens) to prevent hoarding.

**Rationale**: Pokémon GO Raid Pass model (free + premium) proven. Adds Robux monetization layer that's zero-P2W (tokens don't grant combat advantage, just access frequency).

**Zero-P2W check**: DevProduct tokens **only** grant raid attempt frequency, NOT combat power. Player skill + roster strength still determines win/loss + Legendary drop rate. PASS.

---

### Decision 8: Rarity Tier per Source — **Tiered pyramid**
**Locked structure**:

| Source | Brainrot rarity tier | Drop mechanic |
|---|---|---|
| **Wild in Areas** | Common - Uncommon | 100% capture with item (success rate by item tier) |
| **Colony Boss** | Rare | Chance-drop on kill (e.g. ~10-20% per kill) |
| **Super Boss / CEO** | Epic | Guaranteed-or-high-chance per kill, weekly cooldown? (TBD) |
| **Raid Boss Dungeon** | Legendary | Chance-drop per token spent, unique-only-here Brainrots |

**Rationale**: Standard MMO-style pyramid. Volume inverse to rarity — wild Common is daily, Legendary is grind goal. Drives **progression hook** that maps cleanly to existing Evolution + Level/XP systems.

---

## 3. What's PRESERVED (existing work that survives)

All existing implementation + recently-locked decisions that **do NOT change**:

### Code shipped (zero rework)
- ✅ `src/ServerStorage/PlayerData/*` — Persistence (1043 lines + supporting)
- ✅ `src/ReplicatedStorage/Shared/Config/PersistenceConfig.luau`
- ✅ `src/ServerStorage/Personality/PersonalityService.luau` (749 lines)
- ✅ `src/ReplicatedStorage/Shared/Config/PersonalityConfig.luau` (315 lines)
- ✅ `src/ServerStorage/Economy/EconomyService.luau` (466 lines, shipped 2026-05-29)
- ✅ `src/ReplicatedStorage/Shared/Config/EconomyConfig.luau` (607 lines)
- ✅ `src/ServerScriptService/EconomyBootstrap.server.luau` + LeaderboardWriteBootstrap
- ✅ `src/ReplicatedStorage/Shared/Config/CaptureConfig.luau`
- ✅ Pet AI demo code (`src/.../Demo/{DemoConfig §combat, BrainrotAI, DemoServer §fighter}`) — pillar combat engine
- ✅ TestEZ specs (Persistence, Personality, Economy) — all ~3,500 lines

### GDDs that survive intact (no rewrite, just minor cross-ref updates)
- ✅ `persistence-gdd.md` v1.4.1 — data layer agnostic. **Extension needed**: cross-place `TeleportData` handoff design (new §11 or sub-section).
- ✅ `personality-gdd.md` v1.1.1 — 5 personality table + battle tags still relevant for Pet AI dispatch.
- ✅ `evolution-gdd.md` v1.3 — Axis A milestones + Axis B Level/XP still drive progression at all tiers.
- ✅ `economy-gdd.md` v1.3 — faucet/sink discipline + Monetization SKU ladder + circulation lock all carry forward. **Extensions needed**: new sinks (capture items, raid tokens DevProduct), repurposed sinks (raid_send → boss_raid_token).
- ✅ `pet-combat-gdd.md` v1.0 — engine remains, **promoted to pillar**. **Extension needed**: 3-tier boss combat scaling rules (solo Colony / party CEO / party Raid).

### Locked decisions that carry forward
- ✅ Multi-personality system (Hyper/Lazy/Chaotic/Loyal/Rebel)
- ✅ Level/XP curve (xpPerWin 50, xpCurveBase 100, statGrowthPerLevel 0.08, maxLevel 100)
- ✅ baseRatePerWorker = 0.5 (idle kandang base rate)
- ✅ pendingPoolCapBase = 3600 (storage cap)
- ✅ DevProduct Meme Coins Pack ladder (15K/50K/150K/500K @ 49/99/249/599 R)
- ✅ 3 launch GamePasses (2x Offline 199R, Extra Slots 299R, Auto-Catch 399R)
- ✅ Zero pay-to-win rule (extended to raid tokens — Decision 7)
- ✅ Anti-pattern telemetry checklist (10 smells, economy-gdd §10.4) — applies to new context
- ✅ Wallet pressure curve (economy-gdd §10.2) — partial re-validate, mostly intact

---

## 4. What's OBSOLETED (drop list)

These systems / decisions are **CANCELLED**. Move associated GDDs to `design/gdd/archive/` with a note pointing back to this doc.

### Systems obsoleted

| System | Why obsoleted |
|---|---|
| **#5 Battle System (turn-based)** | All combat is now real-time via Pet AI (Decision 4). Turn-based engine has no remaining use case. |
| **#6 Raid v1 (NPC Rival Startups)** | Re-purposed entirely as Boss System (Decision 3). NPC Rival Startups (Grind Corp, Chill Collective, Glitch Gang, Pivot Ventures) **cancelled** — replaced with Colony Bosses + CEO Brainrots + Raid Bosses. |
| **#7 Raid Shield** | No PvP base raid → no shield function (Decision per pivot context). |
| **#18 PvP Raids (Live Player Targets)** | Async open PvP cancelled (owner pivot 2026-05-29). |
| **#19 Revenge System** | Coupled to PvP Raids; obsoleted. |

### Lore obsoleted

| Lore element | Why obsoleted |
|---|---|
| **4 NPC Rival Startups** (Grind Corp, Chill Collective, The Glitch Gang, Pivot Ventures) | Replaced by area-themed Colony Bosses + CEO Brainrot names. The "Rival Startups" framing was for raid targets — no longer needed. |
| **Burnout Inc.** (Phase 2 boss-tier rival) | Could be repurposed as a Raid Boss name, but not committed yet. |

### Locked decisions cancelled

| Prior decision | Why cancelled |
|---|---|
| `raidLootPct = 0.20` (locked 2026-05-29) | Raid mechanic re-purposed to boss raid (PvE, not PvP). New loot economy for boss drops + tokens replaces this. |
| `raidSendCostCoins = 100` | Replaced by **token consumption** for Raid Boss (Decision 7). |

**Note on raid-gdd v1.2 + economy-gdd v1.3 changelog**: The 2026-05-29 circulation lock (raidLootPct 0.25→0.20, DevProduct ladder) is **partially preserved**:
- ✅ DevProduct ladder **survives** (applies to new context).
- ✅ Anti-pattern telemetry + wallet curve **survive**.
- ❌ raidLootPct lock **cancelled** — boss loot is different mechanic.

---

## 5. What's NEW (new systems to design)

These need fresh GDDs. **Priority order** for design work (each blocks the next):

### Tier 1: Infrastructure (BLOCK other work)
1. **World Universe Architecture** — Roblox multi-place layout, TeleportService protocol, TeleportData schema, MemoryStore for cross-server coordination. **MUST come first** — every other GDD depends on knowing place boundaries.
2. **Kandang (private sub-place)** — replaces Showroom #26. Private per-player Roblox place. Simpler 3D layout (utilitarian "kandang/cage" vibe vs. fancy "showroom"). Houses Brainrot → idle production. Visit-able by other players (read-only async social).

### Tier 2: Core gameplay loops
3. **Boss System (3-tier)** — replaces Raid #6. Colony / CEO / Raid Boss specifications. Combat rules per tier. Loot tables. Spawn/respawn mechanics. Difficulty scaling.
4. **Capture System v2** — replaces Capture #4. Item-based instant capture. Area-tier items (Forest/Cave/Sky/etc.). Success rate formulas. Shop integration.
5. **Capture Items Shop + Token Economy** — extension of Economy #9. Item catalog with prices. Token sources (daily/quest/DevProduct). New faucet/sink entries.

### Tier 3: Social systems
6. **Party + Matchmaking** — for co-op CEO + Raid Boss. Lobby UI. Friend invite. Optional public party finder.
7. **Trade Marketplace (Peer-to-peer)** — Pokémon GO style. Friendship gating. Confirmation + atomic transaction. Stardust-analogue cost. Special trade limit.

### Tier 4: Optional polish (Phase 1.5 / Phase 2)
8. **Visit Base (read-only)** — extension of Kandang. Async social. Like/star Fame metric.
9. **Fame / Trending** — Phase 2 social layer (likes, trending, follower count).

---

## 6. Affected GDDs — full mapping

| GDD | Status | Action required |
|---|---|---|
| `persistence-gdd.md` v1.4.1 | ✅ Preserve | Extension: §11 cross-place TeleportData handoff |
| `personality-gdd.md` v1.1.1 | ✅ Preserve | No change |
| `economy-gdd.md` v1.3 | 🔄 Extend | Add §11 Capture Items + Token Economy faucets/sinks. Remove raidLootPct lock from §8.3 (annotate as obsoleted). |
| `capture-gdd.md` v1.3 | ❌ Rewrite | Total rewrite as Capture v2 — area-tier items, instant capture. Old "Explore + Manual Catch" model obsoleted. |
| `idle-production-gdd.md` v1.3 | 🔄 Rewrite | De-emphasize from pillar → "Kandang idle progress helper". Simplify Showroom 3D wrapper → utilitarian Kandang. |
| `pet-combat-gdd.md` v1.0 | 🔄 Extend | Section: 3-tier boss combat (solo Colony / party CEO / party Raid). Difficulty scaling rules. |
| `battle-gdd.md` v1.3 | ❌ OBSOLETE | Move to `design/gdd/archive/`. Add archive note pointing to this doc. |
| `raid-gdd.md` v1.2 | ❌ OBSOLETE | Move to `design/gdd/archive/`. Replaced by new Boss System GDD. |
| `evolution-gdd.md` v1.3 | ✅ Preserve | No change. Level/XP still drives roster power. |
| `systems-index.md` (updated 2026-05-29) | 🔄 Rewrite v3.0 | Major restructure: drop obsoleted systems, add new systems, re-prioritize MVP order. |

**New GDDs to author**:
- `design/gdd/world-universe-gdd.md` (foundation)
- `design/gdd/kandang-gdd.md` (replaces showroom-gdd planned)
- `design/gdd/boss-system-gdd.md` (replaces raid-gdd)
- `design/gdd/capture-v2-gdd.md` (replaces capture-gdd v1.3)
- `design/gdd/items-token-gdd.md` (or fold into economy-gdd v2)
- `design/gdd/party-matchmaking-gdd.md`
- `design/gdd/trade-marketplace-gdd.md`

---

## 7. Naming locks (where decisions made)

| Concept | Old name | New locked name |
|---|---|---|
| Player base | Showroom | **Kandang** |
| Tier 1 boss | (n/a) | **Colony Boss** (or "Pack Leader" — confirm) |
| Tier 2 boss | (n/a) | **🚧 TBD** — candidates: `CEO Brainrot`, `Apex Brainrot`, `Overlord`. **Owner needs to pick.** |
| Tier 3 boss | (n/a) | **Raid Boss** |
| Tier 3 location | (n/a) | **Raid Dungeon** |
| Tokens for Raid Boss | (n/a) | **🚧 TBD** — candidates: `Raid Token`, `Dungeon Key`, `Boss Pass` |
| Capture items | (none — was flat `captureCostCoins`) | **Capture Item** (area-tier: `Forest Item`, `Cave Item`, etc. — names per area) |

**4 NPC Rival Startups** (Grind Corp, Chill Collective, The Glitch Gang, Pivot Ventures) → **CANCELLED as raid targets**. May be repurposed as area-themed worldbuilding (e.g. each area has rival corporation flavor) but not as boss identities.

---

## 8. Next steps roadmap

**Immediate (this session if approved)**:
1. **Update `systems-index.md` v3.0** — restructure system list per this pivot. Drop obsoleted (Raid Shield, PvP Raid, Revenge). Add World Universe, Kandang, Boss System, Capture v2, Items+Token, Party, Trade Marketplace. Re-prioritize MVP build order.
2. **Move obsoleted GDDs to `design/gdd/archive/`** with archive notes pointing back here.
3. **Annotate `raid-gdd.md` v1.2 + `battle-gdd.md` v1.3** with archive header before move.
4. **Annotate `economy-gdd.md` v1.3** — strikethrough raidLootPct lock with "OBSOLETED by Vision Pivot 2026-05-29".

**Short-term (next 1-3 sessions)**:
5. Author `world-universe-gdd.md` v1.0 (FOUNDATION — blocks everything else)
6. Author `kandang-gdd.md` v1.0 (replaces planned showroom GDD)
7. Author `boss-system-gdd.md` v1.0
8. Author `capture-v2-gdd.md` v1.0
9. Author `items-token-gdd.md` v1.0 (or extend economy-gdd v2)

**Medium-term (sessions 4-8)**:
10. Author `party-matchmaking-gdd.md` v1.0
11. Author `trade-marketplace-gdd.md` v1.0
12. Extend `pet-combat-gdd.md` with 3-tier boss combat section

**Open decisions still needed (before some GDDs can lock)**:
- **Super Boss naming** (CEO Brainrot vs Apex Brainrot vs Overlord)
- **Token naming** (Raid Token vs Dungeon Key vs Boss Pass)
- **Token DevProduct prices** (specific Robux ladder)
- **Token consumption rule** (consumed on fail vs refund on fail)
- **Capture item tier success rate formulas**
- **Colony Boss HP scaling with player count** (adaptive or fixed)
- **Boss spawn/respawn cadence** (always-on vs scheduled vs cooldown)
- **Friendship gating in Trade** (how to gate without geo-walking? Mutual play hours? Trade history?)
- **Trade Stardust analogue** (new currency or use coins?)

---

## 9. Audit trail — what changed when

| Date | Change | By |
|---|---|---|
| 2026-05-29 | Vision pivot decided in design conversation. 8 decisions locked. This doc authored. | Owner + Claude |
| (TBD) | systems-index v3.0 restructure | (next session) |
| (TBD) | Obsoleted GDDs moved to archive | (next session) |
| (TBD) | New foundation GDDs authored | (subsequent sessions) |

---

## 10. Cross-reference quick map

When making any future decision or GDD change, check against this doc's anchors:

- "How should X work?" → check Decisions 1-8
- "Does this contradict prior work?" → check §3 (preserved) vs §4 (obsoleted)
- "Is X obsoleted?" → check §4 obsolete list
- "Is X already designed?" → check §6 GDD mapping
- "What still needs deciding?" → check §8 Open decisions list

---

**END OF VISION PIVOT DOC.**

Any subsequent design decision that contradicts this doc must either (a) be reconciled with this doc + this doc updated with explicit revision note, or (b) be rejected.
