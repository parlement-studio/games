--!strict
-- Shared/Config/TravelConfig.luau
--
-- Cross-place TRAVEL config (System #27 traversal layer). Drives the BunkBed →
-- private Sanctuary teleport and the Sanctuary → Overworld return portal. Read by
-- WorldService (server) + TravelBootstrap (server) + TravelClient (client confirm
-- modal). Pairs with WorldConfig.luau (the place registry / placeIds); this file
-- is the player-facing + interaction tuning layer.
--
-- No secrets — pure config, safe in ReplicatedStorage (shared client+server).
-- Vector3/Color3 datatypes are fine here (config is never serialized to DataStore).
--
-- Schema version: 1

return {
    version = 1,

    -- ── DESTINATIONS ─────────────────────────────────────────────────────────
    -- Per-place travel metadata. Keys MUST match a WorldConfig.places key (the
    -- server resolves placeId + readiness through WorldConfig). `reserved=true`
    -- means a PRIVATE per-player server (TeleportService:ReserveServer +
    -- ReservedServerAccessCode); `false` = the public shared place.
    destinations = {
        -- The player's OWN private Sanctuary (internal key "kandang"). Base / Cage
        -- / coins rebuild from the persisted profile on arrival (hydrate), so a
        -- fresh reserved server each trip is still "their" sanctuary.
        kandang = {
            reserved = true,
            title = "🏡 Private Sanctuary",
            body = "Pergi ke Sanctuary pribadimu? Base, Cage, dan koin tetap tersimpan.",
            confirmText = "Pergi",
            loadingText = "Menyiapkan Sanctuary pribadimu…",
        },
        -- The public Overworld (hunting islands). Return destination from the
        -- Sanctuary portal. Not reserved — normal shared servers.
        overworld = {
            reserved = false,
            title = "🌍 Overworld",
            body = "Kembali ke Overworld (dunia berburu publik)?",
            confirmText = "Kembali",
            loadingText = "Kembali ke Overworld…",
        },
    },

    -- ── BUNK BED INTERACTION (overworld place) ───────────────────────────────
    -- The Camping Cabin's BunkBed has NO PrimaryPart and 117 BaseParts, so the
    -- server hosts the prompt on an INVISIBLE part it creates at the bed pivot
    -- (robust — never depends on which authored part is "the bed").
    bunkBed = {
        -- Top-level Workspace model name (the imported free model).
        modelName = "CampingCabin",
        -- Nested model inside the cabin that the prompt anchors to.
        bedName = "BunkBed",
        -- Name of the invisible prompt-host part the server spawns at the pivot.
        promptHostName = "SanctuaryTravelPrompt",
        -- Prompt strings (player-facing). ActionText | ObjectText.
        actionText = "Tidur",
        objectText = "Private Sanctuary",
        -- Hold duration on the prompt (seconds). Range: 0-2 | Default: 0.4
        holdSec = 0.4,
        -- Max activation distance (studs). Range: 4-32 | Default: 10
        distance = 10,
        -- Y offset (studs) added to the bed pivot for the host part / prompt.
        -- Range: -4 to 6 | Default: 0
        promptYOffset = 0,
    },

    -- ── RETURN PORTAL (sanctuary place) ──────────────────────────────────────
    -- Code-spawned pad in the Sanctuary (the place file is per-place .rbxl, so we
    -- build this at runtime instead of authoring it). Placed in front of the
    -- Sanctuary SpawnLocation; falls back to a fixed world position if none.
    returnPortal = {
        -- Workspace part name the server creates / re-adopts (idempotent boot).
        name = "OverworldPortal",
        actionText = "Pulang",
        objectText = "Overworld",
        -- Hold duration (seconds). Range: 0-2 | Default: 0.4
        holdSec = 0.4,
        -- Max activation distance (studs). Range: 4-32 | Default: 12
        distance = 12,
        -- Offset (studs, SpawnLocation-relative) where the pad sits. -Z = in front.
        spawnOffset = Vector3.new(0, 0, -8),
        -- World position used only if the place has no SpawnLocation.
        fallbackPosition = Vector3.new(0, 5, 0),
        -- Visual pad (thin neon block). Size studs | Color RGB.
        padSize = Vector3.new(6, 1, 6),
        padColor = Color3.fromRGB(64, 156, 255),
        -- Overhead billboard text.
        labelText = "🌍 Pulang ke Overworld",
    },

    -- ── SAFETY ───────────────────────────────────────────────────────────────
    -- Min seconds between two travel triggers per player (anti-spam; a teleport
    -- reserves a server + writes a forced save, so it must not be spammable).
    -- Range: 1-15 | Default: 3
    cooldownSec = 3,
}
