---
name: reverse-document
description: Generate design docs from existing code. Reverse-engineer GDDs from implementation when a project has code but no design docs.
---

# /reverse-document — Reverse Engineering Design Docs

## Delegate to: systems-designer (with lead-programmer for code analysis)

## Use When
- Joining a project with no design documentation
- Code has diverged from original design docs
- Need to produce docs for handoff or publishing
- Preparing for `/design-review` on an unfinished codebase

## Steps

### 1. Scan the Codebase
Identify major systems by:
- Top-level directories in `src/`
- Module names
- Service files
- Obvious feature clusters

```bash
ls src/ServerScriptService/
ls src/ServerStorage/
ls src/ReplicatedStorage/
```

### 2. For Each System, Extract Info

#### Purpose (from code inspection)
- Module comments (if any)
- File names
- Public function names
- Type definitions

#### Data Schema
- Find DataStore keys
- Find config tables
- Find Attribute usage
- Find persistent state

```bash
grep -rn "DataStore\|Attribute\|ValueObject" src/
```

#### Remotes
- Find RemoteEvents / RemoteFunctions created
- Find FireServer / FireClient / InvokeServer / InvokeClient
- Find OnServerEvent / OnClientEvent handlers

```bash
grep -rn "RemoteEvent\|RemoteFunction\|OnServerEvent\|OnClientEvent" src/
```

#### Client-Server Split
- What files are in ServerScriptService vs. StarterPlayer?
- What's shared via ReplicatedStorage?

#### UI
- What ScreenGuis exist?
- What buttons/modals/HUDs?
- Sketch the structure

#### Formulas
- Find numeric operations in gameplay code
- Extract the math into explicit formulas
- Flag magic numbers that should be documented

### 3. Draft a GDD
For each system, generate a draft GDD using the template. Mark sections as:
- `[INFERRED FROM CODE]` — extracted from implementation
- `[NEEDS USER INPUT]` — couldn't determine from code

### 4. Present for Review
Show each drafted GDD to the user:
- Ask them to fill in sections marked `[NEEDS USER INPUT]`
- Ask them to correct any `[INFERRED FROM CODE]` that are wrong
- Look for discrepancies (code says X, user says Y — which is authoritative?)

### 5. Save and Link
On approval:
- Save each GDD to `design/gdd/<system>-gdd.md`
- Update or create `design/gdd/systems-index.md`
- Create `design/gdd/master-gdd.md` if missing (may need user input for vision/pillars)

### 6. Flag Discrepancies
Note anywhere the code doesn't match what the user says the design should be:
- "Code implements X, but you said the design is Y — should we update the code or the design?"
- Log these in `production/decision-log.md`

## Output
```markdown
# Reverse Documentation Results

## Systems Found
1. [System A] — GDD draft saved
2. [System B] — GDD draft needs user input for [sections]

## Discrepancies Found
1. [System X] — Code does Y, but that's not documented anywhere. Intentional?

## Missing Systems (code without doc)
1. [Module] — unclear what this is. User clarification needed.

## Docs Without Code (if master-gdd exists)
- [Planned system] — no code yet

## Recommendations
1. [Action item]
```
