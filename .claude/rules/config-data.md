---
paths:
  - "**/Config/**"
  - "**/Data/**"
  - "assets/data/**"
---

# Config & Data Rules

Files matching these paths contain configuration or data (Luau tables, JSON, CSV).

## Core Rules

1. **JSON files must be valid.** Validate before commit (`validate-commit.sh` checks this).
2. **Config tables must have comments explaining each field.** Designers will edit these — they need to understand.
3. **Numeric ranges documented** (min/max/default) for any tunable value.
4. **No duplicate keys** in tables or JSON.
5. **Version field** for data that might need migration.

## Config Table Template

```lua
-- src/ReplicatedStorage/Shared/Config/WeaponConfig.lua
--
-- Weapon definitions. Edited by designers for balance.
-- Schema version: 2

return {
    ["sword_bronze"] = {
        -- Display name shown in UI and shop
        name = "Bronze Sword",

        -- Base damage per hit
        -- Range: 1-1000
        -- Default: 10 (starter weapon baseline)
        damage = 10,

        -- Attack cooldown in seconds
        -- Range: 0.1-5.0
        -- Default: 0.5 (balanced feel)
        cooldown = 0.5,

        -- Price in soft currency
        -- Range: 0-1000000
        price = 100,

        -- Rarity tier (affects visual treatment)
        -- Values: "Common" | "Rare" | "Epic" | "Legendary"
        rarity = "Common",
    },
}
```

## JSON Format

For data that non-programmers might edit, JSON in `assets/data/`:

```json
{
  "version": 2,
  "items": [
    {
      "id": "sword_bronze",
      "name": "Bronze Sword",
      "damage": 10,
      "cooldown": 0.5,
      "price": 100,
      "rarity": "Common"
    }
  ]
}
```

Validate with `jq empty file.json` or an online JSON validator.

## Versioning

Any data structure that might need migration over time needs a `version` field:

```lua
return {
    version = 2,  -- bump when schema changes
    data = {
        -- ...
    },
}
```

When the schema changes, write a migration function that upgrades old data:

```lua
local function migrate(data: {[string]: any}): {[string]: any}
    data.version = data.version or 1
    if data.version == 1 then
        -- v1 → v2: add rarity field
        for id, item in pairs(data.items) do
            item.rarity = item.rarity or "Common"
        end
        data.version = 2
    end
    return data
end
```

## Localization

Localized text goes in dedicated localization files, not inline in other configs:

```lua
-- src/ReplicatedStorage/Shared/Config/Localization/en_US.lua
return {
    ["shop.insufficient_funds"] = "You need {amount} gold to buy this.",
    ["shop.purchase_success"] = "Purchase complete!",
    ["combat.enemy_killed"] = "You defeated the {enemy}.",
}
```

## Forbidden Patterns

- ❌ Invalid JSON (commit hook will catch, but don't rely on it)
- ❌ Numeric values without range/purpose comments
- ❌ Duplicate keys
- ❌ Missing version field on migrateable data
- ❌ Mixing config with logic (config is data, not code)
- ❌ Localized text scattered through configs (centralize in localization files)
- ❌ Secrets in config files that ship to the client
