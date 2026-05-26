---
name: bug-report
description: Structured bug report creation with repro steps, expected/actual behavior, and severity classification.
---

# /bug-report — Bug Report Creation

## Delegate to: qa-tester (with qa-lead for triage)

## Steps

### 1. Gather Information
Ask the user for:
- **Short description**: One sentence summary
- **What happened**: What did you observe?
- **What should have happened**: Expected behavior
- **When**: Did this just start or has it been happening?
- **Where**: Which system/feature is affected?
- **Device**: Platform (mobile/PC/console), screen size, network
- **Frequency**: Always / sometimes / once?
- **Impact**: How many players affected? Data loss risk?

### 2. Reproduce (if possible)
Work with the user to find reliable repro steps:
1. Start from a known state (e.g., fresh login)
2. List each action taken
3. Note the exact point where behavior diverges from expected

### 3. Classify Severity
- **S0 — Critical**: Data loss, crashes, security exploits, can't play
- **S1 — Major**: Feature broken for many users, major visual/UX issues
- **S2 — Normal**: Feature works but with noticeable problems
- **S3 — Minor**: Small glitches, edge cases, polish items
- **S4 — Cosmetic**: Typos, minor style issues

### 4. Generate Bug Report
Use `.claude/docs/templates/bug-report-template.md` as the base.

```markdown
# BUG: [Short descriptive title]

**ID**: BUG-YYYY-MM-DD-NNN
**Severity**: [S0-S4]
**Device**: [Platform, resolution, network]
**Build**: [Version or git commit]
**Reported**: YYYY-MM-DD
**Status**: Open

## Steps to Reproduce
1. [Step 1]
2. [Step 2]
3. [Step 3]

## Expected Behavior
[What should happen]

## Actual Behavior
[What actually happens]

## Evidence
- Screenshots: [paths or links]
- Video: [link if available]
- Console output: [paste relevant errors]
- Stack trace: [paste if available]

## Affected Systems
- [System 1]
- [System 2]

## Suspected Root Cause
[Any theories about where the bug lives]

## Workaround (if known)
[Anything the user can do to avoid it]

## Notes
[Anything else relevant]
```

### 5. Save and Triage
Present the report to the user. On approval:
- Save to `production/bugs/BUG-<date>-<NNN>.md`
- Add to `production/bugs/index.md` if that exists
- For S0/S1: Immediately escalate to qa-lead + producer
- Delegate investigation to the appropriate specialist based on affected system
