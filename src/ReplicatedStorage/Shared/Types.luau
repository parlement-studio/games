--!strict
-- Shared/Types.luau
--
-- The authoritative persisted shapes for Monster Relic, per
-- design/gdd/persistence-gdd.md (v1.2) §3. These types are shared so the
-- client can build a READ-ONLY mirror of the player profile — there are NO
-- secrets here (no txLog/nextSeq/lock data is part of the client mirror; the
-- full PlayerData type is shared only as the contract every server consumer
-- reads/writes against). Per .claude/rules/shared-modules.md, types belong in
-- ReplicatedStorage.
--
-- NEVER store Instances or functions in any of these shapes (DataStore
-- serializes tables of JSON-safe scalars only).
--
-- Canonical field names (locked, §3.6): the per-Monster GUID is `id`; the
-- per-Monster counter/provenance block is `history`. No aliases.

-- Personality enum (personality-gdd §3.1). The ONLY personality data persisted;
-- runtime state (Working/OnBreak/Walkout) is ephemeral and never stored.
export type Personality = "Hyper" | "Lazy" | "Chaotic" | "Loyal" | "Rebel"

-- Element enum (design/decisions/2026-06-07-element-system.md E2, LOCKED).
-- Combat-affinity axis, orthogonal to Personality: rolled SERVER-SIDE at
-- capture mint (uniform), PERMANENT (never rerolled — element doc E4). The
-- advantage circle + multipliers live in Shared/Config/ElementConfig.luau.
export type Element = "Fire" | "Nature" | "Water" | "Volt" | "Wind"

-- Rarity enum (design/decisions/2026-06-07-rarity-droprate.md R1-R5, LOCKED).
-- Rarity-by-SOURCE (Vision Pivot Decision 8): wild catches roll Common 80% /
-- Uncommon 20% server-side at mint; Rare+ only ever arrive via boss-drop
-- paths that SUPPLY the rarity explicitly. PERMANENT once set (like element).
-- Weights/multipliers live in Shared/Config/RarityConfig.luau.
export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"

-- Per-Monster lifetime counters + capture provenance.
export type MonsterHistory = {
    coins: number, -- lifetime Meme Coins this Monster has produced (Idle #3)
    rdef: number, -- raids defended (Raid #6)
    rwon: number, -- raids won (Raid #6)
    fame: number, -- fame contribution (provisioned, 0 at launch)
    capturedAt: number, -- os.time() at capture (server clock)
    captureSource: string, -- "manual" | "auto"
    hotspotId: string, -- where it was caught (flavor + analytics)
}

-- One owned Monster. Keyed in `roster` by its own `id` (GUID).
export type MonsterEntry = {
    id: string, -- GUID, minted server-side at capture; also the roster map key
    species: number, -- numeric species id (not a display name)
    personality: Personality, -- persisted enum
    element: Element, -- persisted enum; rolled at capture mint, PERMANENT (element doc E3/E4)
    rarity: Rarity, -- persisted enum; wild roll 80/20 at mint OR supplied by a boss-drop path, PERMANENT (rarity doc R1/R5)
    level: number, -- progression; default 1
    xp: number, -- accumulated XP; default 0
    evoStage: number, -- evolution stage; 0 = base
    history: MonsterHistory,
    fav: boolean, -- favorite flag: locks from auto/bulk release
}

-- One factory building. MVP seeds exactly one ("b1").
export type Building = {
    id: string, -- stable building id; also the key in BaseData.buildings
    factoryLevel: number, -- upgrade_factory level (0..30)
    workerSlotLevel: number, -- upgrade_worker_slot level (0..10)
    storageLevel: number, -- upgrade_storage level (0..12)
    deployment: { [string]: string? }, -- tostring(slotIndex) -> Monster id | nil
    walkoutCooldownUntil: number, -- os.time() the Rebel walkout cooldown ends; 0 = none
}

-- The whole base / factory block (Idle Production #3 owns the SHAPE).
export type BaseData = {
    buildings: { [string]: Building }, -- keyed by building id; MVP: { b1 = ... }
    pendingOnline: number, -- ONLINE pending sub-accumulator (sibling of pendingOffline.coins)
    deployedCount: number, -- cached count of deployed Monsters across all buildings
}

-- Accrued-but-uncollected OFFLINE rewards (pending-collect model, §2.4).
export type PendingOffline = {
    coins: number, -- coins waiting to be collected (offline slice)
    from: number, -- window start (lastSeen at accrual) — recap UI
    to: number, -- window end (clamped) — recap UI
}

-- Lifetime / global stats (leaderboard + analytics + Evolution milestones).
export type PlayerStats = {
    totalCoinsEarned: number, -- lifetime GROSS coins earned (never decremented); leaderboard value
    playtime: number, -- total seconds played (accrued on save)
    lifetimeCaptures: number, -- total successful captures (Auto-Catch unlock @50)
}

-- The whole player profile (the payload inside the stored wrapper).
export type PlayerData = {
    roster: { [string]: MonsterEntry }, -- map keyed by GUID
    rosterCount: number, -- cached count of roster entries (kept in sync)

    coins: number, -- Meme Coins (soft currency); server-authoritative; >= 0
    gems: number, -- premium currency; provisioned, unused at launch; >= 0

    freeCapturesRemaining: number, -- LEGACY onboarding free-capture counter; new profiles seed 0 (converted to free Capture Nets in `items`); migration drains any legacy remainder into items
    items: { [string]: number }, -- persisted backpack: itemId -> count (S4; e.g. capture_net). JSON-safe, additive

    lastSeen: number, -- os.time() of last SAVE; used to compute offline elapsed
    pendingOffline: PendingOffline,

    base: BaseData, -- factory/deployment block (Idle #3); v1 baseline

    shieldUntil: number, -- raid shield expiry MIRROR (MemoryStore is authoritative)
    revengeTarget: string?, -- UserId (string) the player may counter-raid
    revengeUntil: number, -- os.time() the 24h revenge window closes
    raidsWon: number, -- lifetime raids won (player-level)
    raidsDefended: number, -- lifetime successful defenses (player-level)

    -- FTUE goal-checklist flags (first-hour-daily-loop-gdd §3). Optional/additive:
    -- old profiles carry nil (read defensively). The other 4 goals derive from
    -- rosterCount / deployment / factoryLevel.
    ftue: { wonDuel: boolean, killedBoss: boolean }?,

    -- DAILY LOOP state (first-hour-daily-loop-gdd §3). Optional/additive: old
    -- profiles carry nil and DailyService backfills + applies the first reset on
    -- load. `lastResetAt` is the os.time() of the reset currently applied (0 =
    -- never → forces a reset). `quests` is exactly 3, rolled at each reset.
    -- `bossFirstKill` maps a boss personality -> already-killed-today (Build #4).
    daily: {
        lastResetAt: number,
        loginClaimed: boolean,
        quests: {
            {
                id: string,
                kind: string, -- "catch_element" | "boss_kills" | "earn_coins"
                param: string?, -- e.g. the target Element for catch_element
                target: number,
                progress: number,
                claimed: boolean,
            }
        },
        bossFirstKill: { [string]: boolean },
    }?,

    nextSeq: number, -- monotonic mutation counter; ++ per committed mutation
    txLog: { [string]: any }, -- map idempotencyKey -> small JSON-safe storedResult; bounded to txLogMaxEntries (ADR-001 C2)
    txLogOrder: { string }, -- insertion-order list of txLog keys; drives the ring-trim eviction (oldest first)
    consumedReceipts: { [string]: number }, -- durable ProcessReceipt dedupe markers: purchaseId -> consumedAt (os.time() server clock). TIME-bounded by consumedReceiptHorizonSec, with a consumedReceiptHardCap overflow safety (ADR-002 H-2)
    consumedReceiptsOrder: { string }, -- insertion-order list of consumedReceipts keys; drives the front-of-list age prune + overflow trim (oldest first)

    stats: PlayerStats,

    settings: { [string]: any }, -- free-form JSON-safe settings map

    createdAt: number, -- os.time() at first creation; never changes
}

-- What actually goes into DataStore (the stored wrapper).
--
-- lockJobId / lockGen are FORENSIC fence stamps (ADR-002 M-2): the JobId and
-- monotonic lock generation that authored this write. The PRIMARY save fence is
-- the pre-write SessionLock.ownershipMatches read; these embedded fields let a
-- forensic / future load path detect or audit a backward-generation write. Both
-- are optional (a wrapper written before the fence shipped, or by a path with no
-- lock context, carries nil).
export type StoredWrapper = {
    version: number, -- schema version of `data`
    data: PlayerData, -- the payload above
    savedAt: number, -- os.time() at write
    lockJobId: string?, -- JobId of the server that owned the lock at write time
    lockGen: number?, -- the lock generation this server held when it wrote
}

-- The durable SESSION LOCK value (DataStore "SessionLocks" key). Documented here
-- for reference; SessionLock owns its read/write. Shape (ADR-002 M-2):
--   { jobId: string, time: number, gen: number }
-- `gen` is a monotonic generation that increments on EVERY ownership transfer
-- (fresh acquire / stale-steal / mine-reacquire), and is PRESERVED unchanged by
-- heartbeat (which only refreshes `time`). A save proves it still owns the lock
-- by re-reading and matching both jobId AND gen before SetAsync.
export type SessionLockValue = {
    jobId: string, -- the owning server's JobId
    time: number, -- os.time() of the last acquire/heartbeat (staleness clock)
    gen: number, -- monotonic ownership generation (fence token)
}

-- Arguments to mint a new Monster (Capture supplies these; id is minted).
-- `element` is OPTIONAL: when nil, Schema.newMonster rolls it server-side via
-- ElementConfig.rollElement (the standard capture path); a caller may supply a
-- pre-rolled value (e.g. a deterministic test) which is validated at mint.
export type NewMonsterArgs = {
    species: number,
    personality: Personality,
    element: Element?,
    -- OPTIONAL: nil = wild-catch roll (80/20). Boss-drop paths supply the tier
    -- explicitly (e.g. "Rare" from a Colony Boss); validated at mint, an
    -- invalid value falls back to the wild roll (never trusted).
    rarity: Rarity?,
    source: string, -- "manual" | "auto"
    hotspotId: string,
}

-- Offline resolver injected by Idle Production (#3). Persistence supplies the
-- roster, base, and clamped elapsed seconds; the resolver returns integer coins
-- accrued. Default (until Idle installs one) returns 0 — Persistence never
-- fabricates economy numbers (it owns the CLOCK, not the RATES).
export type OfflineResolver = (roster: { [string]: MonsterEntry }, base: BaseData, elapsedSeconds: number) -> number

return {}
