# Idle Production (Online + Offline) GDD

**Version**: 1.3
**Last Updated**: 2026-05-28
**Author**: systems-designer
**Status**: Draft

> **Changelog v1.3 (2026-05-28)**: **Phase A reconciliation — two clarifications, no formula changes.**
> - **Axis B Level/XP does NOT affect idle production rate (LOCKED).** Evolution v1.3 added an Axis B Level/XP system (§2.7) — combat-only by design. Idle's §2.2 already kept `levelRateBonus = 0` at MVP (line ~76 / §8.1 IdleConfig); v1.3 strengthens the language: **the `levelRateBonus` term in F1 / F3-OFF stays at `0` permanently — it is NOT a future tuning lever for Level/XP.** A level-driven idle multiplier would (a) double-stack with Evolution Axis A's production multiplier (`evoProductionMult` x1.20), (b) double-stack with factory-level upgrades, and (c) couple combat XP to economy inflation. Decision: Level affects **combat only** (Battle #5 + Pet AI #25 via `levelScale(L)`); Evolution Axis A (`evoStage`) is the **sole production multiplier hook** for Brainrot maturity. The `levelRateBonus` config entry is preserved (= 0) only as a non-Level forward-compat slot (e.g. for a future "tier" or "rarity" multiplier unrelated to Axis B). See evolution-gdd v1.3 §2.7 / §2.8.
> - **Base / Showroom (#26) is a separate spatial UI layer over `base.buildings.deployment`.** The factory's worker slots (this GDD's abstract `deployment` map, §3.1) are rendered as **3D pedestals/stands** by the new system #26 Base / Showroom Spatial Layer (`base-showroom-gdd.md` planned; reference impl in demo `e984677`). **#26 owns the spatial UI (pedestal models, `ProximityPrompt("Place")`/`Recall`, model spawn/despawn)**; Idle (this GDD) keeps owning production math, rates, personality multipliers, and the abstract deployment slot map. No schema change — #26 reads/writes the same `base.buildings[BUILDING_ID].deployment` map. §6 Player-Facing UI updated to acknowledge the boundary; §9 Integration adds #26 row.
>
> **Changelog v1.2**: Added the **evolution production multiplier** to `effectiveRate` (F1) + `computeOfflineRate` (F3-OFF) — **FLAG-IDLE resolved**. `effectiveRate` now multiplies by `evoProductionMult = EvolutionConfig.stageMultipliers[b.evoStage].productionMultiplier` (stage 0 = 1.0, stage 1 = 1.20; unknown stage → 1.0 fallback). The **VALUES are OWNED by Work-Based Evolution #8** (`evolution-gdd.md` ≥ v1.1, single source of truth); Idle only reads them via `b.evoStage`. Integration Points #8 updated accordingly.

> **Changelog v1.1**: `base` (BaseData) + `pendingOnline` schema reconciliation RESOLVED — Persistence #1 (`persistence-gdd.md` v1.2) added them to the **v1 baseline** (not a v1→v2 migration), since the project is pre-launch with no live data. Flags below updated from "action required" to "resolved".

> **Parent GDD**: `design/gdd/systems-index.md` — System **#3 (Idle Production, P1 core loop)**.
> **Source of Truth**: `idea/brainrotInc.md` ("you capture unhinged meme creatures … put them to work in your chaotic factory"); the locked pre-production context.
> **Governing standards (NON-NEGOTIABLE)**: `.claude/rules/design-docs.md` (9 sections, explicit formulas, ≥5 edge cases, version header), `.claude/rules/config-data.md` (commented config + ranges + version field), `.claude/rules/gameplay-systems.md` (zero magic numbers, config-driven, delta-time, event-driven, state-machine), `.claude/rules/server-scripts.md` (server-authoritative, never trust client, pcall, rate limit).

> **Depends On**:
> - **#1 Data Persistence & Roster Core** (`persistence-gdd.md` v1.4) — OWNS storage, the atomic mutation path, `lastSeen`, `pendingOffline`, the `roster` map, and the **`base` (BaseData)** + `pendingOnline` fields (added to the v1 baseline, reconciled with this GDD). Idle does NOT touch DataStore directly.
> - **#2 Personality System** (`personality-gdd.md` v1.1) — OWNS the trait table, the per-Brainrot runtime state machine (Working / OnBreak / Walkout), and the `PersonalityMoment` / `WalkoutStarted` / `PersonalityChanged` event contracts. Idle READS modifiers and ADVANCES the state-machine tick + emits those events (see §2.4 ownership lock).
> - **#9 Economy** (`economy-gdd.md` v1.2) — OWNS the wallet + cost curves; Idle deposits via `Economy.award(player, amount, "idle_collect")` and spends via `Economy.spend(...)` for upgrades.

> **Depended On By**: Raid v1 (#6, loot = % of uncollected pending), Work-Based Evolution + Level/XP (#8, production milestones via `history.coins`; Level/XP is combat-only and does NOT affect idle rate — see v1.3 §2.2), Moment System (#12, listens to Idle-emitted events), Daily Quests (#17, "collect X coins" / progress events), Base / Showroom Spatial Layer (#26, 3D UI skin over `base.buildings.deployment` — pure rendering wrapper; reads/writes same data through same Persistence atomic path).

> **Cross-GDD consistency lock (no contradictions introduced — per `design-docs.md`):**
> - **Idle OWNS production rates.** Economy v1.1 §2.3 and §8.10 explicitly defer the *real* rate model to this GDD and flag its `~60 coins/min` as a **placeholder to be reconciled here**. This GDD sets the real rate (§8) and reconciles it against Economy's locked cost curves (factory 200/1.35, worker 150/1.50, storage 300/1.40). Economy still owns the wallet, the curves, and `totalCoinsEarned`; Idle owns only "how many coins per second".
> - **Personality OWNS trait + state machine.** Idle never hardcodes a personality number (it calls `PersonalityService` per personality-gdd §2.2) and never invents a new state-machine state. Ownership of advancing the tick is defined explicitly in §2.4.
> - **Persistence OWNS the clock + pending pool + storage.** Idle supplies `computeOfflineRate(roster, base)` for persistence `F-OFFLINE`; it does NOT re-implement the clock or the save path. **NEW**: this GDD defines `BaseData`, which persistence-gdd v1.1 does **not yet contain** — see the **Schema-update flag** in §3.
> - **Storage upgrade decision (LOCKED here).** `upgrade_storage` raises the **pending-pool cap** (collect headroom); the **offline 8h cap stays fixed** and is expanded only by a separate future monetization item. Rationale in §2.6 / §8.6. This closes Economy Open Question #6.

---

## 1. Overview & Purpose

Idle Production is the **second beat of the core loop** — *capture → **WORK** → collect*. After a player captures a Brainrot (#4) and it is rolled a personality (#2), they **deploy** it into a worker slot in their factory, where it **produces Meme Coins over time** — both while the player is online and (capped at 8 hours) while they are offline. Production accrues into a **pending pool**; the player taps **Collect** to move pending coins into their wallet via Economy. This is the satisfying "watch the number tick, then scoop it up" idle loop that makes the game **AFK-safe by design**: the default state of the game is "your factory is earning."

It is **P1 (core loop)** because:

1. **It is the primary faucet.** Almost all early/mid coins come from idle collect (Economy §3.1: `idle_collect` is the PRIMARY faucet). It funds every sink (capture, upgrades, reroll, raids).
2. **It is where personality becomes felt over time.** A Hyper worker burns out, a Lazy one motivates its neighbors, a Chaotic one doubles or zeroes, a Rebel walks out and drags friends — these are *production* outcomes surfaced as Moments. The pillar lives here in slow motion (Battle/Raid surface it in fast motion).
3. **It validates the server-clock + pending-collect spine early** (systems-index build order step 4): no client time trusted, offline capped at 8h, anti-exploit.
4. **It is a core revenue surface** (collection-cap / 2x-offline / extra-slot GamePasses).

**Player intent:** *"My little guys are working at my factory making me money. I check in, scoop up the pile, and use it to get more guys and bigger machines — and sometimes one of them does something hilarious."* The player thinks in terms of "deploy good workers, upgrade the factory, come back to a fat pile." They do **not** think about rates, ticks, or caps — those are surfaced as one clean ticking number and one Collect button.

What this GDD does **NOT** do: it does not implement DataStore (Persistence #1), does not own the wallet or cost curves (Economy #9), and does not own personality numbers or the state-machine *definition* (Personality #2). It owns *the production rate model, the factory/deployment model, the pending pool + collect mechanic, online/offline accrual, and the events other systems listen to.*

---

## 2. Core Mechanics

### 2.1 The factory model (building → worker slots → deployed Brainrot)

This GDD defines the factory structure that the locked context requires. Three nested concepts, all config-driven:

```
PLAYER BASE
  └── BUILDING[]            (factories the player owns; 1 at start, more unlockable)
        └── WORKER SLOT[]   (the simultaneous-work capacity inside a building)
              └── deployedId (the BrainrotEntry.id occupying that slot, or empty)
```

1. **Building** — a factory the player owns. MVP ships with **one starting building** (`startingBuildings = 1`); additional buildings are gated behind a factory-tier milestone (forward-compat; MVP can live with one). A building is the unit of **adjacency** and **overwork** (§2.7).
2. **Worker slot** — a slot *inside* a building that one deployed Brainrot occupies. The number of slots in a building is `startingWorkerSlots + workerSlotLevel` (the `upgrade_worker_slot` track, Economy §8.4 owns the cost). **This is the "WORKER SLOT factory" axis** in the locked context — simultaneous work capacity.
3. **Deployment** — only a Brainrot **assigned to a worker slot produces.** The roster (cap 200, owned by Persistence; expanded via `slot_unlock` + the Extra Roster Slots GamePass) is *ownership*; deployment is *who is currently clocked in*. These are deliberately distinct axes (locked context):

| Axis | What it is | Cap | Expanded by | Owner of cap |
|---|---|---|---|---|
| **Roster** | How many Brainrots you OWN | 200 | `slot_unlock` sink + Extra Roster Slots GamePass | Persistence #1 (`rosterCap`) |
| **Worker slots** | How many can WORK at once (per building) | `startingWorkerSlots + maxWorkerSlotLevel` per building | `upgrade_worker_slot` sink | Idle (this GDD) + Economy cost curve |

A player can own 200 Brainrots but only have (say) 5 worker slots — so deployment is a **choice** ("which 5 work?"), which is exactly where personality strategy lives (deploy a Lazy next to good workers for the aura; don't cram Rebels together).

### 2.2 Production accrual (the rate model)

Production is computed **server-side** and accrues into the **pending pool** (never directly into the wallet). The unit of accrual is **coins per second**, summed across all deployed Brainrots and scaled by factory upgrades.

1. **Per-Brainrot base rate** — every deployed Brainrot produces `baseRatePerWorker` coins/sec (config, §8). **Per-Brainrot `level` does NOT affect this rate** (locked v1.3, 2026-05-28): the `levelRateBonus` config field is preserved at `0` permanently as a non-Level forward-compat slot (e.g. for a future "tier" multiplier unrelated to Axis B). Per-Brainrot **maturity** scales the rate via **Evolution Axis A's** `evoProductionMult` (#8, +20% at stage 1) — this is the sole maturity-based multiplier on idle production. Combat `level` (Evolution Axis B, evolution-gdd v1.3 §2.7) is **deliberately orthogonal**: it scales HP/damage in Battle (#5) and Pet AI (#25), never `effectiveRate` here. Species variance is also Phase-2 (a `speciesBaseRate` map, currently uniform).
2. **Personality modifier** — multiply by the personality factors via `PersonalityService.getProductionModifier` (Personality F1: `personalityMult` × `chaoticCycleFactor` × `moraleFactor` × `paused?0:1`). Idle never hardcodes +30%/-50%/etc.
3. **Factory upgrade multiplier** — the `upgrade_factory` track raises a **global production multiplier** for that building (§2.5, F2).
4. **Sum & accrue** — sum every deployed worker's effective rate to get the building's coins/sec; sum buildings to get base-wide coins/sec; multiply by elapsed time (delta-time online, clamped elapsed offline) and add to the pending pool — **clamped to the pending-pool cap** (§2.6).

### 2.3 Online vs Offline

| | Online (player in server) | Offline (player gone) |
|---|---|---|
| **Who computes** | Idle server tick loop (this GDD), delta-time | Persistence on load via `IdleProduction.computeOfflineRate(roster, base)` (persistence `F-OFFLINE`) |
| **Clock** | Server `Heartbeat` accumulator (delta-time) | Server `os.time()`; `elapsed = clamp(now - lastSeen, 0, offlineCapSeconds)` (8h) |
| **Personality** | FULL state machine runs (breaks, walkouts, chaotic flips happen live, emit Moments) | **Averaged** — see §2.8 offline personality model (no live state machine while offline) |
| **Destination** | pending pool (online sub-accumulator) | `pendingOffline.coins` (persistence field) |
| **Collect** | one Collect button drains the WHOLE pending pool (online + offline) into the wallet | same button; the "While you were gone…" screen shows the offline slice |
| **2x Offline GamePass** | n/a | multiplies the **offline rate** inside `computeOfflineRate`, within the 8h cap (not the window) |

**Unified pending pool:** online accrual and offline accrual both land in **one pending pool** the player collects with one tap. Persistence stores the offline slice in `pendingOffline.coins`; the online slice is held in `base.pendingOnline` (new field, §3) so it too survives a crash before collect. On Collect, both are summed, deposited via one `Economy.award`, and zeroed in one atomic op.

### 2.4 Personality state-machine ownership (LOCKED coordination with #2)

> **Ownership lock (resolves the "who owns the state machine" question):**
> - **Personality (#2) DEFINES** the state machine: the states (`Working`/`OnBreak`/`Walkout`), the allowed transitions, the transition *conditions* (F2 break roll, F3 overwork/contagion), the runtime-state table shape, and the event payloads. (personality-gdd §2.5, §3.2, §5.3.)
> - **Idle Production (#3) DRIVES it:** Idle owns the **production tick loop**, so on each cycle Idle calls into `PersonalityService` to (a) evaluate break/walkout rolls, (b) advance expired timers back to `Working`, and (c) read the resulting modifier. **Personality performs the transition + emits the event; Idle provides the cadence and the building-occupancy context** (who is co-located, which building) that the rolls need.
> - **Idle EMITS the consumer-facing reaction:** when Personality fires `WalkoutStarted`, Idle zeroes those producers for the cycle (it already does, via `paused`); when a Moment-worthy production event happens (Chaotic double/zero this cycle), Personality emits `PersonalityMoment` and Idle simply respects the returned factor. Idle does not re-emit personality events — it consumes them and adjusts production. The only events **Idle itself** emits are the production-domain ones in §5.3 (`CoinsCollected`, `PendingCapReached`, `OfflineRewardComputed`).

This keeps the pillar's numbers/contracts in Personality and the cadence/orchestration in Idle, with no duplication.

### 2.5 Upgrades (factory / worker slot / storage)

All three upgrade tracks are **per-building** (MVP: one building, so effectively per-base) and their **costs are owned by Economy** (`cost(n) = floor(base * growth^n)`, economy §8.4). Idle owns each track's **gameplay effect**:

| Track | Economy cost curve | Idle effect (this GDD) | maxLevel |
|---|---|---|---|
| `upgrade_factory` | base 200, growth 1.35 | Raises the building **global production multiplier** by `factoryMultPerLevel` per level (F2). | 30 (Economy) |
| `upgrade_worker_slot` | base 150, growth 1.50 | Adds **+1 worker slot** to the building (more simultaneous workers). | 10 (Economy) |
| `upgrade_storage` | base 300, growth 1.40 | Raises the **pending-pool cap** by `pendingCapPerLevel` (F4) — more collect headroom. | 12 (Economy) |

The purchase flow: client fires the `BuyUpgrade` intent (identifier only, never a price); Idle's server handler reads the current level `n` from `base`, asks Economy for the authoritative `cost(n)`, calls `Economy.spend(player, cost, "upgrade_factory"|"upgrade_worker_slot"|"upgrade_storage")`, and on success increments the level in `base` (one critical-event save). The benefit applies on the **next** tick (no retroactive recompute).

### 2.6 Pending pool & the Collect mechanic (storage upgrade decision)

> **STORAGE UPGRADE DECISION (LOCKED — closes Economy Open Question #6):**
> `upgrade_storage` raises the **PENDING-POOL CAP** (how many uncollected coins can accumulate before production stops) — **not** the offline 8h window. The **offline 8h cap stays fixed** at launch (`offlineCapSeconds`, owned by Persistence) and is expanded only by a **separate, future monetization item ("Offline Storage +Xh")**, kept out of the MVP storage track.
>
> **Rationale:**
> 1. **Gives Collect meaning.** With a finite pending cap, "I should log in and collect before it fills" is a real reason to return — the storage upgrade directly buys "I can stay away longer / collect less often." That is the satisfying idle headroom mechanic the locked context asks for.
> 2. **Clean separation of two monetization surfaces.** The pending cap (engagement: collect cadence) and the offline window (convenience: AFK duration) are different value propositions. Bundling them makes both muddy. The 8h window stays a clean, single, separately-sellable lever; the storage upgrade stays a clean coin sink.
> 3. **Inflation-safe.** The pending cap is a *ceiling on uncollected coins*, not a rate — it does not multiply income, so it cannot break the geometric treadmill (Economy §8.9). It just lets a bigger pile sit.

**Pending-pool cap behavior:** the pending pool (online + offline) holds at most `pendingPoolCap(storageLevel)` coins (F4). When the pool **reaches the cap, production stops accruing** (overflow is **discarded**, not banked) until the player collects. This is surfaced clearly: a "Storage full! Collect to keep earning" indicator (§6). Discard-on-full (rather than overflow-banking) is deliberate — it is the gentle pressure that makes Collect a habit and storage upgrades desirable, and it is kid-clear ("your barrel is full").

**Collect flow:**
1. Client taps Collect → fires `CollectRequest` (no amount; rate-limited).
2. Server (Idle) reads `base.pendingOnline + pendingOffline.coins`, calls `Economy.award(player, total, "idle_collect")` (Economy bumps `coins` + `totalCoinsEarned`), and **in the same atomic op** zeroes both pending slices and bumps each contributing Brainrot's `history.coins` (for Evolution milestones, §2.9).
3. Idle emits `CoinsCollected` (Daily Quests / Moment listen).
4. A second collect on an empty pool credits 0 (idempotent by design — the zeroing makes a re-fire a no-op, matching Economy E5 / persistence §2.4).

### 2.7 Adjacency model (LOCKED — closes Personality's open "adjacency" concept)

> **ADJACENCY DECISION (LOCKED — defines what Personality v1.1 left open):**
> "**Adjacent**" = **all worker slots within the SAME building**, gated by a configurable radius. MVP default `moraleRadiusSlots = 999` ⇒ effectively "**whole building**". This is the simplest model for a 10–17 audience and a solo dev: there is no 2D grid, no neighbor-geometry, no positioning puzzle — *which building a Brainrot is deployed in* is the only spatial fact. Personality's `moraleAura.radiusSlots` (default 1 in PersonalityConfig) is honored if a designer lowers Idle's `moraleRadiusSlots` later, but the **building is the adjacency unit**.

Two building-scoped relations follow from this:

1. **Morale aura (Lazy).** A Lazy worker buffs **non-Lazy** workers in the same building within `moraleRadiusSlots` slots (`moraleAura.neighborMultiplier` from PersonalityConfig, default +15%). With the default whole-building radius, one Lazy buffs every non-Lazy worker in its building. Aura does **not** stack per recipient by default (a recipient gets the buff once if ≥1 eligible Lazy neighbor exists — `moraleAuraStacks = false`); it never affects other Lazy workers (`moraleAuraAffectsLazy = false`, personality E1).
2. **Overwork / Walkout (Rebel).** "Overworked" = `rebelCountInBuilding >= overworkRebelCount` (PersonalityConfig default 3 Rebels in one building). Contagion only drags **co-located (same-building)** workers (personality F3 / E2). `overworkThresholdPerBuilding` is the Idle-side config alias that maps to PersonalityConfig's `overworkRebelCount` (single source of truth: PersonalityConfig; Idle reads it).

Both relations are evaluated **per building**, so the building is the unit of all spatial personality interaction. This is the config-driven, kid-simple choice the locked context requested.

### 2.8 Offline personality model (no live state machine offline)

While the player is offline there is no server tick running their personalities, so breaks/walkouts/chaotic-flips cannot fire live. Offline production therefore uses an **expected-value (averaged) multiplier per Brainrot** so the result is fair, deterministic, and exploit-proof:

```
offlinePersonalityFactor(b) = expected steady-state multiplier for b's personality
  Hyper   : productionMultiplier * (1 - breakChance * breakDurationSeconds / cycleSeconds)   -- avg downtime
  Lazy    : productionMultiplier   (+ morale handled at the recipient, see below)
  Chaotic : productionMultiplier * (doubleChance * doubleMultiplier + (1-doubleChance) * zeroMultiplier)  -- = 1.0 at defaults (0.5*2 + 0.5*0)
  Loyal   : productionMultiplier
  Rebel   : productionMultiplier * (1 - expectedWalkoutFraction)   -- expectedWalkoutFraction from config, default small
```

- All inputs are **read from PersonalityConfig** (no Idle magic numbers).
- Morale aura is applied offline too (building composition is known from the deployment map), at the recipient.
- This makes offline income the **honest long-run average** of online income — no jackpot Chaotic runs while AFK, no unlucky all-break streaks. It is computed once on load (persistence `F-OFFLINE`) and is fully deterministic given roster + base + elapsed.

### 2.9 Per-Brainrot lifetime production (Evolution hook)

On Collect, the coins each deployed Brainrot contributed since the last collect are added to that Brainrot's `history.coins` (persistence-owned counter). This is the milestone source Work-Based Evolution (#8) reads (e.g. Hyper → Senior Hyper at lifetime production X). Idle attributes pending coins to producers proportionally to their contribution share over the accrual window (tracked per-Brainrot in the online sub-accumulator; offline attribution is proportional to each deployed worker's offline rate). `history.coins` is monotonic and never decremented.

### 2.10 State diagram — production lifecycle (per base, per session)

```
   ProfileLoaded (Persistence)
        │  pendingOffline.coins computed via F-OFFLINE (8h clamp)
        ▼
  ┌───────────────────────────────┐
  │  HAS UNCOLLECTED PENDING?      │── no ──┐
  └───────────────┬───────────────┘        │
        yes        │                        │
        ▼          │                        ▼
  show "While you  │              ┌────────────────────────┐
  were gone…"      └────────────► │      PRODUCING         │◄────────────┐
  (OfflineRewardReady)            │  (online tick loop,    │             │
        │                         │   delta-time accrual    │   collect / │
        ▼                         │   into pending pool)    │   pending   │
  ┌──────────────┐                └───────┬───────┬────────┘   < cap      │
  │ Collect tap  │───────────────────────►│       │                       │
  │ CollectRequest│   Economy.award         │       │ pending == cap        │
  └──────────────┘   ("idle_collect")       │       ▼                       │
        │            zero pending           │  ┌──────────────────┐         │
        │            history.coins += share │  │  STORAGE FULL    │─────────┘
        ▼            emit CoinsCollected     │  │ (accrual paused; │  collect drains
   wallet +N        ─────────────────────────┘  │  "Collect!" UI)  │  → resume
                                                 └──────────────────┘

   Per deployed Brainrot, the Personality state machine runs INSIDE "PRODUCING":
        Working ──break roll──► OnBreak ──timer──► Working      (Hyper; produces 0 while OnBreak)
        Working ──overwork────► Walkout ──timer──► Working      (Rebel; drags co-located; produces 0)
   (states/transitions owned by Personality #2; Idle drives the tick & respects `paused`)
```

---

## 3. Data Schema

Idle Production **defines a new persisted block `base` (BaseData)** and reuses persistence-owned idle fields. Persistence #1 OWNS the container and the atomic write path; Idle specifies the shape.

> **✅ SCHEMA-UPDATE FLAG — RESOLVED (persistence-gdd.md v1.2):**
> The `base: BaseData` block + `pendingOnline` defined below have been added to `PlayerData` in **persistence-gdd v1.2**, seeded in `Schema.default()` via `Schema.defaultBase()`. Because the project is **pre-launch (no live data)**, they were added to the **v1 baseline** rather than a v1→v2 `migrate()` step (`CURRENT_SCHEMA_VERSION` stays 1). Field names/shapes are identical between the two GDDs. The `migrate()` ladder remains reserved for genuine post-launch schema changes.

### 3.1 `BaseData` (defined here; added to `PlayerData` v1 baseline by Persistence #1 v1.2)

```lua
-- In ServerStorage/PlayerData/Schema.lua PlayerData (added to the v1 baseline by Persistence #1 v1.2).
-- Idle Production (#3) owns this shape; Persistence owns the storage + atomic writes.
-- Schema version: part of the v1 baseline (pre-launch addition; CURRENT_SCHEMA_VERSION stays 1).

-- One factory building the player owns.
export type Building = {
    -- Stable building id (string key in the `buildings` map). MVP: "b1" is the starting building.
    id: string,                         -- default "b1" for the starting building

    -- UPGRADE LEVELS (0-based; n=0 means "first upgrade purchased" per Economy §8.4).
    -- Each maps 1:1 to an Economy cost track; Idle reads the level, Economy computes cost(n).
    factoryLevel: number,               -- default 0.  upgrade_factory level.  Range 0..30 (Economy maxLevel)
    workerSlotLevel: number,            -- default 0.  upgrade_worker_slot level. Range 0..10
    storageLevel: number,               -- default 0.  upgrade_storage level.   Range 0..12

    -- DEPLOYMENT MAP: worker-slot index (1..currentSlotCount) -> BrainrotEntry.id (GUID) | nil.
    -- Sparse map; an absent/nil slot is empty. A Brainrot id appears in AT MOST one slot across
    -- ALL buildings (invariant enforced on deploy). currentSlotCount = startingWorkerSlots + workerSlotLevel.
    deployment: { [string]: string? },  -- default {}.  key = tostring(slotIndex); value = id or nil

    -- WALKOUT COOLDOWN: server os.time() until which this building may not re-trigger a Walkout
    -- (Personality walkoutCooldownSeconds, E2). 0 = no cooldown active.
    walkoutCooldownUntil: number,       -- default 0
}

-- The whole base.
export type BaseData = {
    -- Map of buildings keyed by building id. MVP seeds exactly one ("b1").
    buildings: { [string]: Building },  -- default { b1 = <defaultBuilding> }

    -- ONLINE pending sub-accumulator (mirrors persistence pendingOffline, but for online accrual).
    -- Persists so a crash before Collect never loses online-earned coins. Collected together with
    -- pendingOffline.coins in ONE atomic award (§2.6). Capped by pendingPoolCap (F4).
    pendingOnline: number,              -- default 0.   >= 0, <= pendingPoolCap

    -- Cached count of currently-deployed Brainrots across all buildings (O(1) UI / cap checks).
    -- Invariant: == total non-nil entries across every building's deployment map.
    deployedCount: number,              -- default 0
}
```

```lua
-- Idle supplies these defaults; Persistence calls them from Schema.default()/migrate().
function Schema.defaultBuilding(id: string): Building
    return {
        id = id,
        factoryLevel = 0, workerSlotLevel = 0, storageLevel = 0,
        deployment = {},
        walkoutCooldownUntil = 0,
    }
end

function Schema.defaultBase(): BaseData
    return {
        buildings = { b1 = Schema.defaultBuilding("b1") },
        pendingOnline = 0,
        deployedCount = 0,
    }
end
```

### 3.2 Reused persistence-owned fields

| Field (owner) | Type | Default | Idle's use | Persisted? |
|---|---|---|---|---|
| `lastSeen` (Persistence) | number | `os.time()` | Offline elapsed = `clamp(now - lastSeen, 0, 8h)` (F3-OFF). Server clock only. | Yes |
| `pendingOffline.coins` (Persistence) | number | 0 | Offline accrual destination; summed with `base.pendingOnline` on Collect. | Yes |
| `pendingOffline.from`/`.to` (Persistence) | number | 0 | "While you were gone…" window display. | Yes |
| `roster[id]` (Persistence) | `BrainrotEntry` | — | Read to know which Brainrots exist + their `personality`/`level`. | Yes |
| `roster[id].personality` (Personality) | enum | rolled | Read by `PersonalityService.getProductionModifier`. | Yes |
| `roster[id].history.coins` (Persistence) | number | 0 | Incremented on Collect with each producer's share (Evolution hook, §2.9). | Yes |
| `coins` / `stats.totalCoinsEarned` (Economy) | number | 0 | Mutated only via `Economy.award` on Collect. | Yes |

### 3.3 Ephemeral, NOT persisted (server memory only)

| State | Why ephemeral |
|---|---|
| Online accrual delta accumulator (fractional coins since last whole-coin commit; per-Brainrot contribution shares this session) | Sub-second bookkeeping; flushed to `base.pendingOnline` as whole integers each tick. |
| Personality runtime state machine (`Working`/`OnBreak`/`Walkout`, timers) | Owned & declared ephemeral by Personality #2 §3.2 (re-init to `Working` on load). |
| Last-tick timestamp / Heartbeat accumulator | Server clock bookkeeping for delta-time. |

---

## 4. Client-Server Split

| Concern | Server (authoritative) | Client (presentation only) |
|---|---|---|
| Production rate computation | **YES** — sums deployed rates, applies personality + factory mult, delta-time. | Never. Client renders a **predicted** ticking number. |
| Pending pool value | **YES** — server owns `base.pendingOnline` + `pendingOffline.coins`. | Read-only mirror; client predicts between syncs and reconciles on each `PendingUpdate`/Collect. |
| Offline accrual | **YES** — Persistence on load via `computeOfflineRate` (server `os.time()`). | Receives the computed amount for the recap screen. |
| Personality state machine + rolls | **YES** — server RNG, server clock, server building occupancy (Personality #2). | Receives state changes for visuals (zzz, protest sign). |
| Deploy / undeploy | **YES** — validates ownership, slot capacity, not-in-battle, single-slot invariant. | Sends intent; sees result. |
| Buy upgrade | **YES** — reads level from `base`, asks Economy for authoritative cost, spends atomically. | Sends identifier-only intent; may display a replicated price as a hint. |
| Collect | **YES** — atomic award + pending-zero + history.coins bump. | Sends intent (no amount); plays the collect burst on confirmation. |
| Pending-pool cap / storage full | **YES** — server enforces accrual stop at cap. | Shows "Storage full! Collect!" from replicated flag. |

**Authority rule (locked, per `server-scripts.md`):** the client **never** sends a coin amount, a rate, an offline duration, or a pending value. It sends only intents (`Collect`, `Deploy id→slot`, `Undeploy id`, `BuyUpgrade track`). The ticking number on screen is a **client-side prediction** (last server pending + client-estimated rate × local time) shown for feel; it is **authoritatively reconciled** to the server value on every `PendingUpdate` and on Collect. A tampered client that shows a huge predicted number collects only the server-computed amount.

### 4.1 Client prediction & reconciliation (the "ticking number")

```
On PendingUpdate { pending, ratePerSec, serverTime }:    -- server pushes periodically (§5.1)
    client.basePending = pending
    client.rate        = ratePerSec
    client.t0          = clientNow()
Each render frame (client):
    predicted = client.basePending + client.rate * (clientNow() - client.t0)
    predicted = min(predicted, client.pendingCap)         -- never tick past the cap visually
    display(predicted)
On Collect confirmation (BalanceChanged / DataDelta):
    reset prediction to server truth (pending now 0)
```

The client rate is replicated (read-only) so the prediction is close; drift is corrected at the next `PendingUpdate` (every `pendingSyncIntervalSec`, §8). The server is always the gate.

---

## 5. RemoteEvents / Functions

All remotes registered in `ReplicatedStorage/Shared/Remotes` and documented in the remotes manifest. **No Client→Server `RemoteFunction`** (server-hang risk, per project policy). Every handler validates args, is rate-limited, and trusts no client amount. (Refinable by `remotes-networking-specialist`.)

### 5.1 Server → Client

| Remote | Type | Payload | Purpose |
|---|---|---|---|
| `ProductionSync` | RemoteEvent | `{ ratePerSec: number, pendingCap: number, serverTime: number }` | Sent on deploy/undeploy/upgrade/personality-change (rate changed) so the client updates its prediction slope + cap. Low frequency (event-driven, not per-frame). |
| `PendingUpdate` | RemoteEvent | `{ pending: number, serverTime: number }` | Periodic reconciliation of the true pending value (every `pendingSyncIntervalSec`, default 5s) and immediately after Collect. Cheap (two numbers). |
| `OfflineRewardReady` | RemoteEvent (re-uses persistence §5.1) | `{ coins, from, to, cappedAt8h: boolean }` | Drives "While you were gone…" on load if pending offline > 0. Persistence fires; Idle supplies the amount. |
| `StorageFull` | RemoteEvent | `{ full: boolean }` | Toggles the "Storage full! Collect to keep earning" indicator when pending hits / leaves the cap. |
| `DeployResult` | RemoteEvent | `{ ok: boolean, id: string?, slot: string?, reason: string? }` | Ack for a deploy/undeploy intent (reasons: `not_owned`, `slot_taken`, `no_free_slot`, `in_battle`, `already_deployed`). |

> Personality state visuals (`OnBreak`/`Walkout`) arrive via Personality's own `PersonalityStateChanged` / `PersonalityMomentBurst` (personality §5.2) — Idle does not duplicate them.

### 5.2 Client → Server

| Remote | Type | Payload | Validation |
|---|---|---|---|
| `CollectRequest` | RemoteEvent | `{}` (no amount — server reads its own pending) | Rate-limit 1/sec. Server sums pending, awards via Economy, zeroes pending atomically. Empty pool → no-op (credits 0). |
| `DeployBrainrot` | RemoteEvent | `{ id: string, building: string, slot: number }` | Rate-limit ~5/sec. Validate: caller owns `id`; `id` not already deployed; not locked in battle/raid (E4); `building` exists; `slot` within `currentSlotCount` and empty. Reject with reason via `DeployResult`. |
| `UndeployBrainrot` | RemoteEvent | `{ id: string }` | Rate-limit ~5/sec. Validate caller owns `id` and it is deployed; clears its slot; `deployedCount--`. |
| `BuyUpgrade` | RemoteEvent | `{ building: string, track: "factory"\|"worker_slot"\|"storage" }` | Rate-limit ~3/sec. **Identifier only — never a price.** Server reads current level, gets authoritative `cost(n)` from Economy, `Economy.spend(...)`, on success increments level + critical save. Reject → Economy `SpendRejected` ("Meme Coins tidak cukup") or `max_level`. |

### 5.3 Internal server events (not network — cross-system decoupling per `gameplay-systems.md`)

Bindable/signal layer (`GameEvents`), fired by Idle, consumed by other server systems:

| Event | Payload | Fired When | Listened By |
|---|---|---|---|
| `CoinsCollected` | `{ player, amount, fromOffline: number, fromOnline: number, serverTime }` | After a successful Collect commits | Daily Quests #17 ("collect X coins" objective), Moment #12 (collect recap), Analytics |
| `PendingCapReached` | `{ player, building, cap }` | Pending pool first reaches the cap (production paused) | Moment #12 ("your storage is full!" nudge), Analytics |
| `OfflineRewardComputed` | `{ player, coins, elapsed, cappedAt8h }` | After `computeOfflineRate` runs on load | Moment #12 (recap reel context), Analytics |
| `BrainrotDeployed` / `BrainrotUndeployed` | `{ player, id, building, slot }` | On a successful (un)deploy | Moment #12, Analytics; Raid #6 may read deployment for defense |

> **Consumed (not emitted) by Idle** — from Personality #2: `WalkoutStarted` (zero those producers this cycle + future cycles until recovery), `PersonalityChanged` (invalidate the per-Brainrot modifier cache on next tick). Idle does NOT re-emit `PersonalityMoment`/`WalkoutStarted` — Personality owns those (§2.4).

---

## 6. Player-Facing UI

Rendered through the shared UI/HUD framework (#13); pure presentation (reads replicated state, fires intents). Mobile-first.

> **Spatial UI boundary (v1.3, post-demo reconciliation 2026-05-28):** The factory's worker slots are an **abstract `deployment` map** in this GDD (§3.1) — Idle owns rates, personality multipliers, accrual math, the abstract slot model, and the "Factory view" 2D HUD elements (ticking number, Collect button, storage gauge, upgrade panel — items 2–6 below). The **3D spatial rendering of the slots as physical pedestals/stands in the world, the `ProximityPrompt("Place")`/`Recall` interactions, and the deployed-model spawn/despawn** are owned by the **new system #26 Base / Showroom Spatial Layer** (`base-showroom-gdd.md` planned; reference impl in demo `e984677`). Idle and Showroom share the same `base.buildings[BUILDING_ID].deployment` data (no schema duplication); the boundary is *rendering* (Showroom) vs *math* (Idle). Items 1 + 7 below describe Idle's data contract to Showroom; the spatial UX details belong in the Showroom GDD.

1. **Factory view (data + 2D HUD; spatial rendering is #26)** — the player's building with its **worker slots** as data. Empty slots show a "+" (tap to deploy from roster); occupied slots show the deployed Brainrot with its personality badge (#2) and state icon (Working = none, OnBreak = "zzz/coffee", Walkout = tiny protest sign). The **3D pedestal-and-stand rendering** of this view is #26 Showroom's spatial layer; the **abstract data + Brainrot state icons + deploy/recall intents** described here are Idle's contract to that layer.
2. **Ticking production number** — a big, satisfying coins counter per building (and a base total) that **ticks up live** (client prediction, §4.1). A small "+X/sec" rate label so the player sees the effect of deploying better workers / upgrading.
3. **Collect button** — prominent, shows the current pending amount (e.g. "Collect 1.2K"). Tapping plays the coin-burst into the HUD wallet (Economy §6 item 2). Greyed/disabled at 0 pending.
4. **Storage gauge** — a bar showing pending vs `pendingPoolCap`. Fills as coins accrue; at full it turns amber with **"Storage full! Collect to keep earning"** (from `StorageFull`). Upgrading storage visibly raises the bar's max.
5. **Offline rewards screen ("While you were gone…")** — on load with offline pending > 0: a celebratory recap showing the time window (capped-at-8h note if it hit the cap), the coins earned, optionally a personality recap reel (Moment #12 enriches), and a big **Collect** button. (Owned jointly with Persistence §6 item 3 / Moment.)
6. **Upgrade panel** — three buttons (Factory / Worker Slot / Storage) each showing the next-level effect and its current cost (replicated price hint; server is the gate). Worker Slot shows "+1 slot"; Factory shows "+X% output"; Storage shows "+N pending cap".
7. **Deploy picker** — tapping an empty slot opens a roster list (owned by UI/HUD) filtered to undeployed, not-in-battle Brainrots; shows each one's personality + level so the player makes a strategic choice (Lazy for aura, avoid clumping Rebels).
8. **Indicators** — break/walkout/morale states over deployed Brainrots (Personality drives via `PersonalityStateChanged`); a small morale glow on workers receiving a Lazy aura.

All surfaces are event-driven + one predicted ticking number; **no per-frame networking**, safe on low-end mobile.

---

## 7. Edge Cases & Error States

Covers the `design-docs.md` checklist (zero/max/negative/rapid/lag/disconnect/datastore-down/concurrent). Minimum 5 exceeded.

### E1 — Zero deployed workers (empty factory)
**Trigger:** player owns Brainrots but has deployed none (or has 0 roster).
**Behavior:** base-wide rate = 0; pending pool does not grow; ticking number stays flat at the last pending. No divide-by-zero (rate is a sum, default 0). Offline accrual = 0 (`computeOfflineRate` over an empty deployment returns 0). UI nudges "Deploy a Brainrot to start earning!" (FTUE #14 leans on this). Collect on an empty pool credits 0 (no-op).

### E2 — Pending pool at the cap (storage full)
**Trigger:** accrual reaches `pendingPoolCap(storageLevel)` before the player collects.
**Behavior:** accrual **stops** (overflow discarded, not banked — §2.6); `StorageFull{full=true}` fires; `PendingCapReached` emits (Moment nudge). Production resumes the instant the player collects (pool → 0). This is the intended pressure that makes Collect a habit and storage upgrades valuable — not an error. The cap is a *ceiling*, never negative, never overflowing the number type (well under `maxBalance`).

### E3 — Offline > 8h (clamp) / clock skew / negative elapsed
**Trigger:** player offline 3 days, or `lastSeen` is in the future (region clock skew / tampered legacy value).
**Behavior:** `elapsed = clamp(now - lastSeen, 0, offlineCapSeconds)` (persistence `F-OFFLINE`, server clock). Past 8h, accrual simply stops at the 8h amount (recap shows "capped at 8h"). Negative elapsed clamps to **0** (never subtract coins, never grant >8h) and logs `clock_skew` (persistence E5). The client cannot supply time — server `os.time()` only.

### E4 — Deploy a Brainrot that is in an active battle/raid
**Trigger:** `DeployBrainrot` (or it is already deployed and a raid pulls it) for an `id` locked in a battle/raid session.
**Behavior:** deploy is **rejected** with `reason="in_battle"` (mirrors Personality E4's in-battle lock). A Brainrot **already deployed** that gets sent on a raid: per the locked single-slot model, the **raid system locks the `id`**; while locked, Idle treats that slot's worker as **paused (produces 0)** for the lock duration and shows an "away on a raid" state — it stays in its slot (so the player's layout is preserved) but contributes 0 until the raid resolves. It is never double-counted (can't both produce and fight). Coordinated with Raid #6 / Battle #5 lock contract.

### E5 — All deployed workers on Walkout (production 0)
**Trigger:** a Rebel overwork cascade puts every deployed worker in the building into `Walkout` (Personality E2 worst case).
**Behavior:** building rate = 0 while the walkout lasts (every worker `paused`); pending stops growing; this is a valid, intended "your whole factory walked out" Moment (Personality emits `WalkoutStarted`; Moment surfaces it). Bounded by Personality's `walkoutMaxDurationSeconds` + `walkoutCooldownSeconds` (stored as `base.<building>.walkoutCooldownUntil`); guaranteed to recover to `Working`. No infinite zero — durations are capped and config-driven.

### E6 — All-Lazy building (morale aura with no recipient)
**Trigger:** a building contains only Lazy workers.
**Behavior:** the aura is applied **at the recipient** and `moraleAuraAffectsLazy = false` (Personality E1), so no Lazy is buffed — total = sum of each Lazy's -50% rate, no morale bonus, no error (aura is additive, never a denominator). Surfaced as a weak "everyone's slacking" Moment. **Coordination with Personality E1 honored exactly** (aura computed by recipient, not emitter).

### E7 — Chaotic zero-cycle streak (bad luck online)
**Trigger:** a Chaotic worker rolls `zero` many cycles in a row online.
**Behavior:** that worker contributes 0 for those cycles (per F1 `chaoticCycleFactor`); other workers are unaffected (per-Brainrot factor). High variance is the intended Chaotic fantasy; each flip emits a `chaotic_zero`/`chaotic_double` Moment so a kid understands "it's the Chaotic guy," not a bug. **Offline is unaffected** — offline uses the *expected* Chaotic factor (= 1.0 at defaults, §2.8), so AFK income is never a streak of zeros.

### E8 — Collect during disconnect / network lag (idempotency)
**Trigger:** client fires `CollectRequest`, then lags or disconnects before the result returns; or fires it twice.
**Behavior:** Collect is server-authoritative and **idempotent by design** — the award + pending-zero are ONE atomic op (persistence §2.4); a re-fired Collect on an already-zeroed pool credits 0 (no double-award, matching Economy E5). If the player disconnects after the award commits, the coins are in the wallet (persisted); on rejoin they simply see the new balance. If the disconnect happened before commit, the pending pool is intact and persisted (it is part of `PlayerData`) — collectible on next login. No coins are ever lost or double-counted.

### E9 — Many players producing simultaneously (scale)
**Trigger:** a full server of players all producing + collecting.
**Behavior:** production is **per-player, per-server**, computed in one Heartbeat-driven loop that iterates live profiles (O(deployed workers), bounded by worker-slot caps). No shared global mutable state → no cross-player contention. Collects route through Persistence's atomic path (serialized per profile, persistence E9). Pending syncs are two-number events at `pendingSyncIntervalSec` (5s) — bandwidth scales linearly and modestly. No per-frame networking.

### E10 — Buy upgrade with insufficient coins / stale client price / at max level
**Trigger:** `BuyUpgrade` when balance < authoritative `cost(n)`, or the client's displayed price is stale/tampered, or the track is at `maxLevel`.
**Behavior:** server reads the **authoritative** current level + `cost(n)` from config (ignores any client price, Economy E7); `Economy.spend` rejects cleanly if unaffordable → `SpendRejected` toast (no level change, no coins taken). At `maxLevel` the purchase is rejected with `max_level` before any charge (charge-after-check, mirroring Economy E10). No half-applied upgrade.

### E11 — DataStore unavailable at Collect / upgrade commit
**Trigger:** the underlying `UpdateAsync` fails during a Collect or upgrade.
**Behavior:** the commit is `pcall`-wrapped by Persistence; on failure **nothing mutates** (pending not zeroed, coins not credited, level not raised) and the op returns false. Idle surfaces a gentle "Hiccup — try again!" toast; the pending pool is untouched and still collectible. No partial state (Economy E9 / persistence E3). The dirty-flag retry discipline re-attempts the save of committed state.

---

## 8. Balancing Parameters

> **This is the core of the GDD.** All values in `IdleConfig` (commented, ranged, versioned per `config-data.md`). **Zero magic numbers in code.** Values owned elsewhere (personality multipliers, Economy cost curves, offline cap) are **referenced**, never re-defined contradictorily.

> **Units:** all coin amounts are integers (`math.floor` before touching the wallet). Rates are coins/second. Level `n` is 0-based (first upgrade is n=0), matching Economy §8.4.

### 8.1 `IdleConfig` (the master table)

```lua
-- src/ReplicatedStorage/Shared/Config/IdleConfig.lua
-- (Rates/caps are SAFE to replicate read-only so the client can predict the ticking number;
--  the SERVER is always authoritative — client prediction is reconciled to server, §4.1.)
-- Edited by designers for balance. Schema version: 1
return {
    version = 1,

    -- ── CORE PRODUCTION RATE ──
    -- Coins PER SECOND produced by ONE deployed Brainrot at baseline (no personality/factory mod).
    -- This is THE number that replaces Economy's ~60/min placeholder (see §8.7 reconciliation).
    -- Range: 0.05-50 | Default: 0.5  (0.5/sec/worker × 2 starting workers = 1/sec = 60/min,
    --                                  EXACTLY matching Economy's placeholder early rate.)
    baseRatePerWorker = 0.5,

    -- Forward-compat: extra coins/sec per Brainrot LEVEL above 1. MVP = 0 (flat per worker) so
    -- launch tuning is simple; Battle/Evolution can turn this on later.
    -- Range: 0-5 | Default: 0
    levelRateBonus = 0,

    -- ── EVOLUTION PRODUCTION MULTIPLIER (read-only reference; NOT a copy) ──
    -- The per-evoStage production multiplier (`evoProductionMult` in F1 / F3-OFF) is OWNED BY
    -- Work-Based Evolution #8 — it lives in EvolutionConfig.stageMultipliers[stage].productionMultiplier
    -- (single source of truth: stage 0 = 1.0, stage 1 = 1.20; unknown stage → 1.0 via
    -- EvolutionConfig.unknownStageMultiplier). Idle does NOT store these numbers as a magic number here;
    -- it reads them at runtime via the deployed Brainrot's `evoStage` (the same roster field Battle #5 reads).
    -- DO NOT duplicate the 1.20 here — edit EvolutionConfig (#8) to retune.

    -- ── FACTORY (building) ──
    -- Buildings owned at profile creation. MVP = 1.
    -- Range: 1-10 | Default: 1
    startingBuildings = 1,
    -- Worker slots a building has BEFORE any worker-slot upgrade (workerSlotLevel = 0).
    -- Range: 1-20 | Default: 2  (so day-1 you can deploy 2 → 1 coin/sec → 60/min).
    startingWorkerSlots = 2,
    -- Production multiplier ADDED to a building per factory-upgrade level (F2).
    -- effectiveFactoryMult = 1 + factoryMultPerLevel * factoryLevel.
    -- Range: 0.05-1.0 | Default: 0.20  (each factory level = +20% building output;
    --   at maxLevel 30 → 1 + 0.20*30 = 7.0× — see §8.7 treadmill reconciliation).
    factoryMultPerLevel = 0.20,

    -- ── PENDING POOL / STORAGE ──
    -- Base pending-pool cap (storageLevel = 0), in coins. Production STOPS at this ceiling (E2).
    -- Sized so a starting base (1 coin/sec) fills it in ~minutes-to-an-hour, making Collect a habit.
    -- Range: 100-1e9 | Default: 3600  (= 1 hour of starting output at 1 coin/sec).
    pendingPoolCapBase = 3600,
    -- Pending-cap ADDED per storage-upgrade level (F4). Linear add (simple & predictable for kids).
    -- Range: 100-1e9 | Default: 5400  (each storage level = +1.5h of starting output).
    pendingCapPerLevel = 5400,
    -- Offline accrual cap in SECONDS. OWNED BY Persistence (PersistenceConfig.offlineCapSeconds).
    -- Mirrored here READ-ONLY for the offline-rate math; DO NOT edit here (edit PersistenceConfig).
    -- Default 28800 (= 8h, locked context). The storage upgrade does NOT change this (§2.6).
    offlineCapSeconds_REFERENCE = 28800,

    -- ── ADJACENCY (closes Personality's open concept, §2.7) ──
    -- Radius (in worker slots within the SAME building) for the Lazy morale aura. 999 = whole building.
    -- Honors PersonalityConfig.moraleAura.radiusSlots if a designer wants tighter geometry.
    -- Range: 1-999 | Default: 999  (whole-building = simplest model for kids & solo dev).
    moraleRadiusSlots = 999,
    -- Whether multiple Lazy auras STACK on one recipient. Default false (one buff if >=1 Lazy neighbor).
    moraleAuraStacks = false,
    -- Overwork threshold ALIAS — reads PersonalityConfig.traits.Rebel.overworkRebelCount (single
    -- source of truth = PersonalityConfig). Listed here for the design model only; NOT a second copy.
    overworkThresholdPerBuilding_REFERENCE = 3,

    -- ── OFFLINE PERSONALITY AVERAGING (§2.8) ──
    -- Assumed online cycle length (seconds) used to average Hyper break downtime offline.
    -- Range: 5-300 | Default: 60  (one "cycle" ≈ 1 min of work for averaging purposes).
    cycleSeconds = 60,
    -- Expected fraction of offline time a co-located overworked Rebel spends on Walkout (avg).
    -- Small, since walkouts are bounded + cooldowned. Range: 0.0-0.5 | Default: 0.05.
    expectedWalkoutFraction = 0.05,
    -- 2x Offline Earnings GamePass multiplier on the OFFLINE rate (within the 8h cap, NOT the window).
    -- Applied inside computeOfflineRate for owners (Monetization #15). Range: 1.0-3.0 | Default: 2.0.
    offlineGamePassMultiplier = 2.0,

    -- ── TICK / SYNC ──
    -- Server production-tick interval (seconds). Accrual uses ACTUAL delta-time, not this nominal
    -- value (delta-time rule); this is just how often the loop wakes. Range: 0.25-5 | Default: 1.
    serverTickSec = 1,
    -- How often the server pushes a PendingUpdate reconciliation to the client. Range: 1-30 | Default: 5.
    pendingSyncIntervalSec = 5,

    -- ── RATE LIMITS (per server-scripts.md; also enforced server-side) ──
    rateLimits = {
        collect = 1,        -- CollectRequest: max 1/sec
        deploy = 5,         -- Deploy/Undeploy: max 5/sec
        buyUpgrade = 3,     -- BuyUpgrade: max 3/sec
    },
}
```

### 8.2 Formulas (explicit, named variables)

**F1 — Effective per-worker rate (online).** Delegates personality math to Personality F1.
```
effectiveRate(b) = ( baseRatePerWorker + levelRateBonus * (b.level - 1) )
                 * personalityMult(b)        -- traits[b.personality].productionMultiplier (#2)
                 * chaoticCycleFactor(b)      -- per-cycle x2/x0 for Chaotic, else 1.0 (#2)
                 * moraleFactor(b)            -- neighborMultiplier if a Lazy is in-building & b non-Lazy (#2)
                 * evoProductionMult(b)       -- evolution per-stage production multiplier (#8); see below
                 * (paused(b) ? 0 : 1)        -- 0 if OnBreak / Walkout / away-on-raid (#2 + E4)
  baseRatePerWorker, levelRateBonus : IdleConfig
  personalityMult/chaoticCycleFactor/moraleFactor/paused : read from PersonalityService (NOT hardcoded)
  evoProductionMult(b) = EvolutionConfig.stageMultipliers[b.evoStage].productionMultiplier
                         ?? EvolutionConfig.unknownStageMultiplier   -- = 1.0 fallback for an unknown stage
                       -- VALUES OWNED BY Evolution #8 (single source of truth): stage 0 = 1.0, stage 1 = 1.20.
                       -- Idle never stores these numbers; it reads them via b.evoStage (the roster field).
  Bounds: effectiveRate >= 0 always.  (evoProductionMult >= 1.0 by config; stage 0 leaves the rate unchanged.)
```

**F2 — Building rate (online).**
```
buildingMult(B)   = 1 + factoryMultPerLevel * B.factoryLevel      -- IdleConfig; default +20%/level
buildingRate(B)   = buildingMult(B) * Σ effectiveRate(b) for each Brainrot b deployed in B
baseRate(player)  = Σ buildingRate(B) for each building B
  Bounds: at MVP one building, factoryLevel<=30 → buildingMult <= 1 + 0.20*30 = 7.0.
```

**F3-ON — Online accrual (delta-time).** Runs each server tick.
```
dt              = serverNow() - lastTickTime          -- ACTUAL elapsed seconds (delta-time rule)
accrued         = baseRate(player) * dt               -- fractional; accumulated, floored to integers on flush
newPending      = min( base.pendingOnline + accrued, pendingPoolCap(player) )    -- clamp at cap (E2)
overflowDiscarded = (base.pendingOnline + accrued) - newPending                  -- discarded (>0 only at cap)
base.pendingOnline = floor(newPending)
lastTickTime    = serverNow()
  if base.pendingOnline >= pendingPoolCap(player): fire StorageFull/PendingCapReached, accrual paused.
```

**F3-OFF — Offline accrual (on load; supplied to Persistence F-OFFLINE).**
```
offlineCoins = computeOfflineRate(roster, base) * clamp(now - lastSeen, 0, offlineCapSeconds)

computeOfflineRate(roster, base) =
    Σ over each deployed Brainrot b:
        buildingMult(B(b))
      * ( baseRatePerWorker + levelRateBonus*(b.level-1) )
      * offlinePersonalityFactor(b)          -- §2.8 expected-value factor (NO live state machine)
      * offlineMoraleFactor(b)               -- recipient-applied, building composition known
      * evoProductionMult(b)                 -- SAME evolution per-stage factor as online F1 (#8); reads b.evoStage
                                              --   = EvolutionConfig.stageMultipliers[b.evoStage].productionMultiplier
                                              --     ?? unknownStageMultiplier (=1.0). VALUES OWNED by Evolution #8.
      * (owns2xOfflineGamePass ? offlineGamePassMultiplier : 1)
  then clamp the RESULT add into pendingOffline.coins so (pendingOnline + pendingOffline) <= pendingPoolCap.
  Server os.time() only; deterministic; never trusts client time. (Persistence owns the clamp + write.)
```

**F4 — Pending-pool cap (storage upgrade effect).**
```
pendingPoolCap(player) = pendingPoolCapBase + pendingCapPerLevel * storageLevel(player)
  storageLevel : the upgrade_storage level in base (Economy owns the COST; Idle owns this EFFECT).
  Default L0 = 3600 ; L1 = 9000 ; L5 = 30600 ; L12 (max) = 68400 coins of headroom.
```

**F5 — Collect.**
```
total = base.pendingOnline + pendingOffline.coins
Economy.award(player, floor(total), "idle_collect")     -- bumps coins + totalCoinsEarned (#9)
for each deployed Brainrot b: b.history.coins += floor( total * contributionShare(b) )   -- §2.9, Evolution hook
base.pendingOnline = 0 ; pendingOffline.coins = 0        -- same atomic op (persistence §2.4)
emit CoinsCollected{ amount=total, fromOffline, fromOnline }
  contributionShare(b) = b's accrued share of `total` over the window (sums to 1 across deployed).
```

### 8.3 Pacing reconciliation — RATE vs Economy COST CURVES (the core deliverable)

Goal: confirm the geometric treadmill (Economy §8.9) works — that income grows roughly in step with the next upgrade's cost so a progressing player reinvests most of what they earn, and that early goals hit Economy's target bands (Early 5–15 min, Session 30–60 min).

**Starting state:** 2 worker slots, base rate 0.5/sec each → **1.0 coin/sec = 60 coins/min** (≡ Economy's placeholder, now the *real* number).

Income at a milestone = `buildingMult × deployedWorkers × baseRatePerWorker × personalityAvg`. For pacing we use `personalityAvg = 1.0` (mixed roster averages near steady; Chaotic EV = 1.0, Hyper +30%/Lazy −50% roughly offset with morale aura).

| Milestone (cumulative state) | Deployed | factoryLevel | buildingMult | Income (coins/min) | Next upgrade & its cost (Economy) | Time to afford next (mins) | Band |
|---|---|---|---|---|---|---|---|
| Start | 2 | 0 | 1.0 | 60 | factory n=0 = **200** | ~3.3 | Early (5–15) |
| After factory n=0 | 2 | 1 | 1.2 | 72 | worker slot n=0 = **150** | ~2.1 | Early |
| +1 worker slot (n=0) | 3 | 1 | 1.2 | 108 | factory n=1 = **270** | ~2.5 | Early |
| factory n=1 | 3 | 2 | 1.4 | 126 | factory n=2 = **364** | ~2.9 | Session |
| factory n=2 | 3 | 3 | 1.6 | 144 | worker slot n=1 = **225** | ~1.6 | Session |
| +1 worker slot (n=1) | 4 | 3 | 1.6 | 192 | factory n=3 = **492** | ~2.6 | Session |
| factory n=5, 5 workers | 5 | 6 | 2.2 | 330 | factory n=6 = floor(200·1.35⁶)=**1,210** | ~3.7 | Session |
| factory n=10, 7 workers | 7 | 11 | 3.2 | 672 | factory n=11 ≈ **5,426** | ~8.1 | Multi-session |
| factory n=20, 10 workers (worker max) | 10 | 21 | 5.2 | 1,560 | factory n=21 ≈ floor(200·1.35²¹)≈**109K** | ~70 | Multi-session |
| factory n=29 (max), 10 workers | 10 | 30 | 7.0 | 2,100 | (factory maxed) → storage / slot_unlock sinks | — | Long-term |

**Reading the table:**
- **Early band (first session):** every upgrade is affordable in **~2–4 minutes** of idle — the first factory and worker-slot upgrades land inside Economy's 5–15 min early goal, giving visible progress every few minutes (FTUE-friendly).
- **Treadmill holds:** through the mid-game, "time to afford the next upgrade" stays in a tight **~2–4 minute** band even as both income and cost climb — because both grow geometrically, the player keeps reinvesting (Economy §8.9 confirmed). The factory growth (1.35) bites a little harder than income grows late (n=20+), which is the intended *soft wall* that pushes players toward more workers, raids, and quests rather than pure idle — and that gap is where the late-game sinks (slot_unlock cumulative ~640K, storage) absorb balances (Economy §8.6).
- **No unpassable wall:** even the steepest late factory level (n=21 ≈ 109K) is ~70 min of idle at that stage's income — a multi-session goal, never a dead stop, and supplemented by raid loot + daily quests.

> **Replaces Economy's placeholder:** Economy §8.10's "~60 coins/min (placeholder, to be reconciled with Idle #3)" is now **final at 60 coins/min starting income** with the curve above. Economy's illustrative pacing table (§8.10) should be re-stamped against this when convenient (flag to economy-designer; no contradiction — the placeholder was explicitly provisional).

### 8.4 2x Offline GamePass interaction (confirmation, matches Economy §8.8)
Multiplies the **offline rate** inside `computeOfflineRate` (F3-OFF) by `offlineGamePassMultiplier` (2.0) — doubling coins accrued **within** the 8h cap, **not** extending the window. Pure faucet multiplier on the player's own pace; fully absorbed by the geometric upgrade treadmill; **not pay-to-win** (never touches raid combat power). Confirmed consistent with Economy E4/§8.8.

### 8.5 Balancing assumptions to validate via `/balance-check`
1. **`baseRatePerWorker = 0.5`** (→ 60/min start) is the linchpin; if FTUE testing shows the first upgrade feels slow, raise to 0.6–0.75 (Economy's curves are robust to this — it just shifts the whole table left).
2. **`factoryMultPerLevel = 0.20`** (+20%/level, 7× at max) vs Economy `factory growth 1.35`: validate the late-game soft wall (n=20+) is *motivating* not *frustrating*; lever is this value or Economy's `growth`.
3. **`pendingPoolCapBase = 3600` (1h start)**: validate it is long enough that a casual session isn't constantly hitting "full," but short enough that storage upgrades feel worth buying. Tune with `pendingCapPerLevel`.
4. **`startingWorkerSlots = 2`**: validate two workers is the right "deploy your first capture and see it work" FTUE beat.
5. **Offline personality averaging (§2.8)**: validate offline income ≈ online income over a long window (no systematic over/under-pay); especially the Chaotic EV (=1.0) and Hyper break-downtime average.
6. **`expectedWalkoutFraction = 0.05`**: validate against live walkout frequency once Personality is wired.

### 8.6 Storage upgrade benefit (closes Economy Open Q #6) — summary
`upgrade_storage` (Economy cost base 300 / growth 1.40, maxLevel 12) buys **+`pendingCapPerLevel` (5400) pending-pool cap per level** (F4). It does **not** touch the offline 8h window. The 8h window is a **separate future monetization item**. Economy owns the cost; **Idle owns this benefit** (now defined). Economy §3.2 / Open Q #6 can mark "storage = pending-pool cap; offline window separate" as resolved.

---

## 9. Integration Points

**Reads** = Idle reads state/config; **Writes** = Idle mutates via the owning system's API.

| System | Direction | Interaction |
|---|---|---|
| **#1 Data Persistence** | both | Reads `roster`, `lastSeen`, `pendingOffline`, and the **`base` (BaseData)** + `pendingOnline` (✅ added to the v1 baseline in persistence v1.4, §3 flag resolved in earlier v1.2). Supplies `IdleProduction.computeOfflineRate(roster, base)` for persistence `F-OFFLINE`. Writes go through Persistence's atomic path (Collect, deploy, upgrade-level bumps, `history.coins`). Never touches DataStore directly. |
| **#2 Personality** | both | Reads `PersonalityService.getProductionModifier` / morale aura; respects `paused` (OnBreak/Walkout). **DRIVES** the state-machine tick (Idle provides cadence + building occupancy; Personality performs transitions + emits events — §2.4). Listens to `WalkoutStarted` (zero those producers) and `PersonalityChanged` (invalidate cache). Defines the **adjacency = building** model PersonalityConfig left open (§2.7). |
| **#9 Economy** | both | PRIMARY faucet: on Collect, `Economy.award(player, total, "idle_collect")` (Economy bumps `coins` + `totalCoinsEarned`). SINKS: upgrade purchases via `Economy.spend(..., "upgrade_factory"\|"upgrade_worker_slot"\|"upgrade_storage")` using Economy's `cost(n)` curves. **Sets the real production rate** (replaces Economy's ~60/min placeholder, §8.3) and **resolves storage-upgrade semantics** (§8.6, Economy Open Q #6). Economy owns wallet + curves; Idle owns rate + factory model. |
| **#4 Capture / Roster** | reads | Captured Brainrots become deployable (roster, cap 200, owned by Persistence). Idle reads which Brainrots exist to populate the deploy picker; deployment ≠ ownership (§2.1). |
| **#6 Raid** | both | Raid loot = **% of the target's uncollected pending** (Economy §8.3 `targetPool` = uncollected idle, mirroring `idea/brainrotInc.md`). Idle exposes the pending pool as the lootable pool; a deployed Brainrot sent on a raid is **locked → paused (produces 0), stays in slot** (E4). Coordinated lock contract with Battle #5 / Raid #6. |
| **#8 Work-Based Evolution** | both | **Writes (counter):** on Collect, bumps each producer's `history.coins` proportionally (§2.9, F5) — Evolution reads it for the production milestone (e.g. Hyper → Senior Hyper at lifetime production X). Monotonic, never decremented. **Reads (multiplier):** Idle multiplies `effectiveRate` (and `computeOfflineRate`) by Evolution's **`productionMultiplier` per `evoStage`** — `evoProductionMult(b) = EvolutionConfig.stageMultipliers[b.evoStage].productionMultiplier` (stage 0 = 1.0, stage 1 = 1.20; unknown → 1.0). VALUES OWNED by Evolution #8 (single source of truth); Idle owns only the mechanic (how the factor enters the rate). **FLAG-IDLE resolved.** |
| **#12 Moment System** | emits | Idle emits `CoinsCollected`, `PendingCapReached`, `OfflineRewardComputed`, `BrainrotDeployed/Undeployed`; surfaces Personality's `PersonalityMoment`/`WalkoutStarted` (which Idle consumes for production, Personality emits for display). Moment owns the "while you were gone…" recap presentation; Idle supplies the offline data. |
| **#17 Daily Quests** | emits | `CoinsCollected{ amount }` feeds the "kumpulkan X coins" objective; `BrainrotDeployed` / capture/raid events feed others. Quest reward paid via Economy `quest_daily` (Economy owns reward range; Idle just emits progress events). Event-driven, not polling. |
| **#13 UI/HUD** | both | Drives the factory view, ticking number (client prediction §4.1), Collect button, storage gauge, upgrade panel, deploy picker, offline screen. Sends identifier-only intents; reads replicated state. |
| **#14 Onboarding/FTUE** | reads | The guided "deploy your first Brainrot → watch it work → first Collect" beats live here (systems-index #14). Idle's empty-factory nudge (E1) and first-Collect burst are FTUE anchors. |
| **#15 Monetization** | reads | 2x Offline Earnings GamePass → `offlineGamePassMultiplier` inside `computeOfflineRate` (§8.4); Extra Roster Slots GamePass raises roster cap (Persistence) feeding deployable pool; future "Offline Storage +Xh" extends the 8h window (separate from storage upgrade, §2.6). Zero pay-to-win (rate/pace only, never raid power). |
| **#26 Base / Showroom Spatial Layer** | **NEW v1.3.** Showroom ↔ Idle (shared state) | **Pure UX wrapper** over Idle's abstract `deployment` model. Showroom reads `base.buildings[BUILDING_ID].deployment` to render pedestals/stands in the world; Showroom writes the same map via the same Persistence atomic path Idle uses (for `Place`/`Recall` ProximityPrompt actions). Idle is **rate + math + state-machine cadence**; Showroom is **3D spatial rendering + ProximityPrompt UX + model spawn/despawn**. No new persistence fields. Cross-system invariant (a Brainrot id in at most one slot across all buildings) is honored by both — both write through `update()` so the atomic path serializes any race. Decision deferred to base-showroom-gdd: pedestal-tier visuals for `factoryLevel`/`storageLevel`, mobile reachability of ProximityPrompts. |

### Resolution notes (no contradictions)
- **Rate ownership:** Economy v1.1 explicitly deferred rates to this GDD and flagged its 60/min as a placeholder; this GDD sets 60/min as the *real* starting income and reconciles the full curve (§8.3). No contradiction — the deferral is honored.
- **Storage semantics:** Economy Open Q #6 asked Idle to define the storage benefit; this GDD defines it as **pending-pool cap** (§2.6/§8.6). No contradiction — Economy owns the cost, Idle owns the benefit, as Economy requested.
- **State-machine ownership:** Personality owns the *definition*; Idle owns the *cadence* (§2.4). Matches personality-gdd §2.5 (Personality "maintains a tiny state machine") and the consumer note that "Idle Production … respects `paused`."
- **`base` field:** RESOLVED — persistence-gdd **v1.2** added `base` (BaseData) + `pendingOnline` to the v1 baseline (pre-launch, no migration needed), with identical field names/shapes to this GDD's §3. No contradiction.
- **Offline determinism / anti-exploit:** server clock only, 8h clamp, averaged offline personality — consistent with persistence E5 and the locked anti-exploit context.

---

## Acceptance Criteria (system is "done")

- [ ] Production is server-authoritative; client shows a predicted ticking number reconciled to server on every `PendingUpdate` and Collect; a tampered client collects only the server-computed amount.
- [ ] Factory model implemented as building → worker slots → deployment map; deployment (who works) is distinct from roster (ownership); single-slot invariant enforced on deploy.
- [ ] `baseRatePerWorker` and all rates/caps read from `IdleConfig`; no hardcoded production numbers; no hardcoded personality numbers (all via `PersonalityService`).
- [ ] Online accrual uses **delta-time**; offline accrual uses server `os.time()` clamped `[0, 8h]`; negative elapsed → 0 (E3).
- [ ] Pending pool (online + offline) collects in ONE atomic `Economy.award("idle_collect")` + pending-zero + `history.coins` bump; idempotent under retry/disconnect (E8).
- [ ] Pending-pool cap enforced; accrual stops at cap (overflow discarded); `StorageFull`/`PendingCapReached` fire (E2); storage upgrade raises the cap (F4), NOT the offline window (§2.6).
- [ ] Personality state machine driven by Idle's tick: breaks/walkouts/chaotic flips fire online with Moments; `WalkoutStarted` zeroes producers; adjacency = building (§2.7); all-Lazy (E6) and all-Walkout (E5) handled per Personality E1/E2.
- [ ] Offline personality uses expected-value factors (§2.8); offline income ≈ long-run online income (no jackpots/zero-streaks offline).
- [ ] Upgrade purchases are identifier-only intents; server reads authoritative `cost(n)` from Economy; rejects insufficient/at-max cleanly (E10); no half-applied upgrade.
- [ ] Deploy of an in-battle/raid Brainrot rejected (`in_battle`); a deployed Brainrot sent on a raid is paused-in-slot (E4).
- [ ] `CoinsCollected` / `PendingCapReached` / `OfflineRewardComputed` / `BrainrotDeployed/Undeployed` events fire with the specified payloads and are observable by a test subscriber (Daily Quests / Moment).
- [ ] All player-triggered remotes rate-limited + validated; no Client→Server RemoteFunction; no remote lets a client name a coin amount/rate/time.
- [x] ✅ Persistence #1 has added the `base` (BaseData) + `pendingOnline` fields (persistence-gdd v1.2, v1 baseline) — reconciled before implementation.
- [ ] Pacing table (§8.3) re-validated via `/balance-check` against the assumptions in §8.5; early upgrades affordable in ~2–4 min; treadmill holds; no unpassable wall.
- [ ] Works on low-end mobile (event-driven sync + one predicted number; no per-frame networking).
```
