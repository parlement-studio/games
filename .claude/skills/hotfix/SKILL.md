---
name: hotfix
description: Emergency fix workflow — diagnose, apply minimal fix, test, publish, and post-mortem. Use when a live issue requires immediate action.
disable-model-invocation: true
---

# /hotfix — Emergency Fix Workflow

## Delegate to: release-manager (with technical-director, relevant specialist for actual fix)

## When to Use
- Live game broken for many users
- Critical security exploit discovered
- Data loss occurring
- Monetization broken
- Any issue that warrants interrupting normal sprint work

## DO NOT Use For
- Minor bugs (use normal bug process)
- Features that didn't make the last release
- Polish items

## Steps

### 1. Triage — Is This a Hotfix?
Confirm:
- **Severity**: Is this truly S0 or S1?
- **Impact**: How many users affected?
- **Urgency**: Can this wait for next scheduled release?
- **Workaround**: Is there a temporary workaround players can use?

If answer to "can this wait" is "yes" → not a hotfix. Use normal process.

### 2. Diagnose Fast
- Reproduce the issue (fast repro is critical)
- Identify root cause (not just symptom)
- Identify affected files/systems
- Delegate to the most relevant specialist for root-cause analysis

### 3. Design Minimal Fix
The fix should be:
- **Minimal**: Smallest possible change to fix the issue
- **Targeted**: Only touch files related to the bug
- **Reversible**: Easy to revert if the fix causes new issues
- **Tested**: Verify it fixes the issue without breaking neighbors

DO NOT:
- Bundle unrelated improvements
- Refactor around the bug
- Add new features
- Make "while we're here" changes

### 4. Test the Fix
- Reproduce the original issue → verify fix works
- Test neighboring functionality → verify no regression
- Test common user flows → verify no side effects
- If possible, test in a private place first

### 5. Expedited Review
- Quick code review (via lead-programmer or technical-director)
- Minimum checks: no hardcoded values, no client-trust, no new security holes
- If diff is < 20 lines, review should be < 10 minutes

### 6. Publish
- Publish directly to production place (skip staging if urgent)
- Use feature flag to enable fix if possible (instant rollback path)
- Communicate immediately via community channels

### 7. Monitor
- Watch metrics for 1-2 hours post-publish
- Verify fix is working for affected users
- Watch for new issues introduced by the fix

### 8. Post-Mortem (within 48 hours)
Every hotfix gets a post-mortem. Document:
- **What broke**: Clear description of the issue
- **When it broke**: When did this start affecting users?
- **How it was detected**: Player reports / monitoring / internal
- **Root cause**: Why did this happen?
- **Fix**: What was changed
- **Prevention**: What process change would prevent this in the future?
- **Timeline**: When it was detected → fixed → published

Save to `production/incidents/hotfix-<date>-<summary>.md`.

## Output — Hotfix Report
```markdown
# Hotfix: [Short description]

**Severity**: [S0/S1]
**Reported**: YYYY-MM-DD HH:MM
**Detected By**: [source]
**Fixed**: YYYY-MM-DD HH:MM
**Deployed**: YYYY-MM-DD HH:MM
**Duration of Impact**: X hours

## The Issue
[1-2 sentences on what broke]

## Root Cause
[1 paragraph on why]

## The Fix
- Files changed:
  - [file 1]: [what changed]
- Lines changed: N
- Review: [who reviewed]
- Tests: [what was tested]

## Verification
- [How we verified the fix worked]

## Prevention
- [What to do to prevent this class of issue in the future]

## Action Items
- [ ] [Follow-up action]
- [ ] [Follow-up action]
```
