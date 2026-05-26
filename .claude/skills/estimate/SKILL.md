---
name: estimate
description: Estimation workflow for a feature or task. Breaks the task into sub-tasks, estimates each, sums with contingency buffer.
---

# /estimate — Task Estimation

## Delegate to: producer (with lead-programmer for tech estimates)

## Steps

### 1. Gather Context
Ask: "What task / feature do you want to estimate?"

### 2. Break Down Into Sub-Tasks
For a typical feature, list:
- **Design**: GDD writing (0.5-2 days)
- **Implementation**: Code writing (1-10 days depending on scope)
- **Art assets**: If needed (varies wildly)
- **Integration**: Hooking into existing systems (0.5-2 days)
- **Testing**: QA plan + execution (0.5-2 days)
- **Polish**: Rough edges, edge cases (0.5-1 day)
- **Review**: Code review, design review (0.5 day)

### 3. Estimate Each Sub-Task
Use T-shirt sizing for unclear items, hours for clear items:
- **XS**: < 2 hours (trivial)
- **S**: 2-8 hours (simple)
- **M**: 1-3 days (moderate)
- **L**: 3-7 days (complex)
- **XL**: 1-2 weeks (very complex, consider breaking down)
- **XXL**: 2+ weeks (must break down further before proceeding)

### 4. Apply Contingency Buffer
- For tasks with uncertainty: +30-50%
- For tasks in new territory: +50-100%
- For tasks with external dependencies: +variable (explicit risk note)
- For bug fixes: +20% (things hide)

### 5. Sum and Sanity Check
- Compare to available capacity in current sprint
- Flag if > 40% of sprint capacity (single task dominating the sprint)
- Flag if total breakdown doesn't match vague intuition

### 6. Present Estimate
```markdown
# Estimate: [Feature Name]

## Sub-tasks
| Task | Size | Hours (est) | Risk |
|------|------|-------------|------|
| Design GDD | S | 6 | Low |
| Implement core | M | 16 | Medium |
| Implement UI | S | 8 | Low |
| Test + polish | S | 6 | Low |
| Review + iterate | S | 4 | Low |

**Subtotal**: 40 hours
**Contingency** (30%): 12 hours
**Total estimate**: ~52 hours (~6.5 working days)

## Risks
1. [Risk 1 — how it affects estimate]
2. [Risk 2]

## Assumptions
- [Assumption 1]
- [Assumption 2]

## Dependencies
- [Other tasks/systems this depends on]
```

## Output
Present estimate to user. If too large, suggest splitting the feature.
Save estimates to `production/sprints/estimates/` when approved.
