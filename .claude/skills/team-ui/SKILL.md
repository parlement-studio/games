---
name: team-ui
description: Multi-agent orchestration for UI features. Coordinates ux-designer, ui-programmer, art-director, accessibility-specialist, and writer to build a new UI feature end-to-end.
---

# /team-ui — UI Feature Team

## Orchestration Flow

### Phase 1: Design
1. **ux-designer**: Wireframes and user flows
2. **art-director**: Visual style guidance (colors, icons, font)
3. **writer**: Copy for labels, tooltips, error messages

User reviews and approves design.

### Phase 2: Implementation
4. **ui-programmer**: Build the UI in chosen framework (Native / Roact / Fusion)
5. **remotes-networking-specialist** (if needed): Remote contracts for data the UI needs
6. **accessibility-specialist**: Review for contrast, text size, touch targets, screen reader support

### Phase 3: Quality
7. **qa-tester**: Test across device sizes (mobile portrait / landscape / tablet / PC / console)
8. **performance-analyst**: Profile UI render cost on mobile

### Phase 4: Integration
9. **ui-programmer**: Hook UI into game state
10. **game-designer**: Verify UI supports intended game flow

## Steps

### 1. Gather Context
Ask:
- "What UI feature?" (new menu, new HUD element, new modal, etc.)
- "When does the player see it?"
- "What data does it show?"
- "What actions can the player take through it?"

### 2. Design Phase
- ux-designer presents wireframe (ASCII or described)
- art-director suggests visual palette
- writer drafts copy
- User approves the combined design

### 3. Implementation Phase
- ui-programmer implements
- accessibility-specialist reviews draft
- ui-programmer applies accessibility fixes
- Runs the UI in Studio for visual verification

### 4. Quality Phase
- qa-tester runs device coverage matrix:
  - Mobile portrait 375x667
  - Mobile landscape 844x390
  - Tablet 1024x768
  - Desktop 1920x1080
  - Console 1920x1080 with gamepad
- performance-analyst checks FPS impact

### 5. Integration Phase
- Hook up state
- Link to opening/closing triggers
- Update UI style guide if new patterns introduced

## Output
A complete UI feature: wireframe → design → implementation → accessibility pass → device-tested → integrated.

## Quality Checks
- [ ] Touch targets ≥ 44×44 px
- [ ] Text contrast ≥ 4.5:1
- [ ] Readable at smallest supported device (375×667)
- [ ] Gamepad navigable
- [ ] Screen reader friendly (AccessibleName set)
- [ ] No regressions on other UI
- [ ] Performance: no FPS drop on mobile
