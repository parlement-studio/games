---
name: studio-inspect
description: Inspect the current Roblox Studio state via MCP. Verifies instance hierarchy, checks for common structural issues, and reports findings.
---

# /studio-inspect — Studio State Inspection

## Delegate to: studio-mcp-operator

## Steps

### 1. Connect
- `mcp__roblox-studio__list_roblox_studios` → `mcp__roblox-studio__set_active_studio`

### 2. Verify Service Structure
Search for and inspect each expected service:
- ServerScriptService — should contain server scripts
- ServerStorage — should contain modules and data
- ReplicatedStorage — should contain Shared/ and remotes
- StarterGui — should contain UI
- StarterPlayer — should contain client scripts
- ReplicatedFirst — loading screen (if used)
- Workspace — game world

### 3. Check for Common Issues
- Scripts in wrong services (LocalScript in ServerScriptService, Script in StarterGui)
- Missing remotes (search for RemoteEvent/RemoteFunction instances)
- Orphan instances (parts not in a model or folder)
- Unanchored parts that should be anchored
- Scripts with errors (grep for common patterns)

### 4. Report
```markdown
# Studio Inspection Report

## Service Structure
- [✅/❌] ServerScriptService: X scripts
- [✅/❌] ReplicatedStorage: X modules, Y remotes
- ...

## Issues Found
1. [Issue with location and recommendation]

## Instance Counts
- Parts: X
- Scripts: X
- RemoteEvents: X
- UI elements: X
```
