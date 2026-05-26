---
name: changelog
description: Generate changelog from git history and design docs. Roblox update log format.
---

# /changelog — Generate Changelog

## Delegate to: release-manager (with writer for language polish)

## Steps

### 1. Determine Range
Ask: "What range?" Options:
- Since last release (tag or branch)
- Since last commit of type N
- Custom date range
- Custom commit range

Default: since the last tag matching `v*`.

### 2. Gather Git History
```bash
# Get commits since last tag
git log $(git describe --tags --abbrev=0)..HEAD --format="%H %s"

# Or date range
git log --since="2 weeks ago" --format="%H %s"
```

### 3. Categorize Commits
Parse conventional commit format (`type(scope): description`):
- **feat**: New features
- **fix**: Bug fixes
- **perf**: Performance improvements
- **refactor**: Code refactoring
- **docs**: Documentation
- **test**: Tests
- **chore**: Maintenance
- **style**: Formatting

Group commits by type.

### 4. Extract Design Doc Changes
Cross-reference with design docs that were updated:
```bash
git diff --name-only $(git describe --tags --abbrev=0)..HEAD -- design/
```

Note any GDDs that changed — those probably correspond to feature work.

### 5. Generate Two Outputs

#### Technical Changelog (for team / docs)
```markdown
# Changelog

## [Unreleased]
### Added
- combat: Add dodge mechanic (#42)
- shop: Add GamePass: VIP Membership (#43)

### Changed
- combat: Rebalance weapon damage curves (#44)

### Fixed
- datastore: Fix race condition in save logic (#45)
- ui: Fix shop button alignment on mobile portrait (#46)

### Performance
- combat: Reduce hit detection overhead by 40% (#47)

### Deprecated
- (none)

### Removed
- (none)

### Security
- remotes: Add rate limiting to purchase remote (#48)
```

#### Player-Facing Patch Notes
(Handoff to `/patch-notes` for this — changelog is technical)

### 6. Output
Present the technical changelog. On approval, write to `CHANGELOG.md` (or append to existing).

If the project has no `CHANGELOG.md`, offer to create one using Keep a Changelog format.

## Changelog Style
- Use past tense ("Added" not "Adds")
- One line per change
- Include issue/PR references
- Group related small changes
- Lead with user-facing impact, not implementation details
