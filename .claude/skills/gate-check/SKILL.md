---
name: gate-check
description: Stage gate check — does the project meet criteria to advance to the next production phase (pre-prod → prod → polish → live)?
---

# /gate-check — Stage Gate Review

## Delegate to: producer (with technical-director, qa-lead, creative-director for respective areas)

## Purpose
Stage gates force a deliberate decision about whether to move to the next production phase. Without gates, projects drift — always "almost ready" to start production, or "almost ready" to ship.

## Stages

### Pre-production → Production
**Gate criteria**:
- [ ] Master GDD exists and reviewed
- [ ] Creative pillars defined (3-5, 1 phrase each)
- [ ] Core loop defined (30s / 5min / session / meta)
- [ ] Target audience identified
- [ ] Monetization strategy drafted
- [ ] Target metrics set (retention, session, revenue if applicable)
- [ ] Tech stack decided (sync tool, UI framework, packages)
- [ ] Systems-index exists with priority
- [ ] 2-3 top systems have detailed GDDs
- [ ] Prototype or proof-of-concept validates core loop
- [ ] Team capacity matches estimated scope (or scope cut accordingly)

### Production → Polish
**Gate criteria**:
- [ ] All core systems implemented (from systems-index P0/P1)
- [ ] Game is playable end-to-end (intro → core loop → meta)
- [ ] No S0 bugs open
- [ ] All planned features either done or explicitly cut
- [ ] Basic performance targets met (30 FPS mobile, server heartbeat < 33ms)
- [ ] Security audit has been run at least once
- [ ] DataStore schema is frozen (no more breaking changes)
- [ ] Analytics events implemented
- [ ] At least one external playtest (not just devs) completed

### Polish → Live (Launch Ready)
**Gate criteria**:
- [ ] Zero S0 bugs
- [ ] Zero S1 bugs in critical paths
- [ ] Performance targets exceeded on target devices
- [ ] Security audit passed with no Critical findings
- [ ] Content policy review passed
- [ ] All launch marketing materials ready
- [ ] Community channels active
- [ ] Rollback plan tested
- [ ] Soft launch retention > target (D1 > 20%, ideally > 25%)
- [ ] Server costs projected and manageable
- [ ] Team ready for launch support

### Live → Live Service Optimization
**Gate criteria** (do we continue investing?):
- [ ] Retention trending up or stable
- [ ] Revenue meets minimum threshold
- [ ] Community engaged (growing Discord, positive reviews)
- [ ] Technical debt manageable
- [ ] Team has capacity for sustained live-ops

## Steps

### 1. Current Stage
Run `/project-stage-detect` if unclear. Get the current stage.

### 2. Target Stage
"What stage are you trying to advance to?"

### 3. Run the Checklist
For the target transition, go through each criterion:
- Verify each item
- Delegate to the relevant specialist for verification (e.g., security criteria → exploit-security-specialist)
- Record pass/fail/partial

### 4. Assess Readiness
- If ALL criteria met → Go
- If some criteria missed → No-go with blockers listed
- If close but not complete → "Go with caveats" (user decides risk tolerance)

### 5. Generate Gate Report
```markdown
# Gate Check: [Current Stage] → [Target Stage]

**Date**: YYYY-MM-DD
**Reviewer**: [user]

## Current Status
[Summary of current state]

## Criteria
| Criterion | Status | Notes |
|-----------|--------|-------|
| Master GDD exists | ✅ | |
| Core loop defined | ⚠️ Partial | Meta loop undefined |
| Creative pillars | ✅ | |
| ... | ... | ... |

## Met
[List of passing criteria]

## Not Met / Blockers
1. [Blocker with specific remediation]
2. [Blocker with specific remediation]

## Recommendation
[ ] **PASS** — advance to next stage
[X] **HOLD** — address blockers first
[ ] **PASS WITH CAVEATS** — advance accepting documented risks

## Next Steps (if HOLD)
1. [Action item]
2. [Action item]

## Target Re-review Date
YYYY-MM-DD
```

Save to `production/gates/gate-<stage>-<date>.md` on approval.
