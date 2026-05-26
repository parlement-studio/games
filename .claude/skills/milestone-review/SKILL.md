---
name: milestone-review
description: Review milestone completion against criteria. Generates a status report with go/no-go recommendation for advancing.
---

# /milestone-review — Milestone Completion Review

## Delegate to: producer

## Steps

### 1. Identify Milestone
Ask: "Which milestone are we reviewing?"
- Default: Most recent milestone in `production/milestones/`

### 2. Load Milestone Criteria
Read the milestone document. Extract:
- Success criteria
- Deliverables
- Dependencies
- Risk register
- Definition of done

### 3. Verify Each Criterion
For each criterion, check:
- **Design docs**: Exist and reviewed? (delegate to `game-designer` for verification)
- **Implementation**: Complete and reviewed? (delegate to `lead-programmer`)
- **Tests**: Written and passing? (delegate to `qa-tester`)
- **Security**: No critical findings? (delegate to `exploit-security-specialist`)
- **Performance**: Benchmarks met? (delegate to `performance-analyst`)
- **Polish**: Rough edges addressed?

### 4. Generate Status Report
```markdown
# Milestone Review: [Milestone Name]

**Status**: [Complete / Incomplete / At Risk]
**Date**: YYYY-MM-DD
**Reviewer**: [user name]

## Criteria Status
| Criterion | Status | Notes |
|-----------|--------|-------|
| Feature X implemented | ✅ Done | |
| Feature Y implemented | ⚠️ Partial | UI incomplete |
| No critical security findings | ✅ Done | |
| Performance benchmarks | ❌ Missed | Server frame time 45ms (target 33ms) |

## Deliverables
- [x] GDD for combat system
- [x] Implementation of combat core
- [ ] Polish pass
- [x] Unit tests
- [ ] Exploit check

## Risk Status
- Risk 1: [description] — Mitigated
- Risk 2: [description] — Still open, impact Medium

## Recommendation
[ ] **Advance to next milestone**
[X] **Not ready — blockers listed below**

### Blockers
1. Performance regression in combat system (server frame time)
2. Combat UI 40% incomplete
3. No exploit check run yet

### Next Steps
1. Delegate perf issue to `performance-analyst`
2. Finish UI via `ui-programmer`
3. Run `/exploit-check` before re-review
```

## Output
Present the report. On approval, save to `production/milestones/milestone-<name>-review.md`.
Update `production/session-state/` with milestone status.
