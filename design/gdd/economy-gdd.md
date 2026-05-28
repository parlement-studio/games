# Economy / Currency (Meme Coins) GDD

**Version**: 1.2
**Last Updated**: 2026-05-28
**Author**: economy-designer
**Status**: Draft

> **Changelog**
> - **v1.2 (2026-05-28):** Phase A reconciliation — added **`field_combat_win` faucet (system #25 Field Combat / Pet AI)** to §3.1 catalog, ASCII flow diagram (§2.2), F-FAUCET-FIELDCOMBAT formula (§8.3), `faucetReasons` config (§8.1), and §9 Integration Points. Demo (`a71e545`) already pays `winCoins = 25` per Pet AI win; this GDD now locks that as a config-driven faucet with Pet AI #25 supplying the per-win amount and idempotency key. **Open Question #6 (storage upgrade semantics) RESOLVED**: idle-production-gdd v1.2 §2.6 + storage-cap decision lock `upgrade_storage` to raise **pending-pool cap only** (not the 8h offline window — that stays `PersistenceConfig.offlineCapSeconds`, fixed at launch).
> - **v1.1 (2026-05-26):** Daily Quests added to MVP as systems-index **#17**. The `quest_daily` faucet now pays out **on quest completion** (not a login streak) and its reward is a **per-quest config pool/range** (no flat magic number) — see §3.1 and §8.2. Added Daily Quests (#17) to Integration Points (§9). Cross-references shifted by the Phase 2 renumber: Drama Events #22 → **#23**, Premium Currency / Brain Cells #20 → **#21**.
> - **v1.0 (2026-05-26):** Initial economy model.

> **Parent GDD**: `design/gdd/systems-index.md` — System #9 (Economy / Currency, **P1 currency backbone**).
> **Source of Truth**: `idea/brainrotInc.md` (creative direction); locked pre-production + monetization brainstorm decisions.
> **Governing standards (NON-NEGOTIABLE)**: `.claude/rules/design-docs.md` (9 sections, explicit formulas, ≥5 edge cases, version header), `.claude/rules/config-data.md` (commented config + ranges + version field), `.claude/rules/gameplay-systems.md` (zero magic numbers, event-driven, config-driven), `.claude/rules/server-scripts.md` (server-authoritative, never trust client, pcall, rate limit).
> **Depends On**: System #1 Data Persistence & Roster Core (`persistence-gdd.md` v1.4) — Persistence OWNS storage + the atomic mutation path; Economy is the **service layer** that mutates the wallet through it.
> **Depended On By**: Capture (#4, debit), Idle Production (#3, deposit), Raid (#6, cost + loot), Reroll (#11, cost), Upgrades/Shop, Auto-Catch (#10, optional unlock cost), Leaderboard (#16, net worth), Monetization (#15, DevProduct coin packs), Field Combat / Pet AI (#25, deposit — v1.2).

> **Cross-GDD consistency lock (no contradictions introduced — per `design-docs.md`):**
> - **Storage is owned by Persistence (#1).** Economy does NOT define a new `PlayerData` schema. It mutates the existing fields `coins` (Meme Coins), `gems` (Brain Cells, default 0, Phase 2), and `stats.totalCoinsEarned` (lifetime gross) that `persistence-gdd.md` v1.1 §3.2 already declares. All wallet mutations route through Persistence's atomic `UpdateAsync` path with `nextSeq` + `txLog` idempotency (persistence §2.3).
> - **Capture (#4) contract honored exactly.** Capture reads `Economy.getBalance(player)` and debits `CaptureConfig.captureCostCoins` (default 25) atomically with its roster write; the free-onboarding subsidy is owned by `CaptureConfig.freeCapturesOnboarding` (canonical). This GDD treats capture cost as an **externally-owned sink** and never redefines its value.
> - **Net-worth metric = `stats.totalCoinsEarned`** (lifetime gross, monotonic), NOT current balance — locked by persistence §2.6. Economy is the only system that increments it (on every credit) and it is NEVER decremented by a sink.
> - **One soft currency at launch: Meme Coins.** `gems` (premium "Brain Cells") is provisioned default 0 and **forward-compat only** — no earn/spend flow designed here (deferred to systems-index #21, Phase 2). Robux is the direct premium layer (DevProducts/GamePasses owned by Monetization #15), not an in-game currency.

---

## 1. Overview & Purpose

Economy is the **currency backbone**: the single service through which Meme Coins enter (faucets), leave (sinks), and are read by every gameplay system. It is **P1** because almost every interactive system in Brainrot Inc. either *earns* Meme Coins (Idle Production, Raid loot, quests) or *spends* them (Capture, Upgrades, Reroll, Raid send cost, slot unlocks, drama fixes). If the wallet API is wrong, every consumer inherits double-spend bugs, inflation, or pay-walls.

This system exists to:

1. **Provide one authoritative wallet API** — `getBalance`, `award`, `spend` — that all systems use, so currency mutation logic lives in ONE place and is uniformly atomic, validated, and idempotent (it does not re-implement DataStore; it composes Persistence's atomic path).
2. **Define the faucet/sink model and the high-level balance** that keeps the economy healthy across the playable lifetime — free players feel steady progress, paying players feel value, nobody hits an unpassable wall, and nobody becomes so rich that nothing matters.
3. **Own inflation control.** An idle game grows currency *exponentially* (production scales with roster size and upgrades). Without sinks that scale with player wealth, the late game hyper-inflates and every price becomes meaningless. Economy owns the sink curves that absorb that growth.
4. **Feed the Richest-Manager leaderboard** by being the single writer of `stats.totalCoinsEarned`.

### Why one currency is enough for launch

- **Cognitive load for a 10–17 audience.** One currency = one mental model ("Meme Coins do everything"). A second soft currency at launch would fragment every shop and confuse onboarding for no design payoff.
- **The premium layer is Robux directly.** Monetization sells convenience/cosmetics via GamePass/DevProduct (zero pay-to-win). We do not need an in-game premium currency to intermediate Robux at launch; a DevProduct that grants Meme Coins (the "Meme Coins Pack") covers the "buy progress shortcut" case without a second wallet.
- **Forward-compat is cheap.** The `gems` field already exists (default 0). When Brain Cells ship in Phase 2 (#21), it is additive — no migration of `coins`.
- **The economy is rich enough with one currency** because *depth comes from sink variety* (capture, upgrades, reroll curve, raid send cost, slot unlocks), not from currency variety.

What this GDD does **NOT** do: it does not implement DataStore (that is Persistence #1), and it does not own production *rates* (that is Idle Production #3 — see the boundary contract in §2.3 and §9). It owns *where coins come from and go, how the wallet is mutated safely, and the balance/inflation math.*

---

## 2. Core Mechanics

### 2.1 The money cycle (faucets → wallet → sinks)

```
        ┌──────────────── FAUCETS (coins ENTER the economy) ────────────────┐
        │                                                                    │
        │  Idle Production (#3)  ──► Economy.award(reason="idle_collect")    │   PRIMARY faucet
        │  Raid loot win   (#6)  ──► Economy.award(reason="raid_loot")       │   secondary (turn-based combat)
        │  Pet AI win     (#25)  ──► Economy.award(reason="field_combat_win")│   secondary (real-time combat) — NEW v1.2
        │  Daily quest    (#17)  ──► Economy.award(reason="quest_daily")     │   pacing / retention
        │  Positive reward (—)   ──► Economy.award(reason="reward")          │   moments/codes
        │  DevProduct pack (#15) ──► Economy.award(reason="devproduct")      │   Robux faucet (idempotent)
        │                                                                    │
        └────────────────────────────────┬───────────────────────────────────┘
                                          │  award():  coins += amount
                                          │            stats.totalCoinsEarned += amount   (NET-WORTH, monotonic)
                                          ▼
                              ┌───────────────────────┐
                              │   WALLET (coins)      │   server-authoritative, atomic (Persistence #1)
                              │   PlayerData.coins    │
                              └───────────┬───────────┘
                                          │  spend():  require balance >= cost; coins -= cost
                                          │            totalCoinsEarned UNCHANGED (sinks never reduce net worth)
        ┌─────────────────────────────────▼───────────────────────────────────┐
        │                  SINKS (coins LEAVE the economy)                      │
        │                                                                       │
        │  Capture cost     (#4)  ──► Economy.spend("capture", 25)              │   per-Brainrot, flat
        │  Factory/slot/storage upgrades  ──► Economy.spend("upgrade", cost(n)) │   PRIMARY sink (scales!)
        │  Raid send cost   (#6)  ──► Economy.spend("raid_send", cost)          │   per raid attempt
        │  Reroll cost      (#11) ──► Economy.spend("reroll", curve)            │   capped escalating
        │  Roster slot unlock     ──► Economy.spend("slot_unlock", cost(n))     │   to cap 200
        │  Drama/Walkout fix (opt)──► Economy.spend("drama_fix", cost)          │   optional, always payable
        └───────────────────────────────────────────────────────────────────────┘
```

**Design principle (locked):** Faucets add to BOTH `coins` and `stats.totalCoinsEarned`. Sinks subtract ONLY from `coins`. This makes the leaderboard reward total engagement (you can spend freely and still climb) and makes net worth a clean monotonic value (persistence §2.6 rationale).

### 2.2 The Economy service API (mechanism)

Economy is an internal server service (`EconomyService`) that composes Persistence's atomic mutation path. It exposes three primitives; every consumer uses these and never touches `coins` directly.

```lua
-- ServerScriptService/Economy/EconomyService.lua  (server-only)
-- Composes PlayerDataService's atomic UpdateAsync path (persistence §2.3).
-- NEVER touches DataStore directly; NEVER trusts a client-supplied amount.

-- Read the authoritative balance (server cache; reflects all committed mutations).
function EconomyService.getBalance(player: Player): number            -- returns coins (>= 0)

-- Credit coins (a FAUCET). Bumps stats.totalCoinsEarned by the same amount.
-- `reason` is a string from EconomyConfig.faucetReasons (audit + analytics + BalanceChanged).
-- `idemKey` is OPTIONAL: present for at-most-once sources (DevProduct receipt, raid loot
--   per-raid id) so a retry cannot double-credit; absent for naturally-once sources (idle collect
--   is already guarded by the pending-pool zeroing in persistence §2.4).
function EconomyService.award(player: Player, amount: number, reason: string, idemKey: string?): boolean

-- Debit coins (a SINK). REJECTS (returns false, no mutation) if balance < amount.
-- `reason` from EconomyConfig.sinkReasons. `idemKey` optional (capture/reroll pass one).
-- Does NOT touch totalCoinsEarned.
function EconomyService.spend(player: Player, amount: number, reason: string, idemKey: string?): boolean

-- Convenience for consumers that need an all-or-nothing "can I afford X?" pre-check WITHOUT
-- committing (e.g. UI gating, capture's affordability check before its atomic roster write).
-- The authoritative check still happens INSIDE the atomic spend; this is advisory only.
function EconomyService.canAfford(player: Player, amount: number): boolean
```

**Atomicity guarantees (inherited from Persistence #1 §2.3, not re-implemented):**

- Every `award`/`spend` runs inside the single `UpdateAsync`-based transaction on the live profile. Concurrent mutations are serialized — the second sees post-first state (no double-spend, persistence E9).
- A mutation carrying `idemKey` is de-duped via `txLog`: a replayed key returns the prior result with **no second effect** (persistence §2.3, E7). DevProduct receipts get a double layer (Roblox `ProcessReceipt` is itself idempotent by `PurchaseId` + `txLog`).
- `spend` validates `balance >= amount` **inside** the transaction, so the check cannot be raced past. `coins` can never go below 0.
- A successful mutation marks the profile dirty (triggers save discipline) and fires the internal `CoinsChanged` event (persistence §5.3) which the UI mirror, Leaderboard-dirty marker, and analytics listen to.

> **Capture composition note (locked):** Capture's debit is NOT a standalone `spend` followed by a roster write — that would be two transactions and could half-fail. Per `capture-gdd.md` §5.1 step 10d, the coin debit and the roster append are ONE atomic op. Economy therefore also exposes the debit as an *operation that Persistence composes into the capture transaction* (the capture commit calls the same balance-decrement logic inside its own `UpdateAsync` callback). The *mechanism* (decrement `coins`, never below 0) is shared; the *transaction boundary* belongs to whoever owns the larger atomic unit. Reroll (#11) composes the same way (charge + re-draw in one op).

### 2.3 Idle Production deposit contract (boundary with #4 — owner of rates)

> **Boundary lock (to avoid duplicating Idle Production GDD #3, not yet written):** Idle Production **owns the production rate math** (per-Brainrot base rate, personality multipliers, online tick rate, offline rate, the 8h cap, the 2x-offline GamePass multiplier). Economy owns **only the deposit and the wallet**. This GDD defines the *contract*, not the rates.

The deposit contract:

1. **Online accrual** ticks coins into a pending pool (or directly per Idle's model); on **Collect**, Idle Production calls `Economy.award(player, pendingAmount, "idle_collect")`. Economy credits `coins` and bumps `totalCoinsEarned`. (Persistence §2.4 already zeroes `pendingOffline` atomically on collect — Economy's credit and the pending-zero are part of the same Persistence collect transaction.)
2. **Offline accrual** is computed by Persistence on load using `IdleProduction.computeOfflineRate(roster)` (persistence F-OFFLINE), clamped to `offlineCapSeconds` (8h). It lands in `pendingOffline.coins`; the player taps Collect; same `award` path.
3. Economy **never computes a rate**. It receives an amount and a reason. If Idle's rate model changes, Economy is unaffected.

This keeps the two GDDs cleanly separated: Idle = "how many coins per second," Economy = "credit them safely and track net worth."

### 2.4 State diagram — coin flow per player session

```
   profile loaded (Persistence)                       periodic
        │  pendingOffline.coins may be > 0                │
        ▼                                                 │
  ┌───────────────┐   Collect (CollectOfflineRequest)     │  Idle online tick
  │ PENDING POOL  │ ───────────────────────────────────► │  accrues into pending
  │ (offline+     │       Economy.award("idle_collect")   │  (rate owned by #3)
  │  online accr) │                                       ▼
  └───────────────┘                              ┌────────────────┐
        ▲                                         │     WALLET     │
        │ Raid loot (win)                         │   coins >= 0   │
        │ Economy.award("raid_loot", idemKey)     │                │
        │ Quest/reward                            └───┬────────┬───┘
        │ DevProduct pack (idemKey=PurchaseId)        │        │
        └─────────────────────────────────────────────┘        │
                                                                │ spend() — REJECTED if balance < cost
                       ┌────────────────────────────────────────┘
                       ▼
              ┌──────────────────┐   success → coins -= cost; CoinsChanged(delta<0, reason)
              │  SINK COMMITTED  │   fail    → no mutation; BalanceChanged NOT fired; UI shows
              │ (capture/upgrade/│             "Meme Coins tidak cukup" with shortfall
              │  reroll/raid/...)│
              └──────────────────┘

   On every credit:  stats.totalCoinsEarned += amount  → Leaderboard marked dirty (debounced write)
   On every debit:   stats.totalCoinsEarned UNCHANGED   → spending never lowers rank
```

---

## 3. Data Schema

Economy defines **NO new `PlayerData` fields**. It reads/mutates fields owned by `persistence-gdd.md` v1.1 §3.2:

| Field (owned by Persistence #1) | Type | Default | Economy's use |
|---|---|---|---|
| `coins` | number (≥0) | 0 | Meme Coins balance. Mutated by every `award`/`spend`. Server-authoritative. |
| `gems` | number (≥0) | 0 | Brain Cells (premium). **Provisioned, unused at launch.** No Economy flow reads/writes it; forward-compat for Phase 2 (#21). |
| `stats.totalCoinsEarned` | number (≥0) | 0 | Lifetime GROSS Meme Coins. **Incremented on every `award`, NEVER decremented.** The leaderboard net-worth value (persistence §2.6). |
| `nextSeq`, `txLog` | number / {string} | 1 / {} | Anti-dupe ledger. Economy passes optional `idemKey` into `txLog`; does not own the structure. |
| `pendingOffline.coins` | number | 0 | Read on Collect; Idle deposits flow through here (persistence §2.4). Economy credits on collect. |

Economy's OWN data is the **faucet/sink catalog** — config tables (§8), not persisted player state. They define *what a reason means and what it pays/costs*, decoupled from the wallet.

### 3.1 Faucet catalog (config — `EconomyConfig.faucets`)

| id (reason) | type | value / formula | comment |
|---|---|---|---|
| `idle_collect` | variable | amount supplied by Idle Production (#3) | PRIMARY faucet. Economy credits whatever Idle computes; rate owned by #3. |
| `raid_loot` | formula | `floor(targetPool * raidLootPct)` (§8.3) | Secondary. `targetPool` = NPC Rival Startup's lootable pool (Raid #6). Carries per-raid `idemKey`. |
| `field_combat_win` | flat | `PetCombatConfig.winCoins` (demo = 25; per win) | **NEW v1.2.** Field Combat / Pet AI (#25) — paid when a summoned Brainrot wins against a wild Brainrot. Pet AI supplies the value + a per-engagement `idemKey` (the fighter/wild pairing); Economy credits + bumps `totalCoinsEarned`. Free-feel "found-money" faucet (engagement reward; no send cost — `costToSummon = 0`). Capped implicitly by `fighterLifetimeSec` + summon cooldown (Pet AI design). |
| `quest_daily` | per-quest config range | `EconomyConfig.questRewards[questType]` → roll within `{min,max}` (§8.2) | Daily Quests (#17). Paid **on quest completion** (not login streak). Reward is a per-quest-type config range, not a flat value. |
| `reward_generic` | flat | per-source value (codes, moments, FTUE gifts) | Positive one-off rewards; small. |
| `devproduct_pack` | tier | grant from Monetization SKU (§9) | Robux faucet. **Idempotent by `PurchaseId`** (Monetization #15). |

### 3.2 Sink catalog (config — `EconomyConfig.sinks` + cross-owned values)

| id (reason) | type | value / formula | owner of value | comment |
|---|---|---|---|---|
| `capture` | flat | `CaptureConfig.captureCostCoins` (default 25) | **Capture #4** (referenced, not redefined) | Per-Brainrot. Free during onboarding (`freeCapturesOnboarding`). |
| `upgrade_factory` | curve | `cost(n) = baseFactory * growth^n` (§8.4) | Economy | PRIMARY scaling sink (absorbs idle growth). |
| `upgrade_worker_slot` | curve | `cost(n) = baseWorker * growth^n` (§8.4) | Economy | Per worker-slot in a factory. |
| `upgrade_storage` | curve | `cost(n) = baseStorage * growth^n` (§8.4) | Economy | Raises the pending/offline cap or wallet headroom (interacts with Idle). |
| `raid_send` | flat or tier | `EconomyConfig.raidSendCostCoins` (default 100) | Economy (Raid #6 reads it) | Cost to send a team of 3. Per-attempt sink that gates raid spam. |
| `reroll` | capped curve | `250 → 600 → 1200 → 2000 (cap)`, resets after 24h (§8.5) | **LOCKED** (monetization brainstorm) | Per-Brainrot escalating; Meme Coins path always available (no Robux wall). |
| `slot_unlock` | curve | `cost(n) = baseSlot * slotGrowth^n`, hard cap at roster 200 (§8.6) | Economy | Expands roster capacity toward cap 200. |
| `drama_fix` | flat (optional) | `EconomyConfig.dramaFixCostCoins` (default 200) | Economy (Drama #23, P2) | OPTIONAL — drama always has a free "wait it out" path; coin fix is a convenience sink. |

> **Ethics lock (kid-safe):** every sink that resolves frustration (reroll, drama/Walkout fix) is ALWAYS payable in Meme Coins and ALWAYS has a non-paid alternative (wait it out / earn coins). There is no manufactured frustration that can ONLY be cleared with Robux. The Robux reroll path (Monetization #15) is a *convenience shortcut layered on top of* the Meme Coins path, never the only door.

---

## 4. Client-Server Split

| Concern | Server (authoritative) | Client (presentation only) |
|---|---|---|
| `coins` / `gems` value | **Owns it.** All `award`/`spend` server-side, atomic. | Read-only mirror for the HUD (from Persistence `DataReplicated`/`DataDelta`). |
| `stats.totalCoinsEarned` | Increments on every credit. | Mirror (shown on profile / leaderboard). |
| Faucet amount (idle/raid/quest/devproduct) | Computed/validated server-side; client cannot name an amount. | Sees the *result* (a coin-gain animation + new balance). |
| Sink cost (capture/upgrade/reroll/raid/slot) | Reads cost from config server-side; validates affordability inside the atomic spend. | May *display* a cost from a replicated config copy (so the shop shows prices), but the server re-reads the authoritative cost — client's claimed price is ignored. |
| Affordability decision | Final check inside the atomic transaction (`balance >= cost`). | May grey out a buy button as a hint, but the server is the gate. |
| `idemKey` / `txLog` / `nextSeq` | Server-internal; never replicated. | Never sees them. |
| Leaderboard net-worth write | Server writes OrderedDataStore (via Persistence). | Sees a cached top-N snapshot. |

**Authority rule (locked, per `server-scripts.md`):** the client NEVER sends a coin amount, a balance, or a "I bought it" boolean. It sends only *intents* ("buy upgrade X", "reroll Brainrot G", "send raid"). The server looks up the cost from config, checks the authoritative balance, and commits atomically. Any client-supplied number is ignored. Prices may be replicated *down* (read-only) so shops render, but the server is the only writer.

---

## 5. RemoteEvents / Functions

Economy itself adds **no new client→server remote that names an amount** (per `server-scripts.md` — a client must never name a coin value). Balance replication piggy-backs on Persistence's existing `DataReplicated` / `DataDelta` mirror (persistence §5.1) so a coin tick does not resend the whole profile. Economy's network contribution is one **server→client event** for rich coin-change feedback, and it relies on each consumer's own intent remote for spends.

### 5.1 Server → Client

| Remote | Type | Payload | Purpose |
|---|---|---|---|
| `BalanceChanged` | RemoteEvent (S→C) | `{ newBalance: number, delta: number, reason: string }` | Drives the HUD coin counter + the gain/spend animation. `delta>0` = faucet (green "+N" floats up), `delta<0` = sink (red "−N" ticks off). `reason` lets UI pick the right SFX/label ("Idle collected!", "−25 capture", "Reroll!"). Fired after every committed `award`/`spend`. This is the client-facing projection of the internal `CoinsChanged` event (persistence §5.3). |
| `SpendRejected` | RemoteEvent (S→C) | `{ reason: string, needed: number, have: number, sink: string }` | Fired when a `spend` is rejected for insufficient funds. Drives the "Meme Coins tidak cukup" toast with the exact shortfall (`needed - have`). |

> The **full balance** also arrives via Persistence's `DataReplicated` (initial) / `DataDelta` (`{ ["coins"] = N }`) — `BalanceChanged` is the *animation/feedback* channel layered on top (it carries the delta + reason that a raw delta-sync lacks). Both are server-authored; the client trusts neither for logic, only for display.

### 5.2 Client → Server

Economy exposes **no standalone "spend" remote**. Spending always happens through the *consumer's* validated intent remote (e.g. Capture's `CaptureResolveRequest`, Reroll's `RerollRequest`, an Upgrades `BuyUpgradeRequest`, Raid's `SendRaidRequest`). Each of those:

1. Is rate-limited and type/range-validated by its owning system (per `server-scripts.md`).
2. Carries only an *identifier* (which upgrade, which Brainrot, which raid target) — **never a coin amount**.
3. Server looks up the cost from config, then calls `Economy.spend(player, cost, reason, idemKey?)` (or composes the debit into a larger atomic op for capture/reroll).
4. On rejection, the consumer surfaces `SpendRejected` (or the consumer's own reason, e.g. capture's `insufficient_coins`).

This means Economy adds zero attack surface: there is no remote anywhere that lets a client say "give me 1000 coins" or "this costs 0."

### 5.3 Internal server events (not network)

| Event | Payload | Fired When | Listened By |
|---|---|---|---|
| `CoinsChanged` (re-used from persistence §5.3) | `{ player, newBalance, delta, reason }` | After any committed wallet mutation | UI mirror → projects to `BalanceChanged`; Leaderboard (mark `totalCoinsEarned` dirty); Analytics (faucet/sink telemetry) |

All remotes registered centrally in `ReplicatedStorage/Shared/Remotes`; documented in the remotes manifest.

---

## 6. Player-Facing UI

Economy renders through the shared UI/HUD framework (#13); these are the surfaces it drives:

1. **HUD coin counter** — persistent Meme Coins balance (coin icon + number, mobile-first, top of screen). Reads the replicated `coins` mirror. Large numbers shown with suffixes (1.2K, 3.4M, 1.1B — see §8.7 display formatting) so the HUD never overflows.
2. **Coin gain animation** — on `BalanceChanged` with `delta>0`: a green "+N" floats up from the coin icon with a light chime; the counter rolls up to the new value. Idle collect plays a bigger "burst" (coins fly into the counter) because it is the headline reward beat.
3. **Coin spend animation** — on `delta<0`: a red "−N" ticks off the counter with a soft "spend" SFX; the counter rolls down. Reroll/upgrade get a small satisfying "ka-ching → committed" beat so spending feels purposeful, not punishing.
4. **"Meme Coins tidak cukup" message** — on `SpendRejected`: a clear, kind toast/modal: **"Meme Coins kurang — kamu butuh {needed}, punya {have}."** ("Not enough Meme Coins — you need {needed}, you have {have}.") with a friendly nudge toward earning (e.g. "Collect from your factory or win a raid!"). Never a dead-end; never an aggressive upsell.
5. **Offline-collect screen** — the "While you were gone…" recap (owned by Persistence §6 item 3 / Idle/Moment). Economy's role: the **Collect** button fires the collect; the coin credit animates into the HUD with the burst effect. Shows the capped window note ("capped at 8h") if it hit the cap.
6. **Shop / upgrade prices** — each buyable shows its current cost (from replicated config; for curved sinks the *current tier* cost, e.g. "Upgrade Factory — 1.2K"). Affordable items are bright; unaffordable are dimmed with the needed amount shown (server is still the gate, this is only a hint).
7. **Reroll cost display** — shows the current Meme Coins cost in the escalating curve (250 / 600 / 1200 / 2000) AND the time until it resets to tier-1 (24h), so the player understands the curve is capped and self-healing — never opaque. (Reroll odds are displayed by Reroll #11 for compliance.)

All surfaces are pure presentation: read replicated state, fire the consumer's intent remote, play the feedback the server authorizes. No per-frame work; no client-side balance math.

---

## 7. Edge Cases & Error States

Minimum-5 requirement exceeded. Covers the `design-docs.md` checklist (zero/max/negative/rapid/lag/disconnect/datastore-down/concurrent).

### E1 — Insufficient balance on `spend` (the common rejection)
**Trigger:** a consumer calls `Economy.spend(player, cost, ...)` with `balance < cost`.
**Behavior:** the spend is **rejected inside the atomic transaction** — `coins` is NOT mutated, `false` is returned, no `CoinsChanged` fires. The consumer surfaces `SpendRejected{ needed=cost, have=balance, sink, reason="insufficient_coins" }` → the "Meme Coins tidak cukup" toast (§6 item 4). The player keeps everything they had; nothing is half-committed (e.g. capture leaves the wild creature alive, `capture-gdd.md` §7.1b). This is a *normal, non-error* path — kids must never feel punished, just informed.

### E2 — Overflow / very large balance (number precision & display)
**Trigger:** a long-lived idle player's `coins` or `totalCoinsEarned` grows very large (idle = exponential).
**Behavior:** Luau numbers are IEEE-754 doubles — **exact integers up to 2^53 ≈ 9.007e15** (9 quadrillion). All coin amounts are kept as **integer-valued doubles** (`award`/`spend` use `math.floor` on any computed amount, §8) so no fractional coins ever accumulate. A **soft display cap** formats anything ≥ 1e15 as "999T+" so the HUD never shows garbage; a **hard guard** (`EconomyConfig.maxBalance`, default 1e15) clamps `coins`/`totalCoinsEarned` and logs a `balance_cap_hit` analytics event if ever approached (it should not be reachable with the sink curves in §8 — see E6). Because every sink curve grows geometrically (§8.4), the *effective* spendable economy stays far below 2^53; this guard is a safety net, not an expected state.

### E3 — `award` and `spend` race / concurrent mutations on the same wallet
**Trigger:** idle-collect credit and an upgrade-spend (or two spends — manual capture + auto-catch) hit the same wallet near-simultaneously.
**Behavior:** all wallet mutations go through Persistence's single atomic `UpdateAsync` path (persistence §2.3, E9), which **serializes** them. The second operation observes the first's committed result. A spend that would now overdraw (because a concurrent spend already drained the balance) is cleanly rejected (E1) — never a negative balance. No double-spend, no lost credit. This is the same invariant `capture-gdd.md` §5.1 relies on.

### E4 — Idle deposit when offline cap already reached
**Trigger:** player was offline > 8h; `F-OFFLINE` (persistence §2.4) clamped `elapsed` to `offlineCapSeconds`.
**Behavior:** the pending pool holds at most `floor(rate * 8h)` coins — accrual past 8h simply does not happen (clamp). On Collect, Economy credits exactly that clamped amount via `award("idle_collect")`. The "While you were gone…" screen shows the **"capped at 8h"** note so the player understands why a 3-day absence did not pay 3 days. The **2x-offline GamePass** multiplies the *rate* inside `computeOfflineRate` (Idle #3), so it doubles the coins earned *within* the 8h window — it does NOT extend the window (see §8.8 confirmation). No double-credit on Collect: Persistence zeroes `pendingOffline` in the same atomic op as the `award` (persistence §2.4).

### E5 — Idempotency: double-award from a retried faucet (DevProduct / raid loot)
**Trigger:** a DevProduct receipt or raid-loot grant is re-delivered (Roblox retries `ProcessReceipt`; a raid result remote re-fires after lag).
**Behavior:** the faucet carries an `idemKey` (DevProduct → Roblox `PurchaseId`; raid loot → the unique raid id). `award` checks `txLog` inside the atomic op: **if the key is present, it is a no-op returning the prior result** — no second credit (persistence §2.3, E7). DevProduct gets a double layer (`ProcessReceipt` is itself idempotent by `PurchaseId`). Idle collect does NOT need an `idemKey` because the pending-pool zeroing already makes a re-fired collect a no-op (collecting an empty pool credits 0). This is the single most important guard against minting free coins.

### E6 — Hyperinflation / faucet outruns sinks over the playable lifetime
**Trigger:** late-game idle production scales faster than the player can spend, so balances balloon and every price feels free.
**Behavior:** this is prevented by **design, not by a runtime clamp** (the clamp in E2 is only a last-resort safety net). The primary sinks (factory/worker/storage upgrades and slot unlocks) are **geometric curves** (`base * growth^n`, §8.4) deliberately tuned so the cost of the *next* meaningful upgrade rises roughly in step with how fast production grows. Because production also grows geometrically with upgrades, a player who keeps upgrading keeps spending most of what they earn — the upgrade treadmill is the inflation absorber. See §8.9 for the explicit "sink absorbs faucet" pacing argument. If telemetry ever shows median balance growing unbounded (sinks not keeping up), the levers are `growth` (raise) or `base` (raise) in config — zero code change.

### E7 — Spend with a stale/replicated client price (anti-exploit)
**Trigger:** a client sends a "buy upgrade X" intent but the replicated price it saw is stale, or a tampered client claims a lower price.
**Behavior:** the client intent carries only the *identifier* (which upgrade), never the price. The server reads the **authoritative current cost** from config at spend time (for a curved sink, it reads the player's current tier `n` from persisted state and computes `cost(n)`). The client's belief about price is irrelevant — it cannot be exploited. If the real cost exceeds the balance, normal rejection (E1).

### E8 — Negative or non-finite `amount` passed to `award`/`spend` (programmer/exploit guard)
**Trigger:** a buggy or malicious call path passes `amount < 0`, `0`, `NaN`, or a fractional value.
**Behavior:** `award`/`spend` validate: `amount` must be a finite number, `amount == math.floor(amount)` (integer), and `amount >= EconomyConfig.minMutation` (default 1) for `spend` / `>= 0` for `award`. A negative `spend` (which would secretly *credit*) is **rejected and logged** as a `bad_mutation` incident. A `NaN`/`inf` is rejected. This closes the "negative spend = free coins" class of bug. (Amounts always originate server-side from config or Idle's computed value — never from a client — but defense-in-depth per `server-scripts.md`.)

### E9 — DataStore unavailable at commit
**Trigger:** the underlying `UpdateAsync` fails (DataStore down) during an `award`/`spend`.
**Behavior:** the commit is `pcall`-wrapped by Persistence; on failure **nothing is mutated** (neither `coins` nor `totalCoinsEarned`) and the operation returns `false`. The consumer treats it as a transient failure (capture → "Hiccup, try again!" toast and leaves the creature alive, `capture-gdd.md` §7.8; a shop buy → "try again" toast). No partial state. The dirty-flag retry discipline (persistence E3) re-attempts the *save* of already-committed in-memory state, but a commit that never ran simply did not happen.

### E10 — Roster slot unlock at the hard cap (200)
**Trigger:** player tries to buy a roster-slot unlock when already at `rosterCap` (200).
**Behavior:** the slot-unlock sink checks the cap **before** charging; at 200 the purchase is rejected with a clear "Roster sudah maksimal (200)" message and **no coins are taken** (charge-after-check ordering, mirroring `capture-gdd.md` §7.1). Slot-unlock cost `cost(n)` is only defined for `n < maxRosterUnlocks`; beyond that there is nothing to buy.

---

## 8. Balancing Parameters

> **This is the core of the GDD.** All values in `EconomyConfig` (commented, ranged, versioned per `config-data.md`). **Zero magic numbers in code.** Values that are *owned elsewhere* (capture cost, reroll curve as a locked spec) are referenced with their owner noted, never re-defined contradictorily.

> **Units note:** all coin amounts are integers. Any formula result is `math.floor`-ed before it touches the wallet (E2/E8). "Tier" / "level" `n` is 0-based unless stated (the first upgrade is `n=0`).

### 8.1 `EconomyConfig` (the master table)

```lua
-- ReplicatedStorage/Shared/Config/EconomyConfig.lua
-- (Costs/curves are SAFE to replicate read-only so shops render; the SERVER re-reads
--  authoritative cost at spend time — client price is never trusted, §4/§E7.)
-- Edited by designers for balance. Schema version: 1
return {
    version = 1,

    -- ── GLOBAL GUARDS ──
    -- Hard ceiling on coins / totalCoinsEarned (E2). Doubles are exact to 2^53 (~9e15);
    -- we cap WELL below that. Should be unreachable given the sink curves below — safety net only.
    -- Range: 1e9-9e15 | Default: 1e15 (one quadrillion; formats as "999T+")
    maxBalance = 1e15,
    -- Minimum positive amount a single spend may charge (rejects 0/negative, E8).
    -- Range: 1-100 | Default: 1
    minMutation = 1,

    -- ── FAUCETS (Economy-owned values; idle/raid amounts computed elsewhere) ──
    -- Daily Quests (#17) reward POOL, keyed by quest type. Paid ON QUEST COMPLETION.
    -- Economy owns the reward {min,max} ranges; Daily Quests #17 owns WHICH quests roll,
    -- their progress targets, the 3-per-day count, and the server-clock daily reset.
    -- On completion, Economy rolls a coin reward uniformly in [min,max] (§8.2, F-FAUCET-QUEST).
    -- Pacing intent: a single quest ≈ one early-game upgrade's worth; a full 3-quest day
    -- ≈ a few upgrades, meaningful but not eclipsing idle as the primary faucet.
    -- Each range: 0-100000 (min <= max).
    questRewards = {
        capture_n = { min = 100, max = 200 },   -- "tangkap N Brainrot"
        win_raids = { min = 150, max = 300 },   -- "menang M raid"
        collect_x = { min = 100, max = 200 },   -- "kumpulkan X coins"
        evolve_one = { min = 200, max = 350 },  -- "evolve 1 Brainrot" (rarer goal, higher pay)
    },
    -- Fallback flat reward if a quest type has no range entry (defensive default).
    -- Range: 0-100000 | Default: 150
    questRewardFallbackCoins = 150,
    -- Generic positive reward fallback (codes, FTUE gift, small moment payout).
    -- Range: 0-100000 | Default: 50
    rewardGenericCoins = 50,
    -- Allowed faucet reason strings (audit/analytics whitelist).
    faucetReasons = { "idle_collect", "raid_loot", "field_combat_win", "quest_daily", "reward_generic", "devproduct_pack" },

    -- ── FLAT SINKS ──
    -- Capture cost is OWNED BY CaptureConfig.captureCostCoins (default 25). Mirrored here for
    -- the economy model ONLY; the authoritative value lives in CaptureConfig (§3.2, capture-gdd §8.2).
    -- DO NOT edit here to change capture cost — edit CaptureConfig. Listed for the inflation model.
    captureCostCoins_REFERENCE = 25,
    -- Cost to send a raid team of 3 (per attempt). Gates raid spam; a per-attempt sink.
    -- Tuned so a successful raid's expected loot comfortably exceeds it (positive but not free).
    -- Range: 0-100000 | Default: 100
    raidSendCostCoins = 100,
    -- OPTIONAL drama/Walkout instant-fix cost. ALWAYS has a free "wait it out" alternative (ethics lock).
    -- Range: 0-100000 | Default: 200 (P2 Drama #23; provisioned now)
    dramaFixCostCoins = 200,
    -- Allowed sink reason strings (audit/analytics whitelist).
    sinkReasons = { "capture", "upgrade_factory", "upgrade_worker_slot", "upgrade_storage",
                    "raid_send", "reroll", "slot_unlock", "drama_fix" },

    -- ── UPGRADE CURVES (geometric; the PRIMARY inflation absorber, §8.4/§8.9) ──
    upgrades = {
        factory = {
            -- Base cost of the FIRST factory upgrade (n=0).
            -- Range: 50-100000 | Default: 200
            base = 200,
            -- Geometric growth per level. >1. Higher = steeper wall = stronger sink.
            -- Range: 1.10-2.00 | Default: 1.35 (each upgrade ~35% pricier than the last)
            growth = 1.35,
            -- Max purchasable levels (cap so the curve is bounded; prestige content beyond is Phase 2).
            -- Range: 5-100 | Default: 30
            maxLevel = 30,
        },
        workerSlot = {
            -- Base cost to open the FIRST extra worker slot in a factory (n=0).
            -- Range: 50-100000 | Default: 150
            base = 150,
            -- Range: 1.10-2.00 | Default: 1.50 (slots are powerful; steeper)
            growth = 1.50,
            -- Range: 1-50 | Default: 10
            maxLevel = 10,
        },
        storage = {
            -- Base cost of the FIRST storage (offline-cap / wallet-headroom) upgrade (n=0).
            -- Range: 50-100000 | Default: 300
            base = 300,
            -- Range: 1.10-2.00 | Default: 1.40
            growth = 1.40,
            -- Range: 1-50 | Default: 12
            maxLevel = 12,
        },
    },

    -- ── ROSTER SLOT UNLOCK CURVE (to hard cap 200; persistence rosterCap) ──
    slotUnlock = {
        -- Base cost of the first PAID slot unlock (n=0). Early slots cheap, late slots dear.
        -- Range: 50-100000 | Default: 250
        base = 250,
        -- Range: 1.05-1.50 | Default: 1.20 (gentle; we WANT players to grow the roster)
        growth = 1.20,
        -- How many slots one unlock grants (batch so we don't sell 200 one-at-a-time).
        -- Range: 1-25 | Default: 5
        slotsPerUnlock = 5,
        -- Starting free roster capacity at profile creation.
        -- Range: 5-200 | Default: 25
        startingSlots = 25,
        -- Hard cap (matches persistence rosterCap = 200). maxRosterUnlocks derives from this.
        -- Range: 50-200 | Default: 200
        rosterCap = 200,
    },

    -- ── REROLL CURVE (LOCKED by monetization brainstorm — DO NOT retune the tiers) ──
    -- Per-Brainrot escalating Meme Coins cost; resets to tier 1 after 24h with no reroll.
    -- Mechanic (which reroll # a Brainrot is on, the 24h timer) is OWNED by Reroll #11;
    -- Economy owns only the COST VALUES below and the spend. Robux path is Monetization #15.
    reroll = {
        -- Cost ladder by reroll count on a given Brainrot (1st, 2nd, 3rd, 4th+). Index 4 is the FLAT CAP.
        -- LOCKED VALUES — Range note: these are fixed, not free-tuning (changing them is a design decision).
        costs = { 250, 600, 1200, 2000 },   -- 4th and beyond all cost 2000 (cap)
        -- Hours of no-reroll inactivity after which a Brainrot's reroll tier resets to 1 (250).
        -- Range: 1-72 | Default: 24 (LOCKED)
        resetHours = 24,
    },

    -- ── DISPLAY ──
    -- Number-suffix thresholds for the HUD (§8.7). Keeps big idle numbers readable.
    displaySuffixes = { {1e12,"T"}, {1e9,"B"}, {1e6,"M"}, {1e3,"K"} },
}
```

### 8.2 Faucet values (explicit)

```
F-FAUCET-IDLE   (PRIMARY, amount owned by Idle Production #3 — Economy only credits)
  award_amount = pendingOffline.coins (+ online-pending)   -- computed by #3, clamped to 8h cap
  Economy:  coins += award_amount ; totalCoinsEarned += award_amount

F-FAUCET-QUEST  (Daily Quests #17 — paid ON QUEST COMPLETION, NOT a login streak)
  r = EconomyConfig.questRewards[questType]   -- {min,max}; fallback questRewardFallbackCoins (150) if absent
  quest_amount = floor( r.min + random() * (r.max - r.min) )      -- uniform integer in [r.min, r.max]
  Economy:  award(player, quest_amount, "quest_daily", idemKey = questId)   -- idempotent (E5; one payout per quest)
  Where:
    questType : which quest completed (capture_n | win_raids | collect_x | evolve_one); OWNED by Daily Quests #17.
    questId   : the unique per-day per-quest id; the idemKey so a re-fired completion cannot double-pay.
    random()  : server-side; client never names the amount (§4).
F-FAUCET-REWARD reward_amount = per-source, default rewardGenericCoins    (default 50, flat)
F-FAUCET-DEVP   devproduct_amount = Monetization SKU grant (idemKey = PurchaseId)   (§9)
```

### 8.3 Raid loot faucet formula (explicit)

```
F-FAUCET-RAID — coins awarded to the winner of a raid vs an NPC Rival Startup

  loot = floor( targetPool * raidLootPct )

Where:
  targetPool   : the NPC Rival Startup's current LOOTABLE pool of Meme Coins.
                 OWNED & supplied by Raid #6 (analogous to a real target's uncollected idle).
                 Range in practice scales with the rival tier (Grind Corp .. Pivot Ventures).
  raidLootPct  : fraction of the pool stolen on a WIN. OWNED by Raid #6 config (RaidConfig.lootPct).
                 Recommended Range: 0.10-0.40 | Recommended Default: 0.25 (a meaningful but
                 not total steal — leaves the rival worth raiding again; mirrors the "% of
                 uncollected" steal from idea/brainrotInc.md Raid & Defend).
  On WIN:  Economy.award(player, loot, "raid_loot", idemKey = raidId)     -- idempotent (E5)
  On LOSS: no loot (and raid_send cost was already spent — net negative, the risk).

Net-of-cost expected value (sanity, designer should keep > 0 for a fair-skill player):
  EV = winRate * loot  -  raidSendCostCoins
     positive whenever  winRate * (targetPool * raidLootPct)  >  raidSendCostCoins
```

> **Boundary note:** `raidLootPct` and `targetPool` are referenced here for the economy model but are **owned by Raid #6's config**, not duplicated authoritatively in `EconomyConfig`. Economy only consumes the resulting `loot` amount via `award`. The 0.25 default is a *recommendation* to Raid, ensuring loot meaningfully exceeds the 100-coin send cost.

```
F-FAUCET-FIELDCOMBAT     Pet AI win reward (per win)                              -- NEW v1.2 (#25)

Owner of value:  Pet AI #25 (PetCombatConfig.winCoins; demo a71e545 = 25)
Owner of credit: Economy (this GDD)

  On a winning field combat (a player's summoned fighter knocks out a wild Brainrot):
    pet-ai computes:  amount = PetCombatConfig.winCoins                          -- demo: 25 flat
    pet-ai computes:  idemKey = "fcw:" .. fighterId .. ":" .. wildId              -- one credit per pairing
  Economy:  award(player, amount, "field_combat_win", idemKey)                    -- idempotent (E5)

Where:
  PetCombatConfig.winCoins  : OWNED by Pet AI #25 (will live in PetCombatConfig once graduated;
                              currently DemoConfig.combat.winCoins). Range: 1..1000 | Default: 25
                              Sized to be a "found-money" engagement reward — meaningful per win
                              but well below idle's primary faucet rate, so field combat doesn't
                              displace idle as the economy's spine.
  idemKey                   : pairing-based to prevent the same kill being re-credited if the
                              tick-resolution code retries. Pet AI guarantees one credit per
                              fighter+wild engagement boundary.

Cap discipline:  bounded implicitly by Pet AI's `fighterLifetimeSec` (~60s in demo) + the
                 summon cooldown + the density of wild Brainrots in the hub world. There is no
                 send cost (costToSummon = 0 in v1) — the engagement is meant to feel free.
                 ⚠VALIDATE total per-hour income vs. idle's hourly rate (target: field combat <
                 30% of idle's primary faucet at comparable upgrade level).
```

> **Boundary note:** the value (`winCoins`) is owned by Pet AI #25 (and currently lives in `DemoConfig.combat.winCoins`); Economy only consumes the amount via `award` with the per-engagement idempotency key. Field-combat is **NOT pay-to-win**: no send cost, no Robux-only acceleration; the faucet exists purely to reward engagement.

### 8.4 Upgrade cost curve (explicit — the primary scaling sink)

```
F-SINK-UPGRADE — geometric cost of the (n)th level of an upgrade track

  cost(n) = floor( base * growth ^ n )

Where:
  n      : the level being PURCHASED, 0-based (the first upgrade is n=0 → cost = base).
  base   : track base cost (EconomyConfig.upgrades.<track>.base)
  growth : per-level multiplier > 1 (EconomyConfig.upgrades.<track>.growth)
  valid for n in [0, maxLevel-1]; at n == maxLevel there is nothing left to buy (E-bounded).

Worked example — FACTORY (base = 200, growth = 1.35):
  n=0  → 200
  n=1  → floor(200 * 1.35)      = 270
  n=2  → floor(200 * 1.35^2)    = 364
  n=3  → floor(200 * 1.35^3)    = 492
  n=5  → floor(200 * 1.35^5)    = 896
  n=10 → floor(200 * 1.35^10)   ≈ 4,019
  n=20 → floor(200 * 1.35^20)   ≈ 80,773
  n=29 → floor(200 * 1.35^29)   ≈ 1,267,000   (last buyable level, maxLevel=30)
  Cumulative to buy ALL 30 factory levels ≈ 4.9M coins.

Worked example — WORKER SLOT (base = 150, growth = 1.50):
  n=0 → 150 ; n=1 → 225 ; n=2 → 337 ; n=5 → 1,139 ; n=9 → 5,766 (last, maxLevel=10)
  Cumulative all 10 ≈ 16.9K coins.
```

Geometric growth is deliberate: because production *also* grows geometrically with these upgrades, the cost of the next upgrade rises in step with earning power — so a progressing player keeps spending most of their income (the treadmill that absorbs inflation, §8.9).

### 8.5 Reroll cost curve (LOCKED — capped escalating, 24h reset)

```
F-SINK-REROLL — Meme Coins cost of the (k)th reroll on a given Brainrot

  cost(k) = EconomyConfig.reroll.costs[ min(k, 4) ]      -- k is 1-based reroll count on THIS Brainrot

  k = 1 → 250
  k = 2 → 600
  k = 3 → 1200
  k >= 4 → 2000        (FLAT CAP — never exceeds 2000)

Reset rule (LOCKED): if a Brainrot has not been rerolled for `resetHours` (24h),
  its reroll count k resets to 0, so the NEXT reroll is once again 250 (tier 1).

Where:
  k                : the reroll-count state for that Brainrot. OWNED by Reroll #11 (it tracks
                     per-Brainrot count + last-reroll timestamp; Economy does not store it).
  reroll.costs     : LOCKED ladder {250,600,1200,2000} (EconomyConfig.reroll.costs).
  resetHours       : LOCKED 24 (EconomyConfig.reroll.resetHours).

Economy's role: Reroll #11 computes cost(k) using THIS table and calls Economy as part of the
  atomic "charge + re-draw personality" op (idempotency-keyed). Economy owns the VALUES; Reroll
  owns the MECHANIC (count tracking, 24h timer, the re-draw, odds display).

ECONOMIC INTENT: the curve is a self-healing sink. Spamming rerolls on one Brainrot gets
  expensive FAST (250→600→1200→2000), discouraging compulsive churn, but the 24h reset means a
  patient player is never permanently walled — tier-1 (250) always returns. A Robux shortcut
  (Monetization #15) exists for impatience but is NEVER the only path (ethics lock, §3.2).
```

### 8.6 Roster slot-unlock cost curve (explicit)

```
F-SINK-SLOT — cost of the (n)th slot-unlock purchase

  cost(n) = floor( slotUnlock.base * slotUnlock.growth ^ n )

  Each purchase grants `slotsPerUnlock` (default 5) additional roster slots.
  Starting capacity = startingSlots (default 25).
  Max purchasable n until capacity reaches rosterCap (200):
     maxRosterUnlocks = ceil( (rosterCap - startingSlots) / slotsPerUnlock )
                      = ceil( (200 - 25) / 5 ) = 35 purchases.
  Beyond cap there is nothing to buy (E10).

Worked example (base=250, growth=1.20, +5 slots each):
  n=0  → 250    (25 → 30 slots)
  n=1  → 300    (30 → 35)
  n=2  → 360    (35 → 40)
  n=5  → 622    (50 → 55)
  n=10 → 1,547  (75 → 80)
  n=20 → 9,580  (125 → 130)
  n=34 → ~115,000 (last unlock → 200, the cap)
  Cumulative to reach 200 from 25 ≈ 640K coins.

Gentle growth (1.20) is intentional: roster size is core to the fantasy; we WANT players to
expand. The curve absorbs coins late-game (a 115K final unlock is a real sink) without ever
gating the early/mid game behind a wall.
```

### 8.7 Big-number display formatting (explicit)

```
F-DISPLAY — format a coin amount for the HUD (client-side, presentation only)

  for each {threshold, suffix} in EconomyConfig.displaySuffixes (descending):
     if amount >= threshold then  return formatTo1Decimal(amount / threshold) .. suffix
  return tostring(amount)            -- below 1000, show the raw integer

  Examples: 950 → "950" ; 1500 → "1.5K" ; 4,019,000 → "4.0M" ; 1.27e6 → "1.3M" ; >=1e12 → "T"
  At/over maxBalance (1e15) the HUD shows "999T+" (E2 soft display cap).
```

### 8.8 "2x Offline Earnings" GamePass interaction (confirmation)

> **Requested analysis — confirmed.** The 2x-offline GamePass multiplies the offline *rate* inside `IdleProduction.computeOfflineRate` (Idle #3 / persistence §2.4). Net effects:

- **On the wallet/balance:** it simply doubles the coins accrued *within* the existing 8h cap — it does NOT extend the window (E4). So the maximum single offline collect roughly doubles for owners. This is a clean multiplier on a faucet; it does not break the sink curves (a 2x richer player just climbs the *same* geometric upgrade curve faster — the curve still absorbs it, §8.9). It is a *convenience/pace* boost, **not pay-to-win**, because it only affects the player's own coin pace, never raid combat power (monetization lock).
- **On raids (the "more loot to steal" concern):** a 2x-offline owner's NPC-equivalent pool is not a PvP concern at launch (raids are NPC-only, #6). For *forward-compat* with Phase 2 PvP: a 2x-offline player who is *raided* would have a larger uncollected pool, so a raider could steal more — but this is **symmetric and self-limiting**: (1) the raid shield (4h free, #7) and the pending-collect model mean a 2x player collects sooner / shields up; (2) the *raider* also benefits if they own 2x. Net effect on the economy is small and balanced — confirmed: **2x offline does not break balance.** It is a personal pace multiplier whose only economy-wide effect is slightly faster individual progression, fully absorbed by the scaling sinks.

### 8.9 Inflation control strategy (the core argument)

**The problem (idle games):** production scales with roster size × per-Brainrot rate × upgrade levels, all of which grow geometrically. Without scaling sinks, `coins` grows unbounded, every fixed price becomes trivially cheap, and progression loses meaning ("nothing matters").

**The strategy — sinks that scale with wealth:**

1. **Geometric upgrade treadmill (PRIMARY).** Factory/worker/storage upgrade costs are `base * growth^n` (§8.4). Because each upgrade *also raises production geometrically*, the cost of the next worthwhile upgrade rises in lock-step with income. A progressing player therefore reinvests most of what they earn — the upgrade treadmill is the main inflation absorber. The `growth` knobs (1.35–1.50) set how tightly costs track income.
2. **Roster-slot curve (SECONDARY scaling sink).** Late unlocks cost tens-to-hundreds of thousands (§8.6), draining large balances of players who want maximum roster size, with cumulative ~640K to reach cap.
3. **Per-action flat sinks (CONSTANT outflow).** Capture (25, owned by #4), raid send (100), and drama fix (200) provide a steady, volume-proportional drain that grows naturally as the player does more — the more captures/raids, the more coins removed.
4. **Reroll self-healing curve (BEHAVIORAL sink).** The 250→2000 cap removes large chunks from players churning personalities, while the 24h reset keeps it fair.
5. **No interest, no passive multiplier on the balance itself.** Coins do not breed coins — only *production* (which sinks counter) grows. There is no compounding wallet.
6. **Levers, not rewrites.** If telemetry shows median balance rising unbounded (faucet > sink), the fix is config-only: raise `growth` and/or `base` on the upgrade tracks, or add a new luxury sink (e.g. cosmetics) — never a code change. The `maxBalance` guard (E2) is a final safety net, not the strategy.

**Why this stays kid-fair:** sinks scale with *wealth*, so a casual free player on a small balance never feels the late-game prices (they are buying `n=2` upgrades at ~360 coins), while a whale-of-time grinder always has the next geometric wall to spend on. Nobody hits an *unpassable* wall — every sink (including reroll and drama fix) is always payable in Meme Coins and always has a non-paid alternative (earn more / wait).

### 8.10 Rough progression pacing (time-to-milestone, illustrative)

> Illustrative only — precise idle rates are owned by Idle Production #3 (not yet written). Uses a *placeholder* early-game net rate of ~1 coin/sec (≈60/min) for a starting roster to show the *shape* of pacing; Idle #3 will set the real numbers and this table should be reconciled when it lands.

| Milestone | Approx coins | @ ~60 coins/min (early) | Tier |
|---|---|---|---|
| First paid capture (after 3 free) | 25 | < 1 min | Early goal (5–15 min band) |
| First factory upgrade (n=0) | 200 | ~3–4 min | Early goal |
| First worker slot (n=0) | 150 | ~2–3 min | Early goal |
| First reroll (250) | 250 | ~4 min | Session goal |
| First slot-unlock batch (250 → +5) | 250 | ~4 min | Session goal |
| Factory level 10 (cumulative) | ~10K | hours (and rate has grown) | Multi-session |
| All 30 factory levels (cumulative) | ~4.9M | many sessions (rate compounds) | Long-term |
| Roster to cap 200 (cumulative unlocks) | ~640K | long-term | Long-term / prestige |

The early band intentionally has cheap, fast goals (capture, first upgrades) so the first session delivers visible progress every few minutes; the long-term curves (factory max, roster cap) are the multi-week retention hooks. **These will be re-tuned against Idle #3's real rates** so each band hits its target time-to-earn (Early 5–15 min, Session 30–60 min, Multi-session 2–5 h, Long-term 10–50 h).

---

## 9. Integration Points

Economy is the wallet service every coin-touching system uses. **Reads** = consumer reads balance / config; **Writes** = consumer mutates via `award`/`spend` (or composes the debit into a shared atomic op). No consumer touches DataStore or `coins` directly.

| System | Direction | Interaction |
|---|---|---|
| **#1 Data Persistence** | Economy → it | Persistence OWNS storage + the atomic `UpdateAsync` path + `coins`/`gems`/`totalCoinsEarned`/`txLog`. Economy composes its `award`/`spend` over that path; bumps `totalCoinsEarned` on every credit; never decrements it on a sink. Economy adds no schema. |
| **#3 Idle Production** | it → Economy | PRIMARY faucet. On Collect, Idle calls `Economy.award(player, amount, "idle_collect")`. Idle OWNS the rate/cap/2x-multiplier math; Economy only credits + tracks net worth. (Boundary §2.3.) |
| **#4 Capture** | it → Economy | Reads `Economy.getBalance` (affordability); debits `CaptureConfig.captureCostCoins` (25) **atomically with the roster write** (capture-gdd §5.1 step 10d) — the debit logic is composed INTO capture's atomic op, not a separate spend. Free during onboarding. Economy does not own the 25. |
| **#6 Raid** | both | SINK: `Economy.spend(player, raidSendCostCoins, "raid_send")` to send a team. FAUCET: on win, `Economy.award(player, loot, "raid_loot", raidId)` where `loot = floor(targetPool * raidLootPct)` (§8.3, `raidLootPct`/`targetPool` owned by Raid). Idempotent by `raidId`. |
| **#25 Field Combat / Pet AI** | it → Economy | **NEW v1.2.** FAUCET: on a Pet AI fighter win, Pet AI calls `Economy.award(player, PetCombatConfig.winCoins, "field_combat_win", idemKey)` where `idemKey = "fcw:"..fighterId..":"..wildId` (F-FAUCET-FIELDCOMBAT §8.3). Pet AI OWNS the `winCoins` value (demo `winCoins = 25` in `DemoConfig.combat`; graduates to `PetCombatConfig`); Economy owns the credit + idempotency layer. **No send cost** (`costToSummon = 0`) — pure engagement reward. ⚠VALIDATE total field-combat income stays < 30% of idle's primary faucet at comparable upgrade level (Pet AI density × `winCoins` × win rate vs. idle hourly rate). |
| **#11 Reroll** | it → Economy | SINK: charges `cost(k)` from the LOCKED curve {250,600,1200,2000} (§8.5) as part of the atomic "charge + re-draw personality" op (idempotency-keyed). Reroll owns the count/24h-reset mechanic + odds display; Economy owns the cost values + the debit. |
| **Upgrades / Shop** | it → Economy | SINK: `Economy.spend(player, cost(n), "upgrade_factory" | "upgrade_worker_slot" | "upgrade_storage")` using the geometric curve (§8.4). Server reads current level `n` from persisted upgrade state and computes the authoritative cost (never trusts client price, E7). |
| **Roster slot unlock** | it → Economy | SINK: `Economy.spend(player, cost(n), "slot_unlock")` (§8.6), cap-checked before charging (E10). Grants `slotsPerUnlock` slots up to `rosterCap` 200 (matches persistence). |
| **#10 Auto-Catch** | it → Economy | Auto-Catch's *unlock* is free (at ~50 manual captures, systems-index #10) — no Economy cost for the unlock itself. Its captures reuse `CaptureService.resolveCapture(...,"auto")` which may or may not charge `captureCostCoins` (Auto-Catch's design call, capture-gdd §2.5). Economy is the debit mechanism either way. |
| **#15 Monetization** | it → Economy | FAUCET: the "Meme Coins Pack" DevProduct grants coins via `Economy.award(player, packAmount, "devproduct_pack", PurchaseId)` from inside an idempotent `ProcessReceipt` (double-layer idempotency, E5). GamePass grants (2x-offline → Idle rate multiplier; extra slots → raise capacity; Auto-Catch) are NON-coin grants. **Zero pay-to-win:** no Economy faucet/sink affects raid combat power. |
| **#16 Leaderboard (Richest Manager)** | it → Economy/Persistence | Reads `stats.totalCoinsEarned` (the net-worth value Economy is the sole writer of). The `CoinsChanged` event marks the leaderboard dirty; Persistence writes the OrderedDataStore debounced on save (persistence §2.6, F-LEADERBOARD-WRITE). |
| **#17 Daily Quests** | it → Economy | FAUCET: on quest completion, Daily Quests calls `Economy.award(player, questAmount, "quest_daily", questId)` where `questAmount` is rolled in the per-quest-type `EconomyConfig.questRewards[questType]` range (§8.2, F-FAUCET-QUEST). Idempotent by `questId` (one payout per quest, E5). Daily Quests OWNS the quest set, progress targets, 3/day count, and the server-clock daily reset (`lastQuestReset` in PlayerData, Persistence #1); Economy owns only the reward ranges + the credit. Retention/pacing faucet — kept well below idle as the primary faucet. |
| **#13 UI/HUD** | Economy ↔ it | HUD reads the replicated `coins` mirror; Economy fires `BalanceChanged` (gain/spend animation) + `SpendRejected` ("Meme Coins tidak cukup"). Shops render replicated config prices (read-only); the server is the price authority. |
| **#23 Drama Events (P2)** | it → Economy | OPTIONAL sink: `Economy.spend(player, dramaFixCostCoins, "drama_fix")` to instantly resolve a drama; ALWAYS has a free wait-it-out alternative (ethics lock). |
| **#21 Brain Cells (P2)** | future | `gems` field provisioned default 0; no Economy flow at launch. When Phase 2 ships Brain Cells, Economy adds a parallel premium-wallet API — additive, no `coins` migration. |

**Events emitted (event-driven, per `gameplay-systems.md`):**
- Economy re-uses Persistence's `CoinsChanged` internal event rather than inventing a parallel one (single source of truth for "the wallet moved"). The client-facing `BalanceChanged` / `SpendRejected` remotes are the presentation projection of that event.

---

## Open Questions (for user / monetization-lead / game-designer)

1. **RESOLVED (v1.1): Daily Quests is an MVP system (systems-index #17).** The `quest_daily` faucet pays **on quest completion** (not login streak), with a **per-quest-type reward range** in `EconomyConfig.questRewards` (§8.2) rather than a flat value. Open sub-question for Daily Quests #17 / game-designer: confirm the per-type ranges (capture_n 100–200, win_raids 150–300, collect_x 100–200, evolve_one 200–350) feel right against Idle #3's real rates, and that a full 3-quest day stays below a single big idle-collect (so quests pace, not replace, idle). Note: Daily Quests is a late MVP scope add and a prune candidate — if cut, the fallback daily-login reward reuses this same `quest_daily` faucet (use `questRewardFallbackCoins`).
2. **Raid send cost vs. loot EV.** I recommend `raidSendCostCoins = 100` and `raidLootPct ≈ 0.25` so a fair-skill raid is net-positive (§8.3). Raid #6 owns `lootPct`/`targetPool` — please confirm these recommendations are acceptable so the raid loop is worth doing but not a free coin printer.
3. **Upgrade `growth` tuning (1.35 factory / 1.50 worker / 1.40 storage).** These set how hard the inflation-absorbing treadmill bites. They MUST be reconciled against Idle Production #3's actual production rates (not yet written) so cost rises in step with income. Lock after Idle #3 lands; flagging the dependency now.
4. **Drama fix as a sink (`dramaFixCostCoins` = 200).** Drama Events are Phase 2 (#23). Provisioned now; confirm the value and the always-free-alternative rule when Drama is designed.
5. **"Meme Coins Pack" DevProduct grant amounts.** Owned by Monetization #15, but they directly affect the faucet/sink balance (a too-large pack trivializes the upgrade treadmill). Recommend coordinating pack sizes against the §8.4 cumulative costs (e.g. a pack ≈ one mid-game factory level, not the whole roster cap).
6. **RESOLVED (v1.2): `upgrade_storage` raises the *pending-pool cap* only** — NOT the offline 8h window. Per `idle-production-gdd.md` v1.2 §2.6: `pendingPoolCap = pendingPoolCapBase + pendingCapPerLevel * storageLevel`. The offline 8h window remains fixed at `PersistenceConfig.offlineCapSeconds = 28800` at launch (a separate Phase-2 GamePass lever — see Monetization #15). Economy owns the **cost** of `upgrade_storage` (geometric curve, §8.4); Idle owns the **benefit** (raised pending-pool ceiling so a slow-collect player loses less to overflow). No change to faucets/sinks; clarifies the boundary.
