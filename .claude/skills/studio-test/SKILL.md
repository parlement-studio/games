---
name: studio-test
description: Run a play test in Roblox Studio via MCP and verify the game works. Starts play mode, checks console for errors, captures a screenshot, executes verification Luau, stops play mode, and reports results.
---

# /studio-test — Automated Play Test

## Delegate to: studio-mcp-operator

## Steps

### 1. Connect to Studio
- `mcp__roblox-studio__list_roblox_studios` — verify Studio is open
- `mcp__roblox-studio__set_active_studio` — select the correct instance

### 2. Pre-Test Check
- `mcp__roblox-studio__search_game_tree` — verify key services exist (ServerScriptService, ReplicatedStorage)
- `mcp__roblox-studio__get_console_output` — clear/note any pre-existing errors

### 3. Start Play Test
- `mcp__roblox-studio__start_stop_play` — start play mode
- Wait 3-5 seconds for game initialization

### 4. Verify Runtime State
- `mcp__roblox-studio__execute_luau` — run verification checks:
  - Are core services initialized?
  - Do expected RemoteEvents exist in ReplicatedStorage?
  - Is player data loading without errors?
  - Are any scripts erroring?

### 5. Capture Visual State
- `mcp__roblox-studio__screen_capture` — screenshot the game
- Analyze: Is the UI rendering? Is the world visible? Any obvious visual issues?

### 6. Check Console
- `mcp__roblox-studio__get_console_output` — read all output since play started
- Flag: errors (red), warnings (yellow), unexpected prints
- Categorize: script errors, DataStore errors, remote errors, asset loading errors

### 7. Stop Play Test
- `mcp__roblox-studio__start_stop_play` — stop play mode

### 8. Report Results
```markdown
# Play Test Report

**Status**: [PASS / FAIL / WARNINGS]
**Duration**: X seconds
**Studio**: [instance name]

## Console Output
- Errors: [count]
- Warnings: [count]
- [List each error with source script and message]

## Runtime Verification
- [x] Core services loaded
- [x] Remotes exist
- [ ] Player data initialized (FAILED: DataStore timeout)

## Visual Check
- [Screenshot attached]
- [Any visual issues noted]

## Recommendations
1. [Fix needed]
2. [Investigation needed]
```
