---
name: design-review
description: Comprehensive design document review against GDD standards. Checks all required sections, cross-system consistency, formulas, and edge case coverage. Use when reviewing any design doc for quality.
---

# /design-review — Design Doc Quality Review

## Delegate to: game-designer (with systems-designer assist for technical sections)

## Steps

### 1. Identify Documents to Review
- Ask the user which doc(s) to review, OR
- Default: review the most recently modified doc in `design/gdd/`
- Multi-doc review: check cross-references and consistency

### 2. Structural Checks (8 required sections)
For each GDD, verify presence of:
- [ ] Overview & Purpose
- [ ] Core Mechanics (detailed, not just "attacks")
- [ ] Data Schema (DataStore keys, types, defaults)
- [ ] Client-Server Split
- [ ] RemoteEvents/Functions needed
- [ ] Player-Facing UI (description or mockup)
- [ ] Edge Cases & Error States
- [ ] Balancing Parameters (with formulas, not "balanced appropriately")
- [ ] Integration Points

### 3. Content Quality Checks
- [ ] **Specificity**: No vague phrases like "balanced appropriately", "calculated correctly"
- [ ] **Formulas**: Every calculation explicitly written
- [ ] **Magic Numbers**: All numeric values justified or tunable
- [ ] **Edge Cases**: Minimum of 5 edge cases documented
- [ ] **Integration**: Every other system this depends on is named
- [ ] **Reading Flow**: Sections in logical order; a new reader could understand

### 4. Cross-System Consistency
- [ ] References to other systems match their actual GDDs
- [ ] Data schema doesn't conflict with existing DataStore schema
- [ ] Remote names align with remotes-manifest
- [ ] UI references match UI style guide

### 5. Roblox-Specific Checks
- [ ] Security: Server authority respected
- [ ] DataStore: Budget impact considered
- [ ] Performance: Mobile feasibility acknowledged
- [ ] Content policy: Age-appropriate
- [ ] Accessibility: Considered for player interactions

## Output
Generate a review report:

```markdown
# Design Review: [GDD Name]

## Summary
- Total issues: X
- Critical: X (must fix)
- Important: X (should fix)
- Nice-to-have: X (suggestions)

## Critical Issues
1. [Issue description, location, suggested fix]

## Important Issues
1. [...]

## Nice to Have
1. [...]

## Recommended Actions
- [Specific next steps for the author]
```

Share the report with the user for decision on which fixes to apply.
Never modify the GDD without user approval.
