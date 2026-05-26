---
name: scope-check
description: Evaluate current scope vs. resources. Identify cut candidates and perform risk assessment. Use when feeling overwhelmed or running late on milestones.
---

# /scope-check — Scope vs. Resources Analysis

## Delegate to: producer

## When to Use
- Milestone at risk of slipping
- Feature list seems too long for the available time
- Team/solo dev feeling overwhelmed
- Regular sprint planning activity (midway check-in)

## Steps

### 1. Inventory Current Scope
List all planned work:
- From `production/sprints/current-sprint-plan.md`
- From `design/gdd/systems-index.md` (planned but not started)
- From `production/bugs/index.md` (known issues)

### 2. Assess Capacity
- Remaining sprint time
- Actual velocity (what's been shipped so far)
- Known blockers or distractions
- Dependencies on external work (assets, approvals)

### 3. Categorize Everything as MoSCoW
- **Must Have**: Non-negotiable; milestone fails without this
- **Should Have**: Important but skippable in a crunch
- **Could Have**: Nice to have; add if time permits
- **Won't Have (this time)**: Explicitly defer

### 4. Identify Cut Candidates
Scoring each feature on:
- **Impact**: How much does this improve the player experience? (1-5)
- **Cost**: How much work remains? (hours)
- **Risk**: How uncertain is the estimate? (Low/Med/High)
- **Dependencies**: Does cutting this free up other work?

High cost + low impact = cut first
Low cost + high impact = keep
Low cost + low impact = easy wins, defer unless trivial
High cost + high impact = must deliver but watch carefully

### 5. Propose Cuts
Present 2-3 options:
- **Option A**: Cut X, Y → ships on time with 85% of vision
- **Option B**: Cut Y, Z → ships on time with 75% of vision but easier to test
- **Option C**: No cuts → ship late by N days

### 6. Document the Decision
Write to `production/decision-log.md`:
```markdown
## YYYY-MM-DD — Scope Cut for [Sprint/Milestone]

**Context**: [why scope was reviewed]

**Options Presented**:
1. [Option A]
2. [Option B]
3. [Option C]

**Decision**: [What was chosen]

**Cut Features**:
- [Feature] — deferred to [future sprint / post-launch / killed]

**Reasoning**: [1-3 sentences on why this was the right call]

**Rollback Plan**: [How to bring cut features back if needed]
```

### 7. Update Plans
- Mark cut features in sprint plan as "deferred"
- Update `design/gdd/systems-index.md` with new priority
- Update risk register if cuts introduce new risks

## Output
```markdown
# Scope Check: [Sprint/Milestone]

## Current Status
- Committed work: X items
- Estimated remaining: Y hours
- Available capacity: Z hours
- **Over by**: (Y - Z) hours — NN% over budget

## Recommendation
**Cut**: [list of features]
**Keep**: [list of features]
**Reasoning**: [why this cut set]

## Risks Introduced
- [Risk 1 from cutting X]
- [Risk 2 from cutting Y]

## Next Steps
1. Confirm cuts with user
2. Update sprint plan
3. Communicate to any affected stakeholders
```
