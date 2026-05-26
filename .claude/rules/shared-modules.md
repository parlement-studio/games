---
paths:
  - "src/ReplicatedStorage/**"
---

# Shared Modules Rules

Files matching these paths live in **ReplicatedStorage**, meaning they're accessible to BOTH client and server.

## Core Rules

1. **Never put secrets here.** Admin lists, API keys, server-only config — all forbidden. Anything here is readable by every client.
2. **No server-only logic.** If the logic requires server authority, put it in ServerStorage or ServerScriptService.
3. **Keep modules stateless where possible.** Shared state is dangerous — prefer pure functions.
4. **Type definitions and interfaces go here.** So both client and server can use them.
5. **Shared utilities are welcome.** Math helpers, string formatting, table utilities, signal pattern.
6. **Config tables are fine — as long as they're not sensitive.** Game tuning values, item definitions, localization strings.

## What Belongs Here

- **Types**: `type Player = {...}` definitions
- **Constants**: Game-wide constants (WORLD_SIZE, MAX_PLAYERS, etc.)
- **Item/Weapon/Ability definitions**: Data tables for game content
- **Utility modules**: Signal, Trove, Math helpers, Table helpers
- **Remotes registry**: Central list of RemoteEvents/Functions
- **Localization strings**: Translatable UI text

## What Does NOT Belong Here

- **Server-authoritative logic**: Combat damage application, inventory mutations, purchase processing
- **Admin tools**: UserId allow-lists, debug commands, god mode toggles
- **Secrets**: API keys, webhook URLs, credentials of any kind
- **Stateful singletons that track player data**: DataStore wrappers, session state
- **Third-party API clients**: Anything that makes HTTP requests (server-only)

## Type Sharing Pattern

```lua
-- src/ReplicatedStorage/Shared/Types.lua
export type PlayerData = {
    gold: number,
    level: number,
    inventory: {[string]: number},
}

export type ItemDefinition = {
    id: string,
    name: string,
    price: number,
    rarity: "Common" | "Rare" | "Epic" | "Legendary",
}

return {}
```

Server code and client code can both `require(Types)` and use the exported types.

## Config Pattern

```lua
-- src/ReplicatedStorage/Shared/ItemConfig.lua
return {
    ["sword_bronze"] = {
        name = "Bronze Sword",
        damage = 10,
        price = 100,
    },
    ["sword_iron"] = {
        name = "Iron Sword",
        damage = 25,
        price = 500,
    },
}
```

## Forbidden Patterns

- ❌ Admin lists in shared modules (exploit target)
- ❌ Database connection strings / API keys
- ❌ Server-only logic that the client could call
- ❌ Stateful singletons holding player data
- ❌ HttpService calls (server-only)
- ❌ Instance references to server-only services
