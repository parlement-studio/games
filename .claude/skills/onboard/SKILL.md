---
name: onboard
description: Onboard a new contributor to the project. Overview of architecture, conventions, key files, and first-task suggestions.
---

# /onboard — New Contributor Onboarding

## Delegate to: producer (with technical-director for tech orientation, game-designer for creative orientation)

## Steps

### 1. Welcome
Greet the new contributor. Ask:
- "What's your role?" (programmer, designer, artist, QA, mixed)
- "Experience level?" (new to Roblox / experienced Roblox dev / experienced but new to this project)
- "What are you hoping to contribute to?" (specific system, general help, exploration)

### 2. Context Overview
Based on their role, give a tailored tour:

#### For Programmers
- **CLAUDE.md** — project-wide config
- **`.claude/docs/roblox-architecture-guide.md`** — architecture overview
- **`.claude/docs/luau-style-guide.md`** — coding standards
- **`.claude/rules/`** — path-scoped standards
- **`src/`** — game source
- **`design/gdd/`** — design docs to understand what we're building

#### For Designers
- **`design/gdd/master-gdd.md`** — master design doc
- **`design/gdd/systems-index.md`** — all systems catalog
- **`.claude/docs/templates/gdd-master.md`** and **`gdd-system.md`** — templates for new docs
- **`docs/COLLABORATIVE-DESIGN-PRINCIPLE.md`** — how we work together

#### For Artists
- **`assets/`** — asset directories
- Ask user to confirm art style docs (if they exist, point to them)
- **art-director** agent knowledge via `.claude/agents/art-director.md`

#### For QA
- **`tests/`** — existing tests
- **`production/bugs/`** — bug tracker (if exists)
- **`.claude/docs/templates/bug-report-template.md`** — bug format
- **qa-lead** and **qa-tester** agent knowledge

### 3. Introduce Key Agents
Show them the studio hierarchy:
- Directors (Opus): creative, technical, producer
- Leads (Sonnet): game-designer, lead-programmer, etc.
- Specialists (Sonnet/Haiku): the deep specialists

Explain:
- "We use subagents for specialized work"
- "You can invoke slash commands with `/command`"
- "Most work flows: Question → Options → Decision → Draft → Approval"

### 4. Introduce Workflows
Show the most useful skills for their role:
- **Programmers**: `/code-review`, `/luau-lint`, `/datastore-review`, `/remotes-audit`
- **Designers**: `/gdd`, `/design-review`, `/balance-check`, `/design-system`
- **QA**: `/bug-report`, `/exploit-check`
- **All**: `/sprint-plan`, `/estimate`, `/start` (if jumping in cold)

### 5. Suggest First Tasks
Based on their role and current sprint status:
- **First task**: Something small and self-contained to learn the ropes
- **Second task**: Something that requires collaboration (learn the handoff pattern)
- **Third task**: Actual value-add work

### 6. Explain Norms
- Committing: always ask before commits
- Reviews: every change gets reviewed by a relevant agent
- Decision log: major decisions get logged
- Production/session-state: session continuity via this directory

### 7. Output
```markdown
# Onboarding: [Contributor Name / Role]

## Your Role
[Summary]

## Key Docs to Read (in order)
1. CLAUDE.md
2. [Role-specific doc]
3. Current sprint plan
4. [Agent they should be aware of]

## Your First Tasks
1. **Warm-up**: [Specific starter task]
2. **Collaboration**: [Task requiring handoff]
3. **Real work**: [Value-add task]

## Agents to Know
- Your primary lead: [agent]
- Peer specialists: [list]

## Useful Skills
- `/[skill]` — [what it does]

## Questions?
Just ask. If unclear, I'll route to the right specialist.
```

Save to `production/onboarding/<name>-<date>.md` on approval.
