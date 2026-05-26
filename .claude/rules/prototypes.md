---
paths:
  - "prototypes/**"
---

# Prototypes Rules

Files matching these paths are experimental prototypes — throwaway code to test ideas.

## Core Rules

1. **Relaxed coding standards.** This is throwaway code. Don't waste time on polish.
2. **README.md REQUIRED** explaining: hypothesis, how to run, findings.
3. **Never import from `src/`.** Prototypes are isolated. No dependencies on production code.
4. **Never graduate prototype code directly to `src/` without rewrite.** If the idea is good, rewrite cleanly using production standards.

## What You CAN Skip

- Type annotations (unless they help you reason)
- pcall wrapping (unless the question requires it)
- Unit tests
- Connection cleanup
- Performance optimization
- Documentation comments
- Consistent naming

## What You MUST Do

- Write a README.md in each prototype folder
- Make it runnable (document how)
- Document what you learned
- Mark the verdict: good idea / bad idea / inconclusive

## README Template

```markdown
# Prototype: [Name]

**Date**: YYYY-MM-DD
**Hypothesis**: [What we were testing]
**Time Budget**: [X hours]
**Actual Time**: [Y hours]

## How to Run
1. [Setup steps]
2. [Execution steps]

## What We Learned
- [Finding 1]
- [Finding 2]
- [Unexpected result]

## Verdict
**[Good idea / Bad idea / Needs more research]**

## If Good
- [How to translate this into production]
- [Specialists to involve]
- [Systems affected]

## If Bad
- [Why it didn't work]
- [Alternative approaches to try instead]
```

## Directory Structure

```
prototypes/
├── parry-mechanic/
│   ├── README.md
│   ├── ParryTest.lua
│   └── assets/
└── trading-ui/
    ├── README.md
    └── TradeUIExperiment.lua
```

## Forbidden Patterns

- ❌ Prototype without README (you'll forget what it was testing)
- ❌ `require(script.Parent.Parent.src.Something)` — breaks isolation
- ❌ Copying prototype code directly to src/ without rewrite
- ❌ Testing multiple unrelated hypotheses in one prototype
- ❌ Spending weeks on a "prototype" (set a time budget and stop)
- ❌ Prototyping instead of doing needed production work
