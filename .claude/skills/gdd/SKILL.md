---
name: gdd
description: Create or update a Game Design Document. Use for master GDD creation, system-specific GDDs, or GDD review. Invoke with /gdd [system-name] for a specific system, or /gdd for the master document.
---

# /gdd — Game Design Document Workflow

## If no argument provided (Master GDD):
Create the master GDD at `design/gdd/master-gdd.md` using the template at `.claude/docs/templates/gdd-master.md`.

The master GDD must include:
1. **Game Overview**: Concept, genre, platform (Roblox), target audience
2. **Creative Pillars**: 3-5 pillars that guide all decisions
3. **Core Loop**: 30-second, 5-minute, session, and meta loops
4. **Systems Overview**: List all game systems with 1-sentence descriptions
5. **Player Progression**: How do players grow over time?
6. **Monetization Strategy**: GamePasses, DevProducts, Premium Benefits
7. **Social Features**: Multiplayer, trading, guilds, parties
8. **Target Metrics**: D1/D7/D30 retention targets, session length goals
9. **Content Plan**: Launch content vs. future updates
10. **Technical Overview**: Client-server split, DataStore approach, key technical constraints

## If argument provided (System GDD):
Create a system-specific GDD at `design/gdd/<system-name>-gdd.md` using the template at `.claude/docs/templates/gdd-system.md`.

Every system GDD must include:
1. Overview & Purpose
2. Core Mechanics (detailed)
3. Data Schema (DataStore keys, types, defaults)
4. Client-Server Split (what runs where)
5. RemoteEvents/Functions needed (with argument contracts)
6. Player-Facing UI (mockup or description)
7. Edge Cases & Error States
8. Balancing Parameters (formulas, not magic numbers)
9. Integration Points (dependencies on other systems)

## Workflow Steps
1. **Ask Context**: "Are you creating a new GDD or updating an existing one?"
2. **Delegate**: Route to `game-designer` agent for master GDD, or `systems-designer` for system GDD
3. **Draft**: Show the draft to the user for review (never save directly)
4. **Iterate**: Apply feedback, present updated draft
5. **Approve**: User confirms; save to `design/gdd/`
6. **Update Index**: If a new system, update `design/gdd/systems-index.md`

## After creating any GDD:
- Run `/design-review` to validate quality
- Update `design/gdd/systems-index.md` if a new system was added
- Link related GDDs (combat GDD references weapons GDD, etc.)
