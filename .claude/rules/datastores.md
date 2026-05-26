---
paths:
  - "**/DataStore**"
  - "**/PlayerData**"
  - "**/SaveSystem**"
---

# DataStore Rules

Files matching these paths handle persistent player data. **Data loss is catastrophic** — these rules are non-negotiable.

## Core Rules

1. **Session locking is REQUIRED.** No exceptions. Prevents data duplication across servers.
2. **Schema versioning is REQUIRED.** Every data structure includes `version` field.
3. **All operations wrapped in `pcall` with retry logic.** DataStore can and will fail.
4. **Save debouncing with dirty flag.** Don't spam saves.
5. **`BindToClose` handler REQUIRED.** Saves all player data on server shutdown.
6. **Key format: `"Player_" .. player.UserId`.** Never use player.Name (names can change).
7. **Never store Instance references or functions.** DataStore serializes tables only.

## Request Budget

- `GetAsync` / `SetAsync` / `UpdateAsync`: 60 + (numPlayers × 10) per minute
- 6-second write cooldown per key
- Max key length: 50 characters
- Max value size: 4MB per key

Monitor budget via `DataStoreService:GetRequestBudgetForRequestType(...)` before burst operations.

## Session Lock Pattern

```lua
local SessionLock = {}

local lockStore = game:GetService("DataStoreService"):GetDataStore("SessionLocks")

function SessionLock.acquire(userId: number): boolean
    local jobId = game.JobId
    local ok, result = pcall(function()
        return lockStore:UpdateAsync("Lock_" .. userId, function(existing)
            if existing and existing.jobId ~= jobId and os.time() - existing.time < 60 then
                return nil  -- locked by another server
            end
            return { jobId = jobId, time = os.time() }
        end)
    end)
    return ok and result ~= nil
end

function SessionLock.release(userId: number)
    pcall(function()
        lockStore:RemoveAsync("Lock_" .. userId)
    end)
end
```

## Save Pattern

```lua
local dataStore = game:GetService("DataStoreService"):GetDataStore("PlayerData_v1")

function PlayerData.save(player: Player, data: PlayerData)
    local key = "Player_" .. player.UserId
    local success = false
    local attempts = 0

    while not success and attempts < 5 do
        attempts += 1
        local ok = pcall(function()
            dataStore:SetAsync(key, {
                version = CURRENT_SCHEMA_VERSION,
                data = data,
                savedAt = os.time(),
            })
        end)
        if ok then
            success = true
        else
            task.wait(2 ^ attempts)  -- exponential backoff
        end
    end

    return success
end
```

## BindToClose Pattern

```lua
game:BindToClose(function()
    local players = game:GetService("Players"):GetPlayers()
    local threads = {}
    for _, player in ipairs(players) do
        table.insert(threads, coroutine.create(function()
            PlayerData.save(player, PlayerData.getData(player))
            SessionLock.release(player.UserId)
        end))
    end
    for _, thread in ipairs(threads) do
        coroutine.resume(thread)
    end
    -- Wait up to 25 seconds for saves to complete (Roblox gives 30s)
    local deadline = os.clock() + 25
    for _, thread in ipairs(threads) do
        while coroutine.status(thread) ~= "dead" and os.clock() < deadline do
            task.wait(0.1)
        end
    end
end)
```

## Schema Versioning

```lua
local CURRENT_SCHEMA_VERSION = 3

local function migrate(data: {[string]: any}): {[string]: any}
    data.version = data.version or 1

    if data.version == 1 then
        data.gems = 0  -- v2 added gems
        data.version = 2
    end
    if data.version == 2 then
        data.settings = {}  -- v3 added settings
        data.version = 3
    end

    return data
end
```

## Forbidden Patterns

- ❌ `dataStore:SetAsync(...)` without pcall
- ❌ Saving on every change (budget exhaustion)
- ❌ No session locking
- ❌ Using `player.Name` as key
- ❌ Missing `version` field in data
- ❌ Storing Instance references (`workspace.Part`)
- ❌ Storing functions
- ❌ Missing BindToClose save
- ❌ Synchronous DataStore call in `PlayerAdded` without yield protection
