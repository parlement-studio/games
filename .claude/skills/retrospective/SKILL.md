---
name: retrospective
description: Sprint retrospective facilitation — what went well, what didn't, action items for next sprint.
---

# /retrospective — Sprint Retrospective

## Delegate to: producer

## Steps

### 1. Identify Sprint
Ask: "Which sprint are we retrospecting?"
- Default: most recent sprint in `production/sprints/`

### 2. Load Sprint Data
Read:
- Sprint plan (original commitments)
- Milestone reviews (if this sprint spanned a milestone)
- Decision log entries from this sprint's timeframe
- Any bug reports filed
- Metrics if available (agent log, time tracking)

### 3. Facilitate Reflection
Ask the user to reflect on:

**What went well?**
- Features shipped as planned
- Good process moments
- Effective collaboration
- Technical wins

**What didn't go well?**
- Tasks that slipped
- Unexpected blockers
- Process friction
- Bugs that escaped to production

**What should we try?**
- New practices to experiment with
- Changes to existing process
- Tool improvements
- Agent delegation patterns that might help

**What should we stop?**
- Practices that aren't paying off
- Meetings or overhead that's not useful
- Tool usage that's hurting flow

### 4. Extract Action Items
For each "try" or "stop":
- Make it concrete and assignable
- Give it a target sprint
- Define success criteria

### 5. Generate Retro Document
```markdown
# Retrospective: Sprint [N]

**Date**: YYYY-MM-DD
**Duration**: [start date] to [end date]
**Participants**: [user]

## Sprint Summary
- Committed: X tasks
- Completed: Y tasks
- Added mid-sprint: Z tasks
- Carried over: W tasks

## What Went Well 🟢
1. [Specific win]
2. [Specific win]

## What Didn't Go Well 🔴
1. [Specific issue]
2. [Specific issue]

## What to Try 🆕
1. [Concrete experiment]
2. [Concrete experiment]

## What to Stop 🛑
1. [Practice to drop]

## Action Items
- [ ] [Action item with owner and target sprint]
- [ ] [Action item with owner and target sprint]

## Key Learnings
- [Insight worth remembering]
- [Insight worth remembering]
```

## Output
Present the retro draft. On approval, save to `production/sprints/sprint-<N>-retro.md`.
Update `production/decision-log.md` with key learnings.
