--!strict
-- Shared/Config/WorldConfig.luau
--
-- WORLD UNIVERSE place registry (System #27 / GH #23). Single source of truth for
-- "which Roblox places exist + their role + server model + capacity". Read by the
-- teleport layer (WorldService) and any system that needs to cross a place boundary.
--
-- ARCHITECTURE (world-universe-gdd.md v1.1, owner-locked 2026-06-09):
--   * OVERWORLD — single seamless place: sea + 4-5 hunting islands (TIER differs per
--     island) + Hunter Camp port + Colony Boss Tier-1. Shared public, StreamingEnabled.
--   * SANCTUARY — private per-player base (reserved server, key = UserId).
--   * RAID A/B — Tier-3 raid, party-instanced (reserved), token-gated.
--   * SUPER_BOSS — Tier-2, party-instanced (reserved).
--
-- ⚠️ Island ≠ place: the 4/5 islands ARE IN the overworld (one place, split by
-- StreamingEnabled). ONLY Sanctuary/Raid/Super Boss are SEPARATE places.
--
-- 🔧 placeId is SET TO ZERO until each place is created + published (Studio Asset Manager
-- "Add New Place", or Creator Dashboard / Open Cloud). Teleport to a place with id 0 is
-- SKIPPED + warning (see world-universe-gdd §3.1 / §7 edge case #10). Filled in by the
-- release-manager once the place exists.
--
-- No secrets here — pure config, safe in ReplicatedStorage (shared client+server).
--
-- Schema version: 1

export type PlaceKind = "overworld" | "kandang" | "raid" | "super_boss"

export type PlaceDef = {
    -- Roblox placeId (0 = not built/published yet; teleport skipped + warn).
    placeId: number,
    -- Place role (drives server model + dispatch logic).
    kind: PlaceKind,
    -- Capacity PER server COPY (NOT a total player cap — Roblox runs
    -- many parallel copies). Range per kind in the comment below.
    maxPlayers: number,
}

local WorldConfig = {
    version = 1,

    -- Universe (Experience) id — filled in at publish (informational; teleport uses
    -- the per-place placeId, not this).
    universeId = 10224556071,

    -- ── PLACE REGISTRY ──────────────────────────────────────────────────────
    -- Key = logical name used in TeleportData.intent / WorldService.
    places = {
        -- START PLACE ("monster inc"). First island (`land 1`) + Hunter Camp +
        -- spawn wild + Colony Boss Tier-1. maxPlayers Range 10-40 | Default 26.
        overworld = { placeId = 131913437012360, kind = "overworld" :: PlaceKind, maxPlayers = 26 },

        -- Private per-player base. DISPLAY NAME = "Sanctuary" (place name in Studio;
        -- key code stays "kandang" = stable internal identifier, system #26).
        -- Reserved by UserId; owner + visitor read-only. maxPlayers Range 1-12 | Default 8.
        kandang = { placeId = 92338616596672, kind = "kandang" :: PlaceKind, maxPlayers = 8 },

        -- Raid Dungeon Tier-3, party-instanced, token-gated. Range 1-8 | Default 6.
        raid_a = { placeId = 0, kind = "raid" :: PlaceKind, maxPlayers = 6 },
        raid_b = { placeId = 0, kind = "raid" :: PlaceKind, maxPlayers = 6 },

        -- Super Boss Tier-2, party-instanced. Range 1-8 | Default 6.
        super_boss = { placeId = 0, kind = "super_boss" :: PlaceKind, maxPlayers = 6 },
    } :: { [string]: PlaceDef },

    -- ── STREAMING (overworld) ───────────────────────────────────────────────
    -- StreamingEnabled REQUIRED in the overworld (sea + many islands, mobile). Set in
    -- the place Workspace; the numbers here = the mirrored tuning source.
    streaming = {
        -- Radius (studs) of full streaming around the player. Range 512-2048 | Default 1024
        targetRadius = 1024,
        -- Minimum radius GUARANTEED present (anti fall-through). Range 128-512 | Default 256
        minRadius = 256,
    },

    -- ── SPAWN DENSITY SCALING (per-region, anti empty/overcrowded) ───────────
    -- spawnTarget(region) = clamp(baseSpawn + perPlayer*playersInRegion, min, max)
    -- (world-universe-gdd §2.5). Director server-authoritative per island region.
    spawn = {
        baseSpawn = 6, -- minimum at 0-1 players (an island is never empty). Range 1-20
        perPlayer = 2, -- extra monster slots per player in the region. Range 0-5
        minSpawn = 4, -- lower bound. Range 1-20
        maxSpawn = 40, -- upper bound (mobile perf). Range 5-100
    },

    -- ── TELEPORT / TRAVERSAL ────────────────────────────────────────────────
    teleport = {
        retry = 1, -- pcall retry once if TeleportService fails. Range 0-3
        timeoutSec = 10, -- timeout reserve/dispatch. Range 5-30
    },
    -- Fast-travel intra-overworld (reposition WITHIN the place, NOT TeleportService).
    -- An island can only be fast-traveled to once it has been visited by boat
    -- (persisted `discoveredIslands`, gdd §2.3 / §3.4).
    fastTravel = {
        requiresDiscovered = true, -- must sail there first before you can jump
        fadeSec = 0.4, -- transition fade duration. Range 0.1-1
    },
    -- MemoryStore TTL (seconds) — cross-server coordination (gdd §3.3).
    memoryStore = {
        kandangTTLsec = 1800, -- map UserId -> reserved kandang accessCode
        partyReservationTTLsec = 300, -- map partyId -> reserved raid accessCode
    },
}

-- Resolve a place def by logical name; nil + warn if unknown.
function WorldConfig.getPlace(name: string): PlaceDef?
    local def = WorldConfig.places[name]
    if not def then
        warn("[WorldConfig] unknown place name: " .. tostring(name))
        return nil
    end
    return def
end

-- True iff the place is created/published (placeId set). Teleport callers MUST
-- guard on this — a placeId of 0 means "not built yet"; skip + warn.
function WorldConfig.isPlaceReady(name: string): boolean
    local def = WorldConfig.places[name]
    return def ~= nil and def.placeId > 0
end

-- Which place is THIS server running, by game.PlaceId? Returns the PlaceKind
-- ("overworld" | "kandang" | "raid" | "super_boss") or "unknown" if the running
-- PlaceId isn't in the registry. The SAME code runs in every place; systems gate
-- their place-specific behaviour on this (e.g. wild spawning skips the Sanctuary).
function WorldConfig.currentPlaceKind(): string
    local pid = game.PlaceId
    for _, def in WorldConfig.places do
        if pid > 0 and def.placeId == pid then
            return def.kind
        end
    end
    return "unknown"
end

return WorldConfig
