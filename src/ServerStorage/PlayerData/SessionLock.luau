--!strict
-- ServerStorage/PlayerData/SessionLock.luau
--
-- Session locking, per design/gdd/persistence-gdd.md (v1.2) §"Session Lock
-- Pattern" + E1, and .claude/rules/datastores.md (session locking REQUIRED).
-- SERVER-ONLY. Prevents data duplication across servers: a profile may only be
-- loaded/saved by the server that holds its lock.
--
-- Distinguishes (E1):
--   mine   (existing.jobId == this server) -> re-acquire (fast rejoin)
--   stale  (no heartbeat for >= lockStaleSeconds) -> steal, log lock_stolen
--   active (held & fresh by another server) -> retry/backoff; ultimately KICK
--
-- Liveness: the owning server heartbeats every lockHeartbeatSec (30s); the
-- stale window (90s) is >= 3x the heartbeat, so a live server's lock never
-- looks stale.
--
-- Every store op is pcall-wrapped (datastores.md). The DataStore service is
-- injectable (setDataStoreService) so tests use a MOCK and never touch the real
-- service.

local DataStoreServiceReal = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.PersistenceConfig)

local SessionLock = {}

-- Injected dependencies (overridable for tests). Default to the real service +
-- the real JobId.
local dataStoreService: any = DataStoreServiceReal
local jobId: string = game.JobId
local lockStore: any = nil

-- Optional analytics hook: called as logger(event: string, payload: table).
local logger: ((event: string, payload: { [string]: any }) -> ())? = nil

local function log(event: string, payload: { [string]: any })
    if logger then
        logger(event, payload)
    end
end

-- Returns the lock DataStore handle, or nil if GetDataStore itself throws
-- (ADR-001 H4). Callers MUST treat a nil store as a failed op: acquire -> false
-- (caller kicks); heartbeat/release -> silent no-op (best-effort).
local function getStore(): any?
    if lockStore == nil then
        local ok, store = pcall(function()
            return dataStoreService:GetDataStore(Config.lockStoreName)
        end)
        if not ok or store == nil then
            log("get_store_failed", { store = Config.lockStoreName, err = tostring(store) })
            return nil
        end
        lockStore = store
    end
    return lockStore
end

local function lockKey(userId: number): string
    return Config.lockKeyPrefix .. userId
end

-- ── Dependency injection (tests / ops) ─────────────────────────────────────

-- Inject a (mock) DataStoreService. Resets the cached store handle.
function SessionLock.setDataStoreService(service: any)
    dataStoreService = service
    lockStore = nil
end

-- Override the JobId (tests simulate "another server" by changing it).
function SessionLock.setJobId(id: string)
    jobId = id
end

function SessionLock.getJobId(): string
    return jobId
end

-- Test-only: write a durable lock value directly (no acquire transaction), so a
-- spec can seed a lock whose { jobId, gen } the save-path fence (ADR-002 M-2)
-- reads. `jobIdOverride` defaults to the current jobId. Pass an explicit gen to
-- simulate a foreign steal (different jobId / higher gen).
function SessionLock._writeLockForTest(userId: number, gen: number, jobIdOverride: string?)
    local store = getStore()
    if store == nil then
        return
    end
    pcall(function()
        store:SetAsync(lockKey(userId), {
            jobId = jobIdOverride or jobId,
            time = os.time(),
            gen = gen,
        })
    end)
end

-- Inject a structured logger (analytics: lock_stolen, lock_failed, ...).
function SessionLock.setLogger(fn: (event: string, payload: { [string]: any }) -> ())
    logger = fn
end

-- ── Lock operations ─────────────────────────────────────────────────────

-- Acquires the lock for `userId`. Returns (true, gen) on success (free / mine /
-- stale), where `gen` is the acquired monotonic generation. Returns (false, nil)
-- if the lock is held & fresh by another server after all retries — the caller
-- must KICK the player (E1). Never loads over an active lock.
--
-- FENCE TOKEN (ADR-002 M-2): every OWNERSHIP TRANSFER mints a strictly higher
-- generation. gen = (existing.gen or 0) + 1 on a fresh acquire, a stale-steal,
-- AND a mine-reacquire (all write a new ownership stamp). Heartbeat does NOT
-- bump gen (it refreshes time only). The bump is computed inside the UpdateAsync
-- transform, so it is atomic and cross-server-correct. The caller stores the
-- returned gen on the Profile and replays it into the pre-save ownership fence.
function SessionLock.acquire(userId: number): (boolean, number?)
    local key = lockKey(userId)
    local store = getStore()
    if store == nil then
        -- GetDataStore failed (H4): cannot prove the lock is free -> refuse, so
        -- the caller kicks rather than risk a cross-server dupe.
        log("lock_acquire_failed", { userId = userId, jobId = jobId, reason = "get_store_failed" })
        return false, nil
    end

    for attempt = 1, Config.lockAcquireMaxAttempts do
        local stolenFrom: string? = nil
        local ok, result = pcall(function()
            return store:UpdateAsync(key, function(existing)
                local now = os.time()
                if existing ~= nil and existing.jobId ~= jobId and (now - existing.time) < Config.lockStaleSeconds then
                    -- ACTIVE on another server: refuse. Returning nil makes
                    -- UpdateAsync keep the existing value unchanged.
                    return nil
                end
                if existing ~= nil and existing.jobId ~= jobId then
                    -- Stale: we are stealing a presumed-dead server's lock.
                    stolenFrom = existing.jobId
                end
                -- Mint a strictly higher generation on this ownership transfer.
                -- A lock value with no gen (pre-ADR-002) is treated as gen 0.
                local nextGen = (existing ~= nil and existing.gen or 0) + 1
                return { jobId = jobId, time = now, gen = nextGen }
            end)
        end)

        if ok and result ~= nil and result.jobId == jobId then
            if stolenFrom ~= nil then
                log("lock_stolen", { userId = userId, fromJobId = stolenFrom, thisJobId = jobId, gen = result.gen })
            end
            return true, result.gen
        end

        if not ok then
            log("lock_acquire_error", { userId = userId, attempt = attempt, err = tostring(result) })
        end

        if attempt < Config.lockAcquireMaxAttempts then
            task.wait(Config.lockAcquireBackoffSec)
        end
    end

    log("lock_acquire_failed", { userId = userId, jobId = jobId })
    return false, nil
end

-- Refreshes our lock's timestamp so it never goes stale mid-session. Called
-- every lockHeartbeatSec. No-op (won't clobber) if another server stole it.
-- PRESERVES gen unchanged (ADR-002 M-2): a heartbeat is NOT an ownership
-- transfer, so it must never bump the fence token — only `time` advances.
function SessionLock.heartbeat(userId: number)
    local key = lockKey(userId)
    local store = getStore()
    if store == nil then
        return -- H4: best-effort; a missed beat is recoverable (stale window).
    end
    pcall(function()
        store:UpdateAsync(key, function(existing)
            if existing ~= nil and existing.jobId ~= jobId then
                return nil -- a stealer owns it; do not clobber
            end
            -- Carry the existing gen forward unchanged (default 0 for a pre-gen
            -- lock value); only `time` is refreshed.
            local keepGen = (existing ~= nil and existing.gen) or 0
            return { jobId = jobId, time = os.time(), gen = keepGen }
        end)
    end)
end

-- Returns true IFF the durable lock for `userId` currently reads OUR jobId AND
-- the given gen (ADR-002 M-2 FENCE). A cheap pcalled GetAsync (READ bucket,
-- separate from the write bucket). A FAILED read returns FALSE: we cannot prove
-- ownership, so we fence out — the money-safe direction (a missed save is
-- recoverable via the dirty flag + next tick; a divergent write is not). Called
-- by PlayerDataService.saveProfile right before SetAsync.
function SessionLock.ownershipMatches(userId: number, ourJobId: string, gen: number): boolean
    local key = lockKey(userId)
    local store = getStore()
    if store == nil then
        return false -- H4: cannot prove ownership -> fence out.
    end
    local ok, existing = pcall(function()
        return store:GetAsync(key)
    end)
    if not ok then
        log("ownership_check_failed", { userId = userId, jobId = ourJobId, err = tostring(existing) })
        return false -- failed read -> fence out (money-safe).
    end
    if type(existing) ~= "table" then
        return false -- lock cleared/missing: we no longer own it.
    end
    return existing.jobId == ourJobId and existing.gen == gen
end

-- Releases our lock (clears it). Only releases if WE own it — never clears a
-- lock another server has legitimately taken.
function SessionLock.release(userId: number)
    local key = lockKey(userId)
    local store = getStore()
    if store == nil then
        return -- H4: best-effort; the lock goes stale on its own and is reclaimable.
    end
    pcall(function()
        store:UpdateAsync(key, function(existing)
            if existing ~= nil and existing.jobId ~= jobId then
                return existing -- not ours; leave it
            end
            return nil -- clear (RemoveAsync-equivalent via UpdateAsync)
        end)
    end)
end

return SessionLock
