# Data Persistence & Roster Core GDD

> ⚠️ **POST-PIVOT NOTICE (2026-05-29)**: This GDD survives the Vision Pivot 2026-05-29 with **extension required**: a new **§11 Cross-Place TeleportData Handoff** is needed for multi-place Roblox Universe architecture (per System #27 World Universe). Player state must traverse Lobby ↔ Areas ↔ Super Boss zones ↔ Raid Dungeons ↔ Kandang cleanly. Current §1–§10 content remains canonical and shipped. See `design/decisions/2026-05-29-vision-pivot.md` and `design/gdd/systems-index.md` v3.0 for context.

**Version**: 1.4.1
**Last Updated**: 2026-05-28
**Author**: datastore-architect
**Status**: Draft (pivot-extension pending)

> **Changelog**
> - **1.4.1 (2026-05-28)** — **Phase A cross-system reconciliation note (no schema change, no logic change).** Documents two new MVP consumers of existing persistence-owned data, both shipped in the demo vertical slice (per `design/gdd/systems-index.md` revision 2026-05-28):
>   - **System #25 Field Combat / Pet AI** (`pet-combat-gdd.md` planned; demo `a71e545`) — reads the `roster` map + per-`BrainrotEntry` `personality` / `level` / `xp` / `evoStage` fields to derive a summoned-fighter's combat profile (same data Battle #5 reads, identical access pattern). On a Pet AI win, writes `+xpPerWin` to the participating Brainrot's `xp` via the **same direct `update()` path** Battle uses for Axis B (per `evolution-gdd.md` v1.3 §2.7) — no new `txLog` idempotency key in v1 (acceptable: over-credit XP is low-stakes vs. duplicated currency). No new persisted field is introduced by #25; the `xp`/`level` fields it writes already exist in the v1.4 baseline (§3.2 `BrainrotEntry`). Persistence is unaware of the resolution model (turn-based for #5 vs real-time for #25) — both look identical to the atomic mutation path.
>   - **System #26 Base / Showroom Spatial Layer** (`base-showroom-gdd.md` planned; demo `e984677`) — **reads + writes the same `base.buildings[BUILDING_ID].deployment` map** (added in v1.2 §3.2a) that Idle Production #3 owns. #26 is a pure UX layer (3D pedestals + `ProximityPrompt("Place")`/`Recall` interactions) over Idle's abstract deployment data; the slot-to-Brainrot-id mapping persists through the same `update()` path. No new persisted field is introduced by #26. The cross-system "a Brainrot id occupies at most one slot across all buildings" invariant (§3.2 / Idle §3.1) is upheld because both Idle and #26 write through the atomic path (the in-memory `update()` serializes any race).
>   - **§9 Integration table updated** to include #25 (under "Reads roster / writes xp/level via direct update()") and #26 (under "Reads/writes `base.buildings.deployment` — pure UX wrapper"). Both are *consumers* of v1.4 baseline data; neither requires a schema or migration change.
>   - **No code change required** in `src/ServerStorage/PlayerData/*` from v1.4 → v1.4.1 — this is a pure documentation reconciliation. The shipping `Schema.default()` / `migrate()` / `update()` already support #25 and #26 access without modification.
> - **1.4 (2026-05-26)** — **Receipt-durability + lock-fencing hardening per `docs/architecture/ADR-002-receipt-and-lock-fencing.md` (Accepted, technical-director).** ADR-002 extends ADR-001 (same hybrid A-dominant architecture; no redesign) to close the real-money / anti-dupe findings H-1, H-2, M-2, M-1 that MUST land before Monetization #15 / any live economy:
>   - **§2.3a (H-2)** — `consumedReceipts` is no longer a count-bounded (~100) presence set; it is a **TIMESTAMP map** `{ [purchaseId]: consumedAtUnix }` **pruned by age** (`consumedReceiptHorizonSec`, 60 days) NOT by count, with a `consumedReceiptHardCap` (5000) defense-in-depth overflow trim. The count cap was fundamentally wrong for a set whose required retention is TIME (the redelivery horizon). (ADR-002 §1)
>   - **§2.3a (H-1)** — Added the **save-fail ROLLBACK** rule: `processReceiptGrant` snapshots the live profile (`p.data` + `p.dirty`) BEFORE the grant transaction; on forced-save failure it restores the snapshot (snapshot+restore) so memory equals last durable state and Roblox redelivery re-runs the grant cleanly. The `alreadyGranted` replay path skips the forced save. No drop-then-regrant, no phantom in-memory grant. (ADR-002 §3)
>   - **§2.1 / Session Lock Pattern (M-2)** — Lock value is now `{ jobId, time, gen }`; `gen` is a **monotonic fence token** that increments on every ownership transfer (acquire / stale-steal / mine-reacquire) and is **preserved by heartbeat**. A save now re-verifies durable lock ownership via `ownershipMatches(userId, jobId, gen)` (a read) BEFORE `SetAsync` and **aborts on mismatch or read-failure**, closing the freeze-then-steal divergence dupe. The saved wrapper embeds `lockJobId`/`lockGen` for forensics. (ADR-002 §2)
>   - **§2.1 / Session Lock Pattern (M-1)** — `stopHeartbeat` now **awaits thread death** (`coroutine.status == "dead"`, bounded deadline) before `release()`, so no in-flight heartbeat `UpdateAsync` can resurrect the lock after release. (ADR-002 §4)
>   - **§3.2 schema** — `consumedReceipts` type changes `{ [string]: true }` → `{ [string]: number }` (consumedAt); the durable `StoredWrapper` gains `lockJobId`/`lockGen`; the Profile/runtime gains `lockGen`. Size Estimate updated (timestamp map, horizon-bound; ~400 KB worst case at the 5000 hard cap, realistic < 80 KB; still ≪ 4 MB).
>   - **§8 Config** — Added `consumedReceiptHorizonSec` (5184000 / 60d) and `consumedReceiptHardCap` (5000), plus `heartbeatStopDeadlineSec`; `consumedReceiptsMaxEntries` is **repurposed/renamed** to `consumedReceiptHardCap` (count cap removed as the primary bound).
>   - **Edge cases** — New **E11** (freeze-then-steal fenced by the gen-check on save); **E7** updated (receipt save-fail rollback); **E-receipt / C3-related heartbeat note** updated (heartbeat resurrection closed by await-death).
>   - **§9 #15 Monetization row** — Notes the time-bounded dedupe + save-fail rollback, and that **#15 is BLOCKED** until this rework + the focused re-audit land.
>   - **Acceptance Criteria** — Added: lock fence-token ownership check before save, time-bounded receipt dedupe (horizon + hard cap), receipt save-fail rollback, heartbeat awaits-death.
> - **1.3 (2026-05-26)** — **Mutation-path correction per `docs/architecture/ADR-001-persistence-mutation-path.md` (Accepted, technical-director).** v1.2 over-promised "all economy/roster mutations route through one `UpdateAsync`-based transaction"; the accepted architecture is **hybrid**, and this version replaces that wording everywhere:
>   - **§1 bullet 4 & §2.3** — The authoritative session state lives **in memory under the session lock**, mutated through ONE in-memory `update()` transaction, with periodic/critical durable `SetAsync`. **Cross-server duplication is prevented by the session lock, NOT by per-mutation durability.** `UpdateAsync` is used for the SESSION LOCK only — it is **NOT** used per gameplay mutation. Option B (durable `UpdateAsync` per gameplay mutation) was rejected (an idle game ticks coins continuously; per-tick durable writes blow the `60 + numPlayers*10`/min budget and hit the 6s per-key cooldown). (ADR-001 §Decision)
>   - **§2.2** — Clarified cadence: `autosaveIntervalSec` (300s) is the routine dirty-save cadence; `saveDebounceSec` (7s) is ONLY the per-key write-cooldown floor for critical/final saves, NOT the cadence. (ADR-001 §Rulings)
>   - **§2.3 / new §2.3a** — `txLog` is now a **result map** `{ [key]: storedResult }` (replay returns the prior result), not a string ring buffer. New **§2.3a Durable receipt idempotency** subsection: real-money grants persist `consumedReceipts` and force a durable save before `PurchaseGranted`. (ADR-001 §C2 / §Durable receipt idempotency)
>   - **§3.2 schema** — Added `consumedReceipts: { [string]: true }` (bounded ~100) to `PlayerData`; changed `txLog` type from `{ string }` to the result map. Size estimate still negligible.
>   - **E7 / E9** — E9 reworded to in-memory serialized `update()` + session-lock dupe prevention (not "UpdateAsync serializes them") with the mutator-pcall/rollback guarantee; E7 distinguishes the in-session `txLog` layer from the durable `consumedReceipts` layer for receipts. (ADR-001 §H5 / §C2)
>   - **§9 #15 Monetization row** + **Acceptance Criteria** — reference the durable `consumedReceipts` + forced-save-before-`PurchaseGranted` contract; AC hybrid-wording swap + new criteria (mutator rollback, heartbeat cancel-before-release, BindToClose budget check, 300s autosave cadence, durable receipt idempotency, mock `UpdateAsync` fidelity).
> - **1.2 (2026-05-26)** — Reconciliation with **Idle Production GDD (#3)** (resolves its §3 SCHEMA-UPDATE FLAG):
>   - **Added `base: BaseData` to `PlayerData`** (the factory/deployment block Idle Production owns the *shape* of and Persistence owns the *storage* of). Shape matches `idle-production-gdd.md` §3.1 **exactly**: a `buildings` map (MVP seeds one, `"b1"`) where each `Building` carries the three upgrade levels (`factoryLevel`/`workerSlotLevel`/`storageLevel`, default 0), a `deployment` map (slotIndex→Brainrot `id`), and `walkoutCooldownUntil`; plus base-level `pendingOnline` and `deployedCount`. (§3.2, §3.3 NEW, `Schema.default()`, `migrate()`)
>   - **Added `base.pendingOnline`** — the ONLINE pending sub-accumulator (sibling to the existing `pendingOffline.coins`), so online-earned coins survive a crash before Collect; both slices are summed + zeroed in ONE atomic Collect op (idle §2.3/§2.6). The offline slice stays in `pendingOffline.coins` (unchanged); they are NOT merged into one field — idle §3.2 keeps them as separate persisted fields and we match that.
>   - **Pre-launch decision: `base` is added to the v1 baseline, NOT via a v1→v2 migration.** Because we are pre-production with no live data, the field goes straight into `Schema.default()` / the v1 schema and `CURRENT_SCHEMA_VERSION` stays **1**. The idle GDD's flag *assumed* a v1→v2 step (it didn't know the launch-baseline call); the field *shape* is identical, only the rollout differs. The `migrate()` defensive-backfill still seeds `base` for any partial record, and the `migrate()` path remains in place for genuine POST-launch schema changes. (§3.3, §3.5)
>   - **Size Estimate updated** for the new `base` block (~1 building, a few deployed slots, three small level counters): adds well under 1 KB/player; total worst-case stays ≈ 97–98 KB (≈ 2.4% of 4 MB). (Size Estimate)
>   - **Integration Points §9 #3 row** updated: Idle Production now reads/writes `base` (buildings, upgrade levels, deployment) and `base.pendingOnline` in addition to `pendingOffline`/`lastSeen`/`roster`.
> - **1.1 (2026-05-26)** — Cross-GDD reconciliation pass (applies locked user decisions):
>   - **Canonical field names `id` + `history`.** Renamed the per-Brainrot GUID field `guid → id` and the per-Brainrot counter block `h → history` everywhere (schema, `Schema.newBrainrot`, `migrate()`, prose, size estimate). These are now single canonical names — the old "`h`≡`history` / `id`≡`guid` alias" notes are removed. (§3, §3.4, §3.5, §3.6, Size Estimate, §9)
>   - **Dropped `iv` from the launch schema.** Per-Brainrot IV/innate stats are DEFERRED until the Battle GDD is written; removed from `BrainrotEntry`, `Schema.newBrainrot`, and `migrate()`. Added a note that it is trivially migratable later (add field + default via a v1→v2 `migrate()` step). (§3.2, §3.4, §3.5, Size Estimate)
>   - **Rolling backup key confirmed DEFERRED to post-MVP** (not in MVP design) with rationale (doubles write budget; session-lock + retry + BindToClose already protect the common cases). (E8)
>   - **`freeCapturesOnboarding` deduplicated.** `CaptureConfig` is now the single source of truth (design value); `PersistenceConfig` reads/seeds from it rather than holding a second authoritative copy. (§3.3, §3.5, §8, §9)
>   - **`playtime` accrual on-save confirmed.** Accumulated on each save tick; no separate timer. (§3.2)

> **Parent GDD**: `design/gdd/systems-index.md` — System #1 (Data Persistence & Roster Core, **P0 foundation**).
> **Source of Truth**: `idea/brainrotInc.md` (creative direction); locked context from pre-production brainstorm.
> **Governing standards (NON-NEGOTIABLE)**: `.claude/rules/datastores.md` (session lock, schema versioning, pcall+retry, BindToClose, key-per-UserId, budget, no Instance/function), `.claude/rules/server-scripts.md`, `.claude/rules/config-data.md`, `.claude/rules/design-docs.md`.
> **Depends On**: (none — foundation).
> **Depended On By**: nearly every system — Personality (#2), Idle Production (#3), Capture (#4), Battle (#5), Raid (#6), Raid Shield (#7), Evolution (#8), Economy (#9), Auto-Catch (#10), Reroll (#11), Moment (#12), Monetization (#15), Leaderboard (#16).
>
> **Cross-GDD consistency lock**: This GDD is the **owner** of the player profile, the roster container, the `BrainrotEntry` shape, currency, the `freeCapturesRemaining` counter, the offline-accrual fields, and all anti-dupe machinery. The shapes here are written to be byte-compatible with the contracts asserted by `design/gdd/personality-gdd.md` (v1.1) and `design/gdd/capture-gdd.md` (v1.2), which adopt the same canonical field names (`id`, `history`). Any field those GDDs reference is honored here; see the **Resolution Notes** at the end of Section 3.

---

## 1. Overview & Purpose

Data Persistence & Roster Core is the **single source of truth** for everything a player owns and has progressed: their roster of Brainrots, their Meme Coins, their lifetime stats, their idle/offline state, their raid state, and the anti-duplication ledger. Every other system in Brainrot Inc. reads and mutates player state **through this system's API** — none of them touch `DataStoreService` directly.

It is **P0 (foundation)** because:

1. **Data loss is catastrophic.** Roblox players who lose progress churn permanently and leave 1-star reviews. The session-lock + atomic-write + retry discipline here is what prevents data loss and the duplication exploits that kill an economy.
2. **Every downstream system inherits its schema.** Capture mints a `BrainrotEntry`; Idle Production accrues coins into it; Evolution reads its lifetime counters; Reroll mutates its personality; Economy mutates the wallet. If the schema is not versioned and migratable **on day one**, every later system inherits unpayable debt (you cannot backfill counters you never wrote).
3. **It defines the server-authoritative clock contract.** Idle, shield, and revenge timers all derive from `os.time()` **on the server**. Trusting client time is a duplication/idle-farming exploit; this GDD forbids it everywhere.
4. **It owns the atomic mutation path (hybrid).** The authoritative session state is held **in memory under the session lock**, and every economy/roster mutation is serialized through **ONE in-memory `update()` transaction** with idempotency keys; durable persistence is **periodic/critical `SetAsync`** following the save discipline (§2.2). Cross-server duplication is prevented by the **session lock** (one server owns a profile at a time), **NOT** by per-mutation durability. `UpdateAsync` is used for the **SESSION LOCK** (cross-server compare-and-set) and is **NOT** used per gameplay mutation — a per-tick durable `UpdateAsync` would blow the `60 + numPlayers*10`/min budget on an idle game (ADR-001 §Decision). Concurrent or retried operations (capture + auto-catch racing, a laggy reroll, a re-fired DevProduct receipt) can never double-spend or duplicate because the in-memory `update()` serializes them and idempotency keys de-dupe replays; real-money receipts get an extra **durable** dedupe layer (§2.3a).

This GDD defines: the data lifecycle (lock → load → migrate → play → save → release), the full `PlayerData` schema (with `BrainrotEntry` sub-schema), the session-lock + heartbeat pattern, the migration framework, offline accrual math, the anti-dupe ledger, the MemoryStore usage, the leaderboard net-worth metric, the config surface, and the integration contract every consumer system reads/writes against.

What this GDD does **not** do: it does not implement gameplay (production rates, battle math, capture timing). It owns *where the data lives, how it is read/written safely, and what shape it has* — the **mechanism**, not the gameplay **values**.

---

## 2. Core Mechanics

### 2.1 Data lifecycle (the authoritative path per player session)

```
 PlayerAdded
     │
     ▼
 (1) ACQUIRE SESSION LOCK  ── UpdateAsync on "SessionLocks" store, key "Lock_<UserId>"
     │     ├─ free / mine / stale  → acquire (write {jobId, time, gen}); gen = (existing.gen or 0)+1
     │     │                          (every ownership transfer mints a strictly higher gen — M-2 fence)
     │     │                          acquire returns the minted gen → stored on the Profile as lockGen
     │     └─ held & fresh by other → retry w/ backoff up to lockAcquireMaxAttempts
     │                                 └─ all fail → KICK player ("data in use elsewhere")
     ▼
 (2) START HEARTBEAT  ── every lockHeartbeatSec, refresh lock time so it never goes stale mid-session
     │
     ▼
 (3) LOAD  ── pcall+retry GetAsync on "PlayerData_v1", key "Player_<UserId>"
     │     ├─ found      → wrapper { version, data, savedAt }
     │     ├─ nil (new)  → Schema.default()
     │     └─ all retries fail → DO NOT enter a blank profile; KICK + release lock (E2)
     ▼
 (4) MIGRATE  ── migrate(data) runs version v → CURRENT_SCHEMA_VERSION; repairs invalid records
     │           (Personality.validateOrRepair hooks here per personality-gdd E5)
     ▼
 (5) COMPUTE OFFLINE ACCRUAL  ── using server os.time() and lastSeen (Formula F-OFFLINE, §2.4)
     │           writes into pendingOffline; does NOT auto-collect (pending-collect model)
     ▼
 (6) PLAY  ── data held in-memory (Profile cache). Mutations go through the atomic API.
     │     ├─ DIRTY FLAG set on any mutation
     │     ├─ AUTOSAVE every autosaveIntervalSec IF dirty (debounced)
     │     ├─ CRITICAL-EVENT SAVE on purchase / level-up / reroll / receipt (force, debounced by saveDebounceSec)
     │     └─ EVERY save FENCES (M-2): ownershipMatches(userId, jobId, lockGen) read BEFORE SetAsync;
     │                                 mismatch / read-failure → abort the write (we lost the lock).
     ▼
 PlayerRemoving
     │
     ▼
 (7) STOP HEARTBEAT (await thread death) → FINAL SAVE (set lastSeen = os.time()) → SessionLock.release
     │     strict order (ADR-001 §C3): cancel heartbeat BEFORE release, so a refresh can never
     │     re-write the lock after we let it go. stopHeartbeat now task.cancels AND AWAITS the thread
     │     to reach coroutine.status == "dead" (bounded by heartbeatStopDeadlineSec) before returning,
     │     so no in-flight heartbeat UpdateAsync can resurrect the lock after release (M-1).
     ▼
 (8) RELEASE LOCK + drop cache  (heartbeat already cancelled in step 7)

 game:BindToClose  ── save ALL players in parallel coroutines + release all locks, 25s budget (§2.5, E4)
```

### 2.2 Save discipline (dirty flag + debounce + autosave)

Per `datastores.md` ("Save debouncing with dirty flag", "don't spam saves"):

- Every mutation through the API marks the player's profile **dirty** and stamps `dirtyAt = os.clock()`.
- **Cadence vs. floor (clarified, ADR-001):** `autosaveIntervalSec` (default **300s**) is the **routine dirty-save cadence** — the interval on which the autosave loop persists dirty profiles. `saveDebounceSec` (default **7s**) is **ONLY the per-key write-cooldown floor** for **critical/final** saves (the minimum gap between two actual writes to the same key, ≥ the 6s Roblox cooldown). `saveDebounceSec` is **NOT** the autosave cadence — a critical event may fire a save sooner than 300s, but never closer than `saveDebounceSec` to the previous write.
- The autosave loop (server clock, `task.wait`) **iterates the live `profiles` cache** (the source of truth for who needs saving — ADR-001 §H1, not `Players:GetPlayers()`) and saves a player on each `autosaveIntervalSec` tick **only if dirty**, respecting the `saveDebounceSec` per-key floor (default 7 ≥ the hard 6s cooldown). If the request budget is exhausted, the tick is gated/skipped (ADR-001 §H2).
- **Critical events** (`coins` debit/credit on purchase, level-up, evolution, reroll commit, capture commit, DevProduct receipt grant) request an **immediate** save, still gated by `saveDebounceSec` so we never exceed the per-key cooldown — if a critical save is requested inside the cooldown window, the dirty flag guarantees the next autosave tick (or the deferred flush) persists it.
- A successful write clears the dirty flag and stamps `savedAt`.
- **Playtime accrual on-save (confirmed):** each save adds `(os.time() - lastSeen)` to `stats.playtime` *before* `lastSeen` is refreshed to `now`. Playtime therefore accumulates as a side-effect of the existing save cadence (autosave / critical / PlayerRemoving / BindToClose) — **no separate playtime timer is run.** Because every save advances `lastSeen`, the same delta can never be counted twice.
- **Budget guard**: before a burst (e.g. BindToClose with many players), check `DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync)` and stagger if low. Per-key, per-session traffic is naturally well under the `60 + numPlayers*10`/min budget because each player writes at most ~once per `saveDebounceSec`.

### 2.3 Atomic mutation path (anti-dupe core) — in-memory `update()` under the session lock

All economy/roster mutations are **server-authoritative and atomic**. They are serialized through **ONE in-memory `update()` transaction** — the single place the live profile is ever mutated — while the **session lock** guarantees exactly one server owns that profile at a time. Durable persistence is the periodic/critical `SetAsync` save discipline of §2.2.

**`UpdateAsync` is used for the SESSION LOCK only** (the cross-server compare-and-set that acquires/heartbeats/releases `Lock_<UserId>`); it is **NOT** used per gameplay mutation. Cross-server duplication is prevented by **the session lock, not by per-mutation durability** (ADR-001 §Decision rejects the per-tick durable-`UpdateAsync` path: an idle game ticks coins continuously, so it would immediately blow the `60 + numPlayers*10`/min budget and the 6s per-key cooldown).

`update(player, mutator, idempotencyKey?)` is the **only** mutator of the profile. Its mechanics (ADR-001 §C1/§C2/§H5):

1. **Idempotency check first.** If `idempotencyKey` is present and already in `txLog`, the call is a **no-op that returns the prior stored result** (`(true, storedResult, true)`) — no double-charge, no double-grant.
2. **Run the mutator against a deep copy** of `data` (the transform is **non-yielding**; any network/RNG work happens *before* the call and is passed in — per `datastores.md` "UpdateAsync with yielding callback blocks the queue").
3. **Commit on success only.** On a successful (non-throwing) mutator: swap the copy in as the live profile, **`nextSeq++`**, **record `txLog[idempotencyKey] = storedResult`** (when a key was supplied), and **mark dirty** — each exactly once, only here.
4. **Rollback on throw.** If the mutator errors (it is `pcall`-wrapped), **discard the copy** (no partial state), **do NOT record the key**, and return `(false, "mutation_error", false)`. A throwing mutator therefore commits nothing.

Two devices live inside this transaction:

1. **Monotonic sequence (`nextSeq`)** — every committed mutation increments `nextSeq`. Gives a total order for audit/debug and a cheap "did anything change" check.
2. **Idempotency log (`txLog`)** — a **result map** `{ [key]: storedResult }` (ADR-001 §C2; `storedResult` is a small JSON-safe payload). Any mutation carrying an idempotency key (capture-debit, reroll, DevProduct receipt) consults the map first (see step 1) and, on commit, records its result under the key. Bounded to `txLogMaxEntries` (E7). This is the **in-session** dedupe layer; real-money receipts get an additional **durable** layer (§2.3a).

> **Critical invariant (locked):** capture's "debit coins (or decrement `freeCapturesRemaining`) AND append `BrainrotEntry`" is ONE atomic op (per `capture-gdd.md` §5.1 step 10d); the roster-cap check happens **inside** this same transaction via a pure helper returning a `roster_full` sentinel — the mutator must not debit on that path (ADR-001 §C5). Reroll's "charge AND re-draw personality" is ONE atomic op keyed by an idempotency key (per `personality-gdd.md` E7 / `reroll` notes). A receipt's "grant AND mark consumed" is ONE atomic op (§2.3a). Either both halves commit or neither does — the deep-copy + pcall + rollback guarantees both-or-neither.

### 2.3a Durable receipt idempotency (real-money grants)

Real-money DevProduct grants are the **one narrow carve-out** that cannot rely on the in-session `txLog` alone: a server can die between granting and the next durable save, and Roblox may **re-deliver** the receipt to a fresh server whose in-memory `txLog` is empty. So receipts use a **durable** dedupe marker persisted in the profile.

**Marker is a TIME-bounded timestamp map (H-2, ADR-002 §1), NOT a count-bounded ring.** Roblox redelivers an UNACKED DevProduct receipt **indefinitely** (across sessions, until `PurchaseGranted` is returned). The required retention is therefore defined by **TIME** (the redelivery horizon), not by COUNT — a count cap (the old ~100 ring) can evict a still-redeliverable marker (a whale making >100 purchases between a grant and a redelivery), re-running the grant mutator a second time = a **real-money dupe**. The marker is now:

```lua
consumedReceipts: { [purchaseId: string]: number }   -- value = os.time() (SERVER clock) when consumed
```

- **Pruning is by AGE, not count.** On each consume, drop any entry whose `consumedAt` is older than `now - Config.consumedReceiptHorizonSec`. `consumedReceiptsOrder` (insertion-ordered) keeps this a cheap front-of-list walk (pop the head while its marker is `nil` OR older than the horizon).
- **Horizon = `consumedReceiptHorizonSec` = 5184000 (60 days).** Rationale: Roblox publishes no hard maximum redelivery window; the contract is *until-acknowledged*, which in pathological cases can stretch arbitrarily. We cannot retain forever (4 MB budget), so we pick a horizon that **safely exceeds any realistic redelivery window** (60 days dwarfs any observed redelivery latency by orders of magnitude; a receipt still unacked after 60 days is effectively dead — the player has had 60 days of sessions in which a redelivery would have fired and been acked) while staying tiny on disk. It is config-tunable so ops can raise it without a code change if platform guidance ever tightens.
- **Hard-cap safety (defense-in-depth, NOT the primary bound): `consumedReceiptHardCap` = 5000.** If, *after* time-pruning, the map STILL exceeds 5000 entries (only reachable by an absurd purchase rate inside the 60-day horizon — pathological/abuse), trim oldest-first beyond 5000 and log a `consumed_receipts_overflow` incident. This deterministically caps worst-case key size; under any sane load it never triggers.
- **Migration:** existing/in-flight profiles whose `consumedReceipts` values are boolean `true` (the old presence set) are defensively backfilled in `migrate()` to a numeric timestamp (`wrapper.savedAt` or `os.time()`) so they are NOT immediately pruned. Pre-launch with no real-money data, so a no-op in practice; `CURRENT_SCHEMA_VERSION` stays **1** (consistent with §3.2a — the field went into the v1 baseline directly).

`ProcessReceipt` flow (`processReceiptGrant`, ADR-001 §Durable receipt idempotency + ADR-002 §3):

1. If the player's profile is **not loaded** → return `Enum.ProductPurchaseDecision.NotProcessedYet` (Roblox retries later).
2. **Snapshot BEFORE the grant (H-1):** take `snapshot = deepCopy(p.data)` and `wasDirty = p.dirty` on the LIVE profile, pre-grant.
3. `update(player, mutator, "receipt_" .. purchaseId)`: the mutator checks `consumedReceipts[purchaseId]` — if set (a **replay** / `alreadyGranted`), return the stored result without re-granting; otherwise apply the grant **and stamp `consumedReceipts[purchaseId] = os.time()`** (with the prune + hard-cap trim above) in the same transaction. Grant + consumed-marker commit **atomically in one key under the session lock**.
   - **On the `alreadyGranted` replay path, SKIP the forced save** — the marker is already durable (that is *why* the replay fired), so return `(true, result)` without a needless write.
4. **Force a durable save** (fenced by M-2; see §2.1 / Session Lock Pattern), and return `PurchaseGranted` **only if that save succeeds**; otherwise return `NotProcessedYet`. Returning `PurchaseGranted` without a confirmed durable write is **forbidden** — on redelivery the durable `consumedReceipts` marker dedupes the grant.
5. **On forced-save FAILURE — ROLLBACK (H-1):** restore `p.data = snapshot` and `p.dirty = wasDirty`, then return `(false, "save_failed")`. Both the in-memory grant **AND** the `consumedReceipts` marker are gone, so memory equals last durable state; Roblox redelivers and the next attempt re-runs the grant cleanly (and, once a save succeeds, the durable marker dedupes future redeliveries). **No drop-then-regrant, no phantom in-memory grant.** A reversing mutator is rejected because the grant mutator is opaque (Monetization #15 supplies it); snapshot+restore is exact and simple. If the forced save was **fenced out** (we lost the lock — M-2), `saveProfile` returns `false`, which triggers this same rollback (correct: we lost authority, so we must not claim the grant; the authoritative server re-runs it on redelivery).

Persistence builds the hook (`processReceiptGrant`, the snapshot + forced-save-before-ack + rollback mechanism); Monetization #15 wires the `MarketplaceService.ProcessReceipt` callback to it.

### 2.4 Offline accrual (server clock only, pending-collect)

Idle Production (#3) owns production *rates*; Persistence owns the *clock and the pending pool*. On load (lifecycle step 5):

```
F-OFFLINE — offline accrual on load

  now            = os.time()                         -- SERVER clock, never client
  elapsedRaw     = now - data.lastSeen               -- seconds offline (data.lastSeen is server-stamped)
  elapsed        = clamp(elapsedRaw, 0, offlineCapSeconds)
                     -- clamp low at 0 (E5 negative/clock-skew); clamp high at offlineCapSeconds (8h)
  ratePerSecond  = IdleProduction.computeOfflineRate(data.roster, data.base)   -- owned by #3; reads roster + deployment server-side
  accrued        = floor(ratePerSecond * elapsed)    -- integer coins
  data.pendingOffline.coins  += accrued
  data.pendingOffline.from    = data.lastSeen        -- window start (for the recap UI)
  data.pendingOffline.to      = data.lastSeen + elapsed
  -- lastSeen is refreshed to `now` only on SAVE (step 7), not here, so a failed load cannot eat time.

Where:
  offlineCapSeconds : config, default 28800 (= 8 hours). Range 3600..172800.
  ratePerSecond     : computed by Idle Production from the persisted roster + base.deployment
                      (server-authoritative; only DEPLOYED Brainrots produce; personality multipliers
                      are recomputed live, NOT stored — see personality-gdd §2.4).
```

- **Pending-collect model**: accrued coins land in `pendingOffline`, not the wallet. The player taps "Collect" (Idle Production / UI surfaces it); on collect, an atomic op moves `pendingOffline.coins` into `coins`, zeroes the pending pool, and (for the leaderboard) bumps `stats.totalCoinsEarned` (§2.6). Until collected, the pending pool persists across sessions (it is part of `PlayerData`), so a crash before collect never loses the reward.
- **Why clamp at 0**: if `lastSeen` is somehow in the future (clock skew across regions, or a tampered legacy value), `elapsedRaw` is negative; we floor accrual at 0 rather than subtract coins (E5).
- **2x offline GamePass** (Monetization #15) multiplies `ratePerSecond` or `accrued` — that multiplier is owned by Monetization/Idle config, applied inside `computeOfflineRate`; Persistence only supplies `elapsed` and the pending pool.

### 2.5 Shutdown (BindToClose)

`game:BindToClose` saves **all** connected players in parallel coroutines and releases their locks, bounded by `bindToCloseBudgetSec` (default 25; Roblox grants ~30). This is the race-condition guard `datastores.md` mandates: PlayerRemoving alone is insufficient because a server shutdown may not fire it reliably for every player. See §"Session Lock" and §"BindToClose" patterns below and E4.

### 2.6 Net worth & leaderboard write (Richest Manager, #16)

**Net-worth metric decision (LOCKED): `stats.totalCoinsEarned` — lifetime gross Meme Coins earned — NOT current balance.**

Justification (trade-offs weighed):

| Candidate metric | Pro | Con | Verdict |
|---|---|---|---|
| **Current balance** (`coins`) | Simplest; "how rich are you right now" | **Punishes engagement** — spending on reroll/raids/captures *lowers* your rank. Encourages hoarding (anti-sink, bad for economy). Volatile (rank yo-yos on every purchase). | Rejected |
| **Lifetime coins earned** (`stats.totalCoinsEarned`) | **Monotonic non-decreasing** → rank only goes up, never punishes spending; rewards total engagement; stable; aligns with "Richest Manager" = most successful manager over time. | Doesn't reflect a frugal saver's stash. | **CHOSEN** |
| Net worth = balance + valued roster | "Truest" wealth | Requires a per-Brainrot valuation model that doesn't exist in MVP; expensive to compute; couples leaderboard to Evolution/species values. | Deferred to Phase 2 (Fame infra) |

`stats.totalCoinsEarned` is incremented on **every coin credit** (idle collect, raid loot, future sources) and **never decremented by sinks**. This makes it the natural OrderedDataStore value.

**When the leaderboard is written (debounced, NOT per-tick):**

```
F-LEADERBOARD-WRITE

  Write OrderedDataStore "Leaderboard_RichestManager_v1", key "Player_<UserId>",
        value = data.stats.totalCoinsEarned          -- numeric value stored directly (NOT nested)

  Trigger: piggy-backs on the normal player SAVE (lifecycle step 6 autosave / step 7 final save),
           and ONLY when totalCoinsEarned changed since the last leaderboard write
           (tracked by data.stats._lbLastWritten cache, in-memory).
  Never written on a per-production-tick basis (would exhaust OrderedDataStore budget).
  Reads: GetSortedAsync(false, topN) on a refresh timer (leaderboardRefreshSec) cached server-side
         and replicated to clients; clients NEVER query OrderedDataStore.
```

OrderedDataStore shares the same `60 + numPlayers*10`/min budget as DataStore and the same 6s per-key cooldown — piggy-backing on the existing save cadence keeps it within budget for free.

---

## 3. Data Schema

The persisted value is a **single key per player**: store `PlayerData_v1`, key `"Player_" .. player.UserId` (≤ 50 chars; a UserId is at most 10 digits so `Player_` + UserId ≤ 17 chars — well within limit). The stored value is a **wrapper** carrying the schema version, the data payload, and a save timestamp.

### 3.1 The stored wrapper

```lua
-- What actually goes into DataStore via the durable SetAsync save (§2.2). (UpdateAsync is used
-- ONLY for the session lock, NOT for this payload write — ADR-001 §Decision.)
type StoredWrapper = {
    version: number,   -- schema version of `data`; == CURRENT_SCHEMA_VERSION after migrate()
    data: PlayerData,  -- the payload below
    savedAt: number,   -- os.time() (server) at write; for debugging / "last saved" UI
    -- FENCE STAMP (M-2, ADR-002 §2): which lock generation wrote this value. Belt-and-suspenders —
    -- the PRIMARY fence is the pre-write ownershipMatches read in saveProfile; these embedded fields
    -- let any forensic/future load path detect or audit a backward-generation (stale-writer) write.
    lockJobId: string?,  -- the JobId that held the lock at write time
    lockGen: number?,    -- the monotonic lock generation (see Session Lock Pattern) at write time
}
```

### 3.2 `PlayerData` (the payload) — full commented Luau

```lua
-- ServerStorage/PlayerData/Schema.lua
--
-- The authoritative persisted shape for one player of Brainrot Inc.
-- ONE key per UserId. NEVER store Instances or functions (DataStore serializes tables only).
-- Every field has a type, a default, and a comment. Designers/engineers edit defaults via
-- PersistenceConfig (Section 8) where a value is a tunable; structural defaults live here.
-- Schema version: 1  (see CURRENT_SCHEMA_VERSION + migrate(), Section "Migration")

export type Personality = "Hyper" | "Lazy" | "Chaotic" | "Loyal" | "Rebel"  -- personality-gdd §3.1

-- ── BrainrotEntry: one owned Brainrot. Keyed in `roster` by its own `id` (GUID). ──
-- Shape is the CONTRACT consumed by Capture (#4), Personality (#2), Idle (#3),
-- Battle (#5), Raid (#6), Evolution (#8), Reroll (#11). See Resolution Notes (§3.6).
export type BrainrotEntry = {
    -- Unique per Brainrot. HttpService:GenerateGUID(false), minted server-side at capture.
    -- This is the roster map key as well. NEVER reused.
    id: string,                 -- default: generated at capture (no static default)

    -- Numeric species id (NOT a display name string). Maps to a species config table.
    -- Numeric so renames/localization never break saved data. Range: 1..(species count).
    species: number,            -- default: set at capture from spawn record (capture-gdd §3.3)

    -- Personality enum. The ONLY personality data persisted (personality-gdd §3.1).
    -- Derived multipliers are recomputed live, never stored.
    personality: Personality,   -- default: Personality.roll() at capture; repaired on load if invalid (E-PERS)

    -- Progression.
    level: number,              -- default 1.   Range 1..maxLevel (Battle/Evolution config own the cap)
    xp: number,                 -- default 0.    Lifetime/accumulated XP toward next level. >= 0
    evoStage: number,           -- default 0.    Evolution stage; 0 = base. Evolution (#8) advances it.

    -- NOTE: per-Brainrot IV / innate battle stats are DEFERRED to when the Battle GDD is written
    -- (no `iv` field at launch — see §3.2 deferral note). Trivially migratable later via a v1->v2
    -- migrate() step (add field + default), so omitting it now costs nothing.

    -- Lifetime history / counters for THIS Brainrot. Wired day-1 (cheap now, expensive to
    -- backfill) so Evolution (#8) + multi-branch Evolution (P2) have the data they need.
    -- Sub-keys are intentionally short to keep the value small at roster cap 200 (see Size Estimate).
    history: {
        coins: number,          -- default 0.  Lifetime Meme Coins this Brainrot has produced (Idle #3 increments)
        rdef: number,           -- default 0.  Raids DEFENDED (this Brainrot was on defense) (Raid #6)
        rwon: number,           -- default 0.  Raids WON (this Brainrot was on the winning attack team) (Raid #6)
        fame: number,           -- default 0.  Fame contribution (provisioned for Fame/Trending P2; 0 at launch)

        -- Capture provenance (capture-gdd §3.3 seeds these at mint; analytics + flavor).
        capturedAt: number,     -- default os.time() at capture (server clock)
        captureSource: string,  -- default "manual".  "manual" | "auto"  (capture-gdd)
        hotspotId: string,      -- default "".  Where it was caught (flavor + analytics)
    },

    -- Favorite flag: LOCKS this Brainrot from auto-release / bulk-release tools.
    fav: boolean,               -- default false
}

-- ── DEFERRED (intentional): per-Brainrot IV / innate battle stats. ──
-- There is deliberately NO `iv` field at launch. Per-Brainrot stat rolls (atk/def/hp/spd or
-- whatever the Battle model lands on) are designed WHEN the Battle GDD (#5) is written, so the
-- shape matches Battle's actual needs instead of guessing now. Adding it later is trivial and
-- non-destructive: one additive v1->v2 step in migrate() (`entry.iv = entry.iv or <default>`),
-- backfilling every existing roster entry on load. No data is lost by omitting it today.

-- ── BaseData / Building: the factory + deployment block (Idle Production #3). ──
-- Idle Production OWNS this SHAPE (idle-production-gdd.md §3.1); Persistence OWNS the storage +
-- the atomic write path. Reproduced here VERBATIM-COMPATIBLE so the schema is self-contained;
-- if the two ever diverge, idle-production-gdd.md §3.1 is the source of truth for field
-- names/forms and this block is corrected to match (no contradiction permitted — design-docs.md).

-- One factory building the player owns. MVP ships exactly one ("b1").
export type Building = {
    -- Stable building id (also the string key in BaseData.buildings). MVP: "b1".
    id: string,                         -- default "b1" for the starting building

    -- UPGRADE LEVELS (0-based; n=0 means "first upgrade purchased", matches Economy §8.4).
    -- Each maps 1:1 to an Economy cost track; Idle reads the level, Economy computes cost(n).
    -- These are the upgrade levels persisted per economy-gdd.md §3.2 / §8.4.
    factoryLevel: number,               -- default 0.  upgrade_factory level.       Range 0..30 (Economy maxLevel)
    workerSlotLevel: number,            -- default 0.  upgrade_worker_slot level.    Range 0..10
    storageLevel: number,               -- default 0.  upgrade_storage level.        Range 0..12
                                        --   storageLevel raises the PENDING-POOL CAP (idle §2.6):
                                        --   pendingPoolCap = pendingPoolCapBase + pendingCapPerLevel*storageLevel.
                                        --   It does NOT change the offline 8h window (that is PersistenceConfig
                                        --   .offlineCapSeconds, fixed at launch). The cap bounds base.pendingOnline
                                        --   + pendingOffline.coins combined (accrual stops at the cap, idle E2).

    -- DEPLOYMENT MAP: worker-slot index (1..currentSlotCount) -> BrainrotEntry.id (GUID) | nil.
    -- Sparse map; an absent/nil slot is empty. A Brainrot id appears in AT MOST one slot across
    -- ALL buildings (invariant enforced on deploy). currentSlotCount = startingWorkerSlots + workerSlotLevel
    -- (Idle config). Key is tostring(slotIndex) so it serializes as a JSON-safe string-keyed map.
    deployment: { [string]: string? },  -- default {}.  key = tostring(slotIndex); value = Brainrot id or nil

    -- WALKOUT COOLDOWN: server os.time() until which this building may not re-trigger a Rebel Walkout
    -- (Personality walkoutCooldownSeconds, personality E2 / idle E5). 0 = no cooldown active.
    walkoutCooldownUntil: number,       -- default 0
}

-- The whole base.
export type BaseData = {
    -- Map of buildings keyed by building id. MVP seeds exactly one ("b1").
    buildings: { [string]: Building },  -- default { b1 = Schema.defaultBuilding("b1") }

    -- ONLINE pending sub-accumulator (sibling of pendingOffline.coins, which holds the OFFLINE slice).
    -- Persists so a crash before Collect never loses online-earned coins. Collected together with
    -- pendingOffline.coins in ONE atomic award (idle §2.3/§2.6). Bounded with pendingOffline.coins
    -- by the storage-derived pending-pool cap (>= 0, <= pendingPoolCap).
    pendingOnline: number,              -- default 0

    -- Cached count of currently-deployed Brainrots across all buildings (O(1) UI / cap checks).
    -- Invariant: == total non-nil entries across every building's deployment map.
    deployedCount: number,              -- default 0
}

-- ── PlayerData: the whole player profile. ──
export type PlayerData = {

    -- ROSTER — a MAP keyed by GUID (NOT an array). Map form gives O(1) add/remove/lookup by id
    -- and avoids index-shuffle bugs on release. Capacity enforced via rosterCount + rosterCap.
    roster: { [string]: BrainrotEntry },   -- default {} (empty)

    -- Cached count of entries in `roster`. Kept in sync on every add/remove so we never
    -- pay an O(n) pairs() count on the hot path (cap checks, UI). Invariant: rosterCount == #keys(roster).
    rosterCount: number,                    -- default 0.   Range 0..rosterCap (200)

    -- CURRENCY.
    coins: number,                          -- default 0.   Meme Coins (soft currency). >= 0. Server-authoritative.
    gems: number,                           -- default 0.   Premium "Brain Cells" — PROVISIONED, UNUSED at launch
                                            --              (forward-compat per systems-index #9/#20). No UI yet. >= 0.

    -- ONBOARDING — free capture counter (capture-gdd §3.3.1). Persisted so free catches survive
    -- a relog and can't be farmed by rejoining. Seeded on profile creation from the SINGLE source
    -- of truth, CaptureConfig.freeCapturesOnboarding (Persistence only reads/seeds — see §3.6 / §8).
    freeCapturesRemaining: number,          -- default = CaptureConfig.freeCapturesOnboarding (3). Floored at 0.

    -- IDLE / OFFLINE (server clock only; pending-collect model — §2.4).
    lastSeen: number,                       -- default os.time() at creation. Server os.time() of last SAVE.
                                            --   Used to compute offline elapsed on next load.
    pendingOffline: {                       -- Accrued-but-uncollected OFFLINE rewards. Persists until collected.
        coins: number,                      --   default 0.  Coins waiting to be collected (offline slice).
        from: number,                       --   default 0.  Window start (lastSeen at accrual) — for recap UI.
        to: number,                         --   default 0.  Window end (clamped) — for recap UI.
    },

    -- FACTORY / DEPLOYMENT (Idle Production #3 owns the SHAPE; Persistence owns the storage + atomic
    -- writes). Shape is byte-compatible with idle-production-gdd.md §3.1 (BaseData/Building). See §3.3.
    -- NOTE: the ONLINE pending slice lives inside this block (base.pendingOnline), the sibling of
    -- pendingOffline.coins above — both are summed + zeroed in ONE atomic Collect op (idle §2.6).
    base: BaseData,                         -- default Schema.defaultBase(): one building "b1", 0 levels.

    -- RAID state (Raid #6 / Raid Shield #7).
    -- Shield expiry is AUTHORITATIVE in MemoryStore (cross-server, TTL); this is a MIRROR for
    -- offline display / fast reads. On conflict, MemoryStore wins (E-SHIELD).
    shieldUntil: number,                    -- default 0.  os.time() the raid shield expires (mirror).
    -- Revenge window is AUTHORITATIVE in DataStore (must survive 24h across sessions/servers).
    revengeTarget: string?,                 -- default nil. UserId (as string) the player may counter-raid.
    revengeUntil: number,                   -- default 0.  os.time() the 24h revenge window closes.
    raidsWon: number,                       -- default 0.  Lifetime raids won (player-level total).
    raidsDefended: number,                  -- default 0.  Lifetime successful defenses (player-level total).

    -- ANTI-DUPE LEDGER (§2.3).
    nextSeq: number,                        -- default 1.  Monotonic mutation counter; ++ per committed mutation.
    -- IN-SESSION idempotency: a RESULT MAP keyed by idempotency key (ADR-001 §C2). On replay,
    -- update() returns the stored result instead of re-applying. storedResult is a small JSON-safe
    -- payload. Bounded to txLogMaxEntries (E7). NOT the durable receipt layer (that is consumedReceipts).
    txLog: { [string]: any },               -- default {}. { [idempotencyKey] = storedResult } (was { string } pre-v1.3).
    -- DURABLE receipt idempotency (real money, §2.3a). Marks a Roblox PurchaseId as consumed so a
    -- re-delivered ProcessReceipt on a fresh server (empty in-memory txLog) cannot double-grant.
    -- TIMESTAMP MAP (H-2, ADR-002 §1): value = os.time() when consumed. Pruned by AGE (older than
    -- consumedReceiptHorizonSec ~60d), NOT by count — a count cap could evict a still-redeliverable
    -- marker = real-money dupe. consumedReceiptHardCap (5000) is a defense-in-depth overflow trim only.
    -- Marker + the grant commit atomically in ONE update() under the session lock; a durable save is
    -- FORCED before PurchaseGranted, and on save-fail the grant + marker are ROLLED BACK (§2.3a).
    consumedReceipts: { [string]: number },  -- default {}. { [purchaseId] = consumedAtUnix }, age-pruned (60d horizon), hard-capped 5000.

    -- GLOBAL STATS (lifetime; leaderboard + analytics + Evolution player-level milestones).
    stats: {
        totalCoinsEarned: number,           -- default 0.  Lifetime GROSS coins earned (NEVER decremented).
                                            --             THIS is the leaderboard "net worth" value (§2.6).
        playtime: number,                   -- default 0.  Total seconds played. ACCRUED ON SAVE: each save
                                            --             adds (now - lastSeen) before lastSeen is refreshed.
                                            --             No separate timer needed (§2.2 / §3.6).
        lifetimeCaptures: number,           -- default 0.  Total successful captures (Auto-Catch unlock @50, capture-gdd §3.4).
        -- _lbLastWritten is an IN-MEMORY cache, NOT persisted (see note); listed for clarity only.
    },

    -- PLAYER SETTINGS — free-form map (sound, notifications, low-graphics, etc.).
    -- Values must be JSON-safe scalars/tables (no Instances/functions).
    settings: { [string]: any },            -- default {} (empty)

    -- Profile bookkeeping.
    createdAt: number,                      -- default os.time() at first creation. Never changes.
}
```

> **Ephemeral, NOT persisted (documented explicitly):**
> - **Personality runtime state machine** (`Working` / `OnBreak` / `Walkout`, timers, `draggedInBy`, `lastCycleOutcome`) — per `personality-gdd.md` §3.2, this is **server-memory only, re-initialized to `Working` on every load**. Persistence stores ONLY the `personality` enum on each `BrainrotEntry`. Break/Walkout are short-lived flavor, not save-worthy.
> - **Live capture spawn records** (`capture-gdd.md` §3.2) — server memory only.
> - **In-flight battle/raid combat state** — server memory only; only *results* (loot into wallet, `history.rwon`/`history.rdef`, player `raidsWon`/`raidsDefended`) persist.
> - **`stats._lbLastWritten`** — in-memory leaderboard-debounce cache; recomputed each session.
> - **`lockGen`** (Profile/runtime, M-2) — the monotonic lock **generation** this server acquired for the player (returned by `SessionLock.acquire`; default sentinel `1` in `_setProfileForTest`). Held on the live Profile (NOT inside `PlayerData`), used to fence every save via `ownershipMatches(userId, jobId, lockGen)` before `SetAsync`, and embedded into the stored wrapper (`lockJobId`/`lockGen`, §3.1) for forensics. Re-acquired fresh each load; never persisted in the payload.

### 3.2a `base` (BaseData) — factory / deployment block (Idle Production #3)

`base` is the persisted factory/deployment state. **Idle Production (#3) owns its *shape*** (defined in `idle-production-gdd.md` §3.1); **Persistence owns its *storage* and the atomic write path.** It is reproduced in the schema above so the persisted shape is self-contained. The two GDDs are byte-compatible; if they ever diverge, `idle-production-gdd.md` §3.1 is the source of truth and this block is corrected to match (no contradiction permitted, per `design-docs.md`).

- **`buildings: { [string]: Building }`** — a map of factory buildings keyed by `Building.id`. **MVP seeds exactly one** (`"b1"`, via `Schema.defaultBuilding`). Additional buildings are forward-compat (gated behind a factory-tier milestone, idle §2.1); the map form means adding one later is a pure data write, no migration.
- **`Building.factoryLevel` / `workerSlotLevel` / `storageLevel`** — the three **upgrade levels** persisted here (0-based, default 0 at profile creation). Each maps 1:1 to an Economy cost track (`upgrade_factory` / `upgrade_worker_slot` / `upgrade_storage`, `economy-gdd.md` §3.2/§8.4): Idle reads the current level `n` from `base`, Economy computes the authoritative `cost(n)`, and on a successful spend Idle increments the level here (a critical-event save). Ranges (Economy `maxLevel`): factory 0..30, worker-slot 0..10, storage 0..12.
- **`Building.deployment: { [string]: string? }`** — the **deployment map**: worker-slot index (`tostring(slotIndex)`) → the occupying `BrainrotEntry.id` (a roster GUID), or absent/`nil` for an empty slot. The number of usable slots is `startingWorkerSlots + workerSlotLevel` (Idle config). **Invariant:** a Brainrot `id` occupies at most one slot across *all* buildings (enforced on deploy, idle §3.1). Keys are stringified so the map serializes JSON-safely.
- **`Building.walkoutCooldownUntil: number`** — server `os.time()` until which this building may not re-trigger a Rebel Walkout (Personality `walkoutCooldownSeconds`, personality E2 / idle E5). `0` = no cooldown.
- **`base.pendingOnline: number`** — the **ONLINE pending sub-accumulator**, the sibling of `pendingOffline.coins` (which holds the OFFLINE slice). It persists so a crash before Collect never loses online-earned coins. On Collect both slices are summed, deposited in one `Economy.award(... "idle_collect")`, and zeroed in **one atomic op** (idle §2.3/§2.6). They are deliberately **two separate persisted fields**, not merged — matching idle §3.2.
- **`base.deployedCount: number`** — cached count of currently-deployed Brainrots across all buildings (O(1) UI / cap checks). Invariant: equals the total non-`nil` entries across every building's `deployment` map.

> **Storage cap interaction (idle §2.6, documented in-schema):** `storageLevel` raises the **pending-pool cap** — `pendingPoolCap = pendingPoolCapBase + pendingCapPerLevel * storageLevel` (IdleConfig). That cap bounds `base.pendingOnline + pendingOffline.coins` *combined*; when the pool reaches the cap, accrual **stops** (overflow discarded, idle E2) until the player collects. `storageLevel` does **NOT** change the offline 8h window — that is `PersistenceConfig.offlineCapSeconds`, fixed at launch (idle's storage-upgrade decision, closing Economy Open Question #6). Persistence owns `offlineCapSeconds`; Idle owns `pendingPoolCap`.

> **Pre-launch baseline (v1.2):** `base` is added to the **v1 schema baseline**, not via a v1→v2 migration — we are pre-production with no live data, so `CURRENT_SCHEMA_VERSION` stays **1** and the field ships in `Schema.default()`. The idle GDD §3 flag assumed a v1→v2 step; that is the correct pattern for a *post-launch* addition, but pre-launch we ship it in the baseline with the same field shape. See §3.5.

### 3.3 `Schema.default()`

```lua
-- ServerStorage/PlayerData/Schema.lua  (continued)
local CURRENT_SCHEMA_VERSION = 1

-- Default factory/deployment builders (idle-production-gdd.md §3.1). Idle owns the shape;
-- Persistence calls these from Schema.default() and the migrate() defensive backfill.
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
        buildings = { b1 = Schema.defaultBuilding("b1") },   -- MVP: one starting building
        pendingOnline = 0,
        deployedCount = 0,
    }
end

-- Returns a fresh, fully-populated profile for a brand-new player.
-- Seeds freeCapturesRemaining from the single source of truth, CaptureConfig.freeCapturesOnboarding.
function Schema.default(): PlayerData
    local now = os.time()
    return {
        roster = {},
        rosterCount = 0,

        coins = 0,
        gems = 0,                                   -- provisioned, unused at launch

        freeCapturesRemaining = CaptureConfig.freeCapturesOnboarding,  -- single source of truth (default 3)

        lastSeen = now,
        pendingOffline = { coins = 0, from = 0, to = 0 },

        base = Schema.defaultBase(),                -- factory/deployment block (Idle #3); v1 baseline (pre-launch)

        shieldUntil = 0,
        revengeTarget = nil,
        revengeUntil = 0,
        raidsWon = 0,
        raidsDefended = 0,

        nextSeq = 1,
        txLog = {},                                 -- result map { [idempotencyKey] = storedResult } (ADR-001 §C2)
        consumedReceipts = {},                      -- durable receipt dedupe { [purchaseId] = consumedAtUnix }, age-pruned 60d / hard-cap 5000 (§2.3a)

        stats = {
            totalCoinsEarned = 0,
            playtime = 0,
            lifetimeCaptures = 0,
        },

        settings = {},

        createdAt = now,
    }
end

-- The wrapper Schema.default() is stored inside:
--   { version = CURRENT_SCHEMA_VERSION, data = Schema.default(), savedAt = os.time() }
```

### 3.4 `BrainrotEntry.new()` (the mint Capture calls)

```lua
-- ServerStorage/PlayerData/Schema.lua  (continued)
-- Builds a new entry. Called inside the atomic capture commit (capture-gdd §5.1 step 10d).
-- species + personality + source + hotspotId are supplied by Capture; id is minted here.
function Schema.newBrainrot(args: {
    species: number, personality: Personality, source: string, hotspotId: string,
}): BrainrotEntry
    return {
        id = game:GetService("HttpService"):GenerateGUID(false),
        species = args.species,
        personality = args.personality,
        level = 1,
        xp = 0,
        evoStage = 0,
        -- no `iv` at launch (deferred to Battle GDD; added later via migrate() v1->v2)
        history = {
            coins = 0, rdef = 0, rwon = 0, fame = 0,
            capturedAt = os.time(),
            captureSource = args.source,              -- "manual" | "auto"
            hotspotId = args.hotspotId,
        },
        fav = false,
    }
end
```

### 3.5 Migration framework

```lua
-- ServerStorage/PlayerData/Schema.lua  (continued)
-- Runs on EVERY load, upgrading data v -> CURRENT_SCHEMA_VERSION. Each step is forward-only,
-- idempotent, and additive where possible. NEVER delete data in a migration without a backup window.
local CURRENT_SCHEMA_VERSION = 1

function Schema.migrate(data: any): PlayerData
    data.version = data.version or 1   -- legacy/untagged data is treated as v1

    -- PRE-LAUNCH NOTE (v1.2): the factory/deployment block `base` (BaseData) was added DIRECTLY to
    -- the v1 baseline, NOT via a v1->v2 step, because this is pre-production with NO live data to
    -- migrate. CURRENT_SCHEMA_VERSION therefore stays 1. The idle-production-gdd.md §3 flag assumed a
    -- v1->v2 migration; that was the right call for a POST-launch addition, but pre-launch we simply
    -- ship it in the baseline (identical field shape, no migration needed). The defensive backfill
    -- below still seeds `base` for any partial/older-build record. The migrate() ladder remains the
    -- mechanism for any genuine POST-launch schema change.

    -- v1 is the launch schema; no migration steps yet. Future (post-launch) jumps go here, e.g.:
    --
    -- if data.version == 1 then
    --     -- v1 -> v2 example: split a future "premiumFlags" out of settings.
    --     data.premiumFlags = data.premiumFlags or {}
    --     data.version = 2
    -- end
    -- if data.version == 2 then
    --     -- v2 -> v3 example: rename a BrainrotEntry field across the whole roster.
    --     for _, entry in pairs(data.roster) do
    --         entry.newField = entry.oldField or default
    --         entry.oldField = nil
    --     end
    --     data.version = 3
    -- end

    -- Defensive backfill (runs every load; cheap, makes partial/corrupt records valid):
    data.roster        = data.roster or {}
    data.rosterCount   = data.rosterCount or _countKeys(data.roster)   -- self-heal cache
    data.coins         = data.coins or 0
    data.gems          = data.gems or 0
    data.freeCapturesRemaining = data.freeCapturesRemaining or CaptureConfig.freeCapturesOnboarding
    data.pendingOffline = data.pendingOffline or { coins = 0, from = 0, to = 0 }
    -- Factory/deployment block (Idle #3, idle §3.1). v1 baseline; backfilled here for any partial record.
    data.base          = data.base or Schema.defaultBase()
    data.base.buildings = data.base.buildings or { b1 = Schema.defaultBuilding("b1") }
    data.base.pendingOnline = data.base.pendingOnline or 0
    data.base.deployedCount = data.base.deployedCount or 0
    for bid, building in pairs(data.base.buildings) do
        building.id = building.id or bid
        building.factoryLevel    = building.factoryLevel or 0
        building.workerSlotLevel = building.workerSlotLevel or 0
        building.storageLevel    = building.storageLevel or 0
        building.deployment      = building.deployment or {}
        building.walkoutCooldownUntil = building.walkoutCooldownUntil or 0
    end
    data.txLog         = data.txLog or {}            -- result map (v1.3); a pre-v1.3 array value is harmlessly replaced/ignored
    data.consumedReceipts = data.consumedReceipts or {}   -- durable receipt dedupe map (§2.3a)
    -- H-2 defensive backfill (ADR-002 §1): convert any legacy presence-set entry (boolean `true`)
    -- to a numeric timestamp so it is NOT immediately age-pruned. Pre-launch this is a no-op; it
    -- keeps the code honest if any partial/older-build record carried the old { [id] = true } shape.
    for pid, v in pairs(data.consumedReceipts) do
        if type(v) ~= "number" then
            data.consumedReceipts[pid] = data.savedAt or os.time()   -- conservative "consumed recently" stamp
        end
    end
    data.nextSeq       = data.nextSeq or 1
    data.stats         = data.stats or { totalCoinsEarned = 0, playtime = 0, lifetimeCaptures = 0 }
    data.settings      = data.settings or {}

    -- Per-Brainrot repair: Personality.validateOrRepair re-rolls an invalid/missing enum
    -- (personality-gdd E5) and we ensure the history block exists. (No `iv` at launch — when the
    --  Battle GDD adds it, a v1->v2 step above will backfill `entry.iv = entry.iv or <default>`.)
    for id, entry in pairs(data.roster) do
        entry.id = entry.id or id
        entry.personality = Personality.validateOrRepair(entry)      -- hook into Personality (#2)
        entry.level   = entry.level or 1
        entry.xp      = entry.xp or 0
        entry.evoStage = entry.evoStage or 0
        entry.history = entry.history or { coins = 0, rdef = 0, rwon = 0, fame = 0,
                                     capturedAt = os.time(), captureSource = "manual", hotspotId = "" }
        entry.fav     = entry.fav or false
    end

    data.version = CURRENT_SCHEMA_VERSION
    return data
end
```

> **Migration safety rule:** if `migrate()` itself errors (corrupt/unexpected structure it cannot repair), the load path treats it as a failed load — it does **NOT** overwrite the player's key with a blank profile. See E8.

### 3.6 Resolution Notes (cross-GDD consistency)

These reconcile naming/shape between this GDD and the two GDDs that reference these structures. **No contradictions are introduced** (per `design-docs.md` forbidden pattern). Canonical field names are locked by user decision.

1. **`history` (canonical, single name).** The per-Brainrot counter/provenance block is named **`history`** (full word) in all three GDDs — there is no short alias. It contains BOTH the lifetime counters (`coins`, `rdef`, `rwon`, `fame`) AND the capture-provenance fields Capture asserts (`capturedAt`, `captureSource`, `hotspotId`). Capture's "lifetime production / raids survived / defends" map to `history.coins` / `history.rwon` (and the player-level `raidsDefended`) / `history.rdef`. (User decision: one canonical name, `history`; the former short `h` key is retired.)
2. **`id` (canonical, single name).** The unique per-Brainrot GUID field is named **`id`** in all three GDDs (it is also the roster map key) and holds the GUID minted by `HttpService:GenerateGUID(false)`. (User decision: one canonical name, `id`; the former `guid` field name is retired. `capture-gdd.md` v1.2 and `personality-gdd.md` v1.1 read/write `entry.id`.)
3. **`level=1, history seeded` on capture** — honored exactly (`Schema.newBrainrot`).
4. **`freeCapturesRemaining`** — owned here, but seeded on profile creation from the SINGLE source of truth `CaptureConfig.freeCapturesOnboarding` (default 3) — `PersistenceConfig` no longer holds a duplicate authoritative value, it only reads it. Decremented by Capture inside the atomic capture commit; matches `capture-gdd.md` §3.3.1 byte-for-byte.
5. **Personality persists only the enum**; runtime state machine is ephemeral — matches `personality-gdd.md` §3.1/§3.2 exactly.
6. **Roster cap 200 enforced inside the roster service AND re-checked by Capture** — matches `capture-gdd.md` §3.3 "defense in depth."

---

## 4. Client-Server Split

| Concern | Server (authoritative) | Client (presentation only) |
|---|---|---|
| `DataStoreService` / `MemoryStoreService` / `OrderedDataStore` access | **YES — exclusively.** | **NEVER.** No client code touches any store. |
| Session lock acquire/heartbeat/release | YES | Never (client cannot know JobIds) |
| Load / migrate / save | YES | Never |
| Offline accrual computation | YES (server `os.time()`, server roster) | Receives the pending-collect amount for the recap UI |
| Wallet (`coins`/`gems`) mutation | YES (atomic, validated) | Sees a **read-only mirror** for the HUD |
| Roster add/remove/mutate | YES (atomic, capped) | Sees a **read-only mirror** of entries |
| `nextSeq` / `txLog` / idempotency | YES | Never sees them (internal, not replicated) |
| Net-worth / leaderboard write | YES | Sees a cached top-N list (server-fetched) |
| Settings write | YES (validated) | Sends intent to change a setting; sees the applied result |
| Server clock (`os.time()`) for all timers | YES | Client time is **never trusted** for idle/shield/revenge |

**Authority rule (locked):** the server owns the truth; the client holds a **read-only mirror** built from validated, whitelisted fields. The client never receives `txLog`, `nextSeq`, raw lock data, or another player's private profile. Any client-supplied number (a claimed balance, a claimed offline time, a claimed roster) is ignored — consumers read server state. There is **no DataStore code on the client**, period (`datastores.md`, `server-scripts.md`).

---

## 5. RemoteEvents / Functions

Persistence is primarily an **internal server service** (`PlayerDataService`). Its network surface exists only to replicate the read-only mirror to the owning client and to accept narrow, validated intents. **No Instances or functions are ever sent.** Replication is **delta-based** to stay bandwidth-conscious (a coin tick should not resend the whole roster). Detailed wire formats may be refined by `remotes-networking-specialist`; all remotes are registered centrally in `ReplicatedStorage/Shared/Remotes` and documented in the remotes manifest.

### 5.1 Server → Client

| Remote | Type | Payload | Purpose |
|---|---|---|---|
| `DataReplicated` | RemoteEvent | `{ full: ProfileMirror }` | **Initial sync** after load+migrate completes. One full snapshot of the whitelisted mirror (wallet, roster summaries, stats, pendingOffline, shieldUntil, revenge window, freeCapturesRemaining, settings). Fired once per load. |
| `DataDelta` | RemoteEvent | `{ changes: { [path: string]: any }, removed: { string }? }` | **Incremental update** for any subsequent change. Sends ONLY changed paths (e.g. `{ ["coins"] = 1450 }`, or `{ ["roster.<id>"] = <entryMirror> }`), and a `removed` list of roster ids (GUIDs) to drop. Keeps bandwidth proportional to what changed, not to roster size. |
| `OfflineRewardReady` | RemoteEvent | `{ coins, from, to }` | Tells the client to show the offline-collect screen with the pending amount + window (the recap "while you were gone…"). Fired on load if `pendingOffline.coins > 0`. |
| `SaveStatus` | RemoteEvent | `{ state: "saving" \| "saved" \| "error", at: number }` | Drives the tiny save indicator (§6). `at` is server `os.time()`. |
| `LeaderboardSnapshot` | RemoteEvent | `{ entries: { { userId, name, value, rank } }, refreshedAt }` | Server-fetched top-N Richest-Manager list (clients never query OrderedDataStore). |

```lua
-- ProfileMirror: the WHITELISTED, client-safe projection of PlayerData. NOTE the deliberate
-- omissions: no txLog, no nextSeq, no raw lock data. Roster entries are sent as compact mirrors.
type BrainrotMirror = {
    id: string, species: number, personality: string,
    level: number, evoStage: number, fav: boolean,
    -- xp/history sent only if a UI surface needs them (roster detail), otherwise omitted to save bandwidth.
}
type ProfileMirror = {
    coins: number, gems: number,
    rosterCount: number,
    roster: { [string]: BrainrotMirror },
    freeCapturesRemaining: number,
    pendingOffline: { coins: number, from: number, to: number },
    shieldUntil: number, revengeTarget: string?, revengeUntil: number,
    raidsWon: number, raidsDefended: number,
    stats: { totalCoinsEarned: number, playtime: number, lifetimeCaptures: number },
    settings: { [string]: any },
}
```

### 5.2 Client → Server

| Remote | Type | Payload | Validation |
|---|---|---|---|
| `CollectOfflineRequest` | RemoteEvent | `{}` (no args — server reads its own pending pool) | Rate-limited (1/sec); server moves `pendingOffline.coins` → `coins` atomically, zeroes pending, bumps `totalCoinsEarned`, fires `DataDelta`. Idempotent: a second collect with an empty pool is a no-op. |
| `UpdateSettingRequest` | RemoteEvent | `{ key: string, value: <scalar> }` | Rate-limited; `key` must be in a server-side **settings whitelist**; `value` must be a JSON-safe scalar within the key's allowed domain. Anything else dropped. |

> **No Client→Server `RemoteFunction`** (server-hang risk per project remotes policy). Per `server-scripts.md`: every handler validates every argument, rate-limits, and the server never trusts a client-claimed amount. Persistence has **no remote that lets a client name a coin amount, a roster entry, or a timer** — those mutations are caused only by gameplay systems server-side (Capture, Idle, Raid, etc.) which validate their own intents.

### 5.3 Internal server events (not network — cross-system decoupling)

| Event | Payload | Fired When | Listened By |
|---|---|---|---|
| `ProfileLoaded` | `{ player, data }` | After load+migrate+accrual, before play | Idle (#3), Personality (#2 init runtime), Monetization (#15 reconcile pending receipts), Onboarding (#14) |
| `ProfileSaving` / `ProfileSaved` | `{ player, ok }` | Around each durable write | Analytics, SaveStatus replication |
| `CoinsChanged` | `{ player, newBalance, delta, reason }` | After an atomic wallet mutation | UI mirror, Leaderboard (mark dirty), Analytics |

---

## 6. Player-Facing UI

Persistence renders very little directly; most state surfaces through consumer-owned panels (the HUD wallet, the roster manager). Persistence-owned surfaces are the **trust/safety** ones:

1. **Save indicator** — a tiny, unobtrusive icon (a small cloud/disk) in a corner of the HUD. States from `SaveStatus`: idle (hidden), `saving` (subtle spinner), `saved` (brief checkmark), `error` (amber dot + "Saving… retrying"). Never blocks gameplay; reassures the player their progress is safe.
2. **"Data in use elsewhere" screen** — if session-lock acquisition fails after all retries (the player is active on another server), show a full-screen, kid-friendly modal: **"Your game is open in another place. Close it and rejoin in a moment."** then the client is disconnected gracefully (E1). Never silently drop into a blank profile.
3. **Offline-collect screen** — on load with `pendingOffline.coins > 0`, a celebratory "While you were gone…" recap: shows the time window (`from`→`to`, capped at 8h with a "capped at 8h" note if it hit the cap), the coins earned, and a big **Collect** button (fires `CollectOfflineRequest`). Idle/Moment GDDs may enrich it with a personality recap reel; the *coin collect* itself is Persistence-driven.
4. **Load-failure / retry screen** — if load fails (DataStore down, E2), a friendly "Having trouble loading your save — retrying…" screen with an automatic retry, and a graceful kick if it ultimately fails (never enter a blank profile that would later overwrite real data).

All surfaces are pure presentation reading replicated state / dedicated remotes. Mobile-first, no per-frame work.

---

## 7. Edge Cases & Error States

Minimum-5 requirement exceeded (covers `design-docs.md`'s zero/max/negative/rapid/lag/disconnect/datastore-down/concurrent checklist).

### E1 — Session lock held by another server (stale vs. active)
**Trigger:** PlayerAdded; `Lock_<UserId>` already exists.
**Behavior:** `SessionLock.acquire` distinguishes:
- **Mine** (`existing.jobId == game.JobId`): re-acquire (same server, e.g. fast rejoin) — allowed.
- **Stale** (`os.time() - existing.time >= lockStaleSeconds`, default 90): the owning server is presumed dead (it stopped heartbeating); steal the lock, write ours, proceed — but log `lock_stolen` for analytics. The stale window (90s) is comfortably larger than `lockHeartbeatSec` (30s) so a *live* server's lock never looks stale (it refreshes every 30s; three missed beats ⇒ truly dead).
- **Active** (held & fresh by another JobId): retry with backoff up to `lockAcquireMaxAttempts`. If still held, **kick** the player with the "data in use elsewhere" screen (§6 item 2). We NEVER load over an active lock — that is the data-duplication exploit `datastores.md` exists to prevent.

### E2 — DataStore down at LOAD (after lock acquired)
**Trigger:** lock acquired, but `GetAsync` fails all `loadMaxAttempts` retries.
**Behavior:** **Do NOT enter a blank profile.** Release the lock, show the load-failure/retry screen, and **kick** the player after the final failure. Entering a default profile and later saving it would **erase the real save** — catastrophic. A new player (genuine `nil` from a successful read) is different and DOES get `Schema.default()`; the distinction is *successful read returning nil* (new player) vs *read failed* (kick/retry).

### E3 — Save fails repeatedly during play
**Trigger:** autosave / critical-event durable `SetAsync` fails repeatedly.
**Behavior:** retry with exponential backoff (`2^attempt`, capped) up to `saveMaxAttempts`. The dirty flag is **not** cleared until a write succeeds, so the next autosave tick retries automatically — no data is silently dropped. `SaveStatus("error")` shows the amber indicator. The in-memory profile remains the source of truth for the live session; PlayerRemoving + BindToClose make a final attempt. If ALL attempts (including shutdown) fail, the loss is bounded to changes since the last successful save (≤ one autosave interval) and is logged as a `save_failed` incident (escalate to technical-director per the data-loss protocol).

### E4 — BindToClose timeout
**Trigger:** server shutting down with many players; saves may not all finish in Roblox's ~30s window.
**Behavior:** `game:BindToClose` launches one coroutine per player (parallel save + lock release), then waits up to `bindToCloseBudgetSec` (default 25). Players whose save completes release their lock; any that don't finish keep their lock, which then ages out via `lockStaleSeconds` (E1) so the player can rejoin elsewhere without being permanently locked. Budget is checked first; if `GetRequestBudgetForRequestType` is low, saves are still attempted (shutdown is the last chance) but staggered. This is the race-condition guard PlayerRemoving alone cannot provide.

### E5 — Server clock skew / negative offline elapsed
**Trigger:** `lastSeen` is in the future relative to the loading server's `os.time()` (cross-region skew, or a tampered legacy value).
**Behavior:** `elapsedRaw` is negative; `F-OFFLINE` clamps `elapsed = clamp(elapsedRaw, 0, offlineCapSeconds)` so accrual floors at **0** (never subtract coins, never grant >8h). All idle/shield/revenge math uses **server `os.time()` only**; client time is never an input, so a client cannot inflate offline time. Logged as `clock_skew` if `elapsedRaw < -clockSkewToleranceSec`.

### E6 — Roster at the cap (200)
**Trigger:** an add (capture/auto-catch) when `rosterCount == rosterCap`.
**Behavior:** the atomic add op checks `rosterCount < rosterCap` **inside** the transaction and rejects with `roster_full` if not — no entry written, no coins charged (Capture orders the cap check before the debit, `capture-gdd.md` §5.1 step 10a/§7.1). `rosterCount` is the cached counter (kept exactly in sync on every add/remove), so the check is O(1) and cannot drift; `migrate()` self-heals the cache from the actual map on load. A `fav`-locked entry is never auto-released to make room — freeing a slot is an explicit player action.

### E7 — `txLog` grows unbounded
**Trigger:** a player makes many idempotent mutations (captures, rerolls, purchases) over a long session/lifetime.
**Behavior:** `txLog` is a **result map** `{ [key]: storedResult }` (§2.3, ADR-001 §C2) **bounded to `txLogMaxEntries`** (default 50; oldest entries pruned on insert). This is the **in-session** idempotency layer — it lives with the in-memory profile and covers the realistic retry/replay horizon for an in-flight transaction (seconds to minutes). It bounds both value size (50 small JSON-safe results ≈ small) and lookup cost.
**Two-layer model for receipts:** real-money receipts do **NOT** rely on `txLog` alone, because a server can die before the next durable save and Roblox may re-deliver the receipt to a fresh server whose in-memory `txLog` is empty. Receipts therefore also use the **durable** layer `consumedReceipts` (§2.3a) persisted in the profile — now a **TIMESTAMP map pruned by AGE** (`consumedReceiptHorizonSec` ≈ 60 days), NOT a ~100 count cap (H-2, ADR-002 §1; a count cap could evict a still-redeliverable marker = real-money dupe), with the `consumedReceiptHardCap` (5000) overflow trim as defense-in-depth: the grant + the consumed-marker commit atomically in one `update()` under the session lock, and a durable save is **forced before `PurchaseGranted`** is returned. **Roblox `ProcessReceipt` redelivery is handled by this durable map** — a redelivered `PurchaseId` finds its marker and dedupes without re-granting. (`txLog` = in-session layer; `consumedReceipts` = durable layer for receipts.)
**Receipt save-fail ROLLBACK (H-1, ADR-002 §3):** `processReceiptGrant` snapshots the live profile (`p.data` + `p.dirty`) **before** the grant transaction; if the forced durable save **fails** (DataStore error, retries exhausted, OR a fence-out because we lost the lock — M-2), it **restores the snapshot** (`p.data = snapshot`, `p.dirty = wasDirty`) and returns `(false, "save_failed")`. Both the in-memory grant **AND** the `consumedReceipts` marker are reverted, so memory equals last durable state; Roblox redelivers and the next attempt re-runs the grant cleanly (and once a save succeeds, the durable marker dedupes future redeliveries). **No drop-then-regrant, no phantom in-memory gems.** The `alreadyGranted` replay path skips the forced save entirely (the marker is already durable). See §2.3a steps 2–5.

### E8 — Corrupt data / migration failure
**Trigger:** loaded value is structurally corrupt or `migrate()` throws.
**Behavior:** the whole load is wrapped in `pcall`. If `migrate()` errors, treat it as a **failed load** (E2 path): do **NOT** overwrite the key with a default profile, release the lock, retry/kick. Recoverable corruption (missing fields, bad enum, count drift) is **repaired** by the defensive backfill + `Personality.validateOrRepair` in `migrate()` (it doesn't throw for those). For unrecoverable corruption, the key is preserved untouched for manual recovery and the incident is escalated (data-loss protocol → technical-director).

> **Rolling backup key — DEFERRED to post-MVP (user decision, locked).** A common hardening pattern is to write a rolling backup copy (separate key and/or version stamp) on each save so a corrupt primary can be rolled back. This is **explicitly NOT part of the MVP design.** Rationale: (1) it roughly **doubles the write budget** (every save becomes two writes / two per-key cooldowns), which is the scarcest DataStore resource; (2) the session-lock + pcall-retry + BindToClose discipline already prevents the overwhelming majority of loss/corruption scenarios (no load-over-active-lock, no blank-over-failed-read E2, dirty flag never cleared until a write succeeds E3); (3) unrecoverable corruption already leaves the key untouched for manual recovery. Revisit as a post-MVP hardening item if production telemetry shows a meaningful corruption rate; do not build it for launch.

### E9 — Concurrent atomic mutations on the same profile (double-spend / dupe attempt)
**Trigger:** two operations hit the same player's wallet/roster near-simultaneously (manual capture + auto-catch, remote spam slipping past rate limits, a re-fired receipt).
**Behavior:** all mutations go through the **single in-memory `update()` transaction** (§2.3), which **serializes** them on the one server that owns the profile; the second sees the post-first state. **Cross-server** double-spend/dupe is prevented by the **session lock** (one server owns the profile at a time) — **not** by per-mutation durability; `UpdateAsync` serializes only the lock, never gameplay mutations. Operations carrying an idempotency key are de-duped via the `txLog` result map (a replayed key returns the prior result, no second effect); real-money receipts add the durable `consumedReceipts` layer (§2.3a / E7).
**Mutator rollback guarantee (ADR-001 §H5):** each `update()` runs the mutator (`pcall`-wrapped) against a **deep copy** of the profile and commits — swap-in + `nextSeq++` + `txLog` record + mark-dirty — **only on success**. A **throwing mutator commits nothing**: the copy is discarded, no partial state is left, the idempotency key is **not recorded** (so a legitimate retry can succeed cleanly), and the call returns `(false, "mutation_error", false)`. Net: no double-spend, no duplicated Brainrot, no double-grant, and no half-applied compound op — the invariant from `capture-gdd.md` §5.1 ("the atomic op serializes them and the loser sees `insufficient_coins`/`roster_full` cleanly") holds at the Persistence layer.

### E10 — MemoryStore vs DataStore shield disagreement
**Trigger:** `shieldUntil` mirror in DataStore disagrees with the authoritative MemoryStore shield entry (e.g. a shield was extended on another server).
**Behavior:** **MemoryStore is authoritative for the active shield** (cross-server, TTL-based); the DataStore `shieldUntil` is a best-effort mirror for offline display and fast reads. On any conflict, read MemoryStore. The DataStore mirror is refreshed from MemoryStore on load and on save. `revengeTarget`/`revengeUntil`, by contrast, are **DataStore-authoritative** because the 24h window must survive across sessions/servers/restarts where a MemoryStore entry (max 45-day TTL but volatile) is the wrong tool.

### E11 — Server freeze + foreign lock-steal (the freeze-then-steal divergence dupe) — FENCED
**Trigger:** server A's game thread keeps mutating a profile in memory while its **heartbeat dies** (A is frozen/GC-stalled but not yet shut down). After `lockStaleSeconds` (90s) the lock looks stale, server B **steals** it (minting a strictly higher `gen`) and loads the last **durable** snapshot. Both A and B now hold divergent live state for the same profile.
**Behavior (M-2 fence, ADR-002 §2):** every save **re-verifies durable lock ownership before `SetAsync`** via `SessionLock.ownershipMatches(userId, jobId, lockGen)` — a read that returns true only if the durable lock still reads OUR `jobId` AND OUR `gen`. When A unfreezes and tries to save its divergent state, the durable lock reads `{ jobId_B, gen_B }` (B out-generations A's stored `lockGen`), so A's fence **mismatches and the save is aborted** (returns `false`, **no write**, logged `save_fenced_out`). A's divergent snapshot dies with A; B is the single authority and saves normally with its higher `gen`. **No last-writer-wins dupe.** A **failed fence read** is treated as cannot-prove-ownership and also fences out (money-safe: a missed save is recoverable via the dirty flag + next tick; a divergent write is not). For a receipt grant, the fenced-out `false` triggers the §2.3a H-1 rollback, so the grant is not claimed and redelivery re-runs it on the authoritative server. The residual TOCTOU window between the fence read and the `SetAsync` is inherent to any fence and negligible here (gen monotonicity + the 90s stale window ≫ save latency).
**Heartbeat resurrection (M-1) — also closed:** `stopHeartbeat` now `task.cancel`s the heartbeat thread **and awaits `coroutine.status == "dead"`** (bounded by `heartbeatStopDeadlineSec`) before `release()` runs, so no in-flight heartbeat `UpdateAsync` can land after release and re-stamp (resurrect) the freed lock. Even a pathological late beat only refreshes `time` for OUR jobId (heartbeat refuses a foreign jobId and preserves `gen`) and is moot once the cache is dropped — self-heals, no cross-server dupe.

---

## 8. Balancing Parameters

All tunables live in `PersistenceConfig`. **Zero magic numbers in code** — every number below is read from this table. These are operational/safety knobs (not gameplay balance), but they are still externalized per `config-data.md`. Store/key names are config so a wipe-and-restart or environment split (dev/prod) doesn't require code edits.

```lua
-- src/ServerStorage/PlayerData/PersistenceConfig.lua
--
-- Operational config for Data Persistence & Roster Core (System #1).
-- Edited by engineers (and ops). These are SAFETY/THROUGHPUT knobs, not gameplay balance.
-- NEVER ship to the client. Schema version: 1
return {
    version = 1,

    -- ── STORE / KEY NAMES (config so env splits + wipes don't need code edits) ──
    -- DataStore name for the player profile. Bump the suffix for a hard schema reset (rare).
    dataStoreName = "PlayerData_v1",
    -- DataStore name for session locks.
    lockStoreName = "SessionLocks",
    -- OrderedDataStore name for the Richest Manager leaderboard (§2.6).
    leaderboardStoreName = "Leaderboard_RichestManager_v1",
    -- Key prefix for a player profile: prefix .. UserId. Result must be <= 50 chars.
    -- "Player_" (7) + max UserId (10 digits) = 17 chars. Safe.
    keyPrefix = "Player_",
    -- Key prefix for a session lock: prefix .. UserId.
    lockKeyPrefix = "Lock_",

    -- ── SAVE CADENCE ──
    -- Autosave interval per player while dirty. Recommended ~5 min (datastores.md).
    -- Range: 60-600 | Default: 300 (5 min) — balances data-loss window vs budget.
    autosaveIntervalSec = 300,
    -- Minimum seconds between two ACTUAL writes to the same key (>= 6s Roblox cooldown).
    -- Range: 6-60 | Default: 7 (just above the hard 6s per-key write cooldown).
    saveDebounceSec = 7,
    -- Max save attempts (retry w/ exponential backoff) before giving up this cycle.
    -- Range: 1-10 | Default: 5 (per datastores.md save pattern).
    saveMaxAttempts = 5,
    -- Backoff base for retries: wait = backoffBaseSec ^ attempt (capped by backoffMaxSec).
    -- Range: 1.5-3.0 | Default: 2.0
    backoffBaseSec = 2.0,
    -- Cap on a single backoff wait so retries don't stall too long.
    -- Range: 4-30 | Default: 16
    backoffMaxSec = 16,

    -- ── LOAD ──
    -- Max GetAsync attempts at load before kicking (NEVER load a blank over a failed read, E2).
    -- Range: 1-10 | Default: 5
    loadMaxAttempts = 5,

    -- ── SESSION LOCK ──
    -- Seconds after which a lock with no heartbeat is considered STALE/dead and stealable (E1).
    -- MUST be comfortably > lockHeartbeatSec (default >= 3x) so a live server is never seen stale.
    -- Range: 45-300 | Default: 90
    lockStaleSeconds = 90,
    -- How often the owning server refreshes its lock timestamp (heartbeat).
    -- Range: 10-60 | Default: 30  (3 missed beats -> stale at 90s)
    lockHeartbeatSec = 30,
    -- Retry attempts to acquire a lock held & fresh by another server before kicking (E1).
    -- Range: 1-10 | Default: 5
    lockAcquireMaxAttempts = 5,
    -- Backoff (seconds) between lock-acquire attempts.
    -- Range: 0.5-5 | Default: 1.5
    lockAcquireBackoffSec = 1.5,
    -- Max seconds stopHeartbeat will SPIN awaiting the heartbeat thread to reach
    -- coroutine.status == "dead" after task.cancel, before logging heartbeat_stop_timeout and
    -- proceeding (M-1, ADR-002 §4). Purely defensive — the stop flag + cancel already prevent a
    -- post-resume re-stamp; this guarantees we OBSERVE death rather than assume it, without letting a
    -- pathological stuck thread hang shutdown. Spin granularity is task.wait(0.05).
    -- Range: 0.5-5 | Default: 2 (2s deadline).
    heartbeatStopDeadlineSec = 2,

    -- ── SHUTDOWN ──
    -- Seconds BindToClose waits for parallel saves (Roblox grants ~30; leave headroom).
    -- Range: 10-29 | Default: 25
    bindToCloseBudgetSec = 25,

    -- ── OFFLINE ACCRUAL ──
    -- Hard cap on offline accrual window (§2.4, F-OFFLINE).
    -- Range: 3600-172800 | Default: 28800 (= 8 hours, per locked context).
    offlineCapSeconds = 28800,
    -- If lastSeen is more than this far in the FUTURE, log a clock_skew incident (E5).
    -- Range: 5-300 | Default: 60
    clockSkewToleranceSec = 60,

    -- ── ROSTER ──
    -- Max Brainrots a player may own (MVP). Enforced atomically (E6); capture-gdd asserts 200.
    -- Range: 50-1000 | Default: 200 (MVP). Raising it later is a pure config change (watch size, §"Size Estimate").
    rosterCap = 200,

    -- ── ANTI-DUPE LEDGER ──
    -- Max idempotency keys retained in the txLog result map (oldest pruned on insert) (E7).
    -- Range: 10-500 | Default: 50 (covers realistic in-flight retry horizon; keeps value small).
    txLogMaxEntries = 50,

    -- DURABLE RECEIPT DEDUPE (real money, §2.3a / ADR-002 §1).
    -- Retention HORIZON for consumedReceipts markers — the durable receipt dedupe set is pruned by
    -- AGE, not count. MUST safely exceed Roblox's (unbounded, until-acked) redelivery window; 60 days
    -- dwarfs any observed redelivery latency while staying tiny on disk. Config-tunable so ops can
    -- raise it if platform guidance ever tightens — no code change.
    -- Range: 604800 (7d) - 31536000 (365d) | Default: 5184000 (= 60 days).
    consumedReceiptHorizonSec = 5184000,
    -- DEFENSE-IN-DEPTH overflow safety cap on consumedReceipts entries (NOT the primary bound — that
    -- is the horizon). If the map STILL exceeds this after time-pruning (only reachable by an absurd
    -- purchase rate inside the horizon / abuse), trim oldest-first and log consumed_receipts_overflow.
    -- REPLACES the old consumedReceiptsMaxEntries (~100 count cap, removed — a count cap could evict a
    -- still-redeliverable marker = real-money dupe; retention is a TIME property, ADR-002 §1).
    -- Range: 1000-20000 | Default: 5000 (~400 KB worst case; never triggers under sane load).
    consumedReceiptHardCap = 5000,

    -- ── ONBOARDING ──
    -- (No freeCapturesOnboarding value here.) The number of free onboarding captures is owned
    -- SOLELY by CaptureConfig.freeCapturesOnboarding (capture-gdd §8.2) — the single source of
    -- truth. Persistence READS that value to seed profile.freeCapturesRemaining on profile creation
    -- (Schema.default / migrate backfill). Duplicating it here is forbidden (would risk drift).

    -- ── LEADERBOARD ──
    -- Top-N entries fetched for the Richest Manager board.
    -- Range: 10-100 | Default: 50
    leaderboardTopN = 50,
    -- Seconds between server-side leaderboard GetSortedAsync refreshes (cached + replicated).
    -- Range: 30-600 | Default: 120
    leaderboardRefreshSec = 120,
}
```

### Formulas (explicit)

- **F-OFFLINE** — offline accrual: see §2.4 (clamped to `[0, offlineCapSeconds]`, server clock).
- **F-LEADERBOARD-WRITE** — leaderboard value & write trigger: see §2.6 (value = `stats.totalCoinsEarned`, written on save-when-changed).
- **F-LOCK-STALE** — a lock is stale iff `os.time() - existing.time >= lockStaleSeconds`. Liveness guaranteed by heartbeat: a live owner refreshes every `lockHeartbeatSec`; staleness requires ≥ `lockStaleSeconds / lockHeartbeatSec` (≈3) consecutive missed beats.
- **F-BACKOFF** — retry wait on attempt `n`: `wait = min(backoffBaseSec ^ n, backoffMaxSec)`.

---

## Session Lock Pattern (acquire / heartbeat / release / fence)

Conforms to `datastores.md`. Distinguishes mine / stale / active (E1). The lock value carries a
**monotonic generation `gen`** — a **fence token** (M-2, ADR-002 §2) that lets a save prove it still
owns the profile at write time and forces a stale writer to lose.

**Lock value shape:** `{ jobId = <string>, time = <unix>, gen = <number> }`. `gen` increments on
**every ownership transfer** (free-acquire / stale-steal / mine-reacquire — all bump); **heartbeat
does NOT bump it** (it refreshes `time` only, preserving `gen`). Existing legacy lock values with no
`gen` are treated as `gen = 0` and the next acquire bumps to `1`.

```lua
-- ServerStorage/PlayerData/SessionLock.lua
local DataStoreService = game:GetService("DataStoreService")
local lockStore = DataStoreService:GetDataStore(PersistenceConfig.lockStoreName)
local jobId = game.JobId

-- Returns (acquired: boolean, gen: number?). The caller (PlayerDataService) stores the returned
-- gen on the Profile as lockGen and fences every save with it (ownershipMatches, below).
function SessionLock.acquire(userId: number): (boolean, number?)
    local key = PersistenceConfig.lockKeyPrefix .. userId
    for attempt = 1, PersistenceConfig.lockAcquireMaxAttempts do
        local mintedGen
        local ok, result = pcall(function()
            return lockStore:UpdateAsync(key, function(existing)
                local now = os.time()
                if existing
                   and existing.jobId ~= jobId
                   and (now - existing.time) < PersistenceConfig.lockStaleSeconds then
                    return nil          -- ACTIVE on another server: refuse (UpdateAsync keeps old value)
                end
                -- free / mine / stale -> take it. Every ownership write mints a strictly higher gen
                -- (atomic compare-and-set inside the UpdateAsync transform -> cross-server-correct).
                mintedGen = (existing and existing.gen or 0) + 1
                return { jobId = jobId, time = now, gen = mintedGen }
            end)
        end)
        if ok and result ~= nil and result.jobId == jobId then
            return true, result.gen
        end
        task.wait(PersistenceConfig.lockAcquireBackoffSec)  -- task.* per server-scripts.md (no wait())
    end
    return false   -- caller KICKS the player (E1)
end

function SessionLock.heartbeat(userId: number)   -- called every lockHeartbeatSec while in session
    local key = PersistenceConfig.lockKeyPrefix .. userId
    pcall(function()
        lockStore:UpdateAsync(key, function(existing)
            if existing and existing.jobId ~= jobId then return nil end  -- don't clobber a stealer
            -- PRESERVE gen (M-2): heartbeat refreshes time only, never bumps the generation.
            return { jobId = jobId, time = os.time(), gen = existing and existing.gen or nil }
        end)
    end)
end

-- FENCE READ (M-2): true iff the DURABLE lock currently reads OUR jobId AND OUR gen. A pcalled
-- GetAsync (READ, not write — a separate, ample budget bucket from the write bucket, affordable as
-- one extra read per debounced save). A FAILED read returns false (cannot-prove-ownership -> fence
-- out -> money-safe: a missed save is recoverable via the dirty flag; a divergent write is not).
function SessionLock.ownershipMatches(userId: number, ownJobId: string, ownGen: number): boolean
    local key = PersistenceConfig.lockKeyPrefix .. userId
    local ok, existing = pcall(function() return lockStore:GetAsync(key) end)
    if not ok then return false end                       -- read failure -> fence out
    return existing ~= nil and existing.jobId == ownJobId and existing.gen == ownGen
end

function SessionLock.release(userId: number)
    local key = PersistenceConfig.lockKeyPrefix .. userId
    pcall(function()
        lockStore:UpdateAsync(key, function(existing)
            if existing and existing.jobId ~= jobId then return existing end  -- only release OUR lock
            return nil   -- RemoveAsync-equivalent: clear it
        end)
    end)
end
```

**Save fence (M-2) — `saveProfile` re-verifies ownership BEFORE `SetAsync`.** Right after building
the wrapper (`Schema.wrap(data, jobId, p.lockGen)` — embeds `lockJobId`/`lockGen` for forensics) and
*before* the first `SetAsync` attempt:

```lua
if not SessionLock.ownershipMatches(userId, jobId, p.lockGen) then
    rollback()                                  -- undo the on-save lastSeen / playtime advance
    log("save_fenced_out", { userId = userId, reason = "lock_lost" })
    return false   -- we no longer own the lock; a write here would be the divergent dupe. DO NOT write.
end
```

This closes the **freeze-then-steal divergence dupe**: if server A freezes at `gen=5`, server B steals
at the 90s stale window minting `gen=6` and loads the last durable snapshot; when A unfreezes and tries
to save its divergent state, `ownershipMatches(A, jobId_A, 5)` reads the durable lock `{ jobId_B, gen=6 }`,
mismatches, and A's save is fenced out (returns `false`, **no write**) — A's divergent state dies with A.
B saves normally at `gen=6` as the single authority. No dupe. (For receipts, the fenced-out `false`
triggers the H-1 rollback — see §2.3a step 5.)

**Heartbeat teardown (M-1) — `stopHeartbeat` awaits thread death before `release()`.** Strict order is
still cancel heartbeat → final save → release lock → drop cache (ADR-001 §C3); `stopHeartbeat` now:
1. Sets the stop flag.
2. `task.cancel`s the heartbeat thread, then **SPINS** `while coroutine.status(thread) ~= "dead"` with
   `task.wait(0.05)`, bounded by `heartbeatStopDeadlineSec` (2s) — on deadline, log
   `heartbeat_stop_timeout` and proceed (the stop flag + cancel already prevent a post-resume re-stamp).
3. Clears the thread handle.

Because `release()` runs only after `stopHeartbeat` returns (and it now returns only once the thread is
**dead**), no in-flight `SessionLock.heartbeat` `UpdateAsync` can land after the release and resurrect the
lock. Combined with the gen-fence, even a pathological late beat would only refresh `time` for OUR jobId
(heartbeat refuses a foreign jobId and preserves gen) and is moot once the cache is dropped (E11).

> An optional MemoryStore **fast-path** (a HashMap key checked before the DataStore UpdateAsync) can shave latency on the common "lock is free" case; it is a cache, never authoritative — the DataStore `UpdateAsync` remains the source of truth. Optional for MVP.

## BindToClose Pattern

```lua
-- ServerScriptService: bootstrap
game:BindToClose(function()
    local players = game:GetService("Players"):GetPlayers()
    local threads = {}
    for _, player in ipairs(players) do
        local t = task.spawn(function()
            PlayerDataService.save(player)        -- sets lastSeen, pcall+retry per F-BACKOFF
            SessionLock.release(player.UserId)
        end)
        table.insert(threads, t)
    end
    local deadline = os.clock() + PersistenceConfig.bindToCloseBudgetSec   -- 25s, headroom under 30
    while os.clock() < deadline do
        local alive = false
        for _, t in ipairs(threads) do
            if coroutine.status(t) ~= "dead" then alive = true break end
        end
        if not alive then break end
        task.wait(0.1)
    end
end)
```

---

## MemoryStore Usage (ephemeral, cross-server)

MemoryStore handles session-scoped and cross-server state that must NOT live in DataStore. Budget: `1000 + numPlayers*100` requests/min/instance; all items have a TTL (≤ 45 days). Usage map:

| Structure | MemoryStore type | Authoritative? | TTL | Purpose |
|---|---|---|---|---|
| Session-lock fast-path (optional) | HashMap | No (cache; DataStore wins) | `lockStaleSeconds` | Shave latency on the common "lock free" case |
| Raid matchmaking pool / target snapshot | SortedMap | Yes (transient) | minutes | Cross-server pool of raidable targets (Raid #6) |
| Raid shield expiry | HashMap | **Yes** (mirror in DataStore `shieldUntil`) | `= shield duration` | Cross-server shield that holds across server hops (Raid Shield #7, E10) |
| Raid mailbox (offline raid results) | Queue or HashMap | Yes | until delivered (bounded) | Deliver "you were raided / you won" results to offline players (Raid #6) |
| Trending (Phase 2) | SortedMap | Yes | rolling window | Fame/Trending temporary ranking (P2; not MVP) |

**Authority rules:** active raid shield = MemoryStore authoritative (cross-server TTL); DataStore `shieldUntil` is the mirror (E10). Revenge window = DataStore authoritative (must survive 24h across restarts). Matchmaking pool & mailbox = MemoryStore (inherently transient/cross-server).

---

## Size Estimate (value size vs 4MB limit)

DataStore allows **4,194,304 bytes (4 MB) per key**. The dominant contributor is the roster at cap 200. Conservative per-`BrainrotEntry` JSON estimate (Roblox serializes to an internal JSON-like format; we use generous byte counts):

```
Per BrainrotEntry (worst-case, generous):
  id (GUID string ~36 chars + key overhead)          ~ 80 B   (also the map key)
  species, level, xp, evoStage (4 numbers + keys)    ~ 60 B
  personality (string + key)                         ~ 30 B
  history {coins,rdef,rwon,fame,capturedAt,
           captureSource,hotspotId}                   ~ 180 B
  fav (bool + key)                                   ~ 20 B
  per-entry JSON structural overhead                 ~ 60 B
  ------------------------------------------------------------
  ≈ 430 B per entry  (deliberately rounded UP; no `iv` at launch)

Roster at cap (200 entries):  200 * 430 B            ≈ 86,000 B   (~0.09 MB)

base (BaseData) — factory/deployment block (§3.2a):
  buildings: 1 building "b1" (MVP):
    id, factoryLevel, workerSlotLevel, storageLevel,
    walkoutCooldownUntil (5 small fields + keys)     ~ 120 B
    deployment map (worst case ~ all slots filled;
      startingWorkerSlots 2 + workerSlotLevel<=10 = 12
      entries, each "slot"->GUID ~ 50 B)             ~ 600 B
  pendingOnline, deployedCount (2 numbers + keys)    ~  50 B
  base JSON structural overhead                      ~  60 B
  ------------------------------------------------------------
  ≈ 830 B for `base` at MVP (one fully-upgraded, fully-deployed building)
     — rounds to < 1 KB. Each extra building (forward-compat) adds a similar ~720 B.

Non-roster profile (currency, stats, raid, pendingOffline,
  txLog result map <=50 small entries, consumedReceipts
  timestamp map, settings small, bookkeeping)          ≈ 10,000 B    (~0.01 MB)
  -- txLog (result map, §2.3): <1 KB. consumedReceipts (§2.3a) is now a TIMESTAMP map age-bounded by
  -- the 60-day horizon, NOT a ~100 count cap. Per marker ≈ 80 B (purchaseId GUID ~36 B + numeric
  -- consumedAt ~8 B + the consumedReceiptsOrder id copy ~36 B). REALISTIC load (a heavy spender doing
  -- dozens of purchases inside 60 days) is well under 1000 entries = < 80 KB. WORST CASE at the
  -- consumedReceiptHardCap (5000) ≈ 400 KB (~10% of the 4 MB key) — only reachable by an absurd
  -- purchase rate inside the horizon, and the hard cap guarantees it can never exceed that. Under any
  -- sane load consumedReceipts stays negligible against the 200-entry roster that dominates the value.

Wrapper overhead (version, savedAt, lockJobId, lockGen, JSON braces)  ≈ 1,050 B
  -- + the M-2 fence stamp (lockJobId string + lockGen number, §3.1) adds ~50 B — negligible.

  -------------------------------------------------------------
  TOTAL worst-case ≈ 86,000 + 830 + 10,000 + 1,000 ≈ 97.8 KB  vs  4096 KB limit
  HEADROOM: ~98 KB used = ~2.4% of the limit (≈ 42x headroom).
```

**Conclusion:** at MVP cap (200) we use **~2.4% of the 4 MB budget** — enormous headroom. The new `base` block is tiny (< 1 KB even fully upgraded + fully deployed): it stores only one building, a handful of small upgrade-level counters, a sparse slot→GUID deployment map (≤ a dozen entries at MVP slot caps), and two pending/count numbers — **negligible** against the 200-entry roster that dominates the value. We could raise `rosterCap` ~10x (or add several more buildings) and still fit comfortably. **No sharding needed for MVP.**

**Future sharding strategy (NOT for MVP — documented as a forward option):** if a future design pushes rosters into the thousands or adds heavy per-entry data (e.g. move loadouts, cosmetics, battle logs), split the profile across keys: a small "core" key (`Player_<UserId>`: currency/stats/anti-dupe/index) plus paged roster keys (`Player_<UserId>_roster_<page>`), loaded/saved together under the same session lock. This trades more requests-per-save (budget) for unbounded roster size. Keep it as an option; do not pre-optimize — current headroom makes single-key the correct, simpler MVP choice.

---

## 9. Integration Points

Persistence owns the API every system below calls. **Reads** = consumer reads from the live profile / mirror; **Writes** = consumer mutates via the atomic Persistence API (never DataStore directly).

| System | Reads from Persistence | Writes via Persistence (atomic API) |
|---|---|---|
| **#2 Personality** | `BrainrotEntry.personality` per roster entry | Sets `personality` on capture (via Capture) and on reroll; `validateOrRepair` hook runs in `migrate()` (E-PERS / personality-gdd E5). Stores NO derived stats (runtime state is ephemeral). |
| **#3 Idle Production** | full `roster` + `base` (computes rates server-side: reads `base.buildings[].factoryLevel`/`workerSlotLevel`/`storageLevel` for upgrade effects and the `deployment` map for who is clocked in), `base.pendingOnline` + `pendingOffline`, `lastSeen` | Owns the SHAPE of `base` (BaseData, §3.2a). On deploy/undeploy: writes `base.buildings[].deployment` + `base.deployedCount`. On upgrade buy: increments `factoryLevel`/`workerSlotLevel`/`storageLevel` (critical save). Online accrual writes `base.pendingOnline`; offline accrual writes `pendingOffline.coins` (via `computeOfflineRate(roster, base)`, F-OFFLINE). On Collect: sums `base.pendingOnline + pendingOffline.coins`, credits `coins` + bumps `stats.totalCoinsEarned`, increments per-Brainrot `history.coins`, and zeroes BOTH pending slices — all in ONE atomic op. Sets `base.buildings[].walkoutCooldownUntil`. |
| **#4 Capture** | `rosterCount` (cap check), `freeCapturesRemaining`, `coins` (affordability) | **Atomic capture commit**: mint `BrainrotEntry` (via `Schema.newBrainrot`), append to `roster`, `rosterCount++`; debit `captureCostCoins` OR decrement `freeCapturesRemaining`; `stats.lifetimeCaptures++`; idempotency-keyed. (capture-gdd §5.1 step 10d.) |
| **#5 Battle** | `roster` (combatants: `level`, `personality`, `evoStage`; will own the per-Brainrot stat/IV field it adds when its GDD is written — see §3.2 deferral) | Battle results only — no live combat state persists; outcomes flow to Raid/Evolution counters. |
| **#6 Raid** | `roster` (attack team), `revengeTarget`/`revengeUntil`, target snapshots (MemoryStore), `pendingOffline` (loot = % of target's uncollected) | `raidsWon`/`raidsDefended` (player-level), per-Brainrot `history.rwon`/`history.rdef`; loot into `coins`+`totalCoinsEarned`; sets revenge window (DataStore-authoritative); writes raid mailbox (MemoryStore) for offline targets. |
| **#7 Raid Shield** | `shieldUntil` (mirror) + MemoryStore (authoritative) | Sets shield expiry in MemoryStore (authoritative) and mirrors into `shieldUntil` (E10). |
| **#8 Evolution** | per-Brainrot `history` (lifetime `coins`/`rwon`/`rdef`), `level`, `evoStage`, player `stats` | Advances `evoStage` (and may bump `level`) on milestone — atomic, critical-event save. Relies on day-1 lifetime counters (the reason `history` exists now). |
| **#9 Economy (Meme Coins)** | `coins`, `gems` | Owns the wallet API (`getBalance`/`credit`/`debit`) implemented over the atomic path; bumps `stats.totalCoinsEarned` on every credit; `gems` provisioned (default 0, unused at launch). |
| **#10 Auto-Catch** | `stats.lifetimeCaptures` (unlock @ `autoCatchUnlockCatches` = 50), `rosterCount`, `coins` | Reuses the SAME atomic capture commit as #4 (`CaptureService.resolveCapture(..., "auto")`) — one source of truth; `history.captureSource = "auto"`. |
| **#11 Reroll** | `coins` (cost), `BrainrotEntry.personality` | **Atomic reroll commit**: charge `coins` AND re-draw `personality` in one idempotency-keyed op (personality-gdd E7); rejected mid-battle (E4 there). |
| **#12 Moment System** | reads roster/profile for recap context; listens to events | No direct persisted writes (Moment is display); offline recap reads `pendingOffline`/`from`/`to`. |
| **#15 Monetization** ⛔ **BLOCKED** | `coins`/`gems`/grant flags, `consumedReceipts` (durable, time-bounded dedupe) | `ProcessReceipt` grants commit via the in-memory `update()` keyed by `"receipt_" .. PurchaseId`, with the grant + **durable `consumedReceipts[purchaseId] = consumedAtUnix`** marker (a **TIME-bounded** map pruned by the 60-day `consumedReceiptHorizonSec`, hard-capped at 5000 — NOT a ~100 count cap, H-2) committing atomically in one key under the session lock; Persistence **forces a durable save and returns `PurchaseGranted` ONLY on a confirmed write** (else `NotProcessedYet`; redelivery dedupes via the durable marker) — the `processReceiptGrant` hook (§2.3a). On forced-save failure the grant **AND** marker are **rolled back** (snapshot+restore, H-1) so redelivery re-runs cleanly. The forced save is **fenced** by lock-generation ownership (M-2). In-session `txLog` is a second, faster layer (E7). 2x-offline multiplier feeds `computeOfflineRate`; product grants (slots, etc.) write profile flags. **⛔ #15 is BLOCKED until the ADR-002 receipt + lock rework lands AND the focused re-audit passes** (exploit-security-specialist re-reviews the fence/rollback/horizon; datastore-architect spot-checks the per-save read budget + wrapper size delta) — ADR-002 §7. NOT safe for a live economy until then. |
| **#16 Leaderboard (Richest Manager)** | `stats.totalCoinsEarned` | OrderedDataStore write piggy-backed on save when `totalCoinsEarned` changed (§2.6, F-LEADERBOARD-WRITE); reads top-N server-side, replicates a cached snapshot. |
| **#13 UI/HUD** | the read-only `ProfileMirror` (wallet, roster summaries, pending offline, shield, stats) | Sends only narrow validated intents (`CollectOfflineRequest`, `UpdateSettingRequest`); never names amounts. |
| **#14 Onboarding/FTUE** | `freeCapturesRemaining`, `createdAt` (is-new check), `ProfileLoaded` | Reads to gate the guided flow; seeds nothing itself (profile defaults seed `freeCapturesRemaining`). |
| **#25 Field Combat / Pet AI** (v1.4.1) | `roster` + per-Brainrot `personality` / `level` / `xp` / `evoStage` (same data Battle #5 reads — identical access pattern) to derive a summoned-fighter's combat profile | On a Pet AI win: writes `+xpPerWin` to the winning Brainrot's `xp` via the **same direct `update()` path** Battle uses for Axis B (`evolution-gdd.md` v1.3 §2.7). No new `txLog` idempotency key in v1 (acceptable: over-credit XP is low-stakes, see Evolution §2.7). Persistence is unaware of the resolution model (turn-based for Battle vs real-time tick for Pet AI) — both look identical to the atomic mutation path. No new persisted field; `xp`/`level` already in v1.4 baseline. |
| **#26 Base / Showroom Spatial Layer** (v1.4.1) | `base.buildings[BUILDING_ID].deployment` (the same slot-to-Brainrot-id map Idle #3 owns the shape of) | On `Place`/`Recall` ProximityPrompt actions: writes the `deployment` map via the same Persistence atomic path Idle uses. Pure UX wrapper (3D pedestals + spatial UI); no new persisted field. Cross-system "Brainrot id occupies at most one slot across all buildings" invariant is upheld because both Idle and Showroom write through `update()` (the in-memory `update()` serializes any race). |

### Resolution notes (no contradictions)
- All shapes match `capture-gdd.md` v1.2 and `personality-gdd.md` v1.1 under the single canonical field names spelled out in **§3.6** (`id`, `history` — no aliases). No behavioral divergence is introduced; only field-name canonicalization, explicitly flagged per `design-docs.md`.
- Persistence owns **mechanism** (storage, atomicity, clock, migration); consumers own **values** (rates, costs, thresholds live in their own configs). `freeCapturesOnboarding` is now defined in **one place only** — `CaptureConfig` (the design value). `PersistenceConfig` holds NO copy; `Schema.default()` / `migrate()` READ `CaptureConfig.freeCapturesOnboarding` to seed the persisted `freeCapturesRemaining` counter, eliminating the prior duplication/drift risk.

---

## Acceptance Criteria (system is "done")

- [ ] Session lock acquired before any load; mine/stale/active distinguished; active-on-another-server → graceful kick, never load-over-active (E1).
- [ ] Lock heartbeat refreshes every `lockHeartbeatSec`; stale window ≥ 3× heartbeat.
- [ ] Load failure → kick/retry, NEVER a blank profile over a failed read (E2); genuine `nil` → `Schema.default()`.
- [ ] Every store op `pcall`-wrapped with exponential-backoff retry (`F-BACKOFF`); ignoring a `SetAsync`/`UpdateAsync` failure is impossible (dirty flag persists until success, E3).
- [ ] Dirty-flag save discipline: routine dirty saves run on the `autosaveIntervalSec` (300s) **cadence** iterating the live `profiles` cache (not `Players:GetPlayers()`); `saveDebounceSec` (7s) is used **only** as the per-key write-cooldown floor for critical/final saves (≥ the 6s Roblox cooldown), NOT as the cadence (§2.2).
- [ ] `BindToClose` saves all players in parallel + releases locks within `bindToCloseBudgetSec`, **checking `GetRequestBudgetForRequestType` first and staggering if low** (E4 / §2.2).
- [ ] Heartbeat lifecycle: the lock heartbeat thread is **`task.cancel`ed BEFORE `release()`** in both PlayerRemoving and BindToClose shutdown (strict order: cancel heartbeat → final save → release lock → drop cache); the heartbeat is provably dead after removal.
- [ ] One key per UserId (`Player_<UserId>`, ≤ 50 chars); no Instances/functions stored.
- [ ] `version` present in every stored wrapper; `migrate()` runs every load; corrupt/missing fields repaired; unrecoverable corruption never overwrites the key (E8).
- [ ] Offline accrual uses server `os.time()` only, clamped `[0, 8h]`; negative elapsed → 0 (E5); pending-collect model persists until collected.
- [ ] All economy/roster mutations are atomic + server-authoritative through **ONE in-memory `update()` transaction** (the only place the profile is mutated); **cross-server dupe is prevented by the session lock, NOT per-mutation durability**; `UpdateAsync` is used for the lock only, **not** per gameplay mutation; idempotency keys de-dupe via the `txLog` result map; no double-spend/dupe under concurrency (E9).
- [ ] **Mutator rollback:** `update()` runs the mutator (`pcall`) against a deep copy; commit (swap-in + `nextSeq++` + `txLog` record + mark-dirty) happens once, on success only; a **throwing mutator commits nothing** (no partial state, key not recorded), returns `(false, "mutation_error", false)` (E9 / ADR-001 §H5).
- [ ] **Durable receipt idempotency:** real-money grants set durable `consumedReceipts[purchaseId]` + grant atomically in one `update()`; Persistence **forces a durable save and returns `PurchaseGranted` only on a confirmed write** (else `NotProcessedYet`); redelivery on a fresh server dedupes via the durable marker (§2.3a / E7).
- [ ] **Time-bounded receipt dedupe (H-2):** `consumedReceipts` is a **timestamp map** `{ [purchaseId] = consumedAtUnix }` pruned by **AGE** (`consumedReceiptHorizonSec`, 60d) NOT by count; a marker is NOT evicted by a high purchase count inside the horizon, and a marker older than the horizon is pruned; the `consumedReceiptHardCap` (5000) overflow trim fires oldest-first and logs `consumed_receipts_overflow`; `migrate()` backfills any legacy boolean `true` value to a timestamp (§2.3a / §3.5).
- [ ] **Receipt save-fail rollback (H-1):** on a forced-save failure (or fence-out), `processReceiptGrant` restores the pre-grant snapshot (`p.data` + `p.dirty`) so BOTH the in-memory grant AND the `consumedReceipts` marker are reverted, and returns `(false, "save_failed")`; a subsequent successful redelivery applies the grant **exactly once**; the `alreadyGranted` replay path skips the forced save (§2.3a / E7).
- [ ] **Lock fence-token on save (M-2):** the lock value carries a monotonic `gen` that bumps on every ownership transfer (acquire / stale-steal / mine-reacquire) and is **preserved by heartbeat**; `saveProfile` calls `SessionLock.ownershipMatches(userId, jobId, lockGen)` **before** `SetAsync` and **aborts the write** (rollback + `save_fenced_out` log) on mismatch OR read-failure, so the freeze-then-steal divergent writer is fenced out and the stolen lock's higher-gen owner is the single authority (no last-writer-wins dupe); the stored wrapper embeds `lockJobId`/`lockGen` (§2.1 / E11 / §3.1).
- [ ] **Heartbeat awaits death (M-1):** `stopHeartbeat` `task.cancel`s the heartbeat thread AND spins until `coroutine.status == "dead"` (bounded by `heartbeatStopDeadlineSec`, logs `heartbeat_stop_timeout` on deadline) **before** `release()`, so no in-flight heartbeat `UpdateAsync` lands after release / resurrects the freed lock (§2.1 / E11).
- [ ] `txLog` is a **result map** (replay returns the prior stored result) bounded to `txLogMaxEntries` (E7); `consumedReceipts` is age-bounded (60d horizon) + hard-capped (5000), NOT count-bounded; `rosterCount` cache kept exact and self-healed on load (E6).
- [ ] **Mock fidelity:** `MockDataStore:UpdateAsync` is faithful — a `nil` transform return performs no write and returns the unchanged value (ADR-001 §H3), so lock/save tests exercise real semantics.
- [ ] Leaderboard writes `stats.totalCoinsEarned` to OrderedDataStore, debounced on save-when-changed, never per-tick (§2.6); clients never query OrderedDataStore.
- [ ] MemoryStore authority rules honored: shield = MemoryStore-authoritative + DataStore mirror (E10); revenge = DataStore-authoritative; matchmaking/mailbox = MemoryStore.
- [ ] Client holds a read-only delta-replicated mirror only; no DataStore code on the client; no remote lets a client name an amount/entry/timer.
- [ ] Value size at roster cap 200 (incl. the `base` block) ≈ 2.4% of 4 MB (≈42× headroom); single-key design; sharding documented as a non-MVP option.
- [ ] Schema byte-compatible with `capture-gdd.md` v1.2 and `personality-gdd.md` v1.1, using the single canonical field names `id` + `history` throughout (§3.6 reconciliations).
- [ ] `base` (BaseData) present in the v1 baseline (`Schema.default()` seeds one building "b1"), shape byte-compatible with `idle-production-gdd.md` §3.1 (buildings + upgrade levels + deployment + walkoutCooldownUntil + pendingOnline + deployedCount); `CURRENT_SCHEMA_VERSION` stays 1 (pre-launch, no v1→v2 migration); `migrate()` defensively backfills `base` (§3.2a / §3.5).
