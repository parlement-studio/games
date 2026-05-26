---
name: team-polish
description: Multi-agent orchestration for polish passes. Coordinates game-designer, luau-gameplay-programmer, technical-artist, sound-designer, ui-programmer, and qa-tester to refine an existing feature.
---

# /team-polish — Polish Pass Team

## Purpose
Polish turns "it works" into "it feels great." This skill orchestrates a polish pass across multiple specialists.

## When to Use
- Feature is functional but feels rough
- Before a demo or launch
- After external playtest feedback
- As part of a dedicated polish sprint

## Orchestration Flow

### Phase 1: Identify Rough Edges
1. **qa-tester**: Play through the feature; note every moment that feels off
2. **ux-designer**: Review the flow for friction points
3. **game-designer**: Review for fun factor / moment-to-moment engagement

Present a consolidated list to user for prioritization.

### Phase 2: Visual Polish
4. **technical-artist**: Add juice (particle effects, camera shake, screen flashes)
5. **art-director**: Review visual cohesion with game style
6. **ui-programmer**: UI animation polish (tweens, fades, bounces)

### Phase 3: Audio Polish
7. **sound-designer**: Add missing sound effects (every action should have feedback)
8. **audio-director**: Review audio mix (not too loud, not too quiet, ducking correctly)

### Phase 4: Feel Polish
9. **luau-gameplay-programmer**: Adjust timing, animation weights, input responsiveness
10. **game-designer**: Tune numbers (damage multipliers, cooldowns, speeds)

### Phase 5: Validation
11. **qa-tester**: Replay and confirm improvements
12. **performance-analyst**: Verify polish didn't tank performance

## Steps

### 1. Scope the Polish
Ask:
- "Which feature needs polish?"
- "What specific concerns have you or players mentioned?"
- "How much time do we have for polish?"

### 2. Run Rough Edge Audit
- qa-tester plays the feature with "feel detector" mode: every moment that feels wrong is noted
- Categorize issues: visual, audio, feel, flow

### 3. Prioritize
- Some fixes are 10-minute wins (add a particle, add a sound)
- Some are bigger (rework the UI flow)
- User picks which to address first

### 4. Polish Phase
- Each specialist addresses their items
- Each change goes through Question → Options → Decision → Draft → Approval
- Small changes can batch; big changes reviewed individually

### 5. Playtest the Result
- qa-tester replays
- Note improvements
- Identify any new issues introduced

### 6. Document
- Update the feature's GDD with polish notes
- Log the polish pass in decision log

## Polish Patterns

### Visual Juice
- Particle burst on key actions (impact, pickup, level-up)
- Camera shake for emphasis (use sparingly)
- Screen flash on critical events
- UI element scale bounces on interaction
- Number ticker for currency changes
- Highlight on hover / focus

### Audio Juice
- Click on every button
- Impact sound on every hit
- Whoosh on movement
- Confirmation on purchase / pickup
- Ambient sound for empty moments

### Feel Polish
- Input response < 100ms (no delay between tap and feedback)
- Animation weight (hit reactions, knockback)
- Smoothing (camera follow, cursor movement)
- Forgiveness (coyote time for jumps, input buffering)
- Explicit feedback (damage numbers, status text)

### Flow Polish
- Reduce tap count to common actions
- Skip steps that don't need explicit user confirmation
- Add shortcuts for power users
- Default options that match player intent

## Output
A more polished feature with before/after notes. Document in `production/polish-log.md`.

## Anti-Patterns
- Polishing the wrong feature (always prioritize biggest impact)
- Adding polish to something that's still broken (fix it first)
- Polishing forever (set a time budget and stop)
- Adding juice that hurts performance (mobile-first test)
