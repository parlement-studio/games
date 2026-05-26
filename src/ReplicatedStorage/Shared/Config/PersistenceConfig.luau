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
    -- Autosave interval per player while dirty.
    -- Range: 60-600 | Default: 300 (5 min) — data-loss window vs budget.
    autosaveIntervalSec = 300,
    -- Minimum seconds between two ACTUAL writes to the same key. MUST be >=
    -- the hard 6s Roblox per-key write cooldown.
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

    -- ── SHUTDOWN ─────────────────────────────────────────────────────────
    -- Seconds BindToClose waits for parallel saves (Roblox grants ~30; leave
    -- headroom).
    -- Range: 10-29 | Default: 25
    bindToCloseBudgetSec = 25,

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
    -- Max idempotency keys retained in the txLog ring buffer (E7).
    -- Range: 10-500 | Default: 50
    txLogMaxEntries = 50,

    -- ── LEADERBOARD ──────────────────────────────────────────────────────
    -- Top-N entries fetched for the Richest Manager board.
    -- Range: 10-100 | Default: 50
    leaderboardTopN = 50,
    -- Seconds between server-side leaderboard GetSortedAsync refreshes.
    -- Range: 30-600 | Default: 120
    leaderboardRefreshSec = 120,
}
