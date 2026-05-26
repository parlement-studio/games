---
name: tech-debt
description: Identify and catalog technical debt with severity and estimated fix cost. Use for periodic debt audits or when deciding what to clean up next.
---

# /tech-debt — Technical Debt Catalog

## Delegate to: lead-programmer (with technical-director for architecture debt)

## Steps

### 1. Search for Debt Markers
```bash
grep -rn "TODO\|FIXME\|HACK\|XXX\|DEPRECATED" src/ --include="*.lua" --include="*.luau"
```

### 2. Search for Known Anti-Patterns
```bash
# Deprecated APIs
grep -rn "[^.]wait(" src/ | grep -v "task.wait\|:Wait"

# Magic numbers in gameplay
grep -rn "[^a-zA-Z_][0-9]\{3,\}" src/ServerScriptService src/ServerStorage

# Stringy bools
grep -rn "== \"true\"\|== \"false\"" src/
```

### 3. Catalog Each Item

For each piece of debt:
- **Location**: file:line
- **Category**: Architecture / Code Quality / Performance / Security / Documentation
- **Description**: What's wrong
- **Severity**: Critical / High / Medium / Low
- **Estimated fix cost**: hours or T-shirt size
- **Impact if ignored**: What breaks or gets worse
- **Suggested fix approach**: High-level plan

### 4. Score and Prioritize
Priority = Impact / Cost

High-impact, low-cost items go first.

### 5. Categorize

#### Architecture Debt
- Coupling problems
- Missing abstractions
- Circular dependencies
- Inconsistent patterns

#### Code Quality Debt
- Duplicated code
- Magic numbers
- Missing type annotations
- Commented-out code

#### Performance Debt
- Inefficient algorithms
- Missing caching
- Unoptimized hot paths
- Memory leaks

#### Security Debt
- Missing validation
- Client-trust assumptions
- Deprecated security APIs
- Missing rate limits

#### Documentation Debt
- Missing GDD sections
- Out-of-date comments
- No architecture diagrams
- Missing ADRs

### 6. Generate Report
```markdown
# Tech Debt Inventory

**Date**: YYYY-MM-DD
**Total items**: X
**Estimated total cost**: Y hours

## By Category
- Architecture: X items
- Code Quality: X items
- Performance: X items
- Security: X items
- Documentation: X items

## Top 10 Priority Items
| # | Location | Issue | Category | Severity | Cost | Priority Score |
|---|----------|-------|----------|----------|------|----------------|
| 1 | src/combat/hit.lua:42 | No input validation | Security | High | 1h | 9/10 |
| 2 | ... | ... | ... | ... | ... | ... |

## Critical Items (fix ASAP)
1. [Description]

## Quick Wins (high impact, low cost)
1. [Description]

## Long-term Investments
1. [Description — worth doing but not urgent]

## Recommendations
- Allocate ~15% of each sprint to debt paydown
- Fix critical items this sprint
- Schedule quick wins for next sprint
- Plan dedicated refactor sprint for architecture items
```

### 7. Optionally: Write to Disk
On approval, save to `production/tech-debt-<date>.md`.
Update `production/session-state/tech-debt-tracker.md` with totals.
