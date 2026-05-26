---
name: launch-checklist
description: First launch specific checklist. Soft launch plan, metrics to watch, and go/no-go criteria. Use for the first public launch of a new Roblox game.
---

# /launch-checklist — First Launch Preparation

## Delegate to: release-manager (with producer, analytics-retention-specialist, community-manager)

## Unique to First Launch
First launches are higher-risk than updates — no existing player base to forgive bugs, and a bad first impression is hard to recover from. This checklist goes beyond `/release-checklist` with launch-specific considerations.

## Phases

### Phase 1: Soft Launch (Private Testing)
- [ ] Closed beta with ~50-200 testers
- [ ] Group invite-only or private server code
- [ ] Collect feedback via structured form
- [ ] Monitor crash rate, FPS, feedback quality
- [ ] Iterate on top 3 issues before public launch

### Phase 2: Limited Public (Optional)
- [ ] Public but unadvertised — soft launch to see organic discovery
- [ ] Watch Discover page performance
- [ ] Verify critical metrics hold up at higher concurrency
- [ ] Fix any issues found in limited public before full marketing push

### Phase 3: Marketing Push
- [ ] Content creator outreach kicks off
- [ ] Social media campaign active
- [ ] Paid ads running (if budget)
- [ ] Community events scheduled
- [ ] Launch trailer published

### Phase 4: Launch Day
- [ ] All hands on deck for first 4-8 hours
- [ ] Real-time monitoring in place
- [ ] Quick-response plan for critical bugs
- [ ] Player support active (Discord mods)
- [ ] Press/community engagement

## Critical Go/No-Go Criteria

### Go Criteria (all must be true)
- [ ] No S0 bugs open
- [ ] No S1 bugs affecting core loop
- [ ] Crash rate < 1% in soft launch
- [ ] D1 retention in soft launch > 20% (prefer 25%+)
- [ ] Average session length > 10 minutes in soft launch
- [ ] Server costs manageable at projected launch CCU
- [ ] Team ready for launch-day support
- [ ] Rollback plan tested

### No-Go Triggers
- [ ] Any S0 bug discovered in final testing
- [ ] Crash rate > 2% in soft launch
- [ ] DataStore failures > 0.5% of operations
- [ ] Server crashes > 5% of sessions
- [ ] Team burnout / not ready for launch support
- [ ] Competitive release same day (potential to delay)

## Launch Day Monitoring

### Metrics to Watch (First 4 Hours)
- **CCU**: Real-time concurrent users
- **Join Rate**: New players per minute
- **Session Length**: First-session duration
- **Crash Rate**: Client/server crashes
- **Error Rate**: Script errors
- **DataStore Errors**: Save/load failures
- **Revenue**: ARPDAU, conversion rate (if monetization enabled)

### Alert Thresholds (trigger immediate response)
- CCU drops > 50% in 15 minutes
- Crash rate > 5%
- DataStore error rate > 1%
- Player reports > 10 of same issue

### Response Protocol
1. Verify issue (reproduce or confirm from multiple reports)
2. Classify severity
3. If hotfixable: run `/hotfix` workflow
4. If not: consider rollback via Studio version history
5. Communicate to community (Discord, Twitter)
6. Document for post-launch retro

## Output
```markdown
# Launch Checklist: [Game Name]

**Target Launch Date**: YYYY-MM-DD
**Soft Launch Date**: YYYY-MM-DD
**Phase**: [Planning / Soft Launch / Public Limited / Marketing / Launch / Post-Launch]

## Go/No-Go Status
- Critical criteria: [X/Y met]
- **Recommendation**: [Go / Delay / Reset Soft Launch]

## Monitoring Setup
- Dashboards: [list]
- Alerts: [list]
- On-call: [who]

## Communication Plan
- Discord: [announcement ready?]
- Twitter: [post schedule?]
- Creators: [notified?]

## Risk Register
1. [Top launch risk]
2. [Top launch risk]

## Next Steps
1. [Immediate action]
2. [Immediate action]
```
