--!strict
-- Shared/Config/CaptureConfig.luau
--
-- MINIMAL STUB. The Capture system (#4) owns the full CaptureConfig; this stub
-- exists only so that Persistence (#1) has a single canonical source to read
-- `freeCapturesOnboarding` from when seeding a new profile's
-- `freeCapturesRemaining` counter (persistence-gdd §3.3 / §3.6 / §8).
--
-- DO NOT duplicate `freeCapturesOnboarding` in PersistenceConfig — this is the
-- single source of truth (capture-gdd §8.2). When the Capture GDD is
-- implemented, this file is expanded; the `freeCapturesOnboarding` value and
-- its meaning must remain.
--
-- Schema version: 1

return {
    version = 1,

    -- Number of free captures a brand-new player gets during onboarding.
    -- Persisted per-player as profile.freeCapturesRemaining (seeded from here),
    -- so free catches survive a relog and cannot be farmed by rejoining.
    -- Range: 0-10
    -- Default: 3 (capture-gdd §3.3.1, locked)
    freeCapturesOnboarding = 3,

    -- Coins debited per catch AFTER the free onboarding captures run out.
    -- AUTHORITATIVE value (EconomyConfig.captureCostCoins_REFERENCE mirrors it
    -- for the inflation model; validate() warns on mismatch). The demo's pack
    -- catch consumes this; Capture v2's per-area item prices will supersede it
    -- (items-token-gdd, planned).
    -- Range: 0-100000 | Default: 25 (capture-gdd §8.2)
    captureCostCoins = 25,
}
