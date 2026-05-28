--!strict
-- ServerStorage/PlayerData/Migrations.luau
--
-- The migration framework, per design/gdd/persistence-gdd.md (v1.2) §3.5.
-- Runs on EVERY load, upgrading data v -> CURRENT_SCHEMA_VERSION. Each step is
-- forward-only, idempotent (running twice is harmless), and additive where
-- possible. NEVER delete data in a migration without a backup window.
--
-- SERVER-ONLY (ServerStorage). PURE: operates on a plain table, no Instances.
--
-- SAFETY RULE (E8): if migrate() throws on structurally-corrupt input it cannot
-- repair, the load path treats it as a FAILED load and does NOT overwrite the
-- player's key with a blank profile. Recoverable corruption (missing fields,
-- bad enum, count drift) is REPAIRED here without throwing.
--
-- PRE-LAUNCH NOTE (v1.2): `base` (BaseData) was added DIRECTLY to the v1
-- baseline, NOT via a v1->v2 step, because this is pre-production with NO live
-- data. CURRENT_SCHEMA_VERSION stays 1. The defensive backfill below still
-- seeds `base` for any partial/older-build record. The version ladder remains
-- the mechanism for any genuine POST-launch schema change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local CaptureConfig = require(ReplicatedStorage.Shared.Config.CaptureConfig)
local PersistenceConfig = require(ReplicatedStorage.Shared.Config.PersistenceConfig)
local Schema = require(script.Parent.Schema)

type PlayerData = Types.PlayerData

local Migrations = {}

-- The personality-repair hook. Personality (#2) will replace this via
-- setPersonalityRepair() so migrate() can re-roll an invalid/missing enum
-- (personality-gdd E5). Default: deterministic safe fallback to "Loyal" if the
-- stored enum is invalid, otherwise keep it. We do NOT random-roll here so the
-- framework stays pure/testable; Personality injects the real roll.
local repairPersonality: (entry: any) -> Types.Personality = function(entry)
    if Schema.isValidPersonality(entry.personality) then
        return entry.personality
    end
    return "Loyal"
end

-- Lets Personality (#2) inject its validateOrRepair implementation.
function Migrations.setPersonalityRepair(fn: (entry: any) -> Types.Personality)
    repairPersonality = fn
end

-- Defensive backfill: runs every load. Cheap; makes partial/corrupt records
-- valid. Self-heals the rosterCount cache from the actual map (E6).
local function backfill(data: any)
    data.roster = data.roster or {}
    data.coins = data.coins or 0
    data.gems = data.gems or 0
    data.freeCapturesRemaining = data.freeCapturesRemaining or CaptureConfig.freeCapturesOnboarding

    data.lastSeen = data.lastSeen or os.time()
    data.pendingOffline = data.pendingOffline or { coins = 0, from = 0, to = 0 }
    data.pendingOffline.coins = data.pendingOffline.coins or 0
    data.pendingOffline.from = data.pendingOffline.from or 0
    data.pendingOffline.to = data.pendingOffline.to or 0

    -- Factory/deployment block (Idle #3). v1 baseline; backfilled for any
    -- partial record.
    data.base = data.base or Schema.defaultBase()
    data.base.buildings = data.base.buildings or { b1 = Schema.defaultBuilding("b1") }
    data.base.pendingOnline = data.base.pendingOnline or 0
    data.base.deployedCount = data.base.deployedCount or 0
    for bid, building in pairs(data.base.buildings) do
        building.id = building.id or bid
        building.factoryLevel = building.factoryLevel or 0
        building.workerSlotLevel = building.workerSlotLevel or 0
        building.storageLevel = building.storageLevel or 0
        building.deployment = building.deployment or {}
        building.walkoutCooldownUntil = building.walkoutCooldownUntil or 0
    end

    data.shieldUntil = data.shieldUntil or 0
    data.revengeUntil = data.revengeUntil or 0
    data.raidsWon = data.raidsWon or 0
    data.raidsDefended = data.raidsDefended or 0

    data.nextSeq = data.nextSeq or 1

    -- txLog is now a MAP { [key]: storedResult } with a parallel insertion-order
    -- list (ADR-001 C2). Defensively normalize any legacy ARRAY form (a plain
    -- list of idempotency-key strings) into the map: each key maps to `true`
    -- (no prior stored result is recoverable), preserving order. Then trim the
    -- ring to the configured bound by oldest-first eviction.
    if type(data.txLog) ~= "table" then
        data.txLog = {}
    end
    if type(data.txLogOrder) ~= "table" then
        data.txLogOrder = {}
    end
    if #data.txLog > 0 then
        -- Array form detected: rebuild as map + order list.
        local legacyKeys = data.txLog
        data.txLog = {}
        data.txLogOrder = {}
        for _, key in ipairs(legacyKeys) do
            if type(key) == "string" and data.txLog[key] == nil then
                data.txLog[key] = true
                table.insert(data.txLogOrder, key)
            end
        end
    else
        -- Map form (or empty): rebuild a clean order list, dropping any stale
        -- order entries whose key no longer exists in the map.
        local rebuilt = {}
        local seen: { [string]: boolean } = {}
        for _, key in ipairs(data.txLogOrder) do
            if type(key) == "string" and data.txLog[key] ~= nil and not seen[key] then
                table.insert(rebuilt, key)
                seen[key] = true
            end
        end
        -- Any map keys missing from the order list (corruption) get appended so
        -- they remain trimmable rather than leaking unboundedly.
        for key in pairs(data.txLog) do
            if not seen[key] then
                table.insert(rebuilt, key)
                seen[key] = true
            end
        end
        data.txLogOrder = rebuilt
    end
    while #data.txLogOrder > PersistenceConfig.txLogMaxEntries do
        local oldest = table.remove(data.txLogOrder, 1)
        if oldest ~= nil then
            data.txLog[oldest] = nil
        end
    end

    -- Durable ProcessReceipt dedupe markers (ADR-002 H-2). `consumedReceipts` is
    -- now a TIMESTAMP map purchaseId -> consumedAt (os.time()), TIME-bounded by
    -- consumedReceiptHorizonSec. DEFENSIVE BACKFILL: convert any legacy presence
    -- marker (boolean `true`, the old ADR-001 shape) to a numeric stamp so it is
    -- NOT immediately pruned. We are pre-launch with no real-money data, so this
    -- is a no-op in practice, but it keeps the code honest. Use os.time() as a
    -- conservative "consumed recently" stamp (the wrapper savedAt is not passed
    -- into migrate; os.time() is the safe, non-prunable choice).
    if type(data.consumedReceipts) ~= "table" then
        data.consumedReceipts = {}
    end
    if type(data.consumedReceiptsOrder) ~= "table" then
        data.consumedReceiptsOrder = {}
    end
    do
        local nowStamp = os.time()
        for key, value in pairs(data.consumedReceipts) do
            -- Legacy boolean-true presence marker -> conservative numeric stamp.
            -- Any non-number value (true, or stray garbage) is normalized.
            if type(value) ~= "number" then
                data.consumedReceipts[key] = nowStamp
            end
        end
        local rebuilt = {}
        local seen: { [string]: boolean } = {}
        for _, key in ipairs(data.consumedReceiptsOrder) do
            if type(key) == "string" and data.consumedReceipts[key] ~= nil and not seen[key] then
                table.insert(rebuilt, key)
                seen[key] = true
            end
        end
        for key in pairs(data.consumedReceipts) do
            if not seen[key] then
                table.insert(rebuilt, key)
                seen[key] = true
            end
        end
        data.consumedReceiptsOrder = rebuilt
    end
    -- Overflow safety only here (ADR-002 H-2): time-pruning is owned by the live
    -- markReceiptConsumed path; migrate just guarantees the map cannot exceed the
    -- hard cap on load (oldest-first trim).
    while #data.consumedReceiptsOrder > PersistenceConfig.consumedReceiptHardCap do
        local oldest = table.remove(data.consumedReceiptsOrder, 1)
        if oldest ~= nil then
            data.consumedReceipts[oldest] = nil
        end
    end

    data.stats = data.stats or {}
    data.stats.totalCoinsEarned = data.stats.totalCoinsEarned or 0
    data.stats.playtime = data.stats.playtime or 0
    data.stats.lifetimeCaptures = data.stats.lifetimeCaptures or 0

    data.settings = data.settings or {}
    data.createdAt = data.createdAt or os.time()

    -- Per-Brainrot repair. The roster map key is the canonical id.
    for id, entry in pairs(data.roster) do
        entry.id = entry.id or id
        entry.species = entry.species or 0
        entry.personality = repairPersonality(entry)
        entry.level = entry.level or 1
        entry.xp = entry.xp or 0
        entry.evoStage = entry.evoStage or 0
        entry.history = entry.history or {}
        entry.history.coins = entry.history.coins or 0
        entry.history.rdef = entry.history.rdef or 0
        entry.history.rwon = entry.history.rwon or 0
        entry.history.fame = entry.history.fame or 0
        entry.history.capturedAt = entry.history.capturedAt or os.time()
        entry.history.captureSource = entry.history.captureSource or "manual"
        entry.history.hotspotId = entry.history.hotspotId or ""
        if entry.fav == nil then
            entry.fav = false
        end
    end

    -- Self-heal the cached count from the actual map (E6). Done AFTER the
    -- roster exists so a missing/drifted cache is corrected, never trusted.
    data.rosterCount = Schema.countKeys(data.roster)
end

-- Upgrades `data` from its stored version to CURRENT_SCHEMA_VERSION and repairs
-- recoverable corruption. Idempotent. Throws ONLY on structurally-unusable
-- input (e.g. `data` is not a table) so the load path can treat it as E8.
function Migrations.migrate(data: any): PlayerData
    if type(data) ~= "table" then
        error("Migrations.migrate: data is not a table (got " .. typeof(data) .. ")")
    end

    data.version = data.version or 1

    -- ── Version ladder (forward-only). v1 is the launch schema; no steps yet.
    -- Future POST-launch jumps go here, e.g.:
    --
    -- if data.version == 1 then
    --     data.roster = data.roster or {}
    --     for _, entry in pairs(data.roster) do
    --         entry.iv = entry.iv or defaultIv()   -- Battle GDD adds `iv`
    --     end
    --     data.version = 2
    -- end

    -- Defensive backfill (every load).
    backfill(data)

    data.version = Schema.CURRENT_SCHEMA_VERSION
    return (data :: any) :: PlayerData
end

return Migrations
