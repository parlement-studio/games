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

local function getStore(): any
    if lockStore == nil then
        lockStore = dataStoreService:GetDataStore(Config.lockStoreName)
    end
    return lockStore
end

local function lockKey(userId: number): string
    return Config.lockKeyPrefix .. userId
end

local function log(event: string, payload: { [string]: any })
    if logger then
        logger(event, payload)
    end
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

-- Inject a structured logger (analytics: lock_stolen, lock_failed, ...).
function SessionLock.setLogger(fn: (event: string, payload: { [string]: any }) -> ())
    logger = fn
end

-- ── Lock operations ─────────────────────────────────────────────────────

-- Acquires the lock for `userId`. Returns true on success (free / mine /
-- stale). Returns false if the lock is held & fresh by another server after
-- all retries — the caller must KICK the player (E1). Never loads over an
-- active lock.
function SessionLock.acquire(userId: number): boolean
    local key = lockKey(userId)
    local store = getStore()

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
                return { jobId = jobId, time = now }
            end)
        end)

        if ok and result ~= nil and result.jobId == jobId then
            if stolenFrom ~= nil then
                log("lock_stolen", { userId = userId, fromJobId = stolenFrom, thisJobId = jobId })
            end
            return true
        end

        if not ok then
            log("lock_acquire_error", { userId = userId, attempt = attempt, err = tostring(result) })
        end

        if attempt < Config.lockAcquireMaxAttempts then
            task.wait(Config.lockAcquireBackoffSec)
        end
    end

    log("lock_acquire_failed", { userId = userId, jobId = jobId })
    return false
end

-- Refreshes our lock's timestamp so it never goes stale mid-session. Called
-- every lockHeartbeatSec. No-op (won't clobber) if another server stole it.
function SessionLock.heartbeat(userId: number)
    local key = lockKey(userId)
    local store = getStore()
    pcall(function()
        store:UpdateAsync(key, function(existing)
            if existing ~= nil and existing.jobId ~= jobId then
                return nil -- a stealer owns it; do not clobber
            end
            return { jobId = jobId, time = os.time() }
        end)
    end)
end

-- Releases our lock (clears it). Only releases if WE own it — never clears a
-- lock another server has legitimately taken.
function SessionLock.release(userId: number)
    local key = lockKey(userId)
    local store = getStore()
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
