--!strict
-- ServerStorage/PlayerData/Schema.luau
--
-- The authoritative persisted shape for one player of Brainrot Inc., per
-- design/gdd/persistence-gdd.md (v1.2) §3.2-§3.4. SERVER-ONLY (lives in
-- ServerStorage, never replicated). PURE: every builder here returns a plain
-- table of JSON-safe scalars/tables — NO Instances, NO functions, NO closures
-- stored in the data.
--
-- Schema version: 1 (see CURRENT_SCHEMA_VERSION + Migrations.luau).
-- `base` (BaseData) ships in the v1 baseline (pre-launch, no v1->v2 migration).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Types = require(ReplicatedStorage.Shared.Types)
local CaptureConfig = require(ReplicatedStorage.Shared.Config.CaptureConfig)
local PersistenceConfig = require(ReplicatedStorage.Shared.Config.PersistenceConfig)

type PlayerData = Types.PlayerData
type BrainrotEntry = Types.BrainrotEntry
type BaseData = Types.BaseData
type Building = Types.Building
type Personality = Types.Personality
type NewBrainrotArgs = Types.NewBrainrotArgs

local Schema = {}

-- The launch schema version. `base` was added to this baseline directly (NOT
-- via a v1->v2 migration) because we are pre-production with no live data
-- (§3.2a / §3.5). Future POST-launch changes bump this and add a step in
-- Migrations.luau.
Schema.CURRENT_SCHEMA_VERSION = 1

-- Valid personality enum values (personality-gdd §3.1). Used by validators and
-- by the migrate repair hook.
Schema.PERSONALITIES = { "Hyper", "Lazy", "Chaotic", "Loyal", "Rebel" }

local PERSONALITY_SET: { [string]: boolean } = {}
for _, p in ipairs(Schema.PERSONALITIES) do
    PERSONALITY_SET[p] = true
end

-- ── Pure helpers ────────────────────────────────────────────────────────

-- Counts the keys of a map (used to self-heal a drifted rosterCount cache).
function Schema.countKeys(map: { [any]: any }): number
    local n = 0
    for _ in pairs(map) do
        n += 1
    end
    return n
end

-- True iff the value is a valid Personality enum string.
function Schema.isValidPersonality(value: any): boolean
    return type(value) == "string" and PERSONALITY_SET[value] == true
end

-- ── Default builders ──────────────────────────────────────────────────────

-- One factory building with everything at its starting value.
function Schema.defaultBuilding(id: string): Building
    return {
        id = id,
        factoryLevel = 0,
        workerSlotLevel = 0,
        storageLevel = 0,
        deployment = {},
        walkoutCooldownUntil = 0,
    }
end

-- The whole base: MVP seeds exactly one building ("b1").
function Schema.defaultBase(): BaseData
    return {
        buildings = { b1 = Schema.defaultBuilding("b1") },
        pendingOnline = 0,
        deployedCount = 0,
    }
end

-- A fresh, fully-populated profile for a brand-new player. Seeds
-- freeCapturesRemaining from the single source of truth,
-- CaptureConfig.freeCapturesOnboarding.
function Schema.default(): PlayerData
    local now = os.time()
    return {
        roster = {},
        rosterCount = 0,

        coins = 0,
        gems = 0,

        freeCapturesRemaining = CaptureConfig.freeCapturesOnboarding,

        lastSeen = now,
        pendingOffline = { coins = 0, from = 0, to = 0 },

        base = Schema.defaultBase(),

        shieldUntil = 0,
        revengeTarget = nil,
        revengeUntil = 0,
        raidsWon = 0,
        raidsDefended = 0,

        nextSeq = 1,
        -- txLog is a MAP idempotencyKey -> small storedResult (ADR-001 C2); the
        -- parallel txLogOrder array preserves insertion order for ring-trim.
        txLog = {},
        txLogOrder = {},
        -- Durable ProcessReceipt dedupe markers (ADR-001 §3); bounded ring.
        consumedReceipts = {},
        consumedReceiptsOrder = {},

        stats = {
            totalCoinsEarned = 0,
            playtime = 0,
            lifetimeCaptures = 0,
        },

        settings = {},

        createdAt = now,
    }
end

-- Mints a new Brainrot entry (the atomic capture commit calls this). species /
-- personality / source / hotspotId are supplied by Capture; `id` is minted
-- here via a server-side GUID. NEVER reused.
function Schema.newBrainrot(args: NewBrainrotArgs): BrainrotEntry
    return {
        id = HttpService:GenerateGUID(false),
        species = args.species,
        personality = args.personality,
        level = 1,
        xp = 0,
        evoStage = 0,
        history = {
            coins = 0,
            rdef = 0,
            rwon = 0,
            fame = 0,
            capturedAt = os.time(),
            captureSource = args.source,
            hotspotId = args.hotspotId,
        },
        fav = false,
    }
end

-- Backwards-compatible alias (GDD prose references both names).
Schema.defaultBrainrot = Schema.newBrainrot

-- Wraps a profile for durable storage (what SetAsync writes). Embeds the FENCE
-- STAMP (ADR-002 M-2): the owning server's JobId + lock generation, for forensic
-- detection/audit of a backward-generation write. The primary save fence is the
-- pre-write ownershipMatches read; these fields are belt-and-suspenders. Both
-- are optional so a caller with no lock context can still wrap (lockGen = nil).
function Schema.wrap(data: PlayerData, lockJobId: string?, lockGen: number?): Types.StoredWrapper
    return {
        version = Schema.CURRENT_SCHEMA_VERSION,
        data = data,
        savedAt = os.time(),
        lockJobId = lockJobId,
        lockGen = lockGen,
    }
end

-- ── Pure roster mutation helpers (ADR-001 C1, C5) ──────────────────────────
--
-- These operate ONLY on the `data` table handed to them (the deep copy inside
-- an `update()` transaction). They do NOT touch the cache, bump `nextSeq`, or
-- mark dirty — that happens exactly once, in PlayerDataService.update(). The
-- cap check lives HERE (C5), so the rejection is part of the transaction and a
-- caller composing debit+add never debits on a "roster_full" outcome.

-- Adds a Brainrot entry to `data.roster` IFF below the cap. Maintains the O(1)
-- `data.rosterCount` cache. Returns:
--   (true, entry)            on success
--   (false, "roster_full")   at the cap (E6, C5)
--   (false, "duplicate_id")  GUID collision (effectively impossible)
function Schema.addToRoster(data: PlayerData, entry: BrainrotEntry): (boolean, any)
    if data.rosterCount >= PersistenceConfig.rosterCap then
        return false, "roster_full"
    end
    if data.roster[entry.id] ~= nil then
        return false, "duplicate_id"
    end
    data.roster[entry.id] = entry
    data.rosterCount += 1
    return true, entry
end

-- Removes a Brainrot by id from `data.roster`. Maintains `data.rosterCount`.
-- Refuses to remove a fav-locked entry unless `force` is true (E6). Returns:
--   (true, removedEntry)     on success
--   (false, "not_found")     no such id
--   (false, "favorited")     fav-locked and not forced
function Schema.removeFromRoster(data: PlayerData, id: string, force: boolean?): (boolean, any)
    local entry = data.roster[id]
    if entry == nil then
        return false, "not_found"
    end
    if entry.fav and not force then
        return false, "favorited"
    end
    data.roster[id] = nil
    data.rosterCount -= 1
    return true, entry
end

-- ── Validators (used by tests + the migrate repair pass) ───────────────────

-- True iff `data` is a structurally valid profile at the current version. This
-- is a sanity check, NOT a substitute for migrate() repair. Returns false +
-- reason on the first problem found.
function Schema.validate(data: any): (boolean, string?)
    if type(data) ~= "table" then
        return false, "data is not a table"
    end
    if type(data.roster) ~= "table" then
        return false, "roster missing or not a table"
    end
    if type(data.rosterCount) ~= "number" then
        return false, "rosterCount missing or not a number"
    end
    if type(data.coins) ~= "number" then
        return false, "coins missing or not a number"
    end
    if type(data.base) ~= "table" or type(data.base.buildings) ~= "table" then
        return false, "base/buildings missing"
    end
    if type(data.txLog) ~= "table" then
        return false, "txLog missing or not a table"
    end
    if type(data.nextSeq) ~= "number" then
        return false, "nextSeq missing or not a number"
    end
    for id, entry in pairs(data.roster) do
        if type(entry) ~= "table" then
            return false, "roster entry not a table: " .. tostring(id)
        end
        if not Schema.isValidPersonality(entry.personality) then
            return false, "invalid personality on entry " .. tostring(id)
        end
    end
    return true, nil
end

return Schema
