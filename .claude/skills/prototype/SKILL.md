---
name: prototype
description: Quick prototype workflow — minimal viable implementation, no production standards, README with hypothesis. Code goes in prototypes/, never imported from src/.
---

# /prototype — Rapid Prototyping Workflow

## Delegate to: luau-gameplay-programmer or luau-systems-programmer (depending on scope)

## Purpose
Prototypes are throwaway code to test an idea quickly. They are NOT production code.

## Rules
- Prototypes live in `prototypes/<prototype-name>/`
- Prototypes NEVER import from `src/`
- Prototype code does NOT need to meet production standards
- Prototypes require a README.md explaining the hypothesis
- Prototypes are NOT graduated directly to `src/` — if the idea is good, rewrite cleanly

## Steps

### 1. Define the Hypothesis
Ask the user:
- "What are we testing?"
- "What's the question this prototype answers?"
- "What would 'success' look like?"
- "What's the time budget?" (default: 2-4 hours)

### 2. Scope Ruthlessly
- Only build what's needed to test the hypothesis
- Skip: polished UI, data persistence, multiplayer (unless core to hypothesis)
- Focus: the thing that's being questioned

### 3. Set Up Prototype Directory
```
prototypes/
└── <prototype-name>/
    ├── README.md        # Hypothesis, how to run, findings
    ├── src/             # Prototype Luau files
    └── assets/          # Any placeholder assets
```

### 4. Build the Minimum
Write code that answers the question. Do NOT:
- Add type annotations (unless they help)
- Wrap in pcall (unless necessary for the question)
- Write tests
- Worry about cleanup
- Optimize performance

DO:
- Use clear variable names (so future-you understands)
- Comment the KEY decisions
- Make it runnable (Rojo or manual Studio import)

### 5. Document Findings
After running, update the README:
```markdown
# Prototype: [Name]

## Hypothesis
[What we were testing]

## How to Run
1. [Setup steps]
2. [Run steps]

## What We Learned
- [Finding 1]
- [Finding 2]
- [Unexpected result]

## Go / No-Go
**Verdict**: [Good idea / bad idea / needs more research]

## If Go, Next Steps
1. [How to translate this into production]
2. [What specialists are needed]
3. [What systems it affects]

## If No-Go
- [Why it didn't work]
- [Alternative approaches to consider]
```

### 6. Decide
User decides:
- **Good idea**: Schedule proper implementation (rewrite, not copy-paste)
- **Good idea with tweaks**: Iterate the prototype OR move to production planning
- **Bad idea**: Document learnings, archive the prototype, move on
- **Inconclusive**: Decide if more prototyping is worth the time

## Anti-Patterns
- Prototype sprawl (spending weeks on a "prototype")
- Importing prototype code into production without rewrite
- Skipping the README and losing the findings
- Testing multiple hypotheses in one prototype (hard to learn from)
