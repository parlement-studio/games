---
name: retention-analysis
description: Template-driven analysis of retention metrics. Guides through interpreting D1/D7/D30, session metrics, and funnel analysis. Generates actionable improvement plan.
---

# /retention-analysis — Retention Metrics Analysis

## Delegate to: analytics-retention-specialist

## Steps

### 1. Gather Data
Ask the user to provide or pull from Roblox Analytics:
- **Retention**: D1, D7, D30 percentages (current + last 30 days)
- **Sessions**: Average session length, sessions per day per user
- **Funnel**: New player funnel step completion rates
- **Concurrent Users**: Peak CCU, average CCU trends
- **Revenue**: ARPDAU, conversion rate (if applicable)
- **Platform split**: Mobile vs. PC vs. console %

### 2. Benchmark Against Targets
| Metric | Target | Current | Delta | Status |
|--------|--------|---------|-------|--------|
| D1 Retention | > 25% | ?% | ? | 🟢/🟡/🔴 |
| D7 Retention | > 12% | ?% | ? | 🟢/🟡/🔴 |
| D30 Retention | > 5% | ?% | ? | 🟢/🟡/🔴 |
| Avg Session | > 15 min | ? | ? | 🟢/🟡/🔴 |
| Sessions/Day | > 1.5 | ? | ? | 🟢/🟡/🔴 |
| Conversion | > 3% | ?% | ? | 🟢/🟡/🔴 |

### 3. Identify Weakness
Which metric is furthest from target? That's the priority.

### 4. Hypothesis Generation
For the weak metric, brainstorm causes:

**Low D1 Retention**:
- FTUE is confusing or slow
- No first-session reward
- Performance issues on first load
- Crashes on first play

**Low D7 Retention**:
- No reason to come back
- Daily reward not compelling
- Content runs out quickly
- Social features missing

**Low Session Length**:
- Session loop too short
- Nothing to do after core loop
- AFK handling kicks players

**Low Conversion**:
- Monetization not discoverable
- Items not appealing
- Too expensive for perceived value
- Pay-to-win pushback

### 5. Recommend Experiments
For top 2-3 hypotheses, recommend experiments:
- **Change**: What to change
- **Measure**: What metric will tell us if it worked
- **Duration**: How long to run
- **Sample**: How many players needed

### 6. Generate Report
Save to `production/analytics/retention-<date>.md` on approval using `.claude/docs/templates/retention-report-template.md`.

```markdown
# Retention Analysis: [Period]

**Date**: YYYY-MM-DD
**Period analyzed**: [start] to [end]

## Summary
[1-3 sentences on overall health]

## Metric Status
[Table from step 2]

## Primary Concern
**[Metric name]** is [X%] below target.

## Hypotheses
1. [Hypothesis 1 with reasoning]
2. [Hypothesis 2 with reasoning]
3. [Hypothesis 3 with reasoning]

## Recommended Experiments
### Experiment A: [Name]
- Hypothesis: [What we think will work]
- Change: [Specific change to make]
- Measure: [Metric to watch]
- Duration: 7 days
- Required sample: 500 players per variant

## Next Steps
1. Decide which experiment to run first
2. Implement via live-ops-specialist
3. Monitor metric daily
4. Review results in 7-14 days
```
