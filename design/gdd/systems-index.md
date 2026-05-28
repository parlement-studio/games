# Systems Index — Brainrot Inc.

**Last Updated**: 2026-05-28
**Author**: game-designer
**Status**: Draft (pre-production system map)

> **Revision note (2026-05-28):** **Demo-driven scope reconciliation (Phase A + Phase B cross-GDD reconciliation pass complete).** Two MVP systems surfaced by the playable vertical slice (commits `e984677`, `36724cf`, `a71e545`) were added to the system map: **#25 Field Combat / Pet AI** (real-time field combat with summoned Brainrots vs. wild Brainrots — distinct from turn-based Raid Battle) and **#26 Base / Showroom Spatial Layer** (3D pedestal/stand UI wrapper over Idle Production deployment). Also: **#5 Battle scope clarified** as turn-based-Raid-only (field combat is #25); **#8 Evolution extended** with a parallel **Level/XP progression axis** (`xpPerWin`/`xpCurveBase`/`statGrowthPerLevel`/`maxLevel`, from demo `36724cf`) — Level/XP is **combat-only** (does NOT affect idle production rate, locked decision). Summary count 24→26, build order, dependency graphs updated. **Phase B (2026-05-28) reconciliation pass updated 7 existing GDDs** (persistence v1.4 → v1.4.1, personality v1.1 → v1.1.1, battle v1.2 → v1.3, raid unchanged, evolution v1.2 → v1.3, idle-production v1.2 → v1.3, capture v1.2 → v1.3, economy v1.1 → v1.2) with descriptive cross-references — no schema or formula changes outside the documented renames (`statGrowth` → `statGrowthPerLevel`). New GDDs `design/gdd/pet-combat-gdd.md` and `design/gdd/base-showroom-gdd.md` remain planned. **Capture #4 status correction:** demo's crate/encounter usage is **fallback scaffolding for downstream-system testing**, NOT a promotion of fallback to canonical MVP capture — explore-map remains the MVP target (capture-gdd v1.3 §10 status note); #4 status stays "Not started" for explore-map work.

> **Revision note (2026-05-26):** Added **Daily Quests** as MVP system **#17** (retention/objective layer). Phase 2 systems renumbered #17–23 → **#18–24**. Summary, build order, dependency graphs, and all by-number cross-references updated.

> **Revision note (2026-05-26):** **Raid Shield (#7) moved MVP → Phase 2** (Raid v1 is offense-only — there is nothing attacking you in v1, so a shield has no function until PvP #18). **System number #7 is retained as a stable identifier** to avoid churn in the many by-number cross-references across the GDDs — only its phase/priority changed (MVP/P2 → Phase 2/P3). Summary counts, build order, and both dependency graphs updated; Defense Rating display stays in Raid v1 (owned by Raid #6).

## Summary

- Total systems: 26 (18 MVP, 8 Phase 2)
- Not started: 22 (includes #4 Capture — demo only ships fallback scaffold, NOT canonical explore-map)
- In design: 2 (#25 Pet AI — GDD v1.0 drafted 2026-05-29; #26 Showroom — demo-validated, formal GDD pending)
- In implementation: 2 (#1 Persistence — shipped; #2 Personality — shipped)
- Implemented: 0
- Polished: 0
- Live: 0

> **Phase B reconciliation (2026-05-28) completed for 7 existing GDDs**: persistence-gdd v1.4.1, personality-gdd v1.1.1, battle-gdd v1.3, evolution-gdd v1.3, idle-production-gdd v1.3, capture-gdd v1.3, economy-gdd v1.2 — all updated with descriptive cross-references to #25 and #26 + the Battle-scope clarification + the Level/XP Axis B documentation. No schema or formula changes outside the documented `statGrowth` → `statGrowthPerLevel` rename. Raid-gdd v1.1 unaffected (turn-based Raid scope unchanged by Pet AI #25 addition).

**Legend** — Priority tiers: P0 = foundation/blocker, P1 = core MVP, P2 = MVP-supporting, P3 = Phase 2. Risk: L/M/H. Phase tag in each block.

**World context**: Setting = "The Feed" (internet-as-place). Hub zone = "Downtown Scroll". Raid v1 targets = 4 NPC "Rival Startups" (Grind Corp, Chill Collective, The Glitch Gang, Pivot Ventures); boss-tier rival "Burnout Inc." deferred to Phase 2. See world-bible / Master GDD for narrative detail.

---

## Systems

### 1. Data Persistence & Roster Core
- **Status**: Not started
- **Phase**: MVP
- **Priority**: P0 (foundation)
- **Value**: 5 | **Effort**: 4 | **Risk**: H | **Monetization**: 3
- **GDD**: `design/gdd/persistence-gdd.md` (planned)
- **Depends On**: (none — foundation)
- **Depended On By**: nearly everything (Personality, Idle Production, Capture, Battle, Raid, Evolution, Economy, Auto-Catch, Reroll, Leaderboard)
- **Notes**: GUID per Brainrot; roster cap 200; DataStore for owned roster + currency + progression; MemoryStore for ephemeral cross-server state (raid shield, matchmaking pool, raid mailbox). Server-authoritative clock for all idle/shield timers (never trust client time). High risk: schema must be versioned/migratable on day one or every later system inherits debt. Config-driven: cap values, key names, retry/backoff in a Persistence config.

### 2. Personality System (PILLAR)
- **Status**: Not started
- **Phase**: MVP
- **Priority**: P0 (pillar — gates flavor of all other systems)
- **Value**: 5 | **Effort**: 3 | **Risk**: M | **Monetization**: 4
- **GDD**: `design/gdd/personality-gdd.md` (planned)
- **Depends On**: Data Persistence (stores personality field per GUID)
- **Depended On By**: Idle Production, Battle, Raid, Evolution, Moment System, Reroll, Drama Events (P2), Fame (P2)
- **Notes**: 5 types: Hyper / Lazy / Chaotic / Loyal / Rebel. This is a shared modifier layer, not a self-contained feature — implement as a config-driven trait table (production multipliers, battle behavior hooks) that other systems read. Zero magic numbers: every multiplier (Hyper +30%, Lazy -50%, etc.) lives in a PersonalityConfig table. Build the data + trait-table first; behavior wiring lands as each consumer system is built.

### 3. Idle Production (Online + Offline)
- **Status**: Not started
- **Phase**: MVP
- **Priority**: P1 (core loop)
- **Value**: 5 | **Effort**: 3 | **Risk**: M | **Monetization**: 4
- **GDD**: `design/gdd/idle-production-gdd.md` (planned)
- **Depends On**: Data Persistence, Personality, Economy (deposits Meme Coins)
- **Depended On By**: Raid (steals uncollected production), Evolution (production milestones), Moment System
- **Notes**: Online + offline accrual, offline cap 8 hours, server-clock only, pending-collect model (resources accrue into a pending pool, player taps to collect). Personality modifies rate (Hyper faster w/ random breaks, Lazy slower + morale aura, Chaotic 2x/0x per cycle, Loyal steady, Rebel strike risk). All rates/caps config-driven. AFK-safe by design (idle is the default state). Core revenue surface (collection-speed/cap GamePasses later).

### 4. Capture (Explore + Manual Catch)
- **Status**: Not started
- **Phase**: MVP
- **Priority**: P1 (core loop entry point)
- **Value**: 5 | **Effort**: 5 | **Risk**: H | **Monetization**: 3
- **GDD**: `design/gdd/capture-gdd.md` (planned)
- **Depends On**: Data Persistence, Personality (capture assigns/reveals personality)
- **Depended On By**: Roster growth feeds Idle Production, Battle, Raid, Evolution
- **Notes**: Single hub zone ("Downtown Scroll") + config-driven spawn table + timing mini-game, server-authoritative resolution (client sends intent, server validates spawn ownership + timing window). **Scope risk (solo dev): exploration-map capture is the single highest-effort MVP item.** Fallback if behind schedule: replace free-roam capture with a "crate/encounter" UI (tap-to-encounter → same timing mini-game) — preserves the personality-reveal moment without map/streaming cost. Flag this decision early (lock by build step 5).

### 5. Battle System (Auto, Turn-Based, Spectatable)
- **Status**: Not started
- **Phase**: MVP
- **Priority**: P1 (core combat, blocks Raid)
- **Value**: 5 | **Effort**: 4 | **Risk**: H | **Monetization**: 2
- **GDD**: `design/gdd/battle-gdd.md` (planned)
- **Depends On**: Data Persistence, Personality (battle modifiers), Roster (combatants)
- **Depended On By**: Raid (raid uses battle resolution), Evolution (raid-survival milestones)
- **Notes**: Auto turn-based; player spectates live. Personality drives behavior (Hyper attacks first / 20% mistarget, Lazy berserk-when-last, Chaotic random move, Loyal bodyguard <30% HP, Rebel double-damage counter). Server-authoritative resolution; client is a replay/viewer. All damage/turn formulas config-driven (explicit formula required in GDD, no "calculated appropriately"). Risk H: turn engine + personality hooks + deterministic replay is the most logic-heavy system. **Scope clarification (post-demo, 2026-05-28):** Battle in this GDD is **turn-based, designed for Raid (#6)** vs NPC Rival Startups (deterministic + spectatable replay). It is **NOT** the engine used for real-time hub-world combat against wild Brainrots — that is **Field Combat / Pet AI (#25)**, a separate combat layer with its own GDD. The two coexist: Battle owns Raid combat; Pet AI owns field combat. Both read personality + level + species stats from the same roster entry; only the resolution model (turn-based replay vs real-time tick) differs. Stat-scaling formula `levelScale(L)` is **shared** between both (defined here in Battle §2.1).

### 6. Raid v1 (vs NPC Rival Startups)
- **Status**: Not started
- **Phase**: MVP
- **Priority**: P1 (social engine surrogate at launch)
- **Value**: 4 | **Effort**: 4 | **Risk**: M | **Monetization**: 3
- **GDD**: `design/gdd/raid-gdd.md` (planned)
- **Depends On**: Battle, Personality, Idle Production (loot = % of target's uncollected), Economy (raid cost), Data Persistence + MemoryStore (raid mailbox). *(Raid Shield is NOT an MVP dependency — Raid v1 is offense-only; shield is Phase 2, see #7.)*
- **Depended On By**: Evolution (raid milestones), Revenge System (P2)
- **Notes**: v1 targets are config-defined NPC "Rival Startups" (4 at launch: Grind Corp, Chill Collective, The Glitch Gang, Pivot Ventures) — no live PvP yet, which de-risks matchmaking and griefing for launch while still exercising the full battle + loot pipeline. **Raid v1 is offense-only** (you raid NPCs; nothing raids you), so the Raid Shield is deferred to Phase 2 (#7) — but the **Defense Rating display stays in v1** (owned here, Raid #6). Send team of 3, win = steal % of NPC pool (or apply to defense scoring). PvP + Revenge + boss-tier rival (Burnout Inc.) + Raid Shield deferred to Phase 2. Raid cost/loot %/team size config-driven.

### 8. Work-Based Evolution + Level/XP Progression (MVP: 1 evolution stage/personality, level cap 100)
- **Status**: Partial (Level/XP shipped in demo `36724cf`; work-based evolution not started)
- **Phase**: MVP
- **Priority**: P2 (long-term hook)
- **Value**: 4 | **Effort**: 3 | **Risk**: M | **Monetization**: 2
- **GDD**: `design/gdd/evolution-gdd.md` (planned — needs extension per 2026-05-28 reconciliation)
- **Depends On**: Data Persistence (tracks lifetime stats + `level`/`xp` per GUID), Personality, Idle Production / Battle / Raid / Pet AI (milestone + XP sources)
- **Depended On By**: Moment System (evolution as a moment), Fame (P2), Multi-Branch Evolution (P2)
- **Notes**: This system now covers **two orthogonal progression axes** (post-demo reconciliation 2026-05-28):
  - **Axis A — Work-Based Evolution (transformative milestone, one-shot):** single milestone → single evolved stage per personality (e.g., Hyper→Senior Hyper at lifetime production X; Rebel→Revolutionary at N raids survived; Loyal→Guardian at N defends). Flips identity once; visible model/name change. Multi-branch evolution → Phase 2 (#20). Requires lifetime-stat counters wired from day one (cheap now, expensive to backfill).
  - **Axis B — Level/XP Progression (gradual combat power growth):** per-Brainrot Level/XP system, prototyped in demo `36724cf` (`DemoConfig.progression`: `xpPerWin=50`, `xpCurveBase=100`, `statGrowthPerLevel=0.08`, `maxLevel=100`). XP awarded on battle wins (Raid #6 + Pet AI #25); level-up triggers `levelScale(L) = 1 + statGrowthPerLevel*(L-1)` applied to HP/damage in **both** Battle (#5) and Pet AI (#25) — formula is shared. `level`/`xp` fields persist on `BrainrotEntry`.
  - **Axes are orthogonal:** Level grows gradually with use (combat power); Evolution flips identity once at a milestone. A Lv50 Hyper that hasn't hit the lifetime-coins threshold is still base-form; a freshly-evolved Senior Hyper might still be Lv1. Both feed the Moment System (#12).
  - All milestone thresholds + XP curve params config-driven (no magic numbers).

### 9. Economy / Currency (Meme Coins)
- **Status**: Not started
- **Phase**: MVP
- **Priority**: P1 (currency backbone)
- **Value**: 4 | **Effort**: 2 | **Risk**: M | **Monetization**: 4
- **GDD**: `design/gdd/economy-gdd.md` (planned) — delegate detailed sink/source model to economy-designer
- **Depends On**: Data Persistence
- **Depended On By**: Raid (cost), Reroll, Auto-Catch unlock, Shop/Upgrades, Moment System, Leaderboard
- **Notes**: Single soft currency "Meme Coins" at launch. `gems` field provisioned in schema, default 0, unused at launch (forward-compat, no UI). Premium "Brain Cells" → Phase 2. All earn/spend values config-driven; server-authoritative balance mutations only. Delegate full source/sink tuning to economy-designer.

### 10. Auto-Catch (Hybrid: free unlock + GamePass upgrade)
- **Status**: Not started
- **Phase**: MVP
- **Priority**: P2 (convenience / monetization)
- **Value**: 3 | **Effort**: 3 | **Risk**: M | **Monetization**: 4
- **GDD**: `design/gdd/auto-catch-gdd.md` (planned)
- **Depends On**: Capture, Data Persistence (catch counter), Monetization (GamePass tier), Economy
- **Notes**: Hybrid — free basic auto-catch unlocks at ~50 manual captures (rewards engagement, not pay-to-skip); GamePass upgrades speed/quality. **Not default on day 1** — manual capture must be experienced first so personality-reveal lands and FTUE teaches the mini-game. Auto-catch still shows reveals (batched feed); rare pulls interrupt for a manual celebratory reveal. Unlock threshold + rates config-driven.

### 11. Reroll Personality
- **Status**: Not started
- **Phase**: MVP
- **Priority**: P2 (depth + monetization)
- **Value**: 3 | **Effort**: 2 | **Risk**: L | **Monetization**: 4
- **GDD**: `design/gdd/reroll-gdd.md` (planned)
- **Depends On**: Personality, Economy (Meme Coins cost), Monetization (optional Robux path), Data Persistence
- **Notes**: Capped escalating Meme Coins cost curve (250/600/1200/2000 cap, resets after 24h) + optional Robux shortcut. **Odds must be displayed** (compliance + trust). Server rolls the result authoritatively (UpdateAsync atomic + idempotency key, anti-dupe). Cost curve, cap, and per-personality probabilities all config-driven and shown in UI.

### 12. Moment System (Online burst events + Offline recap reel)
- **Status**: Not started
- **Phase**: MVP
- **Priority**: P2 (the "personality is visible" payoff)
- **Value**: 4 | **Effort**: 3 | **Risk**: M | **Monetization**: 1
- **GDD**: `design/gdd/moment-system-gdd.md` (planned)
- **Depends On**: Personality, Idle Production, Battle/Raid + Evolution (moment sources), Data Persistence (logs moments for recap)
- **Notes**: Online = periodic personality "burst" events surfaced in base (lightweight, event-driven, not per-frame sim — the viral/shareable hook). Offline = recap reel on return ("while you were gone..."). This is the surface that makes the pillar *felt* rather than just numerical — protect it from being cut, but it can ship minimal (text/icon pop-ups) and grow. One moment highlighted at a time (clarity for kids). Distinct from Drama Events (P2): Moments are display/notification; Drama is interactive choice. Event frequency/weighting config-driven.

### 13. UI / HUD
- **Status**: Not started
- **Phase**: MVP
- **Priority**: P1 (every system needs a surface)
- **Value**: 4 | **Effort**: 4 | **Risk**: M | **Monetization**: 2
- **GDD**: `design/gdd/ui-hud-gdd.md` (planned)
- **Depends On**: Economy (currency display), Roster, most systems (each contributes a panel)
- **Depended On By**: Capture, Battle (spectate view), Raid, Reroll, Daily Rewards, Codes, Shop, Settings, Leaderboard
- **Notes**: HUD (currency, roster count, collect button), roster/management panel, battle spectate view, raid screen, moment pop-ups, leaderboard panel. Build incrementally alongside each consumer system rather than all at once. Mobile-first, pure presentation — reads state, fires intent Remotes.

### 14. Onboarding / FTUE
- **Status**: Not started
- **Phase**: MVP
- **Priority**: P1 (Roblox first-5-minutes retention)
- **Value**: 5 | **Effort**: 3 | **Risk**: M | **Monetization**: 1
- **GDD**: `design/gdd/onboarding-gdd.md` (planned)
- **Depends On**: Capture, Personality, Idle Production, Economy, UI/HUD
- **Notes**: Guided first capture → reveal personality → deploy → first collect → soft raid intro, with an immediate reward inside the first session. Guide character ("Incubator HQ mentor") gives one instruction at a time; exactly one glowing objective beacon at all times. Must teach the capture mini-game before Auto-Catch is available. Build after core loop systems are functional (it scripts a path *through* them). Step thresholds/rewards config-driven.

### 15. Monetization (GamePass + DevProduct, zero P2W)
- **Status**: Not started
- **Phase**: MVP
- **Priority**: P1 (launch revenue, but non-blocking to core loop)
- **Value**: 3 | **Effort**: 3 | **Risk**: M | **Monetization**: 5
- **GDD**: `design/gdd/monetization-gdd.md` (planned)
- **Depends On**: Data Persistence, Economy, Auto-Catch, Reroll (the things being sold). *(Raid Shield #7 is Phase 2, so the extended-shield product is a Phase-2 SKU, not a launch SKU.)*
- **Notes**: GamePasses + DevProducts, strict zero pay-to-win (critical: nothing that boosts raid combat power). Launch SKUs: Auto-Catch upgrade, 2x offline earnings, Reroll Robux path, extra Brainrot slots, VIP cosmetics. **Extended Raid Shield (capped) is a Phase-2 SKU** (Raid Shield #7 moved to Phase 2 — no shield function in offense-only Raid v1). Receipt processing must be idempotent + server-authoritative (ProcessReceipt). Product IDs + grants config-driven. Wire after the underlying systems exist.

### 16. Leaderboard (Richest Manager)
- **Status**: Not started
- **Phase**: MVP
- **Priority**: P2 (light social competition + early retention)
- **Value**: 3 | **Effort**: 2 | **Risk**: L | **Monetization**: 1
- **GDD**: `design/gdd/leaderboard-gdd.md` (planned)
- **Depends On**: Data Persistence, Economy (net worth source)
- **Depended On By**: (none in MVP); generalizes into Fame/Trending leaderboard infra (P2)
- **Notes**: Single global leaderboard ranking players by total wealth ("Richest Manager"). Backed by OrderedDataStore; update on collect/save (debounced), not per-tick. Low effort, low risk — pulled forward from Phase 2 for early social hook without full Fame infra. Define "net worth" metric (lifetime coins earned vs current balance) in GDD. Top-N display config-driven. Lays the leaderboard plumbing that Fame/Trending (P2) reuses.

### 17. Daily Quests (Objectives)
- **Status**: Not started
- **Phase**: MVP
- **Priority**: P2 (retention / objective layer)
- **Value**: 3 | **Effort**: 3 | **Risk**: M | **Monetization**: 2
- **GDD**: `design/gdd/daily-quests-gdd.md` (planned)
- **Depends On**: Economy (#9, reward payout), Data Persistence (#1, progress tracking + daily reset state), and objective sources Capture (#4), Raid (#6), Idle Production (#3), Work-Based Evolution + Level/XP (#8), Field Combat / Pet AI (#25)
- **Depended On By**: (none in MVP)
- **Notes**: Gives players a short daily set of goals so a 15–30 min session has direction beyond pure idle. **3 daily quests** rolled at reset from a config-driven pool (examples: "tangkap N Brainrot", "menang M raid", "menang M field battle", "kumpulkan X coins", "evolve 1 Brainrot", "level-up 1 Brainrot"); progress accrues from the objective-source systems' events (event-driven, not polling). On completion of a quest, reward = Meme Coins via Economy faucet `quest_daily` (reward pool is per-quest config, not a flat magic number — see economy-gdd §3.1/§8.2). **Daily RESET on server-clock** (never trust client time): store `lastQuestReset` + the active quest set + per-quest progress in PlayerData (coordinate with Persistence schema; reset = re-roll the 3 quests + zero progress when server-clock day boundary crossed). Quest pool, count (3), per-quest targets, and reward ranges are all config-driven. Risk M: cross-server-consistent daily reset + multi-source progress tracking is the moving part; lean on Persistence's server-clock + atomic mutation path. **Scope note (solo dev MVP addition):** this is a late add to MVP scope — a **prune candidate** if launch schedule slips. Fallback if cut: a simple escalating daily-login reward (no objectives), which still feeds the `quest_daily` faucet. Needs its own GDD: `design/gdd/daily-quests-gdd.md` (planned).

### 25. Field Combat / Summoned Pet AI
- **Status**: In design (GDD v1.0 drafted 2026-05-29; demo `a71e545` shipped reference impl; production code graduation + personality battle-tag wiring pending)
- **Phase**: MVP
- **Priority**: P2 (field-world activity layer; not core loop blocker)
- **Value**: 4 | **Effort**: 3 (much already built in demo) | **Risk**: M | **Monetization**: 2
- **GDD**: `design/gdd/pet-combat-gdd.md` v1.0 (drafted 2026-05-29 — descriptive lock of demo reference impl)
- **Depends On**: Personality (#2, damage multiplier + future battle tags), Data Persistence (#1, roster + `level`), Capture (#4, must own a Brainrot to summon it), Battle (#5, shares `levelScale(L)` stat-scaling formula from §2.1)
- **Depended On By**: Moment System (#12, kill/summon as a moment), Daily Quests (#17, "win N field battles" objective), Evolution + Level/XP (#8, XP source on win)
- **Notes**: **Real-time hub-world combat** — distinct from Battle #5 (turn-based, for Raid #6). Player taps a summon UI to spawn a caught Brainrot as a temporary field pet; the pet follows the player in a fan-out formation (`followSpreadDegrees`, `followJitterStuds`), detects wild Brainrots within `detectionRangeStuds` centered on the **owner player** (not the pet), engages in a combat ring (`combatRingRadiusStuds < attackRangeStuds`, no clipping) with periodic damage ticks (`combatTickSec`), and auto-despawns after `fighterLifetimeSec`. Wins award `winCoins` (Economy faucet). Server-authoritative: spawn, AI seek, damage tick, despawn, formation slot assignment all server-side. Personality currently scales damage via `prodMult`; **full battle behavior tags** (Hyper `act_first_mistarget`, Lazy `berserk_when_last`, etc., as defined in Personality #2) **to be wired** in the formal GDD. All ranges, timings, formation params, and reward values config-driven (currently in `DemoConfig` §combat; will graduate to `PetCombatConfig`). Wild Brainrot AI (wander/flee/engage) lives in `BrainrotAI.server.luau` (114 lines, demo). **Reference impl files:** `src/ReplicatedStorage/Shared/Demo/DemoConfig.luau` §combat (lines ~337–430); `src/ServerScriptService/Demo/DemoServer.server.luau` §fighter logic (lines ~900–1200); `src/ServerScriptService/Demo/BrainrotAI.server.luau`. **Open design questions** (deferred to GDD): leashing model (current = owner-centered detection); kill credit (current = owner only); multi-pet stacking cap; PvP collision (Phase 2).

### 26. Base / Showroom Spatial Layer
- **Status**: In Implementation (demo `e984677` shipped reference impl; formal GDD pending)
- **Phase**: MVP
- **Priority**: P2 (UX wrapper over Idle Production deployment; not core loop blocker)
- **Value**: 3 | **Effort**: 2 (much already built in demo) | **Risk**: L | **Monetization**: 1
- **GDD**: `design/gdd/base-showroom-gdd.md` (planned) *— alternative: fold into `idle-production-gdd.md` §6 UI if Showroom stays a pure UX layer; decision deferred to GDD draft.*
- **Depends On**: Idle Production (#3, owns `base.buildings.deployment` data + production math), UI/HUD (#13, shared UI primitives), Data Persistence (#1, slot map persists in `base.buildings[id].deployment`)
- **Depended On By**: (none yet — visual upgrades for Building/Worker Slot tiers in Phase 2 will skin this layer)
- **Notes**: **3D spatial UI** sitting on top of Idle Production's abstract `deployment` slot map. The factory's worker slots are rendered as **physical pedestals/stands** in the world; the player taps an empty stand's `ProximityPrompt("Place")` to open an inventory picker, picks a caught Brainrot id, and the deployed model walks onto the pedestal and stays there producing coins. A deployed model carries a `ProximityPrompt("Recall")` to un-deploy. Slot-to-Brainrot mapping persists in `base.buildings[BUILDING_ID].deployment` (Persistence #1 + Idle #3 schema — no new fields). **Pure presentation layer:** production math, rates, personality multipliers, and offline accrual remain owned by Idle Production #3; Showroom only owns spatial UI, model spawn/despawn, and place/recall UX. Idempotent deploy/recall remotes (validate roster ownership, slot bounds, no double-occupancy invariant). **Reference impl files:** `src/ReplicatedStorage/Shared/Demo/DemoConfig.luau` §showroom (lines ~202–314); `src/ServerScriptService/Demo/DemoServer.server.luau` §deploy/recall (lines ~429–800); `src/StarterPlayer/StarterPlayerScripts/Demo/DemoUI.client.luau` §placement UI. **Open design questions** (deferred to GDD): naming alignment (`showroom` → `base/factory` per Idle GDD?); pedestal-tier visuals for `factoryLevel`/`storageLevel`; mobile reachability of ProximityPrompts.

---

### Phase 2 Systems

### 7. Raid Shield
*(number retained as stable identifier; phase moved to Phase 2)*
- **Status**: Not started
- **Phase**: Phase 2
- **Priority**: P3 (anti-grief, paired with PvP)
- **Value**: 3 | **Effort**: 2 | **Risk**: M | **Monetization**: 3
- **GDD**: `design/gdd/raid-shield-gdd.md` (planned)
- **Depends On**: Data Persistence + MemoryStore (shield expiry, cross-server), PvP Raids (#18)
- **Depended On By**: PvP Raids (#18, checks shield before allowing), Monetization (extended-shield product)
- **Notes**: **Deferred to Phase 2 alongside PvP Raids (#18)** — in Raid v1 (offense-only NPC raids) the shield has **no function** (nothing attacks you, so there is nothing to shield against). It slots in cleanly when live PvP arrives. **System number #7 is retained as a stable identifier** (used as a by-number cross-reference across the GDDs) — only its phase/priority moved. Free 4-hour shield baseline (sacred — never paywalled as the only option); server-clock expiry stored in MemoryStore so it holds across server hops. The **Defense Rating display** ships in Raid v1 already (owned by Raid #6); only the shield mechanic itself is Phase 2. Durations/cost config-driven.

### 18. PvP Raids (Live Player Targets)
- **Status**: Not started — **Phase**: Phase 2 — **Priority**: P3
- **Value**: 5 | **Effort**: 5 | **Risk**: H | **Monetization**: 3
- **Depends On**: Raid v1, Battle, MemoryStore matchmaking pool, Raid Shield (#7, Phase 2), Personality
- **Notes**: Replaces/extends NPC targets with real player bases + boss-tier rival (Burnout Inc.). Highest social value, highest risk (matchmaking, fairness, griefing, offline-defense correctness). v1 NPC raids are the de-risking runway.

### 19. Revenge System
- **Status**: Not started — **Phase**: Phase 2 — **Priority**: P3
- **Value**: 4 | **Effort**: 3 | **Risk**: M | **Monetization**: 2
- **Depends On**: PvP Raids, MemoryStore (raid mailbox), Economy
- **Notes**: 2x-reward counter-raid quest within 24h. Creates ping-pong retention loop. Requires PvP first.

### 20. Multi-Branch Evolution
- **Status**: Not started — **Phase**: Phase 2 — **Priority**: P3
- **Value**: 4 | **Effort**: 3 | **Risk**: M | **Monetization**: 2
- **Depends On**: Work-Based Evolution (MVP), lifetime-stat counters
- **Notes**: Multiple evolution paths per personality based on play history. Cheap *if* lifetime counters were built in MVP (see systems 1 & 8).

### 21. Premium Currency (Brain Cells)
- **Status**: Not started — **Phase**: Phase 2 — **Priority**: P3
- **Value**: 2 | **Effort**: 2 | **Risk**: M | **Monetization**: 5
- **Depends On**: Economy, Monetization, Data Persistence
- **Notes**: Second hard currency. Schema field pre-provisioned now (default 0). Maintain zero-P2W stance.

### 22. Fame / Trending System
- **Status**: Not started — **Phase**: Phase 2 — **Priority**: P3
- **Value**: 4 | **Effort**: 4 | **Risk**: H | **Monetization**: 2
- **Depends On**: Personality, Battle/Raid + Idle Production (fame sources), Base Visiting, Leaderboard infra (MVP), Data Persistence
- **Notes**: Fame points → "Trending" status (+25% output, fan NPCs), cross-base Likes, global Trending leaderboard. Reuses MVP Leaderboard plumbing + requires base-visiting + cross-server aggregation — hence H risk.

### 23. Drama Events (Interactive Choice Events)
- **Status**: Not started — **Phase**: Phase 2 — **Priority**: P3
- **Value**: 3 | **Effort**: 2 | **Risk**: L | **Monetization**: 2
- **Depends On**: Personality, Idle Production, Economy (some choices cost coins), Moment System
- **Notes**: Two-choice pop-ups triggered by personality combos. Low cost, high flavor. Distinct from MVP Moment System (interactive vs display-only). Event table config-driven.

### 24. Base Visiting / Social Lobby
- **Status**: Not started — **Phase**: Phase 2 — **Priority**: P3
- **Value**: 3 | **Effort**: 4 | **Risk**: H | **Monetization**: 1
- **Depends On**: Data Persistence (load another player's base read-only), MemoryStore, Roster
- **Notes**: Prerequisite for Fame Likes. Loading/rendering another player's base safely (read-only, anti-exploit) is non-trivial — gates Fame.

---

## Dependency Graph

```
                    ┌─────────────────────────────┐
                    │  Data Persistence & Roster  │  (P0 foundation)
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │   Personality System (P0)   │  (pillar trait layer)
                    └──┬────────┬────────┬─────┬──┘
                       │        │        │     │
          ┌────────────┘        │        │     └──────────────┐
          ▼                     ▼        ▼                     ▼
   ┌────────────┐        ┌──────────┐ ┌─────────┐      ┌────────────┐
   │  Capture   │        │   Idle   │ │ Battle  │      │   Reroll   │
   │ (explore)  │        │Production│ │(auto TB)│      │            │
   └─────┬──────┘        └────┬─────┘ └────┬────┘      └─────┬──────┘
         │                    │            │                 │
         │   ┌────────────────┤            ▼                 │
         │   │                │       ┌─────────┐            │
         ▼   ▼                │       │ Raid v1 │◄───────────┤ (cost)
   ┌──────────┐               │       │ (NPC)   │            │
   │Auto-Catch│               │       └──┬──────┘            ▼
   └──────────┘               │          │             ┌──────────┐
                              │          │             │ Economy  │──► Leaderboard
                              │          │             │(MemeCoin)│   (Richest Mgr)
                              │          │             └────┬─────┘
                              │          │                  │
                              ▼          ▼                  │
                        ┌──────────────────┐               │
                        │ Work-Based Evo    │◄──────────────┘
                        │ (lifetime stats)  │
                        └─────────┬─────────┘
                                  ▼
                        ┌──────────────────┐
                        │  Moment System    │
                        └──────────────────┘

   ┌──────────────────────────────────────────────────────────────┐
   │ Daily Quests (#17, MVP)                                        │
   │   reward  ◄── Economy (Meme Coins faucet quest_daily)          │
   │   tracking/reset ◄── Data Persistence (lastQuestReset+progress,│
   │                       server-clock daily reset)                │
   │   progress from objective sources: Capture, Raid, Idle, Evo,   │
   │                                     Pet AI (field-win source)  │
   │   cross-cutting with UI/HUD (quest panel)                      │
   └──────────────────────────────────────────────────────────────┘

   ┌──────────────────────────────────────────────────────────────┐
   │ Field Combat / Pet AI (#25, MVP — demo-validated)              │
   │   shares stat formula  ◄── Battle (#5 §2.1 levelScale(L))      │
   │   reads personality    ◄── Personality (#2)                    │
   │   reads roster + level ◄── Data Persistence (#1) / Capture (#4)│
   │   awards               ──► Economy (winCoins faucet)           │
   │   feeds                ──► Evolution/Level (XP source)         │
   │                            Moment System (#12)                 │
   │                            Daily Quests (#17 field-win)        │
   └──────────────────────────────────────────────────────────────┘

   ┌──────────────────────────────────────────────────────────────┐
   │ Base / Showroom Spatial Layer (#26, MVP — demo-validated)      │
   │   pure UX wrapper over Idle Production deployment              │
   │   reads/writes  ◄──► Idle Production (#3, base.buildings.dep.) │
   │   reads/writes  ◄──► Data Persistence (#1, base block)         │
   │   shares primitives ◄── UI/HUD (#13)                           │
   │   no new persistence; no new production math                   │
   └──────────────────────────────────────────────────────────────┘

   Cross-cutting (depend on many): UI/HUD, Onboarding/FTUE, Monetization, Daily Quests

   ── Phase 2 ──────────────────────────────────────────────
   Raid v1 ──► PvP Raids (+ Burnout Inc. boss) ──► Revenge System
                  ▲
   Raid Shield (#7) ─┘  (defends against live attackers; no function in offense-only Raid v1)
   Evolution ──► Multi-Branch Evolution
   Economy/Monetization ──► Premium Currency (Brain Cells)
   Leaderboard + Data Persistence ──► Base Visiting ──► Fame/Trending
   Personality + Moment ──► Drama Events
```

```mermaid
graph TD
    DP[Data Persistence & Roster P0] --> PS[Personality P0]
    DP --> ECON[Economy: Meme Coins]
    PS --> CAP[Capture]
    PS --> IDLE[Idle Production]
    PS --> BAT[Battle]
    PS --> RR[Reroll]
    PS --> EVO[Work-Based Evolution]
    PS --> MOM[Moment System]
    CAP --> AC[Auto-Catch]
    IDLE --> RAID[Raid v1 NPC]
    BAT --> RAID
    ECON --> RAID
    ECON --> RR
    ECON --> AC
    ECON --> LB[Leaderboard: Richest Manager]
    IDLE --> EVO
    BAT --> EVO
    RAID --> EVO
    EVO --> MOM
    IDLE --> MOM
    UI[UI/HUD] -.-> CAP
    UI -.-> BAT
    UI -.-> RAID
    UI -.-> LB
    FTUE[Onboarding/FTUE] -.-> CAP
    FTUE -.-> IDLE
    MON[Monetization] -.-> AC
    MON -.-> RR

    ECON --> DQ[Daily Quests]
    DP --> DQ
    CAP --> DQ
    RAID --> DQ
    IDLE --> DQ
    EVO --> DQ
    UI -.-> DQ

    %% #25 Field Combat / Pet AI (MVP, demo-validated)
    PS --> PETAI[Field Combat / Pet AI #25]
    DP --> PETAI
    CAP --> PETAI
    BAT -. shared levelScale .-> PETAI
    PETAI --> ECON
    PETAI --> EVO
    PETAI --> MOM
    PETAI --> DQ

    %% #26 Base / Showroom Spatial Layer (MVP, demo-validated)
    IDLE --> SHOW[Base/Showroom #26]
    DP --> SHOW
    UI -.-> SHOW

    RAID --> PVP[PvP Raids P2]
    SHIELD[Raid Shield #7 P2] --> PVP
    MON -.-> SHIELD
    PVP --> REV[Revenge P2]
    EVO --> MBE[Multi-Branch Evo P2]
    ECON --> BC[Brain Cells P2]
    LB --> BV[Base Visiting P2]
    BV --> FAME[Fame/Trending P2]
    PS --> DRAMA[Drama Events P2]
```

---

## Priority List (recommended build order — solo dev)

Foundation-first; each step unlocks the next. MVP target launch July 2026.

1. **Data Persistence & Roster Core** — nothing works without GUID schema, roster cap, server clock, MemoryStore. Build versioned/migratable from day one. Wire lifetime-stat counters now (cheap; enables Evolution + Phase 2 multi-branch later).
2. **Personality System (trait-table layer)** — pillar. Data field + config trait table first; behavior hooks land as consumers are built.
3. **Economy / Currency (Meme Coins)** — currency backbone many systems spend/earn against. Pre-provision `gems` field (default 0).
4. **Idle Production (online + offline)** — first half of the core loop; the AFK-safe default state. Validates server-clock + pending-collect early.
5. **Capture** — second half of core loop and roster growth. **Highest scope risk: decide explore-map vs crate-fallback before committing.** Lock that call here.
6. **UI / HUD (incremental)** — start now and grow per system; needed to make capture + idle playable/testable.
7. **Battle System** — logic-heavy; required before raids. Build deterministic server-authoritative turn engine + personality hooks.
8. **Raid v1 (NPC Rival Startups)** — exercises battle + loot pipeline without PvP risk. *(Raid Shield is Phase 2 — Raid v1 is offense-only; see #7.)*
9. **Work-Based Evolution (1 stage/personality)** — long-term hook; consumes the lifetime counters from step 1.
10. **Moment System** — surfaces the pillar; ship minimal (pop-ups + recap), then enrich.
11. **Reroll Personality** — small, high monetization; needs Personality + Economy (done) + odds-display UI.
12. **Leaderboard (Richest Manager)** — small OrderedDataStore system; light social hook. Slots in once Economy + Persistence are stable.
13. **Daily Quests (objectives)** — slots in here because its objective sources (Capture, Raid, Idle, Evolution) and its reward backbone (Economy) are now all functional, so quests can hook real progress events and pay out via the `quest_daily` faucet. Needs the server-clock daily reset + `lastQuestReset`/progress fields in PlayerData (Persistence). **Late MVP scope add (solo dev) — prune candidate if July 2026 slips; fallback = simple escalating daily-login reward feeding the same faucet.**
14. **Auto-Catch (hybrid)** — convenience; gate behind ~50 manual catches, not default day 1.
15. **Onboarding / FTUE** — script the guided path through the now-functional core loop; first-5-minutes retention. Can surface the first daily quest as an early objective once Daily Quests exists.
16. **Monetization (GamePass + DevProduct)** — wire SKUs onto Auto-Catch, Shield, Reroll, convenience; idempotent ProcessReceipt. Non-blocking to loop, so late but pre-launch.

### Demo-validated late MVP additions (build-order slots, GDD pending)

These two systems were prototyped in the playable vertical slice ahead of formal GDD work (commits `e984677` / `a71e545`) and are folded back into the build order here. Code exists in `src/.../Demo/`; the **build-order obligation is to write the formal GDD, then graduate the demo code** from `Demo/*` namespace into the production `src/.../{PetCombat,BaseShowroom}/*` namespace (renaming and tightening against the GDD as needed). They are **not new code work** at the volume of items 1–16, but they **must not stay un-spec'd** — otherwise they become design debt.

- **#26 Base / Showroom Spatial Layer** — slot **after step 4 (Idle Production)** and **step 6 (UI/HUD)** in scope (it depends on both being designed); GDD work can land in parallel with step 6 since it is the spatial wrapper *for* the Idle deployment data. Pure UX layer over Idle #3's `base.buildings.deployment`; no new persistence.
- **#25 Field Combat / Pet AI** — slot **after step 7 (Battle System)** in scope (shares `levelScale(L)` stat formula). Real-time field combat, **distinct from** turn-based Battle #5. GDD work can land in parallel with step 8 (Raid v1). Requires Personality battle tags (defined in #2 GDD) to be wired for full personality flavor in combat (currently only damage multiplier).

**Phase 2 (post-launch), rough order:** Raid Shield (#7, paired with PvP — defends against live attackers) → PvP Raids (+ Burnout Inc. boss) → Revenge System → Drama Events → Fame/Trending (reuses MVP Leaderboard infra + needs Base Visiting) → Multi-Branch Evolution → Premium Currency (Brain Cells).
