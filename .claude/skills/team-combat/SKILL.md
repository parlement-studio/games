---
name: team-combat
description: Multi-agent orchestration for combat features. Coordinates game-designer, systems-designer, luau-gameplay-programmer, technical-artist, sound-designer, and exploit-security-specialist to tackle a combat feature end-to-end.
---

# /team-combat — Combat Feature Team

## Orchestration Flow

Combat features touch many specialists. This skill coordinates them.

### Phase 1: Design
1. **game-designer**: Define the feature — what mechanic, what player intent, how it feels
2. **systems-designer**: Translate into detailed spec with formulas, edge cases, data schema

User reviews and approves the design before moving to Phase 2.

### Phase 2: Architecture
3. **lead-programmer**: Plan the implementation architecture
4. **remotes-networking-specialist**: Design the client-server contract
5. **exploit-security-specialist**: Review for attack surface (speed hacks, damage exploits, duplication)

User reviews the architecture before Phase 3.

### Phase 3: Implementation
6. **luau-gameplay-programmer**: Implement the combat logic
7. **technical-artist**: Implement VFX (particles, beams, trails)
8. **sound-designer**: Implement audio triggers
9. **ui-programmer**: Update HUD / damage numbers / health bar

Each sub-step goes through the Question → Options → Decision → Draft → Approval flow.

### Phase 4: Quality
10. **qa-tester**: Write test plan and execute
11. **performance-analyst**: Profile the feature on mobile
12. **exploit-security-specialist**: Final security pass

### Phase 5: Integration
13. **game-designer**: Balance tuning (damage, cooldowns, etc.)
14. **producer**: Update sprint plan, systems-index

## Steps

### 1. Gather Context
Ask:
- "What combat feature are we building?" (new weapon, new ability, new enemy, etc.)
- "What's the intended player experience?"
- "What systems does this touch?" (just combat, or also inventory/progression/UI?)
- "What's the scope?" (afternoon prototype, full sprint feature, multi-sprint feature)

### 2. Delegate Through Each Phase
For each phase:
1. Announce which specialist is about to work
2. Have that specialist produce a draft
3. Present to user for approval
4. On approval, move to next phase

### 3. Handle Blockers
If a phase reveals a blocker (e.g., exploit-security-specialist says the design is unsafe):
- Pause the flow
- Escalate to the director (technical-director for tech blockers, creative-director for design blockers)
- Wait for user to resolve
- Resume the flow

### 4. Document the Feature
After completion:
- Update the combat GDD (`design/gdd/combat-gdd.md`)
- Update the remotes manifest
- Update the systems-index status
- Add an entry to the changelog

## Output
A complete combat feature: design doc + code + VFX + audio + tests + security review.

## Example Use
User: "Let's add a parry mechanic to combat"
Flow:
1. game-designer drafts the parry concept
2. systems-designer specifies windows, timing, counter-attack damage
3. remotes-networking-specialist adds ParryRemoteEvent with validation
4. exploit-security-specialist checks for timing exploits
5. luau-gameplay-programmer implements
6. technical-artist adds the parry flash VFX
7. sound-designer adds the parry sound
8. ui-programmer updates HUD to show parry window indicator
9. qa-tester writes test plan, tests edge cases
10. performance-analyst verifies no FPS impact
11. game-designer tunes timing windows based on playtest
12. producer updates sprint plan
