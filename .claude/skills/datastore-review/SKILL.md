---
name: datastore-review
description: Audit all DataStore usage in the project for correctness, security, and best practices. Checks for session locking, pcall usage, schema versioning, budget management, and common anti-patterns.
---

# /datastore-review — DataStore Audit

## Delegate to: datastore-architect

## Steps:
1. Search for all DataStore usage: `grep -rn "DataStoreService" src/`
2. Search for all MemoryStore usage: `grep -rn "MemoryStoreService" src/`
3. Search for all BindToClose handlers: `grep -rn "BindToClose" src/`
4. Search for PlayerAdded / PlayerRemoving: `grep -rn "PlayerAdded\|PlayerRemoving" src/`

## Check each DataStore operation for:

### Critical (must fix):
- [ ] All GetAsync/SetAsync/UpdateAsync wrapped in pcall
- [ ] Session locking implemented (acquire lock on join, release on leave)
- [ ] BindToClose handler saves all player data with timeout
- [ ] Player data keyed by UserId (not Name)
- [ ] Schema includes version number
- [ ] No synchronous DataStore calls in PlayerAdded without yielding protection

### Important (should fix):
- [ ] Auto-save interval implemented (recommended: every 5 minutes)
- [ ] Save debouncing with dirty flag
- [ ] Retry logic for failed operations (with exponential backoff)
- [ ] Data migration functions for schema version upgrades
- [ ] OrderedDataStore used appropriately (leaderboards, rankings)
- [ ] Budget monitoring (not exceeding request limits)

### Nice to have:
- [ ] Data backup system (periodic full save to backup key)
- [ ] Analytics on save failures
- [ ] Admin tools for data inspection/correction

## Output:
Generate a report with findings organized by severity:

```markdown
# DataStore Review

## Scope
Files analyzed: X
DataStore references found: Y
MemoryStore references found: Z

## Critical Findings
1. **[filepath:line]**: [issue]
   - Impact: [data loss / duplication / exploit]
   - Fix: [specific code change]

## Important Findings
...

## Anti-Patterns Detected
...

## Recommended Architecture
[If no DataStore code exists yet, suggest the recommended architecture pattern:]
- ServerStorage/PlayerData/PlayerDataService.lua (main API)
- ServerStorage/PlayerData/SessionLock.lua (lock mechanism)
- ServerStorage/PlayerData/Schema.lua (current schema + migrations)
- ServerStorage/PlayerData/Serializer.lua (compress/decompress)
```

If no DataStore code exists yet, suggest the recommended architecture pattern and offer to scaffold it via `datastore-architect`.
