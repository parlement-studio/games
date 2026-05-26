---
paths:
  - "**/Remotes**"
  - "**/Network**"
  - "**/Net/**"
---

# Remotes Rules

Files matching these paths handle client-server communication. **Never trust the client** — that's the core rule.

## Core Rules

1. **Server-side validation on EVERY handler.** Type check, range check, sanity check.
2. **Type checking EVERY argument.** `typeof(arg) == "number"` — check each one.
3. **Rate limiting on EVERY client→server remote.** No exceptions.
4. **No Client→Server RemoteFunctions.** Server hang risk if the client never returns.
5. **Centralized remote management.** No scattered `Instance.new("RemoteEvent")` calls.
6. **Bandwidth-conscious design.** Target < 50 KB/s per player.

## Validation Template

```lua
local RATE_LIMIT_PER_SECOND = 10
local lastCallTimes: {[Player]: {number}} = {}

local function handleRemote(player: Player, itemId: string, amount: number)
    -- Rate limit
    local now = os.clock()
    lastCallTimes[player] = lastCallTimes[player] or {}
    local calls = lastCallTimes[player]
    while #calls > 0 and calls[1] < now - 1 do
        table.remove(calls, 1)
    end
    if #calls >= RATE_LIMIT_PER_SECOND then
        return
    end
    table.insert(calls, now)

    -- Type validation
    if typeof(itemId) ~= "string" or typeof(amount) ~= "number" then
        return
    end

    -- Length / range validation
    if #itemId > 50 or amount <= 0 or amount > 1000 then
        return
    end

    -- Sanity check (does this make sense in the game?)
    if not Inventory.playerOwnsItem(player, itemId) then
        return
    end

    -- Proceed with the operation
    Inventory.sell(player, itemId, amount)
end

Remotes.SellItem.OnServerEvent:Connect(handleRemote)
```

## Remote Types

| Type | Use For | Notes |
|------|---------|-------|
| `RemoteEvent` | Most communication | Fire-and-forget, both directions |
| `RemoteFunction` | ONLY Server→Client | Server invokes, client returns. NEVER Client→Server. |
| `UnreliableRemoteEvent` | High-frequency cosmetic | Particles, animations, chat bubbles. May drop. |

## Centralized Management

Organize all remotes in a single module:

```lua
-- ReplicatedStorage/Shared/Remotes.lua
local Remotes = {}

local function getOrCreate(name: string, className: string): Instance
    local existing = script:FindFirstChild(name)
    if existing then return existing end

    local remote = Instance.new(className)
    remote.Name = name
    remote.Parent = script
    return remote
end

Remotes.PurchaseItem = getOrCreate("PurchaseItem", "RemoteEvent")
Remotes.RequestData = getOrCreate("RequestData", "RemoteFunction")
Remotes.UpdateHUD = getOrCreate("UpdateHUD", "UnreliableRemoteEvent")

return Remotes
```

Both client and server `require` this module. One place to add / remove / rename remotes.

## Bandwidth Discipline

- Target < 50 KB/s per player outgoing
- Send deltas, not full state
- Batch updates where possible
- Use UnreliableRemoteEvent for cosmetic data
- Never send Instance references (use string IDs or paths)

## Manifest Maintenance

Maintain `design/remotes-manifest.md` with every remote documented:

| Name | Type | Direction | Args | Validation | Rate Limit |
|------|------|-----------|------|------------|------------|
| PurchaseItem | RemoteEvent | C→S | (itemId: string) | length ≤ 50, exists | 5/sec |

When you add a new remote, update the manifest.

## Forbidden Patterns

- ❌ `remote.OnServerEvent:Connect(function(player, args) ... end)` without validation
- ❌ `RemoteFunction.OnServerInvoke` (client can hang the server)
- ❌ `Instance.new("RemoteEvent")` scattered throughout codebase
- ❌ Sending Instance references through remotes
- ❌ High-frequency reliable remotes for cosmetic data
- ❌ No rate limiting on client→server remotes
- ❌ Assuming ordering between remotes (not guaranteed)
