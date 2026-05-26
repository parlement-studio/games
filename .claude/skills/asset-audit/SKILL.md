---
name: asset-audit
description: Review assets — naming conventions, file sizes, unused assets, and organization. Flags assets that violate naming standards or exceed size limits.
---

# /asset-audit — Asset Review

## Delegate to: art-director (with technical-artist for optimization review)

## Steps

### 1. Scan Asset Directories
```bash
find assets/ -type f | sort
```
Categorize by type: images, audio, models, data.

### 2. Naming Convention Check
Standard: `lowercase-kebab-case.ext`

Good: `wooden-crate.fbx`, `sword-swing-01.mp3`, `ui-button-bg.png`
Bad: `Wooden Crate.fbx`, `swordswing1.mp3`, `UI_Button_BG.png`

```bash
# Find files with spaces (violation)
find assets/ -type f -name "* *"

# Find files with uppercase (violation — except extensions)
find assets/ -type f | grep -v "/[a-z0-9-]*\.[a-zA-Z0-9]*$"
```

### 3. File Size Check
Flag large files:
- Images > 1MB (warning), > 5MB (critical)
- Audio > 1MB short SFX (warning), > 10MB music (normal)
- Models > 5MB (warning), > 20MB (critical)

```bash
find assets/images -type f -size +1M
find assets/audio -type f -size +10M
find assets/models -type f -size +5M
```

### 4. Unused Asset Detection
Check which assets are referenced in code:
```bash
# For each asset, grep for its name in src/
for asset in $(find assets/ -type f -name "*.png" -o -name "*.jpg"); do
    name=$(basename "$asset")
    if ! grep -r "$name" src/ > /dev/null; then
        echo "POTENTIALLY UNUSED: $asset"
    fi
done
```

Note: Some assets may be referenced by ID (Roblox asset ID), not by filename. Manual verification needed.

### 5. Organization Check
- [ ] All images in `assets/images/`
- [ ] All audio in `assets/audio/`
- [ ] All models in `assets/models/`
- [ ] All data (JSON) in `assets/data/`
- [ ] Sub-categorized if > 20 files in a folder (e.g., `assets/images/ui/`, `assets/images/icons/`)

### 6. Roblox Limit Check
- **Mesh triangles**: Flag models > 10,000 tris (need DCC tool inspection)
- **Texture resolution**: Flag images > 1024×1024
- **Audio duration**: Flag audio > 60 seconds that isn't music

### 7. Generate Report
```markdown
# Asset Audit

## Summary
- Total assets: X
- Images: X
- Audio: X
- Models: X
- Data files: X

## Violations
### Naming (must fix)
- [path] — violates kebab-case

### Oversized (should fix)
- [path] — [size] exceeds [limit]

### Potentially Unused (investigate)
- [path] — no references found in src/

### Organization (nice to have)
- [suggestion]

## Statistics
- Largest asset: [path, size]
- Most referenced: [path, count]
- Total asset size: XX MB

## Recommendations
1. [Specific cleanup action]
2. [Optimization opportunity]
```

Present to user. Offer to delegate cleanup to art-director.
