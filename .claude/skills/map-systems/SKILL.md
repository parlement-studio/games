---
name: map-systems
description: Enumerate and categorize all game systems. Create design/gdd/systems-index.md. Identify dependencies between systems.
---

# /map-systems — System Inventory

## Delegate to: game-designer

## Purpose
A "system" is a cohesive gameplay feature with its own rules, data, and player interaction (e.g., Combat, Inventory, Shop, Quests, Friends). The systems index is the source of truth for "what does this game have."

## Steps

### 1. Scan Existing State
- Read `design/gdd/` for existing GDDs
- Read `src/` for code organization hints
- Check `production/sprints/` for recently worked-on systems

### 2. Identify Systems
List every system, planned or implemented:

Common Roblox game systems:
- **Core Loop**: the primary gameplay action
- **Combat**: damage, abilities, weapons
- **Inventory**: items, equipment, storage
- **Progression**: XP, levels, skills
- **Economy**: currencies, shops, trading
- **Quests**: missions, objectives, rewards
- **Social**: friends, parties, guilds, chat
- **UI/HUD**: menus, notifications
- **Onboarding**: tutorial, FTUE
- **Daily Rewards**: login streaks
- **Codes**: redemption system
- **Settings**: audio, graphics, controls
- **Monetization**: GamePasses, DevProducts
- **Leaderboards**: global rankings
- **Events**: seasonal content
- **Cosmetics**: skins, pets, accessories

### 3. Categorize by Status
For each system:
- **Not started** — exists only as an idea
- **In design** — GDD being written
- **In implementation** — code being written
- **Implemented** — feature in code, not yet polished
- **Polished** — feature complete and tested
- **Live** — shipped to players

### 4. Identify Dependencies
Which systems depend on which?

Example:
```
Shop
├── depends on: Inventory (to place bought items)
├── depends on: Economy (to charge currency)
└── depends on: UI (to display items)

Trading
├── depends on: Inventory
├── depends on: Economy (for trade tax)
├── depends on: Friends (to choose trade partner)
└── depends on: DataStore (for atomic swap)
```

### 5. Priority Scoring
For each system, assess:
- **Player value** (1-5): How important for the player experience?
- **Effort** (1-5): How much work to build?
- **Risk** (L/M/H): How uncertain is the implementation?
- **Monetization impact** (1-5): Does this drive revenue?

High player value + low effort = do first
High player value + high effort = plan carefully
Low value + low effort = defer
Low value + high effort = consider cutting

### 6. Generate Index

Save to `design/gdd/systems-index.md`:
```markdown
# Systems Index

**Last Updated**: YYYY-MM-DD

## Summary
- Total systems: X
- Not started: X
- In design: X
- In implementation: X
- Implemented: X
- Polished: X
- Live: X

## Systems

### Core Loop
- **Status**: Implemented
- **Priority**: P0 (critical)
- **Value**: 5 | **Effort**: 4 | **Risk**: Medium
- **GDD**: `design/gdd/core-loop-gdd.md`
- **Depends On**: (none — core)
- **Depended On By**: Combat, Progression, Economy
- **Notes**: [any context]

### Combat
- **Status**: In implementation
- **Priority**: P0
- **Value**: 5 | **Effort**: 4 | **Risk**: Medium
- **GDD**: `design/gdd/combat-gdd.md`
- **Depends On**: Core Loop, Inventory
- **Depended On By**: Quests
- **Notes**: Hit detection in progress

...

## Dependency Graph
[ASCII or mermaid diagram showing system dependencies]

## Priority List (recommended build order)
1. Core Loop
2. Combat
3. Inventory
4. Progression
5. ...
```

### 7. Present to User
Present the index for review. On approval, save to disk.
Offer to update individual GDD statuses or add missing system GDDs.
