---
name: code-review
description: Review Luau code for style compliance, type safety, server authority, error handling, and performance. Use for reviewing a file, a PR-sized change, or a whole module.
---

# /code-review — Luau Code Review

## Delegate to: lead-programmer (with exploit-security-specialist for security concerns)

## Scope
Ask the user:
- "Which files should I review? (provide paths, a directory, or say 'recent changes')"
- For git-based review: `git diff HEAD~1` or `git diff main...HEAD` style

## Review Checklist

### Structure & Style
- [ ] Module pattern: `local Module = {} ... return Module`
- [ ] Service caching at top: `local Players = game:GetService("Players")`
- [ ] Type annotations on public functions
- [ ] Naming conventions (PascalCase modules, camelCase functions, UPPER_SNAKE constants)
- [ ] No magic numbers (all constants externalized)
- [ ] No `print()` left in production code (unless behind a debug flag)

### Safety & Correctness
- [ ] No deprecated APIs: `wait()`, `spawn()`, `delay()` — should use `task.wait()`, `task.spawn()`, `task.defer()`
- [ ] All DataStore/HttpService/MarketplaceService calls in `pcall`
- [ ] Retry logic for transient failures
- [ ] No infinite loops without yield
- [ ] Proper cleanup (Trove/Maid/manual disconnection)

### Server Authority (Security)
- [ ] No client-side game state mutations
- [ ] All RemoteEvent handlers validate argument types
- [ ] All RemoteEvent handlers validate argument ranges
- [ ] Rate limiting on player-triggered remotes
- [ ] No RemoteFunction invoked client → server (server hang risk)
- [ ] Purchase processing via `MarketplaceService.ProcessReceipt` server-side

### Performance
- [ ] No expensive work per Heartbeat without throttling
- [ ] Cached references (not repeated `workspace.X` lookups)
- [ ] No string concatenation in loops (use `table.concat`)
- [ ] Table allocations minimized in hot paths
- [ ] Connections disconnected on cleanup

### Architecture
- [ ] No circular module dependencies
- [ ] Clear separation: shared / server / client
- [ ] Shared modules don't leak server secrets
- [ ] Config values externalized to dedicated config module

## Output Format
```markdown
# Code Review: [Scope]

## Summary
- Files reviewed: X
- Critical issues: X
- Important issues: X
- Suggestions: X

## Critical (must fix before merge)
1. **[filepath:line]**: [issue]
   - Reason: [why it's critical]
   - Fix: [specific code change]

## Important
...

## Suggestions
...

## Kudos
- [Things done well — reinforce good patterns]
```

Present the review to the user. Never apply fixes without approval.
Offer to delegate fixes to the appropriate specialist.
