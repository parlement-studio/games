--!strict
-- Shared/Config/PersistenceConfig.luau
--
-- Operational config for Data Persistence & Roster Core (System #1), per
-- design/gdd/persistence-gdd.md (v1.2) §8. Edited by engineers / ops.
-- These are SAFETY / THROUGHPUT knobs, NOT gameplay balance — but they are
-- still externalized here per .claude/rules/config-data.md (zero magic numbers
-- in code). Store/key names are config so a wipe-and-restart or a dev/prod
-- environment split needs no code edits.
--
-- This config holds NO secrets and NO authoritative gameplay value. In
-- particular it does NOT hold `freeCapturesOnboarding` — that lives solely in
-- CaptureConfig (the single source of truth, §3.6 / §9). Persistence READS it
-- from there to seed a new profile.
--
-- Schema version: 1

return {
    version = 1,

    -- ── STORE / KEY NAMES ────────────────────────────────────────────────
    -- DataStore name for the player profile. Bump the suffix for a hard
    -- schema reset (rare). Values: any valid DataStore name.
    dataStoreName = "PlayerData_v1",
    -- DataStore name for session locks.
    lockStoreName = "SessionLocks",
    -- OrderedDataStore name for the Richest Manager leaderboard (§2.6).
    leaderboardStoreName = "Leaderboard_RichestManager_v1",
    -- Key prefix for a player profile: prefix .. UserId. Result must be <= 50
    -- chars. "Player_" (7) + max UserId (10 digits) = 17 chars. Safe.
    keyPrefix = "Player_",
    -- Key prefix for a session lock: prefix .. UserId.
    lockKeyPrefix = "Lock_",

    -- ── SAVE CADENCE ─────────────────────────────────────────────────────
    -- Autosave CADENCE: a dirty profile is saved once this many seconds have
    -- elapsed since its last SUCCESSFUL write (ADR-001 deviation fix — this is
    -- the routine dirty-save interval, NOT the debounce floor).
    -- Range: 60-600 | Default: 300 (5 min) — data-loss window vs budget.
    autosaveIntervalSec = 300,
    -- How often the autosave loop WAKES to scan profiles. Small relative to
    -- autosaveIntervalSec so a profile is saved promptly once its interval (or,
    -- for critical/final saves, its debounce floor) elapses. MUST be >= the 6s
    -- per-key cooldown so a single profile can never be written faster than the
    -- floor by the loop alone.
    -- Range: 6-60 | Default: 7
    autosaveTickSec = 7,
    -- Minimum seconds between two ACTUAL writes to the same key — the per-key
    -- FLOOR for critical/final saves (ADR-001: NOT the autosave cadence). MUST
    -- be >= the hard 6s Roblox per-key write cooldown.
    -- Range: 6-60 | Default: 7 (just above the 6s cooldown).
    saveDebounceSec = 7,
    -- Max save attempts (retry w/ exponential backoff) before giving up this
    -- cycle (dirty flag stays set, so the next tick retries).
    -- Range: 1-10 | Default: 5
    saveMaxAttempts = 5,
    -- Backoff base for retries: wait = backoffBaseSec ^ attempt (capped).
    -- Range: 1.5-3.0 | Default: 2.0
    backoffBaseSec = 2.0,
    -- Cap on a single backoff wait so retries don't stall too long.
    -- Range: 4-30 | Default: 16
    backoffMaxSec = 16,

    -- ── LOAD ─────────────────────────────────────────────────────────────
    -- Max GetAsync attempts at load before kicking. NEVER load a blank
    -- profile over a failed read (E2).
    -- Range: 1-10 | Default: 5
    loadMaxAttempts = 5,

    -- ── SESSION LOCK ─────────────────────────────────────────────────────
    -- Seconds after which a lock with no heartbeat is considered STALE/dead
    -- and stealable (E1). MUST be comfortably > lockHeartbeatSec (>= 3x) so a
    -- live server is never seen as stale.
    -- Range: 45-300 | Default: 90
    lockStaleSeconds = 90,
    -- How often the owning server refreshes its lock timestamp (heartbeat).
    -- Range: 10-60 | Default: 30 (3 missed beats -> stale at 90s)
    lockHeartbeatSec = 30,
    -- Retry attempts to acquire a lock held & fresh by another server before
    -- kicking (E1).
    -- Range: 1-10 | Default: 5
    lockAcquireMaxAttempts = 5,
    -- Backoff (seconds) between lock-acquire attempts.
    -- Range: 0.5-5 | Default: 1.5
    lockAcquireBackoffSec = 1.5,
    -- Bounded deadline (seconds) stopHeartbeat waits for the cancelled heartbeat
    -- thread to reach coroutine.status == "dead" before proceeding (ADR-002 M-1).
    -- Prevents a pathological stuck thread from hanging shutdown; the stop flag +
    -- task.cancel already prevent a post-resume re-stamp, so this is defensive.
    -- Range: 0.5-5 | Default: 2
    heartbeatStopDeadlineSec = 2,
    -- Poll interval (seconds) while awaiting heartbeat-thread death (ADR-002 M-1).
    -- Small so death is observed promptly; well under heartbeatStopDeadlineSec.
    -- Range: 0.01-0.5 | Default: 0.05
    heartbeatStopPollSec = 0.05,

    -- ── SHUTDOWN ─────────────────────────────────────────────────────────
    -- Seconds BindToClose waits for parallel saves (Roblox grants ~30; leave
    -- headroom).
    -- Range: 10-29 | Default: 25
    bindToCloseBudgetSec = 25,
    -- Minimum SetIncrementAsync request budget (GetRequestBudgetForRequestType)
    -- below which saveAllOnClose STAGGERS its per-player save coroutine launches
    -- (instead of bursting them all at once) to avoid hammering an already-low
    -- budget during shutdown (ADR-001 H2). At/above this, launch immediately.
    -- Range: 1-60 | Default: 10 (~one save per connected player headroom)
    shutdownBudgetStaggerThreshold = 10,
    -- Seconds to wait between staggered shutdown save launches when the budget
    -- is low. Kept well within bindToCloseBudgetSec so all saves still fit.
    -- Range: 0.05-1.0 | Default: 0.2
    shutdownStaggerSec = 0.2,
    -- Minimum SetIncrementAsync request budget below which the AUTOSAVE loop
    -- SKIPS the current tick (logs budget_low) rather than spending a scarce
    -- write (ADR-001 H2). The skipped profile stays dirty and retries next tick.
    -- Range: 1-30 | Default: 5
    autosaveBudgetMinRequests = 5,

    -- ── OFFLINE ACCRUAL ──────────────────────────────────────────────────
    -- Hard cap on the offline accrual window (§2.4, F-OFFLINE).
    -- Range: 3600-172800 | Default: 28800 (= 8 hours, locked).
    offlineCapSeconds = 28800,
    -- If lastSeen is more than this far in the FUTURE, log a clock_skew
    -- incident (E5). Accrual still clamps to 0.
    -- Range: 5-300 | Default: 60
    clockSkewToleranceSec = 60,

    -- ── ROSTER ───────────────────────────────────────────────────────────
    -- Max Brainrots a player may own (MVP). Enforced atomically (E6).
    -- Range: 50-1000 | Default: 200 (MVP).
    rosterCap = 200,

    -- ── ANTI-DUPE LEDGER ─────────────────────────────────────────────────
    -- Max idempotency keys retained in the txLog ring buffer (E7). Each entry
    -- now stores a small JSON-safe result payload keyed by idempotency key
    -- (ADR-001 C2), trimmed oldest-first by insertion order.
    -- Range: 10-500 | Default: 50
    txLogMaxEntries = 50,
    -- Retention HORIZON (seconds) for durable ProcessReceipt dedupe markers
    -- (ADR-002 H-2). `consumedReceipts` is a TIMESTAMP map; on each consume,
    -- markers older than (now - this) are pruned. This is the PRIMARY bound —
    -- it MUST safely exceed the Roblox receipt-redelivery window (which has no
    -- published hard maximum; the contract is "until acknowledged"). 60 days
    -- dwarfs any observed redelivery latency by orders of magnitude while
    -- staying tiny on disk. Tunable by ops if platform guidance ever tightens.
    -- Range: 604800 (7d) - 31536000 (365d) | Default: 5184000 (60 days)
    consumedReceiptHorizonSec = 5184000,
    -- Defense-in-depth OVERFLOW safety cap on `consumedReceipts` (ADR-002 H-2).
    -- NOT the primary bound (that is the time horizon above). If, AFTER time-
    -- pruning, the map still exceeds this, trim oldest-first and log a
    -- `consumed_receipts_overflow` incident. Only reachable by an absurd /
    -- abusive purchase rate inside the horizon; under any sane load it never
    -- triggers. Caps worst-case key size deterministically (~80 bytes/marker ->
    -- ~400 KB at the cap, ~10% of the 4MB key budget).
    -- Range: 1000-20000 | Default: 5000
    consumedReceiptHardCap = 5000,

    -- ── LEADERBOARD ──────────────────────────────────────────────────────
    -- Top-N entries fetched for the Richest Manager board.
    -- Range: 10-100 | Default: 50
    leaderboardTopN = 50,
    -- Seconds between server-side leaderboard GetSortedAsync refreshes.
    -- Range: 30-600 | Default: 120
    leaderboardRefreshSec = 120,
}
