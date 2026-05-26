---
name: doctor
description: Run a comprehensive health check on the repo. Verifies README counts match reality, promised files exist, no unresolved placeholders, wiki index is synced, toolchain configs are valid, and agent roster is accurate. Use after making structural changes or before publishing.
---

# /doctor — Repo Health Check

## Purpose

One command that catches all drift, broken promises, stale counts, and missing files. The template should never promise what it doesn't ship.

## Checks (run all programmatically)

### 1. Count Accuracy

Run these and compare with README.md badge/table values:

```bash
# Actual counts
AGENTS=$(ls .claude/agents/ | wc -l | tr -d ' ')
SKILLS=$(find .claude/skills -name "SKILL.md" | wc -l | tr -d ' ')
HOOKS=$(ls .claude/hooks/ | wc -l | tr -d ' ')
RULES=$(ls .claude/rules/ | wc -l | tr -d ' ')
TEMPLATES=$(ls .claude/docs/templates/ | wc -l | tr -d ' ')
WIKI_PAGES=$(find wiki -name "*.md" -not -path "wiki/raw/*" -type f | wc -l | tr -d ' ')
RAW_SOURCES=$(find wiki/raw -name "*.md" -type f | wc -l | tr -d ' ')

echo "Agents: $AGENTS"
echo "Skills: $SKILLS"
echo "Hooks: $HOOKS"
echo "Rules: $RULES"
echo "Templates: $TEMPLATES"
echo "Wiki pages: $WIKI_PAGES"
echo "Raw sources: $RAW_SOURCES"
```

Then grep README.md for the claimed numbers and flag any mismatch.

### 2. Promised Files Exist

Check every file referenced in `.claude/docs/directory-structure.md`:

```bash
# Tool scripts
for f in tools/setup.sh tools/build.sh tools/lint.sh tools/test.sh; do
    [ -f "$f" ] && echo "✅ $f" || echo "❌ $f MISSING"
done

# Toolchain configs
for f in default.project.json selene.toml stylua.toml wally.toml aftman.toml; do
    [ -f "$f" ] && echo "✅ $f" || echo "❌ $f MISSING"
done

# CI
[ -f ".github/workflows/ci.yml" ] && echo "✅ CI workflow" || echo "❌ CI workflow MISSING"

# Production files
for f in production/decision-log.md production/risk-register.md; do
    [ -f "$f" ] && echo "✅ $f" || echo "❌ $f MISSING"
done

# Core docs
for f in CLAUDE.md README.md LICENSE .gitignore UPGRADING.md; do
    [ -f "$f" ] && echo "✅ $f" || echo "❌ $f MISSING"
done
```

### 3. Unresolved Placeholders

```bash
# Scan for common placeholder patterns
grep -rn "\[CHOOSE:" CLAUDE.md README.md .claude/docs/ 2>/dev/null
grep -rn "\[TODO:" CLAUDE.md README.md 2>/dev/null
grep -rn "\[PLACEHOLDER" CLAUDE.md README.md 2>/dev/null
grep -rn "TBD\|tbd" CLAUDE.md README.md 2>/dev/null | grep -v "^Binary"
```

Flag any matches as unresolved.

### 4. Wiki Index Sync

```bash
# Compare index page_count with actual disk count
INDEX_COUNT=$(grep "page_count:" wiki/index.md | head -1 | grep -oE '[0-9]+')
DISK_COUNT=$(find wiki -name "*.md" -not -path "wiki/raw/*" -type f | wc -l | tr -d ' ')
echo "Index claims: $INDEX_COUNT"
echo "Disk has: $DISK_COUNT"
[ "$INDEX_COUNT" = "$DISK_COUNT" ] && echo "✅ Synced" || echo "❌ DRIFT: $((DISK_COUNT - INDEX_COUNT)) pages off"
```

### 5. Wiki Status Breakdown

```bash
for status in complete draft stub; do
    count=$(grep -rl "status: $status" wiki/ --include='*.md' 2>/dev/null | grep -v '/raw/' | wc -l | tr -d ' ')
    echo "$status: $count"
done
```

### 6. Toolchain Validity

```bash
# JSON validity
python3 -c "import json; json.load(open('default.project.json'))" 2>/dev/null && echo "✅ default.project.json valid JSON" || echo "❌ default.project.json INVALID"

# Key fields
grep -q '"roblox"' selene.toml && echo "✅ selene.toml has std=roblox" || echo "❌ selene.toml missing std"
grep -q 'indent_type' stylua.toml && echo "✅ stylua.toml configured" || echo "❌ stylua.toml empty"
grep -q '\[package\]' wally.toml && echo "✅ wally.toml has package section" || echo "❌ wally.toml missing package"
grep -q '\[tools\]' aftman.toml && echo "✅ aftman.toml has tools" || echo "❌ aftman.toml missing tools"
```

### 7. Agent Roster Completeness

```bash
# Every .md in agents/ should be mentioned in agent-roster.md
for f in .claude/agents/*.md; do
    name=$(basename "$f" .md)
    if ! grep -q "$name" .claude/docs/agent-roster.md 2>/dev/null; then
        echo "❌ Agent '$name' not in agent-roster.md"
    fi
done
echo "✅ Roster check complete"
```

### 8. MCP Integration Check

```bash
# Studio MCP agent exists
[ -f ".claude/agents/studio-mcp-operator.md" ] && echo "✅ Studio MCP agent" || echo "❌ Studio MCP agent MISSING"

# Blender MCP agent exists
[ -f ".claude/agents/blender-mcp-operator.md" ] && echo "✅ Blender MCP agent" || echo "❌ Blender MCP agent MISSING"

# CLAUDE.md mentions MCP
grep -q "Studio MCP" CLAUDE.md && echo "✅ CLAUDE.md references Studio MCP" || echo "❌ CLAUDE.md missing Studio MCP ref"
grep -q "Blender MCP" CLAUDE.md && echo "✅ CLAUDE.md references Blender MCP" || echo "❌ CLAUDE.md missing Blender MCP ref"
```

### 9. Source File Bootstrap

```bash
# Minimum runtime files exist
for f in src/ServerScriptService/Main.server.luau src/StarterPlayer/StarterPlayerScripts/ClientBootstrap.client.luau src/ReplicatedStorage/Shared/Remotes.luau src/ReplicatedStorage/Shared/Types.luau; do
    [ -f "$f" ] && echo "✅ $f" || echo "⚠️ $f not yet created (created by /start)"
done
```

### 10. Git State

```bash
# Clean working tree
DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
[ "$DIRTY" = "0" ] && echo "✅ Clean working tree" || echo "⚠️ $DIRTY uncommitted changes"

# Up to date with remote
git fetch --dry-run 2>&1 | grep -q "." && echo "⚠️ Remote has new commits" || echo "✅ Up to date"
```

## Output Format

Compile all results into:

```markdown
# Doctor Report

**Date:** YYYY-MM-DD
**Status:** [HEALTHY / WARNINGS / UNHEALTHY]

## Counts
| Item | README | Actual | Match |
|------|--------|--------|-------|
| Agents | X | X | ✅/❌ |
| Skills | X | X | ✅/❌ |
| Hooks | X | X | ✅/❌ |
| Rules | X | X | ✅/❌ |

## File Integrity
- [✅/❌] All promised files exist
- [List any missing]

## Placeholders
- [✅/❌] No unresolved placeholders

## Wiki
- Index: [synced/drifted]
- Status: X complete, Y draft, Z stub

## Toolchain
- [✅/❌] All configs valid

## Agent Roster
- [✅/❌] All agents in roster

## MCP
- [✅/❌] Studio MCP configured
- [✅/❌] Blender MCP configured

## Git
- [✅/❌] Clean tree
- [✅/❌] Up to date

## Recommendations
1. [Most critical fix]
2. [Next fix]
```

## When to Run

- After structural changes (adding/removing agents, skills, hooks)
- Before publishing or pushing to GitHub
- After a batch of agent operations (ingest, research, etc.)
- Periodically as a sanity check
- Before starting a new game project from the template
