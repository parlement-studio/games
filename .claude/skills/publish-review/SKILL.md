---
name: publish-review
description: Pre-publish review checklist for a Roblox experience update. Covers DataStore readiness, exploit checks, performance, content policy compliance, metadata, and rollback planning.
disable-model-invocation: true
---

# /publish-review — Pre-Publish Checklist

Before publishing an update to Roblox, verify ALL of the following:

## Delegate to: release-manager (with qa-lead, exploit-security-specialist, performance-analyst for verification)

## 1. Code Quality
- [ ] All code reviewed (no TODO/FIXME/HACK remaining for this release)
- [ ] No `print()` debug statements in production code
- [ ] No test/debug features enabled
- [ ] All deprecated API usage removed (wait, spawn, delay)

## 2. Data Safety
- [ ] DataStore schema changes are backwards-compatible OR migration tested
- [ ] Session locking functioning correctly
- [ ] BindToClose handler tested (simulate server shutdown)
- [ ] No data loss possible during update rollout

## 3. Security
- [ ] `/exploit-check` passed with no Critical findings
- [ ] All remotes validated server-side
- [ ] No sensitive logic exposed to client

## 4. Performance
- [ ] Server heartbeat stable (< 30ms per frame)
- [ ] Client FPS acceptable on low-end devices (> 30 FPS mobile)
- [ ] Memory usage within budget (< 2GB server, < 800MB client mobile)
- [ ] No memory leaks (test with 30-min session)

## 5. Content Policy
- [ ] No Roblox ToS violations (violence, gambling, inappropriate content)
- [ ] All text is chat-filter safe (no hardcoded profanity)
- [ ] Age-appropriate content

## 6. Experience Configuration
- [ ] Game icon updated (512x512)
- [ ] Thumbnails updated (if changed)
- [ ] Description updated
- [ ] Social links configured
- [ ] Max players set correctly
- [ ] Genre tags appropriate

## 7. Rollback Plan
- [ ] Previous version identified (what to revert to if something breaks)
- [ ] DataStore rollback procedure documented (if schema changed)
- [ ] Team aware of monitoring procedures post-publish

## 8. Analytics & Monitoring
- [ ] Analytics events updated for new features
- [ ] Dashboards set up to watch post-publish metrics
- [ ] Alert thresholds configured (crash rate, error rate)
- [ ] First 24-hour monitoring plan in place

## 9. Patch Notes & Communication
- [ ] Patch notes written and reviewed (via `/patch-notes`)
- [ ] Social media posts drafted (if applicable)
- [ ] Discord/community announcements drafted
- [ ] Content creators notified if the update is significant

## Output
Checklist with pass/fail for each item. Block publish recommendation if any Critical item fails.

```markdown
# Publish Review: [Version]

**Date**: YYYY-MM-DD
**Version**: X.Y.Z
**Reviewer**: [user]

## Critical Items
- [✅/❌] Item 1
- [✅/❌] Item 2

## Recommendation
[✅] **APPROVED FOR PUBLISH**
[⏸️] **HOLD — blockers listed below**
[❌] **REJECTED — critical issues must be resolved**

## Blockers (if any)
1. [Specific issue, owner, ETA]

## Post-Publish Monitoring
- Watch dashboards for first 2 hours
- Post-publish review in 24 hours
```

Save to `production/releases/publish-review-<version>.md` on approval.
