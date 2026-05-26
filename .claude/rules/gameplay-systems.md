---
paths:
  - "**/Systems/**"
  - "**/Gameplay/**"
  - "**/Combat/**"
  - "**/Inventory/**"
---

# Gameplay Systems Rules

Files matching these paths implement game mechanics (combat, abilities, inventory, quests, etc.).

## Core Rules

1. **Zero magic numbers.** All tuning values in config modules. Tuning is a designer concern, not a programmer concern.
2. **Data-driven design.** Systems read from config tables. Adding a new weapon = adding a config entry, not writing new code.
3. **Delta time for frame-dependent calculations.** `position += velocity * deltaTime`.
4. **State machine pattern for complex entity behavior.** Don't cram all logic into flat conditionals.
5. **Event-driven communication between systems.** Systems emit events; other systems listen. Avoid direct coupling.

## Config-Driven Example

BAD:
```lua
-- damage hardcoded
local function attack(enemy)
    enemy:TakeDamage(50)
end
```

GOOD:
```lua
local WeaponConfig = require(game.ReplicatedStorage.Shared.WeaponConfig)

local function attack(player: Player, enemy: Enemy)
    local weapon = Inventory.getEquippedWeapon(player)
    local config = WeaponConfig[weapon.id]
    if not config then return end

    local damage = config.baseDamage + (config.bonusPerLevel * player.level)
    enemy:TakeDamage(damage)
end
```

Now a designer can rebalance weapons by editing `WeaponConfig.lua` without touching combat code.

## State Machine Pattern

```lua
local States = {
    Idle = "Idle",
    Attacking = "Attacking",
    Stunned = "Stunned",
    Dead = "Dead",
}

local transitions = {
    [States.Idle] = {States.Attacking, States.Stunned, States.Dead},
    [States.Attacking] = {States.Idle, States.Stunned, States.Dead},
    [States.Stunned] = {States.Idle, States.Dead},
    [States.Dead] = {},  -- terminal
}

local function canTransition(fromState, toState): boolean
    for _, allowed in ipairs(transitions[fromState]) do
        if allowed == toState then return true end
    end
    return false
end
```

## Event-Driven Pattern

Instead of System A directly calling System B:

BAD:
```lua
-- combat.lua
local function onEnemyKilled(enemy)
    Inventory.addItem(player, "gold", 10)  -- direct coupling
    Quests.progressObjective(player, "kill_goblins")
    Analytics.track("EnemyKilled", {id = enemy.id})
end
```

GOOD:
```lua
-- combat.lua
local function onEnemyKilled(enemy)
    GameEvents.EnemyKilled:Fire({player = player, enemy = enemy})
end

-- inventory.lua
GameEvents.EnemyKilled:Connect(function(data)
    Inventory.addItem(data.player, "gold", 10)
end)

-- quests.lua
GameEvents.EnemyKilled:Connect(function(data)
    Quests.progressObjective(data.player, "kill_" .. data.enemy.type)
end)
```

Now adding a new reaction to enemy death doesn't require changing combat code.

## Delta Time Rule

All per-frame motion uses delta time:

```lua
game:GetService("RunService").Heartbeat:Connect(function(dt)
    projectile.position += projectile.velocity * dt
end)
```

Not:
```lua
-- WRONG: frame-rate dependent
game:GetService("RunService").Heartbeat:Connect(function()
    projectile.position += projectile.velocity * 0.016  -- hardcoded
end)
```

## Forbidden Patterns

- ❌ Magic numbers in gameplay code (especially damage, XP, cooldowns, prices)
- ❌ Hardcoded enemy/weapon/item lists in code (use config tables)
- ❌ Direct cross-system function calls (use events)
- ❌ Long if/elif chains for entity state (use state machine)
- ❌ Frame-rate-dependent movement (use delta time)
- ❌ One massive "GameLogic.lua" file (split by system)
