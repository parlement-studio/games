---
name: luau-lint
description: Static analysis of Luau code. Checks for type annotation coverage, deprecated API usage, naming convention compliance, and common anti-patterns. Uses `selene` if available or manual grep patterns.
---

# /luau-lint — Luau Static Analysis

## Steps

### 1. Check if `selene` is installed
```bash
selene --version 2>/dev/null
```

### If selene IS available:
```bash
selene src/
```
Parse the output and present findings grouped by severity.

### If selene is NOT available:
Fall back to manual grep-based checks.

## Manual Lint Checks (grep-based fallback)

### Deprecated API Usage (CRITICAL)
```bash
# Find wait() usage (not task.wait)
grep -rn "[^.]wait(" src/ --include="*.lua" --include="*.luau" | grep -v "task.wait\|:Wait"

# Find spawn() usage (not task.spawn)
grep -rn "[^.]spawn(" src/ --include="*.lua" --include="*.luau" | grep -v "task.spawn"

# Find delay() usage
grep -rn "[^.]delay(" src/ --include="*.lua" --include="*.luau" | grep -v "task.delay"
```

### Print Statements (should be logged, not printed)
```bash
grep -rn "print(" src/ --include="*.lua" --include="*.luau" | grep -v "^[^:]*:--"
```

### Missing Type Annotations (basic heuristic)
```bash
# Look for `function ModuleName.xyz(` without type annotations
grep -rn "function [A-Za-z]*\.[a-z][a-zA-Z]*(" src/ --include="*.lua" --include="*.luau"
```
Manually check if these have `: ReturnType` annotations.

### Missing pcall on DataStore/HttpService
```bash
grep -rn "DataStoreService\|HttpService\|MarketplaceService" src/ --include="*.lua" --include="*.luau" -A 3 | grep -B 1 "Async\|Post\|Get"
```
Manually check surrounding code for pcall wrapping.

### Hardcoded Magic Numbers in Gameplay Code
```bash
grep -rn "[^a-zA-Z_][0-9]\{2,\}" src/ --include="*.lua" --include="*.luau" | grep -v "UDim2\|Vector3\|Color3\|Enum\|^[^:]*:--"
```
Manual review for magic numbers that should be in config.

### Naming Conventions
```bash
# PascalCase modules (files)
find src/ -name "*.lua" -o -name "*.luau" | grep -v "/[A-Z][a-zA-Z]*\.lua"

# Check for `function myFunc` (should be `function MyFunc` if public or `local function myFunc` if private)
grep -rn "^function [a-z]" src/ --include="*.lua" --include="*.luau"
```

## Output Format
```markdown
# Luau Lint Report

## Summary
- Files scanned: X
- Errors: X
- Warnings: X
- Info: X

## Errors (must fix)
### Deprecated API Usage
- `src/ServerScriptService/Foo.lua:42` — `wait(1)` should be `task.wait(1)`
- ...

### Missing pcall
- `src/ServerStorage/PlayerData.lua:18` — DataStore:SetAsync() without pcall

## Warnings
### Print Statements
- `src/ServerScriptService/Combat.lua:95` — `print("hit")` (remove or route to logger)

### Magic Numbers
- `src/ServerScriptService/Combat.lua:102` — `damage = 50` (should be configurable)

## Info
### Naming Suggestions
- ...
```

Present the report to the user. Offer to delegate fixes to `lead-programmer`.
