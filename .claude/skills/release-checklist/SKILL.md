---
name: release-checklist
description: Full release checklist (more comprehensive than publish-review). Includes marketing prep, community comms, and post-release monitoring setup.
---

# /release-checklist — Full Release Checklist

## Delegate to: release-manager (with producer for coordination)

## Use When
- Major version release (1.0 → 2.0, etc.)
- Minor release with significant features
- Milestone ship with public announcement

## Checklist

### Pre-Release (1-2 weeks out)
- [ ] Feature freeze confirmed
- [ ] All features tagged for this release frozen
- [ ] Hotfix criteria documented (what warrants a post-release patch)
- [ ] Regression testing plan drafted (delegate to qa-lead)
- [ ] Performance benchmarks re-run (delegate to performance-analyst)
- [ ] Security audit complete (delegate to exploit-security-specialist)
- [ ] DataStore migration tested (if schema changed)

### Code & Content (1 week out)
- [ ] All critical bugs resolved
- [ ] All S0/S1 bugs from bug tracker resolved
- [ ] Code review complete on release branch
- [ ] `/luau-lint` passes without errors
- [ ] `/code-review` passes
- [ ] No `print()` or debug code in production paths
- [ ] All TODO items for this release closed

### Experience Configuration (1 week out)
- [ ] Game icon finalized (512×512)
- [ ] Thumbnails updated (up to 10, 1920×1080)
- [ ] Description updated (key features, call to action)
- [ ] Genre tags reviewed
- [ ] Max players validated
- [ ] Social links active (Discord, Twitter, YouTube)
- [ ] Age guidelines appropriate

### Marketing & Communication (1 week out)
- [ ] Patch notes drafted (`/patch-notes`)
- [ ] Trailer/teaser ready (if major release)
- [ ] Social media posts scheduled
- [ ] Discord announcement prepared
- [ ] Content creators notified (for major releases)
- [ ] Press kit updated (if applicable)

### Release Day (T-0)
- [ ] Final smoke test on production branch
- [ ] DataStore backup confirmed (manual or via backup mechanism)
- [ ] Team monitoring set up
- [ ] Publish to Roblox (`/publish-review` checklist complete first)
- [ ] Verify first server is running new version
- [ ] Social media posts published
- [ ] Community announcement published

### Post-Release (0-24 hours)
- [ ] Crash rate monitored (< 1% target)
- [ ] Error rate monitored
- [ ] Player feedback channels monitored (Discord, in-game chat)
- [ ] CCU trends watched
- [ ] DataStore error rate watched
- [ ] Revenue metrics watched (if applicable)

### Post-Release (24-72 hours)
- [ ] Formal incident review if any S0/S1 bugs occurred
- [ ] Retrospective scheduled
- [ ] Player feedback triaged
- [ ] Hotfix needed? Decide and execute via `/hotfix`

### Post-Release (1 week)
- [ ] Retention metrics checked (`/retention-analysis`)
- [ ] Engagement metrics checked
- [ ] Revenue metrics checked (if applicable)
- [ ] Document learnings in `production/releases/<version>-learnings.md`

## Output
Generate full checklist with status for each item:
```markdown
# Release Checklist: v[X.Y.Z]

**Target Release Date**: YYYY-MM-DD
**Release Lead**: [user]
**Status**: [Planning / Preparing / Ready / Released / Post-Release]

[Full checklist with pass/fail for each item]

## Open Items
1. [Blocker]
2. [Blocker]

## Ready for Release?
[✅ Yes / ⏸️ No, pending items above]
```

Save to `production/releases/checklist-<version>.md` on approval.
