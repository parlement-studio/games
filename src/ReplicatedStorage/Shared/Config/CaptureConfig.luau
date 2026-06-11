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
    -- for the inflation model; validate() warns on mismatch). LEGACY path:
    -- used only while DemoConfig.captureUsesItems is false (the item flow
    -- below is the S4-locked direction; Capture v2's per-area item prices
    -- supersede both — items-token-gdd, planned).
    -- Range: 0-100000 | Default: 25 (capture-gdd §8.2)
    captureCostCoins = 25,

    -- ── CAPTURE ITEMS (S4, decisions/2026-06-07-economy-sinks-fase0.md) ────
    -- Catching consumes ONE item from the persisted backpack (profile.items).
    -- Bought in the Kandang menu shop. Placeholder name "Capture Net" — the
    -- final name follows the rebrand (kandidat `Relic Charm`, rebrand doc §4).
    -- Capture v2 will expand this into per-area tiers; the shape (itemId ->
    -- def) is designed for that.
    items = {
        capture_net = {
            -- Display name (player-facing; localization later).
            name = "Capture Net",
            -- Single-item price. LOCKED S4: effective catch price unchanged
            -- from the legacy coin debit. Range: 0-100000 | Default: 25
            price = 25,
            -- Bundle: pre-commitment purchase ("buy 10 nets first, then go
            -- hunting"). Range: 2-100 | Default: 10
            bundleCount = 10,
            -- Bundle price (~10% discount vs 10 singles). LOCKED S4.
            -- Range: 0-1000000 | Default: 225
            bundlePrice = 225,
        },
    },
}
