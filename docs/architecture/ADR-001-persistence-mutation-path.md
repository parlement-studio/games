# ADR-001: Persistence & Roster Core — Mutation Path Architecture

**Status:** Accepted
**Date:** 2026-05-26
**Author:** technical-director
**Supersedes:** the literal "UpdateAsync per mutation" wording in `design/gdd/persistence-gdd.md` v1.2 §1.4 / §2.3 / E9
**Context:** ruling on datastore-architect audit findings C1–C5, H1–H5 of the Persistence #1 implementation.

---

## Decision: Hybrid (Option A-dominant)

In-memory authoritative session state + **session lock** + periodic/critical `SetAsync` save (ProfileService/ProfileStore-class pattern) as the default mutation path, with **one narrow durable carve-out for real-money grants (ProcessReceipt)**.

Option B (durable `UpdateAsync` per gameplay mutation) is **rejected**: an idle game ticks coins continuously; per-tick durable writes would blow the `60 + numPlayers*10`/min budget and hit the 6s per-key cooldown immediately. Cross-server dupe is prevented by the **session lock**, not per-mutation durability.

### Hybrid split

| Operation class | Path |
|---|---|
| Idle coin accrual, `history.coins`, playtime, stats | A — in-memory + periodic save |
| Routine roster/wallet/base mutations (capture, reroll, deploy, evolution, upgrade, collect, credit/debit) | A — in-memory `update()` transaction + critical-event save, in-memory `txLog` idempotency |
| **ProcessReceipt (DevProduct, real money)** | Hybrid — durable `consumedReceipts` in profile + forced-save before `PurchaseGranted` |

**Invariant:** all gameplay mutations route through the single in-memory `update()` transaction — the only place the profile is mutated.

---

## Rulings on findings

**CRITICAL — all must-fix before any system builds on this:**
- **C1** — fold all roster/wallet/base mutation INTO `update()`. `addBrainrot`/`removeBrainrot` become pure `Schema.addToRoster(data, entry)` / `removeFromRoster(data, id, force)` helpers operating on the `data` passed to a mutator; they do not touch the cache, bump `nextSeq`, or mark dirty. `nextSeq++`, txLog record, markDirty happen exactly once, in `update()`.
- **C2** — `txLog` becomes a map `{ [key]: storedResult }`; replay returns `(true, storedResult, true)`. storedResult is a small JSON-safe payload.
- **C3** — `task.cancel` the heartbeat thread BEFORE `release()`, in both `onPlayerRemoving` and `saveAllOnClose`. Strict order: cancel heartbeat → final save → release lock → drop cache.
- **C4** — folds into C3: first action of each shutdown coroutine is stopHeartbeat for that userId.
- **C5** — roster cap check moves inside the `update()` transaction (via the pure helper returning a `"roster_full"` sentinel; mutator must not debit on that path).

**HIGH:**
- **H5** — `update()` runs the mutator (pcall) against a deep copy of `data`; commit (swap in + nextSeq++ + record txLog + markDirty) only on success; on error discard the copy, do not record the key, return `(false, "mutation_error", false)`. Transform stays non-yielding.
- **H2** — add `GetRequestBudgetForRequestType` check in `saveAllOnClose` (stagger if low) and gate the autosave tick if exhausted.
- **H1** — autosave iterates `profiles` (cache = source of truth for who needs saving), not `Players:GetPlayers()`.
- **H3** — make `MockDataStore:UpdateAsync` faithful: `nil` transform return = no write, return unchanged value.
- **H4** — pcall-wrap `GetDataStore`; on failure treat as failed load (release lock, return nil → kick).

**GDD deviations:**
- Autosave cadence — routine dirty saves on `autosaveIntervalSec` (300s); `saveDebounceSec` (7s) is ONLY the per-key floor for critical/final saves. (Code took the floor as the cadence — fix.)
- Pending-pool cap — owned by Idle #3 (not a Persistence defect); flag for #3 integration.
- OrderedDataStore leaderboard write + MemoryStore shield mirror — deferred to owning systems (#16, #7). No speculative stubs.

---

## Durable receipt idempotency (real money)

Persist `consumedReceipts: { [string]: true }` (bounded, ~last 100) in the profile. ProcessReceipt:
1. If profile not loaded → return `NotProcessedYet`.
2. `update(player, mutator, "receipt_"..purchaseId)`: mutator checks `consumedReceipts[purchaseId]` (replay → return stored result); else apply grant, set marker, return result.
3. **Force a durable save; return `PurchaseGranted` ONLY if the save succeeds**, else `NotProcessedYet` (redelivery dedupes via the durable marker). Returning `PurchaseGranted` without a confirmed durable write is forbidden.

Grant + consumed-marker commit atomically in one key under the session lock. Persistence builds the hook (`processReceiptGrant`); Monetization #15 wires the callback.

---

## Rework sequence (luau-systems-programmer, in order)

1. Rework `update()` → real transaction (txLog map, deep-copy + pcall + rollback, fold roster/cap helpers in). (C1, C2, C5, H5)
2. Durable receipt hooks: `consumedReceipts` + `processReceiptGrant` (forced-save-before-ack). (C2 follow-on)
3. Heartbeat lifecycle: `stopHeartbeat` + cancel-before-release in removing/shutdown. (C3, C4)
4. Budget guard in `saveAllOnClose` + autosave tick. (H2)
5. Autosave cadence 300s + iterate `profiles`. (deviation, H1)
6. Load-path pcall hardening (`getStore`). (H4)
7. MockDataStore UpdateAsync fidelity. (H3)
8. Tests: replay-returns-prior-result, throwing-mutator-rollback, compound both-or-neither, cap-in-transaction, heartbeat-dead-after-removal, receipt grant/replay/save-fail, budget stagger, autosave cadence, orphan save, mock nil-semantics.

---

## GDD amendments

Bump `persistence-gdd.md` → v1.3: §1.4/§2.3 (hybrid wording; UpdateAsync used for the lock, not per gameplay mutation), §2.2 (cadence), §2.3a (durable receipt idempotency), §3.2 (txLog map + `consumedReceipts`), E7/E9 (in-memory serialized + rollback + durable receipt layer), §9 #15 row, Acceptance Criteria.

---

## Verdict

Not safe to build on as-is. Safe after Steps 1–8 + new tests pass. Architecture is correct for the genre; defects are bounded, surgical.

**Second audit required (focused, not full):**
1. datastore-architect re-reviews Step 1 (reworked `update()`) + Step 2 (durable receipt).
2. exploit-security-specialist reviews the receipt path + heartbeat/lock dupe window before Monetization #15 ships.
