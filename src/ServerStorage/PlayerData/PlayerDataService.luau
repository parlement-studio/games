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
    player: Player?, -- the Player object (nil for orphaned/test profiles); used only to fire signals
    data: PlayerData,
    dirty: boolean,
    dirtyAt: number, -- os.clock() when first marked dirty (debug)
    lastSaveClock: number, -- os.clock() of last ACTUAL successful write (debounce + cadence)
    loaded: boolean,
    lockGen: number, -- the lock generation this server acquired (ADR-002 M-2 fence token); replayed into the pre-save ownership check
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
local heartbeatStop: { [number]: boolean } = {}
local autosaveRunning = false

-- Forward declaration: recordTx is defined after update() (which calls it) but
-- must be a module-local, not a global.
local recordTx: (p: Profile, key: string, result: any) -> ()

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

-- Returns the profile DataStore handle, or nil if GetDataStore itself fails
-- (ADR-001 H4). GetDataStore can throw (bad name, service down). Callers MUST
-- treat a nil store as a failed op: load -> kick, save -> leave dirty + retry.
local function getStore(): any?
    if profileStore == nil then
        local ok, store = pcall(function()
            return dataStoreService:GetDataStore(Config.dataStoreName)
        end)
        if not ok or store == nil then
            log("get_store_failed", { store = Config.dataStoreName, err = tostring(store) })
            return nil
        end
        profileStore = store
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

-- Deep-copies a JSON-safe value (the profile is tables of scalars/tables only —
-- NO Instances/functions, per the datastore rules). Used by update() so the
-- mutator runs against a COPY and a thrown mutator leaves the live profile
-- untouched (ADR-001 H5). Cheap relative to a DataStore round-trip.
local function deepCopy<T>(value: T): T
    if type(value) ~= "table" then
        return value
    end
    local out: { [any]: any } = {}
    for k, v in pairs(value :: any) do
        out[k] = deepCopy(v)
    end
    return (out :: any) :: T
end

-- F-BACKOFF: retry wait on attempt n = min(backoffBaseSec ^ n, backoffMaxSec).
local function backoffWait(attempt: number): number
    return math.min(Config.backoffBaseSec ^ attempt, Config.backoffMaxSec)
end

-- Remaining write-request budget for SetIncrementAsync (SetAsync/IncrementAsync
-- share this bucket), per .claude/rules/datastores.md "Monitor budget ... before
-- burst operations" (ADR-001 H2). pcall-wrapped: if the API is unavailable
-- (older mocks / odd platforms) we return math.huge so we NEVER wrongly throttle
-- a save — the budget guard is a safety optimization, not a correctness gate.
local function setWriteBudget(): number
    local ok, budget = pcall(function()
        return dataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync)
    end)
    if ok and type(budget) == "number" then
        return budget
    end
    return math.huge
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
    if store == nil then
        return false, nil -- GetDataStore failed (H4): treat as a failed read.
    end
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
    heartbeatStop[userId] = false
    heartbeatThreads[userId] = task.spawn(function()
        -- Belt-and-suspenders: a profile drop OR an explicit stop flag ends the
        -- loop. stopHeartbeat (ADR-001 C3/C4) also task.cancels this thread, so
        -- the flag is the fallback for the window between cancel and the next
        -- wait resuming.
        while profiles[userId] ~= nil and not heartbeatStop[userId] do
            task.wait(Config.lockHeartbeatSec)
            if profiles[userId] == nil or heartbeatStop[userId] then
                break
            end
            SessionLock.heartbeat(userId)
        end
    end)
end

-- Stops the heartbeat for `userId`: sets the stop flag, task.cancels the thread,
-- and AWAITS its death before clearing the handle. MUST run BEFORE release() so
-- a cancelled heartbeat can never re-write (refresh) a lock we are about to
-- release (ADR-001 C3/C4).
--
-- M-1 (ADR-002): an in-flight SessionLock.heartbeat UpdateAsync could otherwise
-- land AFTER release and resurrect the lock. After task.cancel we SPIN until
-- coroutine.status(thread) == "dead" with a bounded deadline
-- (heartbeatStopDeadlineSec), polling every heartbeatStopPollSec. If the
-- deadline passes (a pathological stuck thread) we log heartbeat_stop_timeout and
-- proceed — purely defensive: the stop flag + cancel already prevent the loop
-- body from re-stamping once the current task.wait resumes. The await is the
-- guarantee that we OBSERVE dead rather than assume it.
function PlayerDataService.stopHeartbeat(userId: number)
    heartbeatStop[userId] = true
    local thread = heartbeatThreads[userId]
    if thread ~= nil then
        -- Do not cancel/await ourselves if (defensively) called from inside the
        -- heartbeat thread — that would deadlock the await.
        if thread ~= coroutine.running() and coroutine.status(thread) ~= "dead" then
            pcall(task.cancel, thread)
            local deadline = os.clock() + Config.heartbeatStopDeadlineSec
            while coroutine.status(thread) ~= "dead" and os.clock() < deadline do
                task.wait(Config.heartbeatStopPollSec)
            end
            if coroutine.status(thread) ~= "dead" then
                log("heartbeat_stop_timeout", { userId = userId })
            end
        end
        heartbeatThreads[userId] = nil
    end
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

    -- (1) Acquire session lock. Held-and-fresh-elsewhere -> kick. Capture the
    -- acquired generation (ADR-002 M-2): it is the fence token the save path
    -- re-verifies against the durable lock before every SetAsync.
    local acquired, lockGen = SessionLock.acquire(userId)
    if not acquired then
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

    -- (6) Cache + start heartbeat. Store the acquired lock generation (M-2).
    profiles[userId] = {
        userId = userId,
        player = player,
        data = data,
        dirty = false,
        dirtyAt = 0,
        lastSaveClock = 0,
        loaded = true,
        lockGen = lockGen or 0,
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

-- THE single in-memory transaction (ADR-001: the ONLY place the profile is
-- mutated). Every gameplay mutation routes through here.
--
-- Contract (returns (ok, result, wasDuplicate)):
--   * Not loaded                    -> (false, "not_loaded", false)
--   * Replay (idempotencyKey known) -> (true, storedResult, true) — the PRIOR
--       committed result is returned, NOT nil; the prior commit stands.
--   * Fresh key / no key:
--       - DEEP-COPY data, pcall(mutator, copy).
--       - mutator ERROR -> discard the copy, NO seq bump, NO key record, NOT
--         dirty; log mutation_error; return (false, "mutation_error", false).
--         The live profile is byte-for-byte unchanged (full rollback, H5).
--       - mutator SUCCESS -> swap the copy in as the live profile, nextSeq += 1,
--         record txLog[key] = result (ring-trimmed by insertion order), mark
--         dirty; return (true, result, false).
--
-- The mutator MUST be NON-YIELDING (precompute any RNG / network / store reads
-- BEFORE calling update). It receives the deep copy and mutates it freely;
-- compose roster ops via Schema.addToRoster / Schema.removeFromRoster so a
-- compound debit+add commits both-or-neither (a "roster_full" return from the
-- helper lets the mutator bail WITHOUT debiting — and even if it errored after
-- a partial debit, the rollback discards it).
--
-- The stored result MUST be a small JSON-safe payload (it is persisted in the
-- txLog map). Do NOT return Instances/functions/large tables from a mutator
-- whose key is recorded.
function PlayerDataService.update(
    player: Player,
    mutator: (data: PlayerData) -> any,
    idempotencyKey: string?
): (boolean, any, boolean)
    local p = profileFor(player)
    if p == nil then
        return false, "not_loaded", false
    end

    -- Replay: return the PRIOR stored result (ADR-001 C2), not nil.
    if idempotencyKey ~= nil then
        local stored = p.data.txLog[idempotencyKey]
        if stored ~= nil then
            return true, stored, true
        end
    end

    -- Run the mutator against a DEEP COPY so a throw cannot leave partial state.
    local copy = deepCopy(p.data)
    local ok, result = pcall(mutator, copy)
    if not ok then
        -- Discard the copy entirely: no swap, no seq bump, no key record, not
        -- dirty. The live profile is untouched (ADR-001 H5). Retry re-applies.
        log("mutation_error", { userId = player.UserId, key = idempotencyKey, err = tostring(result) })
        return false, "mutation_error", false
    end

    -- Commit: the copy becomes the live profile. nextSeq++, txLog record, and
    -- markDirty happen EXACTLY ONCE, here (ADR-001 C1).
    copy.nextSeq += 1
    p.data = copy
    if idempotencyKey ~= nil then
        recordTx(p, idempotencyKey, result)
    end
    PlayerDataService.markDirty(player)
    return true, result, false
end

-- Records a committed idempotency key -> storedResult in the txLog MAP and
-- appends it to the insertion-order list, trimming the ring to txLogMaxEntries
-- oldest-first (ADR-001 C2, E7). Internal: only update() calls this, on commit.
function recordTx(p: Profile, key: string, result: any)
    local data = p.data
    if data.txLog[key] == nil then
        table.insert(data.txLogOrder, key)
    end
    -- Normalize a nil result to `true` so the key is still a recorded marker
    -- (presence == processed); a literal nil would be indistinguishable from
    -- "never seen" on replay lookup.
    data.txLog[key] = if result == nil then true else result
    while #data.txLogOrder > Config.txLogMaxEntries do
        local oldest = table.remove(data.txLogOrder, 1)
        if oldest ~= nil then
            data.txLog[oldest] = nil
        end
    end
end

-- True iff `key` was already processed (present in the player's txLog map).
function PlayerDataService.hasProcessed(player: Player, key: string): boolean
    local p = profileFor(player)
    if p == nil then
        return false
    end
    return p.data.txLog[key] ~= nil
end

-- ── Roster operations (§9 #4, E6) ───────────────────────────────────────────
--
-- Thin ergonomic wrappers that compose the PURE Schema helpers through
-- update() (ADR-001 C1), so add/remove share the ONE transaction's idempotency
-- / nextSeq / dirty bookkeeping. Gameplay systems that need to ALSO debit coins
-- / free captures atomically should call update() directly and invoke
-- Schema.addToRoster / Schema.removeFromRoster inside their mutator.

-- Adds a Brainrot to the roster IFF below the cap (E6). Returns
-- (true, entry) | (false, "roster_full") | (false, "duplicate_id"). Optional
-- idempotencyKey de-dupes a retried add.
function PlayerDataService.addBrainrot(player: Player, entry: BrainrotEntry, idempotencyKey: string?): (boolean, any)
    -- Pre-check the rejection reasons so callers get the PRECISE sentinel
    -- ("roster_full" / "duplicate_id") and no idempotency key is consumed on a
    -- rejected add. The authoritative check still runs inside the transaction.
    local pre = profileFor(player)
    if pre == nil then
        return false, "not_loaded"
    end
    if pre.data.rosterCount >= Config.rosterCap then
        return false, "roster_full"
    end
    if pre.data.roster[entry.id] ~= nil then
        return false, "duplicate_id"
    end

    local ok, result = PlayerDataService.update(player, function(data)
        local added, addResult = Schema.addToRoster(data, entry)
        if not added then
            -- Surface the sentinel by throwing so update() rolls back and does
            -- NOT record the idempotency key (the add never happened).
            error(addResult, 0)
        end
        return addResult
    end, idempotencyKey)
    if not ok then
        return false, result
    end
    return true, result
end

-- Removes a Brainrot by id. Returns (true, removedEntry) | (false, reason).
-- Refuses to remove a fav-locked entry unless `force` is true (E6).
function PlayerDataService.removeBrainrot(
    player: Player,
    id: string,
    force: boolean?,
    idempotencyKey: string?
): (boolean, any)
    -- Pre-check the rejection reasons WITHOUT a transaction so callers get the
    -- precise sentinel ("not_found" / "favorited") rather than a generic error,
    -- and no idempotency key is consumed on a rejected remove.
    local pre = profileFor(player)
    if pre == nil then
        return false, "not_loaded"
    end
    local existing = pre.data.roster[id]
    if existing == nil then
        return false, "not_found"
    end
    if existing.fav and not force then
        return false, "favorited"
    end

    local ok, result = PlayerDataService.update(player, function(data)
        local removed, removeResult = Schema.removeFromRoster(data, id, force)
        if not removed then
            error(removeResult, 0)
        end
        return removeResult
    end, idempotencyKey)
    if not ok then
        return false, result
    end
    return true, result
end

-- Reads a single Brainrot by id (nil if absent).
function PlayerDataService.getBrainrot(player: Player, id: string): BrainrotEntry?
    local p = profileFor(player)
    if p == nil then
        return nil
    end
    return p.data.roster[id]
end

-- ── Durable receipt grant (ADR-001 §3, real money) ──────────────────────────

-- Marks a purchaseId consumed in the DURABLE `consumedReceipts` map (ADR-002
-- H-2). The map is purchaseId -> consumedAt (os.time() server clock), TIME-
-- bounded by Config.consumedReceiptHorizonSec (NOT count-bounded — a count cap
-- could evict a still-redeliverable marker and cause a real-money double grant).
-- Operates on the `data` handed to a mutator (so it commits atomically with the
-- grant under the session lock). Pure: no cache/seq/dirty side effects.
--
-- Pruning is a cheap front-of-list walk over consumedReceiptsOrder (insertion-
-- ordered, so the head is always the oldest): pop the head while it is missing
-- from the map OR older than the horizon. A defense-in-depth overflow trim then
-- caps the map at consumedReceiptHardCap (only reachable by an abusive purchase
-- rate inside the horizon) and logs a consumed_receipts_overflow incident.
local function markReceiptConsumed(data: PlayerData, purchaseId: string)
    local now = os.time()
    if data.consumedReceipts[purchaseId] == nil then
        table.insert(data.consumedReceiptsOrder, purchaseId)
    end
    data.consumedReceipts[purchaseId] = now

    -- TIME prune (primary bound): drop oldest-first while the head is stale or
    -- dangling. We stop at the first still-fresh head (the rest are newer).
    local horizon = Config.consumedReceiptHorizonSec
    while #data.consumedReceiptsOrder > 0 do
        local head = data.consumedReceiptsOrder[1]
        local stamp = if head ~= nil then data.consumedReceipts[head] else nil
        if head == nil or stamp == nil then
            -- Dangling order entry whose marker is gone: drop and keep walking.
            table.remove(data.consumedReceiptsOrder, 1)
            if head ~= nil then
                data.consumedReceipts[head] = nil
            end
        elseif (now - stamp) > horizon then
            table.remove(data.consumedReceiptsOrder, 1)
            data.consumedReceipts[head] = nil
        else
            break -- head is fresh; everything after it is newer.
        end
    end

    -- OVERFLOW trim (defense-in-depth): cap the map deterministically.
    if #data.consumedReceiptsOrder > Config.consumedReceiptHardCap then
        log("consumed_receipts_overflow", {
            count = #data.consumedReceiptsOrder,
            cap = Config.consumedReceiptHardCap,
        })
        while #data.consumedReceiptsOrder > Config.consumedReceiptHardCap do
            local oldest = table.remove(data.consumedReceiptsOrder, 1)
            if oldest ~= nil then
                data.consumedReceipts[oldest] = nil
            end
        end
    end
end

-- The Persistence-side ProcessReceipt hook (ADR-001 §3). Monetization (#15)
-- wires the real MarketplaceService.ProcessReceipt callback to this.
--
-- `grantMutator(data)` applies the purchase's effect to the profile (e.g.
-- credit gems). It MUST be non-yielding and idempotent in shape (it only runs
-- on a FIRST grant — never on a replay). It may return a small JSON-safe result.
--
-- Flow:
--   1. Profile not loaded -> (false, "not_loaded"). Caller returns NotProcessedYet.
--   2. update() with key "receipt_"..purchaseId. Inside the transaction:
--        - already in consumedReceipts -> replay: return the prior result, no
--          double credit.
--        - else apply grant + set the durable marker (commits atomically).
--   3. FORCE a durable save. Return (true, result) ONLY if the save succeeds —
--      else (false, "save_failed"). Returning success without a confirmed
--      durable write is forbidden (a redelivery dedupes via the durable marker).
--
-- Returns (granted: boolean, result: any). The caller maps granted==true ->
-- Enum.ProductPurchaseDecision.PurchaseGranted, else NotProcessedYet.
function PlayerDataService.processReceiptGrant(
    player: Player,
    purchaseId: string,
    grantMutator: (data: PlayerData) -> any
): (boolean, any)
    local p = profileFor(player)
    if p == nil then
        return false, "not_loaded" -- caller -> NotProcessedYet
    end

    -- H-1 SNAPSHOT (ADR-002): capture the LIVE profile state BEFORE the grant
    -- transaction so a failed forced save can be exactly reversed (compensating
    -- rollback). We snapshot the live p.data reference (deep copy, mirroring how
    -- update() swaps a copy in) and the dirty flag. On save_failed we reassign
    -- p.data = snapshot and p.dirty = wasDirty, so BOTH the in-memory grant AND
    -- the durable consumedReceipts marker vanish; redelivery then re-runs the
    -- grant cleanly. Do NOT mutate the snapshot in place.
    local snapshot = deepCopy(p.data)
    local wasDirty = p.dirty

    local idempotencyKey = "receipt_" .. purchaseId
    local ok, result = PlayerDataService.update(player, function(data)
        if data.consumedReceipts[purchaseId] ~= nil then
            -- Replay inside the transaction (the durable marker survived a
            -- restart even if the txLog ring rolled the key out). No double
            -- credit. Return a stable marker for the caller.
            return { alreadyGranted = true }
        end
        local grantResult = grantMutator(data)
        markReceiptConsumed(data, purchaseId)
        return grantResult
    end, idempotencyKey)

    if not ok then
        -- Mutator threw (mutation_error) or not loaded: nothing committed.
        return false, result
    end

    -- ALREADY-GRANTED replay path (H-1): the durable marker is ALREADY durable
    -- (that is why the in-transaction replay fired), so there is nothing new to
    -- persist. SKIP the forced save (avoids a needless write) and ack — the prior
    -- grant stands.
    if type(result) == "table" and result.alreadyGranted == true then
        return true, result
    end

    -- ADR-001 §3 / ADR-002 H-1: PurchaseGranted ONLY after a confirmed durable
    -- write. Force a save; if it fails (or is FENCED out because we lost the lock,
    -- M-2), restore the pre-grant snapshot so the in-memory grant AND the marker
    -- both vanish and memory equals the last durable state. We must NOT ack —
    -- redelivery (on the authoritative server) re-runs the grant cleanly and,
    -- once a save succeeds, the durable marker dedupes future redeliveries.
    local saved = PlayerDataService.save(player, { force = true })
    if not saved then
        p.data = snapshot
        p.dirty = wasDirty
        log("receipt_save_failed", { userId = player.UserId, purchaseId = purchaseId })
        return false, "save_failed" -- caller -> NotProcessedYet
    end

    return true, result
end

-- ── Save (§2.2, E3) ──────────────────────────────────────────────────────

-- Whether at least saveDebounceSec has elapsed since the last actual write to
-- this profile's key (respects the 6s per-key cooldown; saveDebounceSec >= 7).
local function debounceElapsed(p: Profile): boolean
    return (os.clock() - p.lastSaveClock) >= Config.saveDebounceSec
end

-- Writes a profile durably with pcall + exponential-backoff retry (F-BACKOFF).
-- Works off the cached Profile + its userId, so it serves BOTH a live Player and
-- an ORPHANED cache entry whose Player has left (ADR-001 H1). Before writing:
-- accrues playtime ((now - lastSeen) into stats.playtime) and advances lastSeen
-- (so the same delta is never double-counted). The dirty flag clears ONLY on a
-- successful write (E3) — a failed save leaves it set so the next tick retries.
-- Returns true on success (or no-op success when not dirty + not forced).
local function saveProfile(userId: number, p: Profile, force: boolean): boolean
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

    -- Embed the FENCE STAMP in the wrapper (ADR-002 M-2): the JobId + lock gen
    -- this server holds. Forensic belt-and-suspenders; the primary fence is the
    -- pre-write ownershipMatches read below.
    local ourJobId = SessionLock.getJobId()
    local wrapper = Schema.wrap(data, ourJobId, p.lockGen)
    local key = profileKey(userId)
    local store = getStore()

    local function rollback()
        -- E3 / H4: undo the on-save advance so playtime/offline are not corrupted
        -- by an un-persisted write; dirty stays set so the next tick retries.
        data.lastSeen = now - delta
        if delta > 0 then
            data.stats.playtime -= delta
        end
    end

    if store == nil then
        rollback()
        log("save_failed", { userId = userId, reason = "get_store_failed" }) -- H4
        if p.player ~= nil then
            PlayerDataService.DataSaved:Fire(p.player, false)
        end
        return false
    end

    -- FENCE (ADR-002 M-2): prove we STILL own the lock before writing. AFTER the
    -- wrapper is built, BEFORE the first SetAsync. If a foreign server stole our
    -- (frozen) lock, the durable lock now reads a different jobId/gen and this
    -- read returns false; a FAILED read also returns false (cannot prove
    -- ownership = money-safe). On a fence-out we ABORT the write entirely (a
    -- divergent last-writer-wins SetAsync is the exact dupe we are preventing),
    -- roll back the on-save advance, log, and return false. Returning false also
    -- triggers the H-1 receipt rollback when this save is a forced receipt save.
    if not SessionLock.ownershipMatches(userId, ourJobId, p.lockGen) then
        rollback()
        log("save_fenced", { userId = userId, reason = "lock_lost", jobId = ourJobId, gen = p.lockGen })
        if p.player ~= nil then
            PlayerDataService.DataSaved:Fire(p.player, false)
        end
        return false
    end

    local success = false
    for attempt = 1, Config.saveMaxAttempts do
        local ok, err = pcall(function()
            store:SetAsync(key, wrapper)
        end)
        if ok then
            success = true
            break
        end
        log("save_attempt_failed", { userId = userId, attempt = attempt, err = tostring(err) })
        if attempt < Config.saveMaxAttempts then
            task.wait(backoffWait(attempt))
        end
    end

    if success then
        p.dirty = false
        p.lastSaveClock = os.clock()
    else
        rollback()
        log("save_failed", { userId = userId })
    end

    if p.player ~= nil then
        PlayerDataService.DataSaved:Fire(p.player, success)
    end
    return success
end

-- Saves a player's profile. `opts.force` skips the debounce gate (used by
-- PlayerRemoving / BindToClose so the final save is never skipped). Returns
-- true (no-op success) if not loaded or not dirty.
function PlayerDataService.save(player: Player, opts: { force: boolean? }?): boolean
    local p = profileFor(player)
    if p == nil then
        return true -- nothing to save (already removed)
    end
    return saveProfile(player.UserId, p, opts ~= nil and opts.force == true)
end

-- Saves a profile by userId (serves the autosave loop + shutdown, which iterate
-- the cache and may hit ORPHANED profiles with no live Player — ADR-001 H1).
function PlayerDataService.saveByUserId(userId: number, opts: { force: boolean? }?): boolean
    local p = profiles[userId]
    if p == nil then
        return true
    end
    return saveProfile(userId, p, opts ~= nil and opts.force == true)
end

-- ── Lifecycle: removing + autosave + shutdown ──────────────────────────────

-- True iff this dirty profile is due for a ROUTINE autosave: at least
-- autosaveIntervalSec (300s) has elapsed since its last successful write
-- (ADR-001 deviation fix — cadence is the interval, NOT the debounce floor).
local function autosaveDue(p: Profile): boolean
    return (os.clock() - p.lastSaveClock) >= Config.autosaveIntervalSec
end

-- Called on Players.PlayerRemoving. STRICT ORDER (ADR-001 C3): stop heartbeat ->
-- final save (force) -> release lock -> drop cache. Stopping the heartbeat first
-- guarantees no in-flight beat refreshes the lock after we release it.
function PlayerDataService.onPlayerRemoving(player: Player)
    local userId = player.UserId
    PlayerDataService.stopHeartbeat(userId)
    PlayerDataService.save(player, { force = true })
    SessionLock.release(userId)
    profiles[userId] = nil
    heartbeatStop[userId] = nil
end

-- The autosave loop (§2.2, ADR-001 H1 + cadence deviation). Iterates the
-- `profiles` CACHE (the source of truth for who needs saving — covers orphaned
-- profiles whose Player object left Players but whose cache entry lingers), NOT
-- Players:GetPlayers(). Saves a dirty profile once autosaveIntervalSec has
-- elapsed since its last write. Skips the whole tick if the write budget is
-- exhausted (H2). Idempotent to start. task.wait only (no deprecated wait()).
-- One autosave scan pass (factored out so the loop stays DRY and the pass is
-- unit-testable without waiting a full tick). H2 budget gate + cadence (H1).
local function runAutosavePass()
    -- H2: if the write budget is exhausted, skip this pass rather than spend a
    -- scarce request. Dirty profiles stay dirty and retry next tick (no loss).
    if setWriteBudget() < Config.autosaveBudgetMinRequests then
        log("budget_low", { phase = "autosave" })
        return
    end
    -- Snapshot the due userId set so a concurrent removal mutating `profiles`
    -- mid-iteration is safe.
    local dueUserIds: { number } = {}
    for userId, p in pairs(profiles) do
        if p.dirty and autosaveDue(p) then
            table.insert(dueUserIds, userId)
        end
    end
    for _, userId in ipairs(dueUserIds) do
        local p = profiles[userId]
        if p ~= nil and p.dirty and autosaveDue(p) then
            PlayerDataService.saveByUserId(userId)
        end
    end
end

function PlayerDataService.startAutosave()
    if autosaveRunning then
        return
    end
    autosaveRunning = true
    task.spawn(function()
        while autosaveRunning do
            task.wait(Config.autosaveTickSec)
            if not autosaveRunning then
                break
            end
            runAutosavePass()
        end
    end)
end

function PlayerDataService.stopAutosave()
    autosaveRunning = false
end

-- Saves ALL cached profiles in parallel + releases their locks, bounded by
-- bindToCloseBudgetSec (E4). Iterates the `profiles` CACHE (H1 — covers orphans
-- the Players list would miss). Each coroutine's STRICT ORDER (ADR-001 C3/C4):
-- stop heartbeat -> final save (force) -> release lock -> drop cache. If the
-- write budget is low (H2) the launches are STAGGERED (shutdownStaggerSec apart)
-- instead of bursting all at once, still within the budget window.
function PlayerDataService.saveAllOnClose()
    local userIds: { number } = {}
    for userId in pairs(profiles) do
        table.insert(userIds, userId)
    end

    local stagger = setWriteBudget() < Config.shutdownBudgetStaggerThreshold
    if stagger then
        log("budget_low", { phase = "shutdown", count = #userIds })
    end

    local threads: { thread } = {}
    for index, userId in ipairs(userIds) do
        local t = task.spawn(function()
            PlayerDataService.stopHeartbeat(userId)
            PlayerDataService.saveByUserId(userId, { force = true })
            SessionLock.release(userId)
            profiles[userId] = nil
            heartbeatStop[userId] = nil
        end)
        table.insert(threads, t)
        if stagger and index < #userIds then
            task.wait(Config.shutdownStaggerSec)
        end
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
-- store (so unit tests can exercise mutations directly). Optional `player` is
-- stored so DataSaved fires in tests that assert on it.
function PlayerDataService._setProfileForTest(userId: number, data: PlayerData, player: Player?)
    profiles[userId] = {
        userId = userId,
        player = player,
        data = data,
        dirty = false,
        dirtyAt = 0,
        lastSaveClock = 0,
        loaded = true,
        lockGen = 1, -- sentinel generation for tests (matches a fresh acquire)
    }
    -- Seed a matching durable lock so the save-path fence (ADR-002 M-2) passes by
    -- default. Freeze-steal tests overwrite this via SessionLock._writeLockForTest.
    SessionLock._writeLockForTest(userId, 1)
end

-- Test-only: override a cached profile's lock generation (so a spec can simulate
-- a freeze-then-steal where this server holds a stale gen — ADR-002 M-2).
function PlayerDataService._setLockGenForTest(userId: number, gen: number)
    local p = profiles[userId]
    if p ~= nil then
        p.lockGen = gen
    end
end

-- Test-only: clears all cached state (call between tests for isolation). Cancels
-- any live heartbeat threads so they cannot leak across tests.
function PlayerDataService._resetForTest()
    for userId in pairs(profiles) do
        profiles[userId] = nil
    end
    for userId, thread in pairs(heartbeatThreads) do
        if coroutine.status(thread) ~= "dead" then
            pcall(task.cancel, thread)
        end
        heartbeatThreads[userId] = nil
    end
    for userId in pairs(heartbeatStop) do
        heartbeatStop[userId] = nil
    end
    autosaveRunning = false
end

-- Test-only: count of currently-tracked (live or pending-cleanup) heartbeat
-- threads. Lets a spec assert the heartbeat was torn down after removal/shutdown.
function PlayerDataService._heartbeatThreadCountForTest(): number
    local n = 0
    for _ in pairs(heartbeatThreads) do
        n += 1
    end
    return n
end

-- Test-only: start a real heartbeat for a cached profile (so a spec can assert
-- it is cancelled by removal/shutdown). Returns the spawned thread.
function PlayerDataService._startHeartbeatForTest(userId: number): thread
    startHeartbeat(userId)
    return heartbeatThreads[userId]
end

-- Test-only: force a profile's last-successful-save clock, so the autosave
-- cadence (autosaveDue) can be exercised deterministically without waiting.
function PlayerDataService._setLastSaveClockForTest(userId: number, clockValue: number)
    local p = profiles[userId]
    if p ~= nil then
        p.lastSaveClock = clockValue
    end
end

-- Test-only: run ONE autosave scan pass synchronously (budget gate + cadence).
function PlayerDataService._runAutosavePassForTest()
    runAutosavePass()
end

return PlayerDataService
