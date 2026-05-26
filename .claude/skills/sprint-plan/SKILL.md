---
name: sprint-plan
description: Create a sprint plan from the systems-index and current priorities. Breaks features into tasks with estimates and owners.
---

# /sprint-plan — Sprint Planning Workflow

## Delegate to: producer

## Prerequisites
- `design/gdd/systems-index.md` exists (run `/map-systems` first if not)
- Current sprint context in `production/session-state/` (if any)

## Steps

### 1. Ask Planning Context
- "What's the sprint length?" (default: 2 weeks)
- "What's the theme/goal for this sprint?"
- "Any hard deadlines or events driving priorities?"
- "What went well / poorly last sprint?" (if returning)

### 2. Review Backlog
- Read `design/gdd/systems-index.md`
- Read `production/decision-log.md` (if exists)
- Read `production/risk-register.md` (if exists)
- Check open bug tickets (`production/bugs/` if tracked here)

### 3. Propose Sprint Goals
Present 2-4 sprint theme options based on priorities:
- **Feature-focused**: Ship N new features
- **Quality-focused**: Polish existing, fix bugs, reduce tech debt
- **Content-focused**: Add maps/quests/items to existing systems
- **Infrastructure-focused**: Refactor, CI/CD, tools
- **Live-ops-focused**: Events, balance tweaks, retention features

### 4. Break Into Tasks
For the chosen theme, break into tasks:
- **Design tasks**: GDDs to write/update
- **Implementation tasks**: Code to write
- **Art tasks**: Assets needed
- **QA tasks**: Tests to run
- **Polish tasks**: Fixes and improvements

### 5. Estimate & Assign
- Use `/estimate` for each task
- Assign each to a specialist (not a human, but the agent that would own it)
- Flag dependencies
- Sum total effort; verify it fits sprint capacity

### 6. Generate Sprint Plan Document
Write to `production/sprints/sprint-<N>-plan.md` using `.claude/docs/templates/sprint-plan-template.md`.

## Sprint Plan Template Sections
1. **Sprint Goal** (1-2 sentences)
2. **Duration** (start date, end date)
3. **Theme**
4. **Committed Tasks** (list with estimates and owners)
5. **Stretch Goals** (if capacity allows)
6. **Risks** (known blockers, unknowns)
7. **Definition of Done** (what "sprint complete" means)
8. **Review Cadence** (when to check progress)

## Output
Present the draft plan to the user for approval. On approval, save to disk.
Add sprint plan filename to `production/session-state/current-sprint.txt`.
