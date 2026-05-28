--!strict
-- Shared/Types.luau
--
-- The authoritative persisted shapes for Brainrot Inc., per
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
-- Canonical field names (locked, §3.6): the per-Brainrot GUID is `id`; the
-- per-Brainrot counter/provenance block is `history`. No aliases.

-- Personality enum (personality-gdd §3.1). The ONLY personality data persisted;
-- runtime state (Working/OnBreak/Walkout) is ephemeral and never stored.
export type Personality = "Hyper" | "Lazy" | "Chaotic" | "Loyal" | "Rebel"

-- Per-Brainrot lifetime counters + capture provenance.
export type BrainrotHistory = {
    coins: number, -- lifetime Meme Coins this Brainrot has produced (Idle #3)
    rdef: number, -- raids defended (Raid #6)
    rwon: number, -- raids won (Raid #6)
    fame: number, -- fame contribution (provisioned, 0 at launch)
    capturedAt: number, -- os.time() at capture (server clock)
    captureSource: string, -- "manual" | "auto"
    hotspotId: string, -- where it was caught (flavor + analytics)
}

-- One owned Brainrot. Keyed in `roster` by its own `id` (GUID).
export type BrainrotEntry = {
    id: string, -- GUID, minted server-side at capture; also the roster map key
    species: number, -- numeric species id (not a display name)
    personality: Personality, -- persisted enum
    level: number, -- progression; default 1
    xp: number, -- accumulated XP; default 0
    evoStage: number, -- evolution stage; 0 = base
    history: BrainrotHistory,
    fav: boolean, -- favorite flag: locks from auto/bulk release
}

-- One factory building. MVP seeds exactly one ("b1").
export type Building = {
    id: string, -- stable building id; also the key in BaseData.buildings
    factoryLevel: number, -- upgrade_factory level (0..30)
    workerSlotLevel: number, -- upgrade_worker_slot level (0..10)
    storageLevel: number, -- upgrade_storage level (0..12)
    deployment: { [string]: string? }, -- tostring(slotIndex) -> Brainrot id | nil
    walkoutCooldownUntil: number, -- os.time() the Rebel walkout cooldown ends; 0 = none
}

-- The whole base / factory block (Idle Production #3 owns the SHAPE).
export type BaseData = {
    buildings: { [string]: Building }, -- keyed by building id; MVP: { b1 = ... }
    pendingOnline: number, -- ONLINE pending sub-accumulator (sibling of pendingOffline.coins)
    deployedCount: number, -- cached count of deployed Brainrots across all buildings
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
    roster: { [string]: BrainrotEntry }, -- map keyed by GUID
    rosterCount: number, -- cached count of roster entries (kept in sync)

    coins: number, -- Meme Coins (soft currency); server-authoritative; >= 0
    gems: number, -- premium currency; provisioned, unused at launch; >= 0

    freeCapturesRemaining: number, -- onboarding free captures; seeded from CaptureConfig

    lastSeen: number, -- os.time() of last SAVE; used to compute offline elapsed
    pendingOffline: PendingOffline,

    base: BaseData, -- factory/deployment block (Idle #3); v1 baseline

    shieldUntil: number, -- raid shield expiry MIRROR (MemoryStore is authoritative)
    revengeTarget: string?, -- UserId (string) the player may counter-raid
    revengeUntil: number, -- os.time() the 24h revenge window closes
    raidsWon: number, -- lifetime raids won (player-level)
    raidsDefended: number, -- lifetime successful defenses (player-level)

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

-- Arguments to mint a new Brainrot (Capture supplies these; id is minted).
export type NewBrainrotArgs = {
    species: number,
    personality: Personality,
    source: string, -- "manual" | "auto"
    hotspotId: string,
}

-- Offline resolver injected by Idle Production (#3). Persistence supplies the
-- roster, base, and clamped elapsed seconds; the resolver returns integer coins
-- accrued. Default (until Idle installs one) returns 0 — Persistence never
-- fabricates economy numbers (it owns the CLOCK, not the RATES).
export type OfflineResolver = (roster: { [string]: BrainrotEntry }, base: BaseData, elapsedSeconds: number) -> number

return {}
