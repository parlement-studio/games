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
}
