# ADR-002: Receipt Durability and Lock Fencing - Anti-Dupe Hardening

**Status:** Accepted
**Date:** 2026-05-26
**Author:** technical-director
**Extends:** docs/architecture/ADR-001-persistence-mutation-path.md (Accepted). Same hybrid A-dominant architecture; this ADR hardens the durable receipt carve-out (ADR-001 section 3) and the session-lock save path.
**Context:** exploit-security-specialist re-reviewed the reworked Persistence receipt + lock paths (post-ADR-001 rework) and found H-1, H-2 (HIGH) and M-2, M-1 (MEDIUM). These are the real-money + anti-dupe core. They MUST be fixed before Monetization #15 and any live economy. User directive: fix ALL of them now.

**Scope of files:** PlayerDataService.luau, SessionLock.luau, Schema.luau, Migrations.luau, PersistenceConfig.luau, Types.luau, plus specs under tests/ServerStorage/PlayerData/.

---

## Summary of decisions

| Finding | Decision |
|---|---|
| H-1 save-fail leaves in-memory grant w/o rollback | Compensating rollback via snapshot+restore. processReceiptGrant snapshots the live profile BEFORE the grant transaction; on save_failed, restore the snapshot so memory equals last durable state and redelivery re-runs cleanly. |
| H-2 count-cap can evict a still-redeliverable marker | Time-bounded pruning, NOT count-bounded. consumedReceipts becomes a map purchaseId to consumedAtUnix. Prune only markers older than consumedReceiptHorizonSec = 5184000 (60 days). Drop the 100 count cap. Add a safety overflow cap at 5000. |
| M-2 save does not re-verify lock ownership | Fence-token via a monotonic lock gen re-read before SetAsync. Lock schema gains gen; wrapper gains lockJobId + lockGen. A save re-reads the lock and aborts (treats as failed save) if we no longer own it. Ships now. |
| M-1 heartbeat in-flight at cancel can resurrect lock | stopHeartbeat awaits thread death (coroutine.status equals dead) before returning. |

---

## 1. H-2 - consumedReceipts cap policy (DECISION)

### Problem recap
Roblox redelivers an UNACKED DevProduct receipt indefinitely (across sessions, until the callback returns PurchaseGranted). The current dedupe is a count-bounded ring of 100 (consumedReceiptsMaxEntries). A whale who makes 100 or more purchases between a grant and a redelivery (or via H-1 unacked-but-granted window) evicts the marker, the grant mutator runs a second time, real-money item/currency dupe. A count cap is fundamentally wrong for a set whose required retention is defined by TIME (the redelivery horizon), not COUNT.

### Decision: time-bounded pruning. Drop the count cap.
consumedReceipts changes from a presence set to a TIMESTAMP map:

    consumedReceipts: { [purchaseId: string]: number }   -- value = os.time() when consumed (server clock)

Pruning rule (replaces the count-trim in markReceiptConsumed): on each consume, remove any entry whose consumedAt is older than now minus Config.consumedReceiptHorizonSec. Keep consumedReceiptsOrder (insertion-ordered) so pruning is a cheap front-of-list walk: pop the head while consumedReceipts[head] is nil OR (now minus consumedReceipts[head]) is greater than horizon.

HORIZON VALUE: consumedReceiptHorizonSec = 5184000 (60 days).

Rationale for 60 days:
- Roblox does not publish a hard maximum redelivery window. Empirical reports put practical redelivery at minutes-to-hours after a server is available, but the contract is until-acknowledged, which in pathological cases (a product that keeps failing to grant, a player who does not rejoin) can stretch arbitrarily. We cannot retain forever (4MB budget), so we pick a horizon that SAFELY EXCEEDS any realistic redelivery window while staying tiny on disk.
- 60 days dwarfs any observed redelivery latency by orders of magnitude. A receipt still unacknowledged after 60 days is effectively dead (the player has had 60 days of sessions in which a redelivery would have fired and been acked). The residual double-grant risk at 60 days is negligible and bounded.
- It is config-tunable; ops can raise it without a code change if Roblox guidance ever tightens.

### Safety overflow cap (defense-in-depth, NOT the primary bound)
Add consumedReceiptHardCap = 5000. If, after time-pruning, the map STILL exceeds 5000 entries (only reachable by an absurd purchase rate inside the horizon, pathological/abuse), trim oldest-first beyond 5000 and log a consumed_receipts_overflow incident so we notice. This caps the worst-case key size deterministically; under any sane load it never triggers.

### 4MB budget check
A marker is purchaseId (a GUID-ish string, about 36 bytes) plus a numeric timestamp (about 8 bytes serialized) plus the order-list copy of the id (about 36 bytes) = about 80 bytes/entry. At the 5000 hard cap that is about 400 KB, about 10 percent of the 4MB key. Realistic load (a heavy spender doing dozens of purchases inside 60 days) is well under 1000 entries = under 80 KB, negligible against the GDD about-98 KB profile estimate. WITHIN BUDGET. The hard cap guarantees it stays bounded.

### Migration
Existing/in-flight profiles have consumedReceipts as a presence set ({ [string]: true }). Migration step in Migrations.migrate: for any consumedReceipts whose values are boolean true, replace each with savedAt (the wrapper timestamp) or os.time() as a conservative consumed-recently stamp so they are NOT immediately pruned. We are pre-launch with no real-money data so this is a no-op in practice but keeps the code honest. Bump Schema.CURRENT_SCHEMA_VERSION? NO - still version 1, pre-launch baseline (consistent with ADR-001 / GDD v1.3 section 3.2a rationale: base went into the v1 baseline directly). Update the v1 baseline shape plus add the defensive backfill in migrate.

---

## 2. M-2 - Fence token on save (DECISION)

### Problem recap
The 90s stale-steal is by-design (a frozen/dead server lock must be reclaimable). But saveProfile calls SetAsync(profileKey, wrapper) WITHOUT re-checking that we still hold the lock. Attack: force server A to freeze (heartbeat dies) while its game thread keeps mutating in-memory; after 90s server B steals the lock and loads the last DURABLE snapshot; both A and B now hold divergent live state and both SetAsync last-writer-wins, currency/item dupe across the divergence.

The fix is a FENCE TOKEN: a save must prove current lock ownership at write time, and a stale writer must lose.

### Decision: lock-generation fence carried into the profile wrapper, verified before SetAsync.

(a) LOCK SCHEMA GAINS A MONOTONIC GENERATION. SessionLock value becomes:

    { jobId = <string>, time = <unix>, gen = <number> }

gen increments every time the lock is (re)acquired or STOLEN, i.e. every ownership transfer mints a strictly higher generation. On acquire: read existing; set gen = (existing and existing.gen or 0) + 1 whenever we write a new ownership stamp (free / stale-steal / mine-reacquire all bump). Heartbeat does NOT bump gen (it refreshes time only, preserving gen). This is a compare-and-set inside the existing UpdateAsync transform, so it is atomic and cross-server-correct.

SessionLock.acquire returns the acquired gen to the caller (new signature acquire(userId) returns (boolean, number?)). The service stores it on the Profile as lockGen.

SessionLock.heartbeat keeps refusing to clobber a foreign jobId (unchanged), and now preserves gen.

Add SessionLock.ownershipMatches(userId, jobId, gen) returns boolean - a pcalled GetAsync (READ, not write) that returns true iff the durable lock currently reads jobId equals ours AND gen equals ours. The GetAsync read budget is a separate, ample bucket from the write bucket, so one extra read per actual write is affordable (saves are debounced to at least 7s/key).

(b) saveProfile FENCES BEFORE SetAsync. New strict order inside saveProfile, right before the retry loop:

    if not SessionLock.ownershipMatches(userId, ourJobId, p.lockGen) then
        rollback()  -- undo the on-save lastSeen/playtime advance
        log("save_fenced_out", { userId = userId, reason = "lock_lost" })
        -- We no longer own the lock: another server has taken authority.
        -- Do NOT write - that would be the divergent last-writer-wins dupe.
        return false
    end

Place the fence check AFTER computing the wrapper but BEFORE the first SetAsync attempt. The wrapper ALSO embeds lockJobId and lockGen (see (c)) so a forensic read of any profile shows which generation wrote it.

(c) WRAPPER CARRIES THE FENCE STAMP. Schema.wrap(data, lockJobId, lockGen) adds:

    StoredWrapper = { version, data, savedAt, lockJobId: string?, lockGen: number? }

This is belt-and-suspenders: the primary defense is the pre-write ownershipMatches read. The embedded lockGen lets us (and any future load path) detect/audit a backward-generation write. Optional future hardening (NOT required this round): a load could reject a wrapper whose lockGen is lower than a value it just stole at - deferred, the read-fence covers the live attack.

### Interaction with the stale-steal path
- Server A freezes at gen=5. B steals at 90s, mints gen=6, loads last durable.
- A unfreezes, tries to save its divergent state. ownershipMatches(A, jobId_A, 5) reads the durable lock = { jobId_B, gen=6 }, mismatch, A save is fenced out (returns false, no write). A divergent state dies with A. NO DUPE.
- B saves normally with gen=6. Single authority. Correct.
- Edge: A fence read itself fails (DataStore read error). Treat a FAILED ownership read as cannot-prove-ownership, fence out (do NOT write). This is the money-safe direction (a missed save is recoverable via the dirty flag plus next tick; a divergent write is not).

### Does it ship now / change the lock schema?
YES, ships now (user wants all fixed; M-2 is the anti-dupe core for a live economy). YES, it changes the lock schema (+gen) and the wrapper schema (+lockJobId, +lockGen). Both are additive and pre-launch, so no live migration risk. Existing lock values with no gen are treated as gen=0 and the next acquire bumps to 1.

### Why not seq-in-wrapper-only (the other option offered)?
A monotonic nextSeq in the wrapper with backward-seq rejection on WRITE is not enforceable with SetAsync (SetAsync does not read-compare). It would require switching profile writes to UpdateAsync (read-modify-write) per save, which ADR-001 explicitly rejected for the routine path on budget grounds, and which still would not stop two servers from each advancing their own nextSeq independently after a divergence. The lock-generation read-fence directly answers the real question (do I still own this profile?) with one cheap read and no architecture reversal. Decision stands on the gen-fence.

---

## 3. H-1 - receipt save-fail rollback (DIRECTIVE)

### Confirmed approach: snapshot + restore (compensating rollback).
A reversing mutator is rejected: the grant mutator is opaque (Monetization #15 supplies it) so we cannot synthesize its exact inverse. Snapshot+restore is exact and simple.

processReceiptGrant changes:
1. BEFORE the grant update(): take local snapshot = deepCopy(p.data) and local wasDirty = p.dirty (the live profile, pre-grant). deepCopy already exists and the profile is JSON-safe.
2. Run the grant transaction as today (apply grant plus markReceiptConsumed, commit in-memory).
   - If the in-transaction replay path hit (alreadyGranted), there was no new grant, so no save needed beyond what already exists; return (true, result) WITHOUT forcing a save (the marker is already durable, that is why the replay fired). This also avoids a needless write.
3. Force the durable save.
4. ON SAVE FAILURE: restore - p.data = snapshot and p.dirty = wasDirty. Then return (false, save_failed).

Result: on save_failed, BOTH the in-memory grant AND the consumedReceipts marker are gone, memory equals last durable state. Roblox redelivers; the next attempt re-runs the grant cleanly and (once a save succeeds) the durable marker dedupes future redeliveries. No drop-then-regrant, no phantom in-memory gems.

ORDERING WITH H-2: the snapshot must be taken on the LIVE p.data reference and restored by reassigning p.data = snapshot, exactly mirroring how update() swaps the copy in. Do not mutate the snapshot in place.

INTERACTION WITH THE FENCE (M-2): if the forced save is fenced out (we lost the lock), saveProfile returns false, which triggers the H-1 rollback, correct: we lost authority, so we must not claim the grant; redelivery on the authoritative server re-runs it.

---

## 4. M-1 - heartbeat resurrection (DIRECTIVE)

### Confirmed: stopHeartbeat awaits thread death before returning.
The tombstone approach (heartbeat refuses to stamp if it observes a released tombstone) is rejected as more complex and still racy. Awaiting death is deterministic.

stopHeartbeat(userId):
1. Set heartbeatStop[userId] = true.
2. If the thread exists and is not us-calling-from-within-it: task.cancel it, then SPIN until coroutine.status(thread) equals dead with a bounded task.wait(0.05) loop and a small deadline (e.g. 2s) so a pathological stuck thread cannot hang shutdown. If the deadline passes, log heartbeat_stop_timeout and proceed (the stop flag plus cancel already prevent the loop body from re-stamping after the current task.wait resumes, so this is purely defensive).
3. Clear heartbeatThreads[userId].

Because release() runs AFTER stopHeartbeat returns (existing strict order, ADR-001 C3), and stopHeartbeat now returns only once the heartbeat thread is dead, no in-flight SessionLock.heartbeat UpdateAsync can land after the release. Combined with the gen-fence, even a pathological late beat would only refresh time for OUR jobId (heartbeat already refuses foreign jobId and now preserves gen), and would be moot because the cache is dropped. Self-heals; no cross-server dupe. M-1 was the weakest finding and this closes it cleanly.

Note: task.cancel of a coroutine currently suspended inside task.wait is sufficient; the await loop is the guarantee that we observe dead rather than assuming it.

---

## 5. Rework task list (luau-systems-programmer - IN ORDER)

Do these in order; each is small and testable. Run the existing suite after each.

STEP 1 - Config (PersistenceConfig.luau).
- Repurpose consumedReceiptsMaxEntries: rename to consumedReceiptHardCap = 5000 (overflow safety) with a clear comment, range 1000-20000.
- Add consumedReceiptHorizonSec = 5184000 (60 days), commented: retention horizon for durable receipt dedupe markers; MUST safely exceed the redelivery window. Range 604800 (7d) to 31536000 (365d), default 5184000 (60d).
- No new lock config needed; gen is data, not config.

STEP 2 - Types (Types.luau).
- consumedReceipts: { [string]: number } (was { [string]: true }); update the comment.
- StoredWrapper: add lockJobId: string?, lockGen: number?.
- Document the { jobId, time, gen } lock-value shape in a comment.

STEP 3 - Schema (Schema.luau) plus Migrations.luau.
- Schema.default(): consumedReceipts = {} stays (now a timestamp map by usage).
- Schema.wrap(data, lockJobId, lockGen): new signature; embed both fields.
- Migrations.migrate: defensive backfill - convert any consumedReceipts[id] == true to a numeric timestamp (wrapper.savedAt or os.time()).

STEP 4 - SessionLock (SessionLock.luau).
- acquire: bump gen on every ownership write (free/steal/reacquire); return (boolean, number?) (the acquired gen).
- heartbeat: preserve existing.gen when refreshing time.
- release: unchanged (still only clears if ours).
- Add ownershipMatches(userId, jobId, gen) returns boolean - pcalled GetAsync; true iff durable lock reads our jobId AND our gen; a FAILED read returns false (fence-out = money-safe).

STEP 5 - PlayerDataService load plus Profile (PlayerDataService.luau).
- Capture acquire returned gen; store lockGen on the Profile type plus the cache entry (and in _setProfileForTest, default to a sentinel like 1).
- saveProfile: call Schema.wrap(data, SessionLock.getJobId(), p.lockGen); insert the ownershipMatches fence check after building the wrapper, before the SetAsync retry loop; on fence-fail, rollback() plus log save_fenced_out plus return false.

STEP 6 - H-1 rollback in processReceiptGrant.
- Snapshot p.data plus p.dirty before the grant transaction; on the alreadyGranted replay path skip the forced save; on save_failed restore p.data and p.dirty from the snapshot, then return (false, save_failed).

STEP 7 - M-1 stopHeartbeat awaits death.
- After task.cancel, spin while coroutine.status(thread) is not dead with task.wait(0.05) and a 2s deadline plus heartbeat_stop_timeout log.

STEP 8 - H-2 time-pruning in markReceiptConsumed.
- Stamp data.consumedReceipts[purchaseId] = os.time(); prune front-of-consumedReceiptsOrder entries older than consumedReceiptHorizonSec; apply consumedReceiptHardCap overflow trim with a consumed_receipts_overflow log.

### Tests to add (each maps to a finding)
Use the existing tests/ServerStorage/PlayerData/*.spec.luau conventions (TestEZ, _setProfileForTest, setJobId, MockDataStore).

- H-1 SAVE-FAIL ROLLBACK (PlayerDataService.spec): mock store whose SetAsync always fails; call processReceiptGrant; assert returns (false, save_failed) AND getData().consumedReceipts[purchaseId] is nil AND the granted currency is reverted (gems back to pre-grant) AND p.dirty matches pre-grant. Then make SetAsync succeed, re-run, assert grant applies exactly once.
- H-2 CAP-EVICTION REDELIVERY (PlayerDataService.spec): consume one receipt; consume 200 more (well past the old 100 cap); assert the FIRST marker still present (not evicted by count); then advance a mocked clock past consumedReceiptHorizonSec and consume again, assert the old marker is pruned. Assert the overflow hard-cap trims at 5000 and logs.
- M-2 FREEZE-STEAL DUPE (PlayerDataService.spec plus SessionLock.spec): server A acquires (gen=1), profile cached with lockGen=1; simulate B stealing (setJobId to B, acquire to gen=2, write durable lock as B); restore jobId to A; call save on A profile, assert ownershipMatches returns false, save returns false, NO SetAsync write occurred (assert store write count unchanged), save_fenced_out logged. Then assert B save (gen=2) succeeds.
- M-1 HEARTBEAT RESURRECTION (PlayerDataService.spec): start a real heartbeat; stopHeartbeat; assert coroutine.status(thread) equals dead immediately after the call returns; assert no SessionLock.heartbeat UpdateAsync lands after a subsequent release (track lock-store write calls; count must not increase post-release).
- GEN BUMP SEMANTICS (SessionLock.spec): acquire on free key to gen 1; reacquire same jobId, gen bumps; heartbeat, gen unchanged plus time refreshed; stale-steal by other jobId, gen strictly greater than prior.
- MIGRATION BACKFILL (Schema.spec/Migrations.spec): a profile with consumedReceipts = { x = true } migrates to consumedReceipts.x being a number not pruned by the next consume.

---

## 6. GDD amendments (design/gdd/persistence-gdd.md to v1.4)

- section 2.3a Durable receipt idempotency - consumedReceipts is now a TIMESTAMP map pruned by a 60-day horizon (not a count-bounded ring); document the horizon rationale (exceeds the redelivery window) and the 5000 overflow safety cap. Add the H-1 snapshot+restore-on-save-failure guarantee (no drop-then-regrant; no phantom in-memory grant).
- section 2.1 lifecycle / Session Lock Pattern - lock value is now { jobId, time, gen }; gen increments on every ownership transfer (acquire/steal/reacquire), preserved by heartbeat. Document the SAVE FENCE: a profile save re-verifies durable lock ownership (jobId plus gen) via a read before SetAsync and ABORTS if it lost the lock (closes the freeze-then-steal divergence dupe). Add the heartbeat teardown guarantee (stopHeartbeat awaits thread death before release).
- section 3.2 schema - consumedReceipts: { [string]: number } (consumedAt); StoredWrapper gains lockJobId, lockGen. Update size estimate: durable markers worst-case about 400 KB at the 5000 hard cap, realistic under 80 KB; total well within 4MB.
- section 8 Config - document consumedReceiptHorizonSec (60d) and consumedReceiptHardCap (5000); note consumedReceiptsMaxEntries was repurposed/renamed.
- E-series edge cases - add: (a) receipt forced-save fails, in-memory grant plus marker rolled back, redelivery re-runs; (b) server freeze plus foreign steal, fenced save, divergent snapshot discarded; (c) heartbeat in-flight at teardown, awaited to death, no post-release lock refresh.
- Acceptance Criteria - add the four new tests as criteria.
- Changelog 1.4 entry referencing ADR-002.

---

## 7. Verdict + re-audit scope

VERDICT: NOT safe for Monetization #15 / live economy as-is (H-1, H-2 are real-money dupe/loss; M-2 is an anti-dupe-core divergence dupe). Safe AFTER Steps 1-8 land with all new tests green. The architecture from ADR-001 is unchanged and correct; these are surgical hardening fixes, not a redesign. Appropriate for a solo-dev game - no over-engineering (one extra read per debounced save; about 80 bytes/marker; no UpdateAsync-per-mutation reversal).

RE-AUDIT REQUIRED (focused, NOT full) before #15 ships:
1. exploit-security-specialist re-reviews:
   - the fence read placement plus the failed-read-fences-out rule in saveProfile (confirm the residual TOCTOU window between the ownershipMatches read and the SetAsync is acceptable - inherent to any fence; the gen monotonicity plus the 90s stale window being much larger than save latency makes it negligible, but confirm),
   - the H-1 snapshot/restore (confirm marker plus grant both revert and dirty is consistent),
   - the H-2 horizon vs. the redelivery window (confirm 60d is conservative enough; flag if platform guidance differs),
   - the gen-bump on every ownership transfer (confirm a stolen lock always out-generations the frozen owner).
2. datastore-architect spot-checks the read-budget impact of the per-save ownershipMatches GetAsync and the wrapper size delta.

No other departments affected. Producer: note Monetization #15 is BLOCKED on this rework plus re-audit.
