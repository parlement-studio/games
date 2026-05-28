--!strict
-- ServerScriptService/LeaderboardWriteBootstrap.server.luau
--
-- F-LEADERBOARD-WRITE (persistence-gdd v1.4 §2.6 / economy-gdd v1.2 §9 #16).
--
-- Writes `stats.totalCoinsEarned` (the LOCKED Richest Manager net-worth metric)
-- into OrderedDataStore "Leaderboard_RichestManager_v1" with key "Player_<UserId>".
--
-- TRIGGER (debounced, NEVER per-tick):
--   * Piggy-backs on the normal player SAVE (PlayerDataService.DataSaved signal).
--   * Writes ONLY when `totalCoinsEarned` changed since the last leaderboard
--     write for that player (in-memory cache `lbLastWritten[userId]`, NOT
--     persisted — re-initialized each session).
--   * pcall-wrapped; on failure the cache is NOT updated so the next save
--     retries. No retry queue needed — the next dirty save naturally re-fires.
--
-- BUDGET (.claude/rules/datastores.md):
--   * OrderedDataStore shares DataStore's `60 + numPlayers*10`/min budget and
--     6s per-key cooldown. Piggy-backing on the existing save cadence keeps
--     this within budget for free (one write per save, only if changed).
--
-- READ side (top-N for the Richest Manager leaderboard) lives in Leaderboard
-- (#16) when that GDD ships; this bootstrap is the WRITE side only so the
-- store is populated from day one and the read side has data when it lands.
--
-- COMPLIANCE:
--   * `totalCoinsEarned` is MONOTONIC NON-DECREASING (EconomyService.award is
--     the sole writer, never decremented by a sink) — so a leaderboard rank
--     ONLY goes up, never punishing engagement. See persistence-gdd §2.6
--     metric decision lock.
--   * Server clock authority: `serverTime = os.time()` is recorded only for
--     audit/logging, NEVER used to weight the leaderboard (the value IS the rank).

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local PlayerDataService = require(ServerStorage.PlayerData.PlayerDataService)

local LEADERBOARD_KEY = "Leaderboard_RichestManager_v1"
local KEY_PREFIX = "Player_"

-- In-memory write cache. `nil` (never written) is distinct from `0` (zeroed
-- legacy state). Re-initialized empty each server boot — a server restart
-- will re-write the first save per player (cheap, expected).
local lbLastWritten: { [number]: number } = {}

-- Structured logger; keep light to avoid noise on hot saves.
local function log(event: string, payload: { [string]: any })
    warn(string.format("[Leaderboard] %s %s", event, HttpService:JSONEncode(payload)))
end

-- Resolve the OrderedDataStore lazily so the boot does not throw if Studio
-- launched without API access (Studio default). GetOrderedDataStore returns
-- the same handle for identical args, so repeated calls are cheap.
local function getStore(): OrderedDataStore?
    local ok, store = pcall(function()
        return DataStoreService:GetOrderedDataStore(LEADERBOARD_KEY)
    end)
    if not ok then
        log("ods_get_failed", { error = tostring(store) })
        return nil
    end
    return store
end

-- Write a single player's `totalCoinsEarned` to the OrderedDataStore. Returns
-- true on success, false on any failure (caller leaves the cache untouched so
-- the next save retries).
local function writeOne(userId: number, value: number): boolean
    local store = getStore()
    if store == nil then
        return false
    end
    local key = KEY_PREFIX .. tostring(userId)
    local ok, err = pcall(function()
        store:SetAsync(key, value)
    end)
    if not ok then
        log("ods_set_failed", { userId = userId, value = value, error = tostring(err) })
        return false
    end
    return true
end

-- React to a successful save: if the player's `totalCoinsEarned` changed since
-- the cached last-written value, write the new value to the OrderedDataStore.
-- A FAILED save (ok=false) is ignored — we want only writes that actually
-- persisted the player's profile.
PlayerDataService.DataSaved:Connect(function(player: Player, ok: boolean)
    if not ok then
        return
    end
    if typeof(player) ~= "Instance" or not player:IsA("Player") then
        return
    end
    local data = PlayerDataService.getData(player)
    if data == nil or typeof(data.stats) ~= "table" then
        return
    end
    local current = data.stats.totalCoinsEarned
    if typeof(current) ~= "number" then
        return
    end
    local cached = lbLastWritten[player.UserId]
    if cached == current then
        return -- no change since last write; budget-respecting no-op
    end
    -- Only write a POSITIVE value (a fresh profile with 0 totalCoinsEarned has
    -- no business cluttering the top-N store; once they earn coins the write
    -- fires naturally).
    if current <= 0 then
        return
    end
    local wrote = writeOne(player.UserId, current)
    if wrote then
        lbLastWritten[player.UserId] = current
    end
end)
