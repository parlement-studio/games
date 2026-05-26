---
name: balance-check
description: Check game balance — damage formulas, XP curves, drop rates, difficulty scaling. Verifies formulas are explicit and values are in config, not magic numbers.
---

# /balance-check — Game Balance Verification

## Delegate to: game-designer (with systems-designer for formula review)

## Steps

### 1. Identify What to Check
Ask: "Which system or formula are we checking?"
- Default: All tunable systems (combat, progression, economy)

### 2. Locate Formulas
Search for relevant code:
```bash
grep -rn "damage\|XP\|drop\|spawn" src/ --include="*.lua" --include="*.luau"
grep -rn "config\|CONFIG\|Config" src/ReplicatedStorage/
```

### 3. Verify Each Formula

#### Checklist per formula:
- [ ] Formula explicitly written (not buried in complex code)
- [ ] Constants externalized to config module
- [ ] Formula documented in relevant GDD
- [ ] Formula result bounded (no infinite scaling without cap)
- [ ] Edge cases handled (zero inputs, negative, max)

### 4. Simulate the Curve
For each formula, tabulate values across the expected input range:

Damage example:
```
Level | Base ATK | Weapon | Total Damage (avg)
------|----------|--------|--------------------
1     | 10       | 5      | 15
5     | 20       | 15     | 35
10    | 35       | 30     | 65
20    | 60       | 60     | 120
50    | 150      | 150    | 300
100   | 300      | 300    | 600
```

XP curve example:
```
Level | XP to next | Cumulative XP | Hours to reach (at 500 XP/hr)
------|------------|---------------|------------------------------
1 → 2 | 100        | 100           | 0.2
5 → 6 | 500        | 1500          | 3
10 → 11 | 2000     | 9500          | 19
20 → 21 | 10000    | 75000         | 150
50 → 51 | 100000   | 2000000       | 4000
```

### 5. Flag Balance Issues
- **Too steep**: Grind feels unfair (target: fun, not punishing)
- **Too shallow**: Player outgrows content too fast
- **Discontinuities**: Sudden difficulty spikes
- **Unbounded**: Values that can grow infinitely without cap
- **Undefined edges**: What happens at max level / zero input?

### 6. Recommend Adjustments
For each issue, propose concrete changes:
```markdown
Issue: XP curve at level 50 requires 4000 hours
Recommendation: Cap XP requirement at 50000 per level (reduces to 100 hours)
Impact: Whale players won't grind forever; retention curve healthier
```

### 7. Generate Balance Report
```markdown
# Balance Check: [System Name]

## Formulas Reviewed
1. [Formula 1] — status
2. [Formula 2] — status

## Curve Analysis
[Tables showing curves]

## Issues Found
### Critical
1. [Issue with recommendation]

### Important
1. ...

### Minor
1. ...

## Recommendations
1. [Concrete change 1]
2. [Concrete change 2]

## Not Yet Verified
- [Systems that need play testing to confirm balance]
```

Present the report. Offer to delegate fixes to `systems-designer`.
