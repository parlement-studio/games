---
name: studio-screenshot
description: Capture a screenshot of the current Roblox Studio viewport and analyze it. Use for visual verification of UI, lighting, level layout, and general game appearance.
---

# /studio-screenshot — Visual Capture and Analysis

## Delegate to: studio-mcp-operator

## Steps

### 1. Connect
- `mcp__roblox-studio__list_roblox_studios` → `mcp__roblox-studio__set_active_studio`

### 2. Capture
- `mcp__roblox-studio__screen_capture` — capture the current viewport

### 3. Analyze
Examine the screenshot for:
- **UI**: Is the HUD rendering? Are buttons visible and properly positioned? Text readable?
- **World**: Is geometry visible? Correct lighting? Expected objects present?
- **Layout**: Mobile-safe spacing? No overlapping elements? Correct aspect ratio?
- **Visual quality**: Materials rendering? Colors correct? No z-fighting or flickering?

### 4. Report
Present the screenshot with observations:
- What looks correct
- What looks wrong or suspicious
- Specific recommendations for fixes
- Which agent should address each issue (ui-programmer for UI, level-designer for world, technical-artist for materials)
