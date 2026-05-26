--!strict
-- ServerStorage/PlayerData/PlayerDataService.luau
--
-- The main Persistence service for Brainrot Inc., per
-- design/gdd/persistence-gdd.md (v1.2). SERVER-ONLY, server-authoritative.
-- EVERY other system reads/mutates player state THROUGH this API; none touch
-- DataStoreService directly.
--
-- Lifecycle (§2.1):  acquire lock -> heartbeat -> load (pcall+retry) ->
-- migrate -> default-if-new -> cache -> compute offline accrual ->
-- (play: dirty-flag + autosave + atomic mutations + idempotency) ->
-- final save + release lock.
--
-- KEY DISCIPLINE (.claude/rules/datastores.md, NON-NEGOTIABLE):
--   * session locking required (SessionLock)
--   * schema versioning required (Schema.wrap / Migrations.migrate)
--   * every store op pcall-wrapped with exponential-backoff retry (F-BACKOFF)
--   * save debounce + dirty flag (never spam saves; respect 6s per-key cooldown)
--   * key format "Player_" .. UserId
--   * never store Instances/functions
--   * NEVER load a blank profile over a FAILED read (E2)
--
-- ANTI-EXPLOIT: all timestamps use server os.time() only (never client time).
-- All mutations are server-authoritative and atomic (§2.3, E9).
--
-- The DataStoreService is injectable (setDataStoreService) so tests use a MOCK.

local DataStoreServiceReal = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayersReal = game:GetService("Players")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config.PersistenceConfig)
local Signal = require(ReplicatedStorage.Packages.Signal)

local Schema = require(script.Parent.Schema)
local Migrations = require(script.Parent.Migrations)
local SessionLock = require(script.Parent.SessionLock)

type PlayerData = Types.PlayerData
type BrainrotEntry = Types.BrainrotEntry
type OfflineResolver = Types.OfflineResolver

-- A live in-memory profile for one player.
type Profile = {
    userId: number,
    data: PlayerData,
    dirty: boolean,
    dirtyAt: number, -- os.clock() when first marked dirty (debug)
    lastSaveClock: number, -- os.clock() of last ACTUAL successful write (debounce)
    loaded: boolean,
}

local PlayerDataService = {}

-- ── Injected dependencies (overridable for tests) ────────────────────────
local dataStoreService: any = DataStoreServiceReal
local profileStore: any = nil

-- Offline resolver injected by Idle Production (#3). DEFAULT is a no-op that
-- returns 0 coins: Persistence owns the CLOCK + the pending pool, NOT the
-- economy RATES. We never fabricate an offline coin number (§2.4 critical
-- note). Idle installs the real resolver via setOfflineResolver.
local offlineResolver: OfflineResolver = function(_roster, _base, _elapsed)
    return 0
end

-- Optional structured logger (incidents: save_failed, clock_skew, ...).
local logger: ((event: string, payload: { [string]: any }) -> ())? = nil

-- ── State ────────────────────────────────────────────────────────────────
local profiles: { [number]: Profile } = {}
local heartbeatThreads: { [number]: thread } = {}
local autosaveRunning = false

-- ── Signals (cross-system decoupling, §5.3) ───────────────────────────────
PlayerDataService.DataLoaded = Signal.new() -- (player, data)
PlayerDataService.DataSaved = Signal.new() -- (player, ok)
PlayerDataService.CoinsChanged = Signal.new() -- (player, newBalance, delta, reason)

-- ── Helpers ───────────────────────────────────────────────────────────────

local function log(event: string, payload: { [string]: any })
    if logger then
        logger(event, payload)
    end
end

local function getStore(): any
    if profileStore == nil then
        profileStore = dataStoreService:GetDataStore(Config.dataStoreName)
    end
    return profileStore
end

local function profileKey(userId: number): string
    return Config.keyPrefix .. userId
end

local function clamp(value: number, low: number, high: number): number
    if value < low then
        return low
    elseif value > high then
        return high
    end
    return value
end

-- F-BACKOFF: retry wait on attempt n = min(backoffBaseSec ^ n, backoffMaxSec).
local function backoffWait(attempt: number): number
    return math.min(Config.backoffBaseSec ^ attempt, Config.backoffMaxSec)
end

local function profileFor(player: Player): Profile?
    return profiles[player.UserId]
end

-- ── Dependency injection (tests / wiring) ──────────────────────────────────

-- Inject a (mock) DataStoreService into BOTH this service and SessionLock so a
-- test never touches the real store.
function PlayerDataService.setDataStoreService(service: any)
    dataStoreService = service
    profileStore = nil
    SessionLock.setDataStoreService(service)
end

-- Idle Production (#3) installs the real offline coin resolver here.
function PlayerDataService.setOfflineResolver(fn: OfflineResolver)
    offlineResolver = fn
end

-- Inject a structured logger.
function PlayerDataService.setLogger(fn: (event: string, payload: { [string]: any }) -> ())
    logger = fn
    SessionLock.setLogger(fn)
end

-- ── Offline accrual (F-OFFLINE, §2.4) ──────────────────────────────────────

-- Computes offline accrual on load. Server clock only. Clamps elapsed to
-- [0, offlineCapSeconds]. Calls the INJECTED resolver for the coin amount; if
-- nothing is installed, accrues 0 (never fabricates economy). Does NOT advance
-- lastSeen (that happens on SAVE, so a failed load cannot eat time).
local function applyOfflineAccrual(data: PlayerData, now: number)
    local elapsedRaw = now - data.lastSeen

    if elapsedRaw < -Config.clockSkewToleranceSec then
        log("clock_skew", { lastSeen = data.lastSeen, now = now, elapsedRaw = elapsedRaw })
    end

    local elapsed = clamp(elapsedRaw, 0, Config.offlineCapSeconds)
    if elapsed <= 0 then
        return -- nothing offline (new player, negative skew, or no time passed)
    end

    local accrued = 0
    local ok, result = pcall(function()
        return offlineResolver(data.roster, data.base, elapsed)
    end)
    if ok and type(result) == "number" and result > 0 then
        accrued = math.floor(result)
    elseif not ok then
        log("offline_resolver_error", { err = tostring(result) })
    end

    if accrued > 0 then
        data.pendingOffline.coins += accrued
    end
    data.pendingOffline.from = data.lastSeen
    data.pendingOffline.to = data.lastSeen + elapsed
end

-- ── Load (§2.1 steps 1-5) ──────────────────────────────────────────────────

-- pcall + retry GetAsync. Returns:
--   ok=true,  value=<wrapper|nil>  -> successful read (nil means NEW player)
--   ok=false                        -> all retries failed (caller must KICK, E2)
local function readWithRetry(key: string): (boolean, any)
    local store = getStore()
    for attempt = 1, Config.loadMaxAttempts do
        local ok, result = pcall(function()
            return store:GetAsync(key)
        end)
        if ok then
            return true, result
        end
        log("load_attempt_failed", { key = key, attempt = attempt, err = tostring(result) })
        if attempt < Config.loadMaxAttempts then
            task.wait(backoffWait(attempt))
        end
    end
    return false, nil
end

local function startHeartbeat(userId: number)
    heartbeatThreads[userId] = task.spawn(function()
        while profiles[userId] ~= nil do
            task.wait(Config.lockHeartbeatSec)
            if profiles[userId] == nil then
                break
            end
            SessionLock.heartbeat(userId)
        end
    end)
end

-- Loads (or creates) a player's profile. Returns the loaded PlayerData on
-- success, or nil if the player must be KICKED (lock held by another server, or
-- load/migrate failed — E1/E2/E8). NEVER returns a blank profile over a failed
-- read. On any failure path the lock is released.
function PlayerDataService.load(player: Player): PlayerData?
    local userId = player.UserId

    if profiles[userId] ~= nil then
        return profiles[userId].data -- already loaded (defensive)
    end

    -- (1) Acquire session lock. Held-and-fresh-elsewhere -> kick.
    if not SessionLock.acquire(userId) then
        log("load_kick_locked", { userId = userId })
        return nil
    end

    -- (3) Read with retry. Failed read -> kick (E2). NEVER blank-over-failed.
    local readOk, wrapper = readWithRetry(profileKey(userId))
    if not readOk then
        log("load_kick_read_failed", { userId = userId })
        SessionLock.release(userId)
        return nil
    end

    -- (4)/(5) Migrate or default. A genuine nil (successful read) is a NEW
    -- player and gets Schema.default(); a structurally-broken migrate is a
    -- failed load (E8) -> kick, key preserved untouched.
    local data: PlayerData
    if wrapper == nil then
        data = Schema.default()
    else
        -- Normalize + migrate inside ONE pcall so a structurally-broken value
        -- (e.g. a non-table payload) is caught and treated as a failed load
        -- (E8) rather than crashing the load thread. We do NOT overwrite the
        -- stored key on this path — it is preserved untouched for recovery.
        local migrateOk, migrated = pcall(function()
            local raw = wrapper.data or wrapper -- tolerate an un-wrapped legacy value
            if type(raw) == "table" then
                raw.version = wrapper.version or raw.version
            end
            return Migrations.migrate(raw)
        end)
        if not migrateOk then
            log("load_kick_migrate_failed", { userId = userId, err = tostring(migrated) })
            SessionLock.release(userId)
            return nil
        end
        data = migrated
    end

    -- (5) Offline accrual (server clock only; pending-collect).
    applyOfflineAccrual(data, os.time())

    -- (6) Cache + start heartbeat.
    profiles[userId] = {
        userId = userId,
        data = data,
        dirty = false,
        dirtyAt = 0,
        lastSaveClock = 0,
        loaded = true,
    }
    startHeartbeat(userId)

    PlayerDataService.DataLoaded:Fire(player, data)
    return data
end

-- ── Accessors ──────────────────────────────────────────────────────────────

-- The live profile wrapper (internal callers). nil if not loaded.
function PlayerDataService.get(player: Player): Profile?
    return profileFor(player)
end

-- The live PlayerData payload. nil if not loaded.
function PlayerDataService.getData(player: Player): PlayerData?
    local p = profileFor(player)
    return if p then p.data else nil
end

-- True iff the player's profile is loaded and cached.
function PlayerDataService.isLoaded(player: Player): boolean
    return profiles[player.UserId] ~= nil
end

-- Marks the profile dirty so the next autosave tick persists it.
function PlayerDataService.markDirty(player: Player)
    local p = profileFor(player)
    if p and not p.dirty then
        p.dirty = true
        p.dirtyAt = os.clock()
    end
end

-- ── Atomic mutation path (§2.3, E9) ─────────────────────────────────────────

-- Runs `mutator(data)` against the live in-memory profile as ONE serialized
-- transaction (the in-memory profile is the single source of truth this server
-- mutates; the durable write follows the save discipline). Increments nextSeq,
-- marks dirty, and returns whatever the mutator returns.
--
-- Idempotency (optional): pass `idempotencyKey`. If that key was already
-- processed (present in txLog), the mutation is a NO-OP and `update` returns
-- (true, nil, true) — (ok, result, wasDuplicate). On a fresh key the mutator
-- runs and the key is recorded in the ring buffer. This is how capture-debit /
-- reroll / receipt grants avoid double-spend/double-grant on a replay.
function PlayerDataService.update(
    player: Player,
    mutator: (data: PlayerData) -> any,
    idempotencyKey: string?
): (boolean, any, boolean)
    local p = profileFor(player)
    if p == nil then
        return false, "not_loaded", false
    end
    local data = p.data

    if idempotencyKey ~= nil and PlayerDataService.hasProcessed(player, idempotencyKey) then
        return true, nil, true -- replay: no-op, prior commit stands
    end

    local result = mutator(data)

    data.nextSeq += 1
    if idempotencyKey ~= nil then
        PlayerDataService.recordTx(player, idempotencyKey)
    end

    PlayerDataService.markDirty(player)
    return true, result, false
end

-- True iff `key` is already in the player's txLog (a processed idempotency key).
function PlayerDataService.hasProcessed(player: Player, key: string): boolean
    local p = profileFor(player)
    if p == nil then
        return false
    end
    for _, existing in ipairs(p.data.txLog) do
        if existing == key then
            return true
        end
    end
    return false
end

-- Appends an idempotency key to the txLog ring buffer, trimming to the last
-- txLogMaxEntries (E7). Bounds both value size and lookup cost.
function PlayerDataService.recordTx(player: Player, key: string)
    local p = profileFor(player)
    if p == nil then
        return
    end
    local log_ = p.data.txLog
    table.insert(log_, key)
    while #log_ > Config.txLogMaxEntries do
        table.remove(log_, 1)
    end
end

-- ── Roster operations (§9 #4, E6) ───────────────────────────────────────────

-- Adds a Brainrot to the roster IFF below the cap (E6). Returns
-- (true, entry) on success or (false, "roster_full"). The cap check uses the
-- O(1) cached rosterCount, which is kept exactly in sync here and self-healed
-- on load. Does NOT charge coins / free captures — Capture composes that into
-- one atomic op via update().
function PlayerDataService.addBrainrot(player: Player, entry: BrainrotEntry): (boolean, any)
    local p = profileFor(player)
    if p == nil then
        return false, "not_loaded"
    end
    local data = p.data
    if data.rosterCount >= Config.rosterCap then
        return false, "roster_full"
    end
    if data.roster[entry.id] ~= nil then
        return false, "duplicate_id" -- GUID collision (effectively impossible)
    end
    data.roster[entry.id] = entry
    data.rosterCount += 1
    data.nextSeq += 1
    PlayerDataService.markDirty(player)
    return true, entry
end

-- Removes a Brainrot by id. Returns (true, removedEntry) or (false, reason).
-- Refuses to remove a fav-locked entry unless `force` is true (E6: fav locks
-- from auto/bulk release; an explicit player action passes force=true).
function PlayerDataService.removeBrainrot(player: Player, id: string, force: boolean?): (boolean, any)
    local p = profileFor(player)
    if p == nil then
        return false, "not_loaded"
    end
    local data = p.data
    local entry = data.roster[id]
    if entry == nil then
        return false, "not_found"
    end
    if entry.fav and not force then
        return false, "favorited"
    end
    data.roster[id] = nil
    data.rosterCount -= 1
    data.nextSeq += 1
    PlayerDataService.markDirty(player)
    return true, entry
end

-- Reads a single Brainrot by id (nil if absent).
function PlayerDataService.getBrainrot(player: Player, id: string): BrainrotEntry?
    local p = profileFor(player)
    if p == nil then
        return nil
    end
    return p.data.roster[id]
end

-- ── Save (§2.2, E3) ──────────────────────────────────────────────────────

-- Whether at least saveDebounceSec has elapsed since the last actual write to
-- this profile's key (respects the 6s per-key cooldown; saveDebounceSec >= 7).
local function debounceElapsed(p: Profile): boolean
    return (os.clock() - p.lastSaveClock) >= Config.saveDebounceSec
end

-- Writes the profile durably with pcall + exponential-backoff retry
-- (F-BACKOFF). Before writing: accrues playtime ((now - lastSeen) into
-- stats.playtime) and advances lastSeen to now (so the same delta is never
-- counted twice). The dirty flag is cleared ONLY on a successful write (E3) —
-- a failed save leaves it set so the next tick retries; no data silently lost.
-- Returns true on success.
--
-- `opts.force` skips the debounce gate (used by PlayerRemoving / BindToClose so
-- the final save is never skipped). Returns true (no-op success) if not dirty.
function PlayerDataService.save(player: Player, opts: { force: boolean? }?): boolean
    local p = profileFor(player)
    if p == nil then
        return true -- nothing to save (already removed)
    end
    local force = opts ~= nil and opts.force == true

    if not p.dirty and not force then
        return true
    end
    if not force and not debounceElapsed(p) then
        return false -- too soon; dirty flag remains, next tick retries
    end

    local data = p.data
    local now = os.time()
    -- Playtime accrual on-save (§2.2 / §3.6). Guard against negative skew.
    local delta = now - data.lastSeen
    if delta > 0 then
        data.stats.playtime += delta
    end
    data.lastSeen = now

    -- Mirror the live shield expiry would be refreshed from MemoryStore here
    -- (E10) once Raid Shield (#7) is implemented; out of scope for #1.

    local wrapper = Schema.wrap(data)
    local key = profileKey(player.UserId)
    local store = getStore()

    local success = false
    for attempt = 1, Config.saveMaxAttempts do
        local ok, err = pcall(function()
            store:SetAsync(key, wrapper)
        end)
        if ok then
            success = true
            break
        end
        log("save_attempt_failed", { userId = player.UserId, attempt = attempt, err = tostring(err) })
        if attempt < Config.saveMaxAttempts then
            task.wait(backoffWait(attempt))
        end
    end

    if success then
        p.dirty = false
        p.lastSaveClock = os.clock()
    else
        -- E3: do NOT clear the dirty flag — the next autosave / removing /
        -- BindToClose attempt retries. Roll lastSeen back so playtime/offline
        -- are not corrupted by an un-persisted advance.
        data.lastSeen = now - delta
        if delta > 0 then
            data.stats.playtime -= delta
        end
        log("save_failed", { userId = player.UserId })
    end

    PlayerDataService.DataSaved:Fire(player, success)
    return success
end

-- ── Lifecycle: removing + autosave + shutdown ──────────────────────────────

-- Called on Players.PlayerRemoving: final save (force) then release the lock
-- and drop the cache + heartbeat (§2.1 steps 7-8).
function PlayerDataService.onPlayerRemoving(player: Player)
    local userId = player.UserId
    PlayerDataService.save(player, { force = true })

    -- Stop heartbeat by removing the profile entry, then release the lock.
    profiles[userId] = nil
    heartbeatThreads[userId] = nil
    SessionLock.release(userId)
end

-- The debounced autosave loop (§2.2). Saves each dirty profile whose debounce
-- window has elapsed. Idempotent to start (guards against double-start). Uses
-- task.wait (no deprecated wait()).
function PlayerDataService.startAutosave()
    if autosaveRunning then
        return
    end
    autosaveRunning = true
    task.spawn(function()
        while autosaveRunning do
            -- Tick frequently but only WRITE when dirty + debounce elapsed.
            task.wait(Config.saveDebounceSec)
            for _, player in ipairs(PlayersReal:GetPlayers()) do
                local p = profiles[player.UserId]
                if p ~= nil and p.dirty and debounceElapsed(p) then
                    PlayerDataService.save(player)
                end
            end
        end
    end)
end

function PlayerDataService.stopAutosave()
    autosaveRunning = false
end

-- Saves ALL connected players in parallel + releases their locks, bounded by
-- bindToCloseBudgetSec (E4). Called from game:BindToClose in the bootstrap.
function PlayerDataService.saveAllOnClose()
    local players = PlayersReal:GetPlayers()
    local threads: { thread } = {}
    for _, player in ipairs(players) do
        local t = task.spawn(function()
            PlayerDataService.save(player, { force = true })
            SessionLock.release(player.UserId)
            profiles[player.UserId] = nil
            heartbeatThreads[player.UserId] = nil
        end)
        table.insert(threads, t)
    end

    local deadline = os.clock() + Config.bindToCloseBudgetSec
    while os.clock() < deadline do
        local alive = false
        for _, t in ipairs(threads) do
            if coroutine.status(t) ~= "dead" then
                alive = true
                break
            end
        end
        if not alive then
            break
        end
        task.wait(0.1)
    end
end

-- ── Test support ────────────────────────────────────────────────────────

-- Test-only: inject a fully-formed profile into the cache without touching the
-- store (so unit tests can exercise mutations directly). Returns the profile.
function PlayerDataService._setProfileForTest(userId: number, data: PlayerData)
    profiles[userId] = {
        userId = userId,
        data = data,
        dirty = false,
        dirtyAt = 0,
        lastSaveClock = 0,
        loaded = true,
    }
end

-- Test-only: clears all cached state (call between tests for isolation).
function PlayerDataService._resetForTest()
    for userId in pairs(profiles) do
        profiles[userId] = nil
    end
    for userId in pairs(heartbeatThreads) do
        heartbeatThreads[userId] = nil
    end
    autosaveRunning = false
end

return PlayerDataService
