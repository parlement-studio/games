---
name: project-stage-detect
description: Analyze project state — code volume, doc coverage, asset count. Determine if the project is in pre-production, production, polish, or live.
---

# /project-stage-detect — Project Stage Analysis

## Delegate to: producer (with technical-director for code analysis)

## Steps

### 1. Scan Code
```bash
# Count Luau files
find src/ -name "*.lua" -o -name "*.luau" | wc -l

# Count total lines of code
find src/ -name "*.lua" -o -name "*.luau" -exec wc -l {} + | tail -1

# Look for major systems (directories or modules)
ls src/ServerScriptService src/ServerStorage src/ReplicatedStorage 2>/dev/null
```

### 2. Scan Design Docs
```bash
# Count GDDs
find design/gdd -name "*.md" | wc -l

# Check for master GDD
ls design/gdd/master-gdd.md 2>/dev/null && echo "EXISTS" || echo "MISSING"

# Check for systems index
ls design/gdd/systems-index.md 2>/dev/null && echo "EXISTS" || echo "MISSING"
```

### 3. Scan Assets
```bash
# Count assets by type
find assets/images -type f 2>/dev/null | wc -l
find assets/audio -type f 2>/dev/null | wc -l
find assets/models -type f 2>/dev/null | wc -l
```

### 4. Check Testing
```bash
find tests -name "*.spec.lua" -o -name "*.spec.luau" 2>/dev/null | wc -l
```

### 5. Check Production Artifacts
```bash
ls production/sprints/*.md 2>/dev/null | wc -l
ls production/milestones/*.md 2>/dev/null | wc -l
```

### 6. Check Git History
```bash
git log --oneline | wc -l  # total commits
git log --since="1 month ago" --oneline | wc -l  # recent activity
```

### 7. Classify Stage

| Stage | Signals |
|-------|---------|
| **Pre-production** | No master GDD, <5 GDDs, <1000 LOC, minimal assets |
| **Production** | Master GDD exists, systems being built, code growing fast, sprints active |
| **Polish** | All core systems implemented, bug triage focused, perf work happening |
| **Live** | Published, version tags exist, patch notes history, active retro cadence |

### 8. Identify Gaps
For each stage, identify what's missing:

#### Pre-production gaps
- No game concept?
- No creative pillars?
- No target audience defined?

#### Production gaps
- No systems-index?
- GDDs without corresponding code?
- Code without corresponding GDDs?
- No tests?
- No CI?

#### Polish gaps
- No `/exploit-check` run?
- No performance benchmarks?
- No accessibility review?

#### Live gaps
- No analytics events?
- No live ops plan?
- No community structure?

### 9. Output
```markdown
# Project Stage Detection

**Date**: YYYY-MM-DD

## Metrics
- Source files: X
- Lines of code: X
- GDDs: X
- Total assets: X
- Tests: X
- Commits: X (total), Y (last 30 days)
- Sprints: X
- Milestones: X

## Detected Stage
**[Pre-production / Production / Polish / Live]**

## Confidence
- High / Medium / Low

## Reasoning
[Why this classification]

## Gaps for Current Stage
1. [Gap 1]
2. [Gap 2]
3. [Gap 3]

## Recommended Next Steps
1. [Action 1]
2. [Action 2]

## Readiness for Next Stage
- [What's needed to advance]
```

Present the analysis for user confirmation. The classification is a proposal — the user may disagree based on context you don't have.
