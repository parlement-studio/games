--!strict
-- ServerStorage/PlayerData/Schema.luau
--
-- The authoritative persisted shape for one player of Monster Relic, per
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
local ElementConfig = require(ReplicatedStorage.Shared.Config.ElementConfig)
local PersistenceConfig = require(ReplicatedStorage.Shared.Config.PersistenceConfig)
local RarityConfig = require(ReplicatedStorage.Shared.Config.RarityConfig)

type PlayerData = Types.PlayerData
type MonsterEntry = Types.MonsterEntry
type BaseData = Types.BaseData
type Building = Types.Building
type Personality = Types.Personality
type Element = Types.Element
type Rarity = Types.Rarity
type NewMonsterArgs = Types.NewMonsterArgs

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

-- Valid element enum values (element doc E2). Single source of truth is
-- ElementConfig.order; mirrored here so validators read one schema surface.
Schema.ELEMENTS = ElementConfig.order

-- Valid rarity enum values (rarity doc R1-R5). Single source of truth is
-- RarityConfig.order; mirrored here so validators read one schema surface.
Schema.RARITIES = RarityConfig.order

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

-- True iff the value is a valid Element enum string (delegates to the config).
function Schema.isValidElement(value: any): boolean
    return ElementConfig.isValidElement(value)
end

-- True iff the value is a valid Rarity enum string (delegates to the config).
function Schema.isValidRarity(value: any): boolean
    return RarityConfig.isValidRarity(value)
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

        -- S4 (item capture): the onboarding freebies are now SEEDED AS ITEMS
        -- (visible in the backpack — "3 item gratis" per the decision doc)
        -- instead of the legacy hidden counter, which new profiles seed at 0.
        -- Migrations drains any LEGACY remainder into items on load.
        freeCapturesRemaining = 0,
        items = { capture_net = CaptureConfig.freeCapturesOnboarding },

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

-- Mints a new Monster entry (the atomic capture commit calls this). species /
-- personality / source / hotspotId are supplied by Capture; `id` is minted
-- here via a server-side GUID. NEVER reused.
--
-- `element` (element doc E3): rolled HERE server-side (uniform via
-- ElementConfig.rollWeights) when the caller does not supply one — the standard
-- capture path. A supplied-but-INVALID value is re-rolled, never trusted (the
-- args may have crossed a remote boundary upstream).
--
-- `rarity` (rarity doc R1/R5): same contract — nil = wild-catch roll (80/20
-- via RarityConfig.rollWeights); a boss-drop path supplies its tier explicitly
-- (e.g. "Rare"); a supplied-but-INVALID value falls back to the wild roll.
function Schema.newMonster(args: NewMonsterArgs): MonsterEntry
    local element: Element
    if args.element ~= nil and ElementConfig.isValidElement(args.element) then
        element = args.element :: Element
    else
        element = ElementConfig.rollElement()
    end
    local rarity: Rarity
    if args.rarity ~= nil and RarityConfig.isValidRarity(args.rarity) then
        rarity = args.rarity :: Rarity
    else
        rarity = RarityConfig.rollRarity()
    end
    return {
        id = HttpService:GenerateGUID(false),
        species = args.species,
        personality = args.personality,
        element = element,
        rarity = rarity,
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
Schema.defaultMonster = Schema.newMonster

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

-- Adds a Monster entry to `data.roster` IFF below the cap. Maintains the O(1)
-- `data.rosterCount` cache. Returns:
--   (true, entry)            on success
--   (false, "roster_full")   at the cap (E6, C5)
--   (false, "duplicate_id")  GUID collision (effectively impossible)
function Schema.addToRoster(data: PlayerData, entry: MonsterEntry): (boolean, any)
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

-- Removes a Monster by id from `data.roster`. Maintains `data.rosterCount`.
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
        if not Schema.isValidElement(entry.element) then
            return false, "invalid element on entry " .. tostring(id)
        end
        if not Schema.isValidRarity(entry.rarity) then
            return false, "invalid rarity on entry " .. tostring(id)
        end
    end
    return true, nil
end

return Schema
