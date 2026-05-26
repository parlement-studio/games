---
name: asset-from-image
description: Generate a 3D asset from a reference image using Blender MCP's image-to-3D AI (Hyper3D). Optimizes for Roblox and exports FBX.
---

# /asset-from-image — Image-to-3D Asset Generation

## Delegate to: blender-mcp-operator

## Steps

### 1. Get the Reference Image
Ask: "Share the reference image (screenshot, concept art, photo)"
The image will be passed to the AI generation tool.

### 2. Generate
- `mcp__blender-mcp__generate_hyper3d_model_via_images` with the reference image
- Poll `mcp__blender-mcp__get_hyper3d_status` until generation completes (30-120s)
- `mcp__blender-mcp__import_generated_asset` into the Blender scene

### 3. Compare with Reference
- `mcp__blender-mcp__get_viewport_screenshot` — capture the generated model
- Compare side-by-side with the original reference image
- Note differences and decide if regeneration is needed

### 4. Optimize for Roblox
Same as `/generate-asset` step 5:
- Decimate to triangle budget
- Scale to Roblox units
- Set origin, clean topology
- UV unwrap if needed

### 5. Export and Approve
- Export FBX to `assets/models/`
- Present screenshot + poly count + comparison with reference
- User approves or requests adjustments
