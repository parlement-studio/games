---
name: team-release
description: Multi-agent orchestration for publishing a release. Coordinates release-manager, qa-lead, exploit-security-specialist, performance-analyst, community-manager, and writer.
---

# /team-release — Release Publishing Team

## Orchestration Flow

Releases involve many disciplines. This orchestrates them into a publish.

### Phase 1: Verification
1. **qa-lead**: Verify test plan completion
2. **exploit-security-specialist**: Final security pass
3. **performance-analyst**: Final perf benchmarks
4. **release-manager**: Runs `/publish-review` checklist

### Phase 2: Documentation
5. **release-manager**: Generate `/changelog`
6. **writer**: Polish technical changelog into player-facing `/patch-notes`
7. **community-manager**: Prep Discord / social announcements

### Phase 3: Configuration
8. **release-manager**: Verify experience configuration (icon, thumbnails, description, social links)
9. **devops-engineer**: Verify CI/CD and deployment pipeline ready

### Phase 4: Publish
10. **release-manager**: Execute publish
11. **release-manager**: Verify new version is live
12. **community-manager**: Publish community announcements

### Phase 5: Monitor
13. **analytics-retention-specialist**: Watch metrics dashboards
14. **qa-lead**: Watch bug reports
15. **incident-responder-style workflow**: Ready for hotfix if needed

## Steps

### 1. Gather Context
- "What version?" (X.Y.Z)
- "What's the theme?"
- "What's the rollout strategy?" (immediate / gradual / canary)

### 2. Verification Phase
- Run `/publish-review` (comprehensive checklist)
- Any critical blockers → halt release until resolved
- Verify all metrics targets met

### 3. Documentation Phase
- Generate changelog
- Polish into patch notes
- Draft community announcements

### 4. Configuration Phase
- Verify all Roblox experience settings
- Ensure CI/CD is ready
- Verify rollback plan is documented

### 5. Go/No-Go Decision
Present the full situation to the user:
- Verification status
- Documentation ready
- Configuration ready
- Monitoring set up
- Rollback plan

User makes the final go/no-go call.

### 6. Publish Phase
- Execute publish (via Studio or Open Cloud)
- Verify new version running
- Send announcements
- Start monitoring

### 7. First 24 Hours
- Team on call
- Watch crash rate, error rate, retention, revenue
- Respond to any issues via `/hotfix` if needed

## Output
A successful release with documentation, monitoring, and communication.

## Blockers (halt release)
- S0 bug discovered in verification
- Performance regression vs. baseline
- Critical security finding
- DataStore migration untested
- Rollback plan not documented
- Team not ready for launch support

## Quality Checks
- [ ] All phases completed
- [ ] User explicitly approved go/no-go
- [ ] New version verified live
- [ ] Monitoring active
- [ ] Communications sent
