---
paths:
  - "src/ServerScriptService/**"
  - "src/ServerStorage/**"
---

# Server Scripts Rules

Files matching these paths are **server-only** code. These rules are NON-NEGOTIABLE.

## Core Rules

1. **Server is authoritative for ALL game state.** If the server doesn't bless it, it doesn't happen.
2. **Never trust the client.** Every argument from a RemoteEvent handler is attacker-controlled.
3. **All DataStore/HttpService/MarketplaceService calls must be wrapped in `pcall`.** These can and will fail.
4. **All RemoteEvent handlers must validate every argument.** Type check, range check, sanity check.
5. **Rate limit every player-triggered operation.** No exceptions.
6. **No deprecated APIs.** `wait()`, `spawn()`, `delay()` — forbidden. Use `task.*` equivalents.
7. **Services cached at module top.** `local Players = game:GetService("Players")` — not inside every function.

## Type Annotations

All public function signatures must include Luau type annotations:

```lua
-- Good
function PlayerDataService.getData(player: Player): PlayerData?
    -- ...
end

-- Bad (no annotations)
function PlayerDataService.getData(player)
    -- ...
end
```

## Error Handling Pattern

```lua
local success, result = pcall(function()
    return DataStore:GetAsync(key)
end)

if success then
    -- use result
else
    warn("DataStore GetAsync failed: " .. tostring(result))
    -- fallback or retry
end
```

## Rate Limiting Pattern

```lua
local RATE_LIMIT_PER_SECOND = 10
local playerCalls: {[Player]: {number}} = {}

local function isRateLimited(player: Player): boolean
    local now = os.clock()
    playerCalls[player] = playerCalls[player] or {}
    local calls = playerCalls[player]
    while #calls > 0 and calls[1] < now - 1 do
        table.remove(calls, 1)
    end
    if #calls >= RATE_LIMIT_PER_SECOND then
        return true
    end
    table.insert(calls, now)
    return false
end
```

## Player Data Handling

- Always key player data by `player.UserId` (not `player.Name` — names can change)
- Include schema version in every data structure
- Use session locking for DataStore operations
- Handle `Players.PlayerRemoving` AND `game:BindToClose` for save guarantees

## Service Hierarchy

- **ServerScriptService**: Scripts (active code). Default ClassName `Script`.
- **ServerStorage**: Data, ModuleScripts, templates. Not replicated to clients.
- Never put secrets (API keys, admin lists) in ReplicatedStorage or StarterGui — only here.

## Forbidden Patterns

- ❌ Trust a value passed from client: `local amount = args.amount` (check it!)
- ❌ DataStore without pcall: `DataStore:SetAsync(key, value)` (wrap it!)
- ❌ Deprecated `wait()`: use `task.wait()`
- ❌ `while true do wait() end`: use `task.wait()` or event-driven design
- ❌ Infinite loops without yields
- ❌ Magic numbers in gameplay code — externalize to config
