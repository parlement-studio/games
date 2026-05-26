---
name: start
description: Begin a new Roblox game project or onboard to an existing one. Use when starting a fresh session with no context, or when the user says "let's start" or "new project".
disable-model-invocation: true
---

# /start — Project Onboarding

Welcome the user and determine their starting point by asking:

**"Where are you with this project?"**

1. **No idea** — I don't even have a game concept yet
2. **Vague concept** — I have a rough idea but nothing documented
3. **Clear design** — I have a GDD or design docs ready
4. **Existing code** — I have a Roblox project with code already

## Based on their answer:

### If "No idea":
1. Run `/brainstorm` to explore game ideas
2. Guide through genre selection, target audience, core loop definition
3. Help define creative pillars (3-5 words each that describe the experience)
4. Draft a 1-page game concept document
5. Proceed to `/gdd` for the master GDD

### If "Vague concept":
1. Ask them to describe their idea in 2-3 sentences
2. Ask: What Roblox games inspire this? What's the core loop?
3. Help crystallize: genre, setting, core mechanic, target audience
4. Define creative pillars
5. Proceed to `/gdd`

### If "Clear design":
1. Ask them to share or describe their existing design docs
2. Review for completeness against GDD standards
3. Run `/project-stage-detect` to assess readiness
4. Identify gaps and create a plan to fill them
5. Set up the project structure if not already done

### If "Existing code":
1. Ask them to describe the project and share the codebase location
2. Run `/reverse-document` to generate docs from existing code
3. Run `/project-stage-detect` to assess current stage
4. Identify technical debt with `/tech-debt`
5. Create a plan for what's next

---

## Team Size Preset

After the starting-point question, ask:

**"What's your team size?"**

1. **Solo** — just me. Streamlined review, fewer agent interactions.
2. **Small team** (2-5) — lean review, key specialists involved.
3. **Studio** (5+) — full review pipeline, all agents active.

Based on the answer, set `review_mode` automatically:
- Solo -> `solo`
- Small team -> `lean`
- Studio -> `full`

---

## Genre Preset (optional)

Ask:

**"What genre?"** (Tell the user they can skip this if they don't know yet.)

1. **Simulator** — sets up simulator-specific patterns
2. **RPG** — sets up RPG progression, combat, equipment
3. **FPS** — sets up first-person framework, weapons, viewmodel
4. **Obby** — sets up checkpoint system, kill bricks
5. **Tycoon** — sets up dropper pipeline, buttons, upgrades
6. **Social / Hangout** — sets up social features, housing
7. **Tower Defense** — sets up tower placement, wave spawning, targeting
8. **Custom** — no preset, start from scratch

### Genre-specific guidance

When a genre is selected, provide the following recommendations:

#### Simulator
- **Wiki pages**: `wiki/patterns/simulator-loop.md`, `wiki/services/DataStoreService.md`, `wiki/concepts/server-authority.md`
- **Skills to run first**: `/gdd`, `/datastore-design`
- **Key agents**: `economy-designer`, `datastore-architect`, `luau-systems-programmer`

#### RPG
- **Wiki pages**: `wiki/patterns/rpg-progression.md`, `wiki/services/DataStoreService.md`, `wiki/concepts/session-locking.md`
- **Skills to run first**: `/gdd`, `/datastore-design`, `/combat-design`
- **Key agents**: `game-designer`, `systems-designer`, `economy-designer`, `luau-gameplay-programmer`

#### FPS
- **Wiki pages**: `wiki/patterns/fps-framework.md`, `wiki/concepts/server-authority.md`, `wiki/performance/heartbeat-budget.md`
- **Skills to run first**: `/gdd`, `/combat-design`
- **Key agents**: `luau-gameplay-programmer`, `remotes-networking-specialist`, `exploit-security-specialist`, `performance-analyst`

#### Obby
- **Wiki pages**: `wiki/patterns/obby-checkpoints.md`, `wiki/services/DataStoreService.md`
- **Skills to run first**: `/gdd`, `/level-design`
- **Key agents**: `level-designer`, `luau-gameplay-programmer`

#### Tycoon
- **Wiki pages**: `wiki/patterns/tycoon-dropper.md`, `wiki/services/DataStoreService.md`, `wiki/concepts/server-authority.md`
- **Skills to run first**: `/gdd`, `/datastore-design`, `/economy-design`
- **Key agents**: `economy-designer`, `datastore-architect`, `luau-systems-programmer`

#### Social / Hangout
- **Wiki pages**: `wiki/patterns/social-features.md`, `wiki/patterns/housing-system.md`
- **Skills to run first**: `/gdd`, `/ui-design`
- **Key agents**: `ui-programmer`, `ux-designer`, `game-designer`

#### Tower Defense
- **Wiki pages**: `wiki/patterns/tower-defense.md`, `wiki/concepts/object-pooling.md`, `wiki/performance/heartbeat-budget.md`
- **Skills to run first**: `/gdd`, `/combat-design`, `/economy-design`
- **Key agents**: `luau-gameplay-programmer`, `systems-designer`, `performance-analyst`, `economy-designer`

#### Custom
- No preset guidance. Start from scratch with `/gdd`.

---

## Configuration Questions

After the genre step (or skip), confirm:

1. **Sync tool**: Rojo / Argon / Manual Studio (default: Rojo)
2. **UI framework**: Native ScreenGui / Roact / Fusion (default: Native)
3. **Project name**: What should the game be called? (used in `default.project.json` and config)
4. **Max players**: How many players per server? (default: 20)

---

## Write Configuration

After the user answers all questions, write the configuration to persistent files. This is the critical step that makes `/start` durable across sessions.

### Step 1: Create `project.config.json`

Write the file to the repo root at `project.config.json`:

```json
{
  "project_name": "<user's game name>",
  "sync_tool": "<rojo | argon | manual>",
  "ui_framework": "<native | roact | fusion>",
  "review_mode": "<solo | lean | full>",
  "genre": "<simulator | rpg | fps | obby | tycoon | social | tower-defense | custom | none>",
  "max_players": <number>,
  "configured_at": "<YYYY-MM-DD>"
}
```

- `genre` should be `"none"` if the user skipped the genre question.
- `configured_at` should be today's date.

### Step 2: Update `CLAUDE.md`

In the `## Technology Stack` section of `CLAUDE.md`, replace the placeholder lines with the actual choices:

- Replace `- **Sync Tool**: [CHOOSE: Rojo / Argon / Manual Studio]` with the chosen tool, e.g. `- **Sync Tool**: Rojo`
- Replace `- **UI Framework**: [CHOOSE: Native ScreenGui / Roact / Fusion]` with the chosen framework, e.g. `- **UI Framework**: Native ScreenGui`

### Step 3: Update `default.project.json`

Set the `"name"` field in `default.project.json` to the project name the user provided.

For example, if the user named their game "Dragon Quest Obby":
```json
{
  "name": "Dragon-Quest-Obby",
  ...
}
```

Use the project name with spaces replaced by hyphens.

### Step 4: Create `production/review-mode.txt`

Write the chosen review mode to `production/review-mode.txt`. The file should contain just the mode string on a single line:

```
solo
```

or `lean` or `full`, depending on the team size preset.

---

## After onboarding, always:
- Confirm the configuration was written by listing the files created/updated
- If a genre was selected, show the recommended wiki pages, skills, and agents
- Suggest next steps based on the starting point and genre
- Remind the user they can re-run `/start` to change configuration

## Review Mode Reference
- **Full** (`full`): Every change gets reviewed by relevant agents before implementation. Best for production work with a studio team.
- **Lean** (`lean`): Critical changes reviewed; minor changes proceed with a single approval. Best for small teams moving fast.
- **Solo** (`solo`): Minimum review. User makes most decisions directly. Best for prototyping or solo development.
