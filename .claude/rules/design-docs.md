---
paths:
  - "design/**"
---

# Design Docs Rules

Files matching these paths are design documentation (GDDs, economy models, narrative docs, level plans).

## Core Rules

1. **GDDs must include all 8 required sections.** See `.claude/docs/templates/gdd-system.md`.
2. **Formulas must be explicit.** No "damage is calculated appropriately" — write the math.
3. **Edge cases must be documented.** Minimum 5 per GDD.
4. **Integration points must be listed.** Which other systems does this depend on?
5. **Version and date at top of every document.** So we know what's current.

## Required Sections (for system GDDs)

Every system GDD must have:

1. **Overview & Purpose** — Why this system exists
2. **Core Mechanics** — Detailed mechanical description
3. **Data Schema** — DataStore keys, types, defaults
4. **Client-Server Split** — What runs where
5. **RemoteEvents/Functions** — Network contracts
6. **Player-Facing UI** — What the player sees
7. **Edge Cases & Error States** — What breaks
8. **Balancing Parameters** — Formulas and tunable values
9. **Integration Points** — Dependencies

## Master GDD Sections

The master GDD at `design/gdd/master-gdd.md` must include:

1. Game Overview
2. Creative Pillars
3. Core Loop
4. Systems Overview
5. Player Progression
6. Monetization Strategy
7. Social Features
8. Target Metrics
9. Content Plan
10. Technical Overview

## Formula Standards

Explicit formulas with named variables:

GOOD:
```
damage = (base_attack + weapon_power) * (1 + crit_multiplier * is_crit) * (1 - defense_reduction)

Where:
- base_attack: player stat (10-500)
- weapon_power: weapon stat (5-200)
- crit_multiplier: weapon/skill (1.5-3.0)
- is_crit: 0 or 1 (from crit_chance roll)
- defense_reduction: target stat, capped at 0.8
```

BAD:
```
Damage is calculated based on the player's attack, weapon, and target defense.
```

## Edge Case Coverage

Document what happens for each of:
- Zero inputs
- Max values
- Negative values (if theoretically possible)
- Rapid repeated calls
- Network delay mid-operation
- Disconnection mid-operation
- DataStore unavailable
- Concurrent operations from multiple players

## Version Header

Every design doc starts with:

```markdown
# System Name GDD

**Version**: 1.2
**Last Updated**: YYYY-MM-DD
**Author**: [role or name]
**Status**: [Draft / Review / Approved / Implemented / Live]
```

When updating, bump version and date.

## Forbidden Patterns

- ❌ "Balanced appropriately" (vague)
- ❌ "Calculated correctly" (vague)
- ❌ Missing one of the 8 required sections
- ❌ Magic numbers without justification
- ❌ No integration points listed
- ❌ No version/date header
- ❌ Stale docs (not updated when code changed)
- ❌ Contradicting another GDD without an explicit resolution note
