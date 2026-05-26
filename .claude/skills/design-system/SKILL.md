---
name: design-system
description: Create a per-system GDD. Interactive flow — select system from index, then generate a comprehensive design doc through a structured conversation.
---

# /design-system — Per-System GDD Creation

## Delegate to: systems-designer (with game-designer for creative direction)

## Prerequisites
- `design/gdd/systems-index.md` exists (run `/map-systems` if not)
- `design/gdd/master-gdd.md` exists (run `/gdd` if not)

## Steps

### 1. Select the System
Present options from the systems-index:
- Systems without a GDD (prioritize these)
- Systems with outdated GDDs (mark for update)
- Or, ask the user for a new system name

### 2. Gather Design Intent
Work through each section via structured questions:

#### Overview & Purpose
- "What is this system in 2-3 sentences?"
- "What player need does it serve?"
- "How does it fit into the core loop?"

#### Core Mechanics
- "How does the player interact with this system?"
- "What are the key inputs and outputs?"
- "What makes it fun / engaging?"
- Walk through typical player interactions step-by-step

#### Data Schema
- "What needs to persist?"
- "What's ephemeral (per-session)?"
- "Who owns the data — server or client?"
- Design the DataStore schema (or delegate to datastore-architect)

#### Client-Server Split
- "What runs on the server?"
- "What runs on the client?"
- "What's server-authoritative (game state) vs. client-authoritative (visuals/input)?"

#### Remotes
- "What Client → Server calls are needed?"
- "What Server → Client updates?"
- "Anything high-frequency that should be UnreliableRemoteEvent?"
- Delegate detail to `remotes-networking-specialist`

#### Player-Facing UI
- "What does the player see?"
- "What UI elements exist (HUD, menus, modals)?"
- "ASCII wireframe or description?"

#### Edge Cases & Error States
- "What happens when:
  - Player has zero resources?
  - Player has max resources?
  - System is used rapidly in succession?
  - Player disconnects mid-action?
  - Server restarts during use?
  - DataStore is unavailable?
  - Network lag occurs?"

#### Balancing Parameters
- "What values should be tunable?"
- "What's the formula?" (write it explicitly, no "balanced appropriately")
- "Min / max / default for each parameter?"

#### Integration Points
- "Which other systems does this depend on?"
- "Which systems depend on it?"
- "Any shared data or shared modules?"

### 3. Draft the GDD
Using `.claude/docs/templates/gdd-system.md` as the skeleton, fill in from the gathered intent.

### 4. Present for Review
Show the complete draft to the user for review.

### 5. Iterate
Apply feedback, present updated draft, repeat until approved.

### 6. Save
On approval, save to `design/gdd/<system-name>-gdd.md`.
Update `design/gdd/systems-index.md` to mark this system as "In design" or "Ready for implementation."

### 7. Next Steps
Suggest:
- Run `/design-review` on the new GDD to verify quality
- Schedule implementation via `/sprint-plan`
- Link related GDDs
