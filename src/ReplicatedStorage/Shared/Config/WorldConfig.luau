--!strict
-- Shared/Config/WorldConfig.luau
--
-- WORLD UNIVERSE place registry (System #27 / GH #23). Single source of truth for
-- "which Roblox places exist + their role + server model + capacity". Read by the
-- teleport layer (WorldService) and any system that needs to cross a place boundary.
--
-- ARSITEKTUR (world-universe-gdd.md v1.1, owner-locked 2026-06-09):
--   * OVERWORLD — single seamless place: laut + 4-5 pulau berburu (TIER beda per
--     pulau) + Hunter Camp port + Colony Boss Tier-1. Shared publik, StreamingEnabled.
--   * KANDANG  — basis privat per-pemain (reserved server, key = UserId).
--   * RAID A/B — Tier-3 raid, party-instanced (reserved), token-gated.
--   * SUPER_BOSS — Tier-2, party-instanced (reserved).
--
-- ⚠️ Pulau ≠ place: ke-4/5 pulau ADA DI overworld (satu place, dipisah
-- StreamingEnabled). HANYA Kandang/Raid/Super Boss yang place TERPISAH.
--
-- 🔧 placeId DIISI NOL sampai tiap place dibuat + dipublish (Studio Asset Manager
-- "Add New Place", atau Creator Dashboard / Open Cloud). Teleport ke place ber-id 0
-- DI-SKIP + warning (lihat world-universe-gdd §3.1 / §7 edge case #10). Diisi oleh
-- release-manager setelah place ada.
--
-- No secrets here — pure config, aman di ReplicatedStorage (shared client+server).
--
-- Schema version: 1

export type PlaceKind = "overworld" | "kandang" | "raid" | "super_boss"

export type PlaceDef = {
    -- Roblox placeId (0 = belum dibuat/dipublish; teleport di-skip + warn).
    placeId: number,
    -- Peran place (drives server model + dispatch logic).
    kind: PlaceKind,
    -- Kapasitas PER SALINAN server (BUKAN batas total pemain — Roblox jalankan
    -- banyak salinan paralel). Range per kind di komentar bawah.
    maxPlayers: number,
}

local WorldConfig = {
    version = 1,

    -- Universe (Experience) id — diisi saat publish (informational; teleport pakai
    -- placeId per-place, bukan ini).
    universeId = 10224556071,

    -- ── PLACE REGISTRY ──────────────────────────────────────────────────────
    -- Key = logical name dipakai di TeleportData.intent / WorldService.
    places = {
        -- START PLACE ("monster inc"). Pulau pertama (`land 1`) + Hunter Camp +
        -- spawn wild + Colony Boss Tier-1. maxPlayers Range 10-40 | Default 26.
        overworld = { placeId = 131913437012360, kind = "overworld" :: PlaceKind, maxPlayers = 26 },

        -- Basis privat per-pemain. DISPLAY NAME = "Sanctuary" (place name di Studio;
        -- key code tetap "kandang" = identifier internal stabil, sistem #26).
        -- Reserved by UserId; owner + visitor read-only. maxPlayers Range 1-12 | Default 8.
        kandang = { placeId = 92338616596672, kind = "kandang" :: PlaceKind, maxPlayers = 8 },

        -- Raid Dungeon Tier-3, party-instanced, token-gated. Range 1-8 | Default 6.
        raid_a = { placeId = 0, kind = "raid" :: PlaceKind, maxPlayers = 6 },
        raid_b = { placeId = 0, kind = "raid" :: PlaceKind, maxPlayers = 6 },

        -- Super Boss Tier-2, party-instanced. Range 1-8 | Default 6.
        super_boss = { placeId = 0, kind = "super_boss" :: PlaceKind, maxPlayers = 6 },
    } :: { [string]: PlaceDef },

    -- ── STREAMING (overworld) ───────────────────────────────────────────────
    -- StreamingEnabled WAJIB di overworld (laut + banyak pulau, mobile). Set di
    -- place Workspace; angka di sini = sumber tuning yg di-mirror.
    streaming = {
        -- Radius (studs) stream penuh di sekitar pemain. Range 512-2048 | Default 1024
        targetRadius = 1024,
        -- Radius minimum yang DIJAMIN ada (anti fall-through). Range 128-512 | Default 256
        minRadius = 256,
    },

    -- ── SPAWN DENSITY SCALING (per-region, anti sepi/rebutan) ────────────────
    -- spawnTarget(region) = clamp(baseSpawn + perPlayer*playersInRegion, min, max)
    -- (world-universe-gdd §2.5). Director server-authoritative per region pulau.
    spawn = {
        baseSpawn = 6, -- minimal saat 0-1 pemain (pulau tak pernah kosong). Range 1-20
        perPlayer = 2, -- tambahan slot monster per pemain di region. Range 0-5
        minSpawn = 4, -- pagar bawah. Range 1-20
        maxSpawn = 40, -- pagar atas (perf mobile). Range 5-100
    },

    -- ── TELEPORT / TRAVERSAL ────────────────────────────────────────────────
    teleport = {
        retry = 1, -- pcall retry sekali kalau TeleportService gagal. Range 0-3
        timeoutSec = 10, -- timeout reserve/dispatch. Range 5-30
    },
    -- Fast-travel intra-overworld (reposisi DALAM place, BUKAN TeleportService).
    -- Pulau cuma bisa fast-travel kalau sudah pernah dikunjungi via perahu
    -- (persisted `discoveredIslands`, gdd §2.3 / §3.4).
    fastTravel = {
        requiresDiscovered = true, -- harus berlayar dulu sebelum bisa loncat
        fadeSec = 0.4, -- durasi fade transisi. Range 0.1-1
    },
    -- MemoryStore TTL (detik) — koordinasi lintas-server (gdd §3.3).
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
